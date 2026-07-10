const crypto = require('node:crypto');

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAppCheck } = require('firebase-admin/app-check');
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { GoogleAuth } = require('google-auth-library');
const {
  CHALLENGE_TTL_SECONDS,
  buildRateLimitKey,
  createRateLimiter,
  getAllowedPackages,
  isDevelopmentPackage,
  issueChallenge,
  normalizeStringList,
  verifyChallenge,
  verifyRequestTimestamp,
} = require('./play_integrity_helpers');

if (!getApps().length) {
  initializeApp();
}

const firestore = getFirestore();

const CHALLENGE_COLLECTION = 'playIntegrityChallenges';
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const CHALLENGE_RATE_LIMIT_MAX = 12;
const VERIFY_RATE_LIMIT_MAX = 24;
const APP_CHECK_HEADER = 'x-firebase-appcheck';

const challengeSecret = defineSecret('PLAY_INTEGRITY_CHALLENGE_SECRET');
const rateLimiter = createRateLimiter({ windowMs: RATE_LIMIT_WINDOW_MS });

const PLAY_INTEGRITY_SCOPE =
  'https://www.googleapis.com/auth/playintegrity';
const PLAY_INTEGRITY_ENDPOINT =
  'https://playintegrity.googleapis.com/v1/%s:decodeIntegrityToken';

function jsonError(response, code, message, status = 400, details = undefined) {
  response.status(status).json({
    ok: false,
    error: {
      code,
      message,
      details,
    },
  });
}

function isRateLimited(key, maxCount) {
  return rateLimiter.isRateLimited(key, maxCount);
}

async function verifyAppCheckToken(request) {
  const token =
    request.header(APP_CHECK_HEADER) ||
    request.header(APP_CHECK_HEADER.toUpperCase());

  if (!token) {
    const error = new Error('Firebase App Check token is missing.');
    error.code = 'app-check-required';
    throw error;
  }

  try {
    return await getAppCheck().verifyToken(token);
  } catch (error) {
    const wrapped = new Error('Firebase App Check verification failed.');
    wrapped.code = 'app-check-invalid';
    wrapped.cause = error;
    throw wrapped;
  }
}

async function persistChallenge({
  challengeId,
  packageName,
  operation,
  appId,
  expiresAtSeconds,
}) {
  await firestore.collection(CHALLENGE_COLLECTION).doc(challengeId).set({
    packageName,
    operation,
    appId,
    issuedAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(expiresAtSeconds * 1000),
  });
}

async function consumeChallenge({
  challengeId,
  packageName,
  operation,
  appId,
}) {
  const docRef = firestore.collection(CHALLENGE_COLLECTION).doc(challengeId);
  const now = Timestamp.now();

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    if (!snapshot.exists) {
      return { ok: false, code: 'challenge-not-found', message: 'Challenge was not found or was already used.' };
    }

    const data = snapshot.data() || {};
    const expiresAt = data.expiresAt;
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.toMillis()) {
      transaction.delete(docRef);
      return { ok: false, code: 'expired-challenge', message: 'Challenge has expired.' };
    }

    if (data.packageName !== packageName) {
      transaction.delete(docRef);
      return { ok: false, code: 'package-mismatch', message: 'Stored challenge package did not match.' };
    }

    if (data.operation !== operation) {
      transaction.delete(docRef);
      return { ok: false, code: 'operation-mismatch', message: 'Stored challenge operation did not match.' };
    }

    if (data.appId !== appId) {
      transaction.delete(docRef);
      return { ok: false, code: 'app-check-mismatch', message: 'Stored challenge app did not match.' };
    }

    transaction.delete(docRef);
    return { ok: true };
  });
}

async function pruneExpiredChallenges() {
  const cutoff = Timestamp.now();
  const snapshot = await firestore
    .collection(CHALLENGE_COLLECTION)
    .where('expiresAt', '<=', cutoff)
    .limit(20)
    .get();

  if (snapshot.empty) {
    return;
  }

  const batch = firestore.batch();
  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
}

async function decodeIntegrityToken({ packageName, integrityToken }) {
  const auth = new GoogleAuth({ scopes: [PLAY_INTEGRITY_SCOPE] });
  const client = await auth.getClient();
  const accessTokenResponse = await client.getAccessToken();
  const accessToken =
    typeof accessTokenResponse === 'string'
      ? accessTokenResponse
      : accessTokenResponse?.token;

  if (!accessToken) {
    throw new Error('Unable to obtain Google access token for Play Integrity.');
  }

  const endpoint = PLAY_INTEGRITY_ENDPOINT.replace(
    '%s',
    encodeURIComponent(packageName),
  );

  const apiResponse = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ integrityToken }),
  });

  const payload = await apiResponse.json().catch(() => ({}));
  if (!apiResponse.ok) {
    throw new Error(
      payload?.error?.message ||
        `Play Integrity decode failed with ${apiResponse.status}.`,
    );
  }
  return payload;
}

