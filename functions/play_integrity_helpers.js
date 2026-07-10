const crypto = require('node:crypto');

const DEFAULT_ALLOWED_PACKAGES = ['org.ruhenheim.himemo'];
const DEFAULT_ALLOWED_DEV_PACKAGES = ['org.ruhenheim.himemo.dev'];
const CHALLENGE_TTL_SECONDS = 60;
const MAX_TOKEN_AGE_MS = 90 * 1000;
const REQUEST_CLOCK_SKEW_MS = 15 * 1000;

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

function normalizeStringList(value) {
  return Array.isArray(value)
    ? value.filter((entry) => typeof entry === 'string')
    : [];
}

function parseConfiguredPackages(configured, fallback) {
  if (typeof configured !== 'string' || !configured.trim()) {
    return fallback;
  }
  return configured
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

function getAllowedPackages(
  { allowDevelopment = false } = {},
  environment = process.env,
) {
  const basePackages = parseConfiguredPackages(
    environment.HIMEMO_ALLOWED_ANDROID_PACKAGES,
    DEFAULT_ALLOWED_PACKAGES,
  );

  if (!allowDevelopment) {
    return basePackages;
  }

  const devPackages = parseConfiguredPackages(
    environment.HIMEMO_ALLOWED_ANDROID_DEV_PACKAGES,
    DEFAULT_ALLOWED_DEV_PACKAGES,
  );
  return [...new Set([...basePackages, ...devPackages])];
}

function createHmacSignature(secret, payload) {
  return crypto
    .createHmac('sha256', secret)
    .update(payload, 'utf8')
    .digest('base64url');
}

function isDevelopmentPackage(packageName) {
  return typeof packageName === 'string' && packageName.endsWith('.dev');
}

function buildRateLimitKey(request, scope) {
  const forwardedFor = request.headers?.['x-forwarded-for'];
  const ip = `${request.ip || forwardedFor || 'unknown'}`
    .split(',', 1)[0]
    .trim();
  return `${scope}:${ip || 'unknown'}`;
}

function createRateLimiter({ windowMs, now = () => Date.now() }) {
  if (!Number.isFinite(windowMs) || windowMs <= 0) {
    throw new TypeError('windowMs must be a positive number.');
  }

  const state = new Map();
  return {
    isRateLimited(key, maxCount) {
      if (!Number.isInteger(maxCount) || maxCount <= 0) {
        throw new TypeError('maxCount must be a positive integer.');
      }

      const currentTime = now();
      const current = state.get(key);
      if (!current || currentTime - current.windowStart >= windowMs) {
        state.set(key, { windowStart: currentTime, count: 1 });
        return false;
      }

      current.count += 1;
      state.set(key, current);
      return current.count > maxCount;
    },
  };
}

function issueChallenge({
  secret,
  packageName,
  operation,
  challengeId,
  nowMs = Date.now(),
  randomBytes = crypto.randomBytes,
}) {
  const nowSeconds = Math.floor(nowMs / 1000);
  const payload = JSON.stringify({
    challengeId,
    packageName,
    operation,
    issuedAt: nowSeconds,
    expiresAt: nowSeconds + CHALLENGE_TTL_SECONDS,
    nonce: randomBytes(18).toString('base64url'),
  });
  const payloadEncoded = base64UrlEncode(payload);
  const signature = createHmacSignature(secret, payloadEncoded);
  return `${payloadEncoded}.${signature}`;
}

function invalidChallenge(code, message) {
  return { ok: false, code, message };
}

function verifyChallenge({
  secret,
  challenge,
  packageName,
  operation,
  nowMs = Date.now(),
}) {
  if (typeof challenge !== 'string' || !challenge.trim()) {
    return invalidChallenge('invalid-challenge', 'Challenge is missing.');
  }

  const parts = challenge.split('.');
  if (parts.length !== 2) {
    return invalidChallenge(
      'invalid-challenge',
      'Challenge format is invalid.',
    );
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
    return invalidChallenge(
      'invalid-challenge',
      'Challenge signature is invalid.',
    );
  }

  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(payloadEncoded));
  } catch (_error) {
    return invalidChallenge(
      'invalid-challenge',
      'Challenge payload could not be decoded.',
    );
  }

  if (payload.packageName !== packageName) {
    return invalidChallenge(
      'package-mismatch',
      'Challenge package did not match.',
    );
  }
  if (payload.operation !== operation) {
    return invalidChallenge(
      'operation-mismatch',
      'Challenge operation did not match.',
    );
  }
  if (typeof payload.challengeId !== 'string' || !payload.challengeId.trim()) {
    return invalidChallenge('invalid-challenge', 'Challenge id is missing.');
  }

  const nowSeconds = Math.floor(nowMs / 1000);
  if (
    typeof payload.expiresAt !== 'number' ||
    typeof payload.issuedAt !== 'number' ||
    payload.expiresAt <= nowSeconds ||
    payload.issuedAt > nowSeconds + 15
  ) {
    return invalidChallenge('expired-challenge', 'Challenge has expired.');
  }

  return { ok: true, payload };
}

function verifyRequestTimestamp({
  requestTimestampMillis,
  issuedAtSeconds,
  expiresAtSeconds,
  nowMs = Date.now(),
}) {
  const rawTimestamp = `${requestTimestampMillis}`.trim();
  if (!/^\d+$/.test(rawTimestamp)) {
    return false;
  }
  const requestTimestamp = Number(rawTimestamp);
  if (!Number.isSafeInteger(requestTimestamp)) {
    return false;
  }

  const issuedAtMs = issuedAtSeconds * 1000;
  const expiresAtMs = expiresAtSeconds * 1000;

  if (requestTimestamp < issuedAtMs - REQUEST_CLOCK_SKEW_MS) {
    return false;
  }
  if (requestTimestamp > expiresAtMs + REQUEST_CLOCK_SKEW_MS) {
    return false;
  }
  if (nowMs - requestTimestamp > MAX_TOKEN_AGE_MS) {
    return false;
  }

  return true;
}

module.exports = {
  CHALLENGE_TTL_SECONDS,
  buildRateLimitKey,
  createRateLimiter,
  getAllowedPackages,
  isDevelopmentPackage,
  issueChallenge,
  normalizeStringList,
  verifyChallenge,
  verifyRequestTimestamp,
};
