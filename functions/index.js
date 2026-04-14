const crypto = require('node:crypto');

const { logger } = require('firebase-functions');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { GoogleAuth } = require('google-auth-library');

const DEFAULT_ALLOWED_PACKAGES = ['org.ruhenheim.himemo'];
const DEFAULT_ALLOWED_DEV_PACKAGES = ['org.ruhenheim.himemo.dev'];
const CHALLENGE_TTL_SECONDS = 60;
const CHALLENGE_RATE_LIMIT_WINDOW_MS = 60_000;
const CHALLENGE_RATE_LIMIT_MAX = 12;
const challengeSecret = defineSecret('PLAY_INTEGRITY_CHALLENGE_SECRET');
const rateLimitState = new Map();

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

function base64UrlEncode(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64UrlDecode(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString('utf8');
}

function normalizeVerdictList(value) {
  return Array.isArray(value)
    ? value.filter((entry) => typeof entry === 'string')
    : [];
}

function getAllowedPackages({ allowDevelopment = false } = {}) {
  const configured = process.env.HIMEMO_ALLOWED_ANDROID_PACKAGES;
  const configuredDev = process.env.HIMEMO_ALLOWED_ANDROID_DEV_PACKAGES;
  const basePackages = (configured && configured.trim()
    ? configured
        .split(',')
        .map((entry) => entry.trim())
        .filter((entry) => entry.length > 0)
    : DEFAULT_ALLOWED_PACKAGES);

  if (!allowDevelopment) {
    return basePackages;
  }

  const devPackages = (configuredDev && configuredDev.trim()
    ? configuredDev
        .split(',')
        .map((entry) => entry.trim())
        .filter((entry) => entry.length > 0)
    : DEFAULT_ALLOWED_DEV_PACKAGES);

  return [...new Set([...basePackages, ...devPackages])];
}

function createHmacSignature(secret, payload) {
  return crypto
    .createHmac('sha256', secret)
    .update(payload, 'utf8')
    .digest('base64url');
}

function issueChallenge({ secret, packageName, operation }) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const payload = JSON.stringify({
    packageName,
    operation,
    issuedAt: nowSeconds,
    expiresAt: nowSeconds + CHALLENGE_TTL_SECONDS,
    nonce: crypto.randomBytes(18).toString('base64url'),
  });
  const payloadEncoded = base64UrlEncode(payload);
  const signature = createHmacSignature(secret, payloadEncoded);
  return `${payloadEncoded}.${signature}`;
}

function verifyChallenge({ secret, challenge, packageName, operation }) {
  if (typeof challenge !== 'string' || !challenge.trim()) {
    return { ok: false, code: 'invalid-challenge', message: 'Challenge is missing.' };
  }

  const parts = challenge.split('.');
  if (parts.length !== 2) {
    return { ok: false, code: 'invalid-challenge', message: 'Challenge format is invalid.' };
  }

  const [payloadEncoded, signature] = parts;
  const expectedSignature = createHmacSignature(secret, payloadEncoded);
  if (
    expectedSignature.length !== signature.length ||
    !crypto.timingSafeEqual(
      Buffer.from(expectedSignature, 'utf8'),
      Buffer.from(signature, 'utf8'),
    )
  ) {
    return { ok: false, code: 'invalid-challenge', message: 'Challenge signature is invalid.' };
  }

  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(payloadEncoded));
  } catch (_error) {
    return { ok: false, code: 'invalid-challenge', message: 'Challenge payload could not be decoded.' };
  }

  if (payload.packageName !== packageName) {
    return { ok: false, code: 'package-mismatch', message: 'Challenge package did not match.' };
  }
  if (payload.operation !== operation) {
    return { ok: false, code: 'operation-mismatch', message: 'Challenge operation did not match.' };
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (
    typeof payload.expiresAt !== 'number' ||
    typeof payload.issuedAt !== 'number' ||
    payload.expiresAt <= nowSeconds ||
    payload.issuedAt > nowSeconds + 15
  ) {
    return { ok: false, code: 'expired-challenge', message: 'Challenge has expired.' };
  }

  return { ok: true, payload };
}

function isDevelopmentPackage(packageName) {
  return packageName.endsWith('.dev');
}

function isRateLimited(ip) {
  const now = Date.now();
  const current = rateLimitState.get(ip);
  if (!current || now - current.windowStart > CHALLENGE_RATE_LIMIT_WINDOW_MS) {
    rateLimitState.set(ip, { windowStart: now, count: 1 });
    return false;
  }
  current.count += 1;
  if (current.count > CHALLENGE_RATE_LIMIT_MAX) {
    return true;
  }
  rateLimitState.set(ip, current);
  return false;
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
    cors: true,
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

    const ip = request.ip || request.headers['x-forwarded-for'] || 'unknown';
    if (isRateLimited(`${ip}`)) {
      return jsonError(
        response,
        'rate-limited',
        'Too many challenge requests. Please wait and retry.',
        429,
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

    const secretValue = challengeSecret.value();
    const challenge = issueChallenge({
      secret: secretValue,
      packageName: resolvedPackageName,
      operation: resolvedOperation,
    });

    logger.info('Issued Play Integrity challenge', {
      packageName: resolvedPackageName,
      operation: resolvedOperation,
      allowDevelopment: isDevelopmentPackage(resolvedPackageName),
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
    cors: true,
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
      const appVerdict = appIntegrity.appRecognitionVerdict || 'UNKNOWN';
      const deviceVerdicts = normalizeVerdictList(
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
        appVerdict,
        deviceVerdicts,
        licensingVerdict,
        allowDevelopment,
        verdictOk,
      });

      return response.json({
        ok: true,
        verdictOk,
        packageMatches,
        requestChallengeMatches,
        requestHashMatches,
        nonceMatches,
        appIntegrity: {
          appRecognitionVerdict: appVerdict,
          packageName: requestDetails.requestPackageName || null,
          certificateDigests: normalizeVerdictList(
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