exports.issuePlayIntegrityChallengeV2 = onRequest(
  {
    cors: false,
    region: 'asia-northeast1',
    timeoutSeconds: 10,
    memory: '128MiB',
    minInstances: 0,
    maxInstances: 3,
    secrets: [challengeSecret],
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.set('Allow', 'POST');
      return jsonError(response, 'method-not-allowed', 'Use POST.', 405);
    }

    if (isRateLimited(buildRateLimitKey(request, 'challenge'), CHALLENGE_RATE_LIMIT_MAX)) {
      return jsonError(
        response,
        'rate-limited',
        'Too many challenge requests. Please wait and retry.',
        429,
      );
    }

    let appCheckClaims;
    try {
      appCheckClaims = await verifyAppCheckToken(request);
    } catch (error) {
      logger.warn('Play Integrity challenge rejected by App Check', {
        code: error.code,
      });
      return jsonError(
        response,
        error.code || 'app-check-invalid',
        error.message,
        401,
      );
    }

    const { packageName, operation } = request.body || {};
    const resolvedPackageName =
      typeof packageName === 'string' ? packageName.trim() : '';
    const resolvedOperation =
      typeof operation === 'string' ? operation.trim() : '';

    if (!resolvedPackageName) {
      return jsonError(response, 'invalid-argument', 'packageName must be provided.');
    }
    if (!resolvedOperation) {
      return jsonError(response, 'invalid-argument', 'operation must be provided.');
    }

    const allowedPackages = getAllowedPackages({ allowDevelopment: true });
    if (!allowedPackages.includes(resolvedPackageName)) {
      return jsonError(
        response,
        'forbidden-package',
        'The requested package is not allowed for this backend.',
        403,
      );
    }

    const challengeId = crypto.randomBytes(16).toString('hex');
    const secretValue = challengeSecret.value();
    const challenge = issueChallenge({
      secret: secretValue,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
      challengeId,
    });
    const challengeCheck = verifyChallenge({
      secret: secretValue,
      challenge,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
    });

    await persistChallenge({
      challengeId,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
      appId: appCheckClaims.appId,
      expiresAtSeconds: challengeCheck.payload.expiresAt,
    });
    await pruneExpiredChallenges().catch(() => {});

    logger.info('Issued Play Integrity challenge', {
      packageName: resolvedPackageName,
      operation: resolvedOperation,
      allowDevelopment: isDevelopmentPackage(resolvedPackageName),
      appId: appCheckClaims.appId,
    });

    return response.json({
      ok: true,
      challenge,
      expiresInSeconds: CHALLENGE_TTL_SECONDS,
    });
  },
);

exports.verifyPlayIntegrityV2 = onRequest(
  {
    cors: false,
    region: 'asia-northeast1',
    timeoutSeconds: 15,
    memory: '128MiB',
    minInstances: 0,
    maxInstances: 3,
    secrets: [challengeSecret],
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.set('Allow', 'POST');
      return jsonError(response, 'method-not-allowed', 'Use POST.', 405);
    }

    if (isRateLimited(buildRateLimitKey(request, 'verify'), VERIFY_RATE_LIMIT_MAX)) {
      return jsonError(
        response,
        'rate-limited',
        'Too many verification requests. Please wait and retry.',
        429,
      );
    }

    let appCheckClaims;
    try {
      appCheckClaims = await verifyAppCheckToken(request);
    } catch (error) {
      logger.warn('Play Integrity verification rejected by App Check', {
        code: error.code,
      });
      return jsonError(
        response,
        error.code || 'app-check-invalid',
        error.message,
        401,
      );
    }

    const { integrityToken, challenge, packageName, expectedPackageName, operation } =
      request.body || {};

    if (typeof integrityToken !== 'string' || !integrityToken.trim()) {
      return jsonError(
        response,
        'invalid-argument',
        'integrityToken must be a non-empty string.',
      );
    }

    const resolvedPackageName =
      (typeof expectedPackageName === 'string' && expectedPackageName.trim()) ||
      (typeof packageName === 'string' && packageName.trim()) ||
      '';
    const resolvedOperation =
      typeof operation === 'string' ? operation.trim() : '';

    if (!resolvedPackageName) {
      return jsonError(response, 'invalid-argument', 'packageName must be provided.');
    }
    if (!resolvedOperation) {
      return jsonError(response, 'invalid-argument', 'operation must be provided.');
    }

    const allowDevelopment = isDevelopmentPackage(resolvedPackageName);
    const allowedPackages = getAllowedPackages({ allowDevelopment });
    if (!allowedPackages.includes(resolvedPackageName)) {
      return jsonError(
        response,
        'forbidden-package',
        'The requested package is not allowed for this backend.',
        403,
      );
    }

    const challengeCheck = verifyChallenge({
      secret: challengeSecret.value(),
      challenge,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
    });
    if (!challengeCheck.ok) {
      return jsonError(
        response,
        challengeCheck.code,
        challengeCheck.message,
        403,
      );
    }

    const challengeConsumeResult = await consumeChallenge({
      challengeId: challengeCheck.payload.challengeId,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
      appId: appCheckClaims.appId,
    });
    if (!challengeConsumeResult.ok) {
      return jsonError(
        response,
        challengeConsumeResult.code,
        challengeConsumeResult.message,
        403,
      );
    }

    try {
      const decoded = await decodeIntegrityToken({
        packageName: resolvedPackageName,
        integrityToken,
      });
      const tokenPayload = decoded.tokenPayloadExternal || {};
      const requestDetails = tokenPayload.requestDetails || {};
      const appIntegrity = tokenPayload.appIntegrity || {};
      const deviceIntegrity = tokenPayload.deviceIntegrity || {};
      const accountDetails = tokenPayload.accountDetails || {};

      const expectedNonce = Buffer.from(challenge.trim(), 'utf8').toString('base64');
      const requestHashMatches = requestDetails.requestHash === challenge;
      const nonceMatches = requestDetails.nonce === expectedNonce;
      const requestChallengeMatches = requestHashMatches || nonceMatches;
      const packageMatches =
        requestDetails.requestPackageName === resolvedPackageName;
      const freshnessOk = verifyRequestTimestamp({
        requestTimestampMillis: requestDetails.timestampMillis,
        issuedAtSeconds: challengeCheck.payload.issuedAt,
        expiresAtSeconds: challengeCheck.payload.expiresAt,
      });
      const appVerdict = appIntegrity.appRecognitionVerdict || 'UNKNOWN';
      const deviceVerdicts = normalizeStringList(
        deviceIntegrity.deviceRecognitionVerdict,
      );
      const licensingVerdict =
        accountDetails.appLicensingVerdict || 'UNKNOWN';

      const isAppRecognized = appVerdict === 'PLAY_RECOGNIZED';
      const hasStrongIntegrity = deviceVerdicts.includes('MEETS_STRONG_INTEGRITY');
      const hasDeviceIntegrity =
        hasStrongIntegrity || deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY');
      const hasBasicIntegrity =
        hasDeviceIntegrity || deviceVerdicts.includes('MEETS_BASIC_INTEGRITY');
      const meetsRequiredDeviceIntegrity = allowDevelopment
        ? hasBasicIntegrity
        : hasDeviceIntegrity;
      const isLicensed = licensingVerdict === 'LICENSED';
      const verdictOk =
        packageMatches &&
        requestChallengeMatches &&
        freshnessOk &&
        isAppRecognized &&
        meetsRequiredDeviceIntegrity &&
        isLicensed;

      logger.info('Play Integrity verification completed', {
        packageName: resolvedPackageName,
        operation: resolvedOperation,
        packageMatches,
        requestChallengeMatches,
        requestHashMatches,
        nonceMatches,
        freshnessOk,
        appVerdict,
        deviceVerdicts,
        licensingVerdict,
        allowDevelopment,
        appId: appCheckClaims.appId,
        verdictOk,
      });

      return response.json({
        ok: true,
        verdictOk,
        packageMatches,
        requestChallengeMatches,
        requestHashMatches,
        nonceMatches,
        freshnessOk,
        appIntegrity: {
          appRecognitionVerdict: appVerdict,
          packageName: requestDetails.requestPackageName || null,
          certificateDigests: normalizeStringList(
            appIntegrity.certificateSha256Digest,
          ),
          versionCode: appIntegrity.versionCode || null,
        },
        deviceIntegrity: {
          verdicts: deviceVerdicts,
          requiresDeviceIntegrity: !allowDevelopment,
        },
        accountDetails: {
          appLicensingVerdict: licensingVerdict,
        },
        requestDetails: {
          requestHash: requestDetails.requestHash || null,
          nonce: requestDetails.nonce || null,
          timestampMillis: requestDetails.timestampMillis || null,
        },
      });
    } catch (error) {
      logger.error('Play Integrity verification failed', error);
      return jsonError(
        response,
        'play-integrity-failed',
        error instanceof Error ? error.message : String(error),
        500,
      );
    }
  },
);
