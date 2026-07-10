const assert = require('node:assert/strict');
const { test } = require('node:test');

const {
  buildRateLimitKey,
  createRateLimiter,
  getAllowedPackages,
  isDevelopmentPackage,
  issueChallenge,
  normalizeStringList,
  verifyChallenge,
  verifyRequestTimestamp,
} = require('../play_integrity_helpers');

const NOW_MS = 1_800_000_000_000;
const SECRET = 'test-secret-with-sufficient-entropy';

function makeChallenge(overrides = {}) {
  return issueChallenge({
    secret: SECRET,
    packageName: 'org.ruhenheim.himemo',
    operation: 'unlock',
    challengeId: 'challenge-123',
    nowMs: NOW_MS,
    randomBytes: () => Buffer.alloc(18, 7),
    ...overrides,
  });
}

test('challenge round trip preserves the signed security context', () => {
  const result = verifyChallenge({
    secret: SECRET,
    challenge: makeChallenge(),
    packageName: 'org.ruhenheim.himemo',
    operation: 'unlock',
    nowMs: NOW_MS + 30_000,
  });

  assert.equal(result.ok, true);
  assert.equal(result.payload.challengeId, 'challenge-123');
  assert.equal(result.payload.packageName, 'org.ruhenheim.himemo');
  assert.equal(result.payload.operation, 'unlock');
  assert.equal(result.payload.issuedAt, NOW_MS / 1000);
  assert.equal(result.payload.expiresAt, NOW_MS / 1000 + 60);
});

test('challenge verification rejects tampering, context mismatch, and expiry', () => {
  const challenge = makeChallenge();
  const [payload, signature] = challenge.split('.');
  const tamperedSignature = `${signature.slice(0, -1)}${
    signature.endsWith('A') ? 'B' : 'A'
  }`;

  assert.equal(
    verifyChallenge({
      secret: SECRET,
      challenge: `${payload}.${tamperedSignature}`,
      packageName: 'org.ruhenheim.himemo',
      operation: 'unlock',
      nowMs: NOW_MS,
    }).code,
    'invalid-challenge',
  );
  assert.equal(
    verifyChallenge({
      secret: SECRET,
      challenge,
      packageName: 'org.ruhenheim.other',
      operation: 'unlock',
      nowMs: NOW_MS,
    }).code,
    'package-mismatch',
  );
  assert.equal(
    verifyChallenge({
      secret: SECRET,
      challenge,
      packageName: 'org.ruhenheim.himemo',
      operation: 'delete',
      nowMs: NOW_MS,
    }).code,
    'operation-mismatch',
  );
  assert.equal(
    verifyChallenge({
      secret: SECRET,
      challenge,
      packageName: 'org.ruhenheim.himemo',
      operation: 'unlock',
      nowMs: NOW_MS + 60_000,
    }).code,
    'expired-challenge',
  );
});

test('rate limiter enforces a bounded fixed window and then resets', () => {
  let nowMs = NOW_MS;
  const limiter = createRateLimiter({
    windowMs: 1_000,
    now: () => nowMs,
  });

  assert.equal(limiter.isRateLimited('verify:client', 2), false);
  assert.equal(limiter.isRateLimited('verify:client', 2), false);
  assert.equal(limiter.isRateLimited('verify:client', 2), true);

  nowMs += 1_000;
  assert.equal(limiter.isRateLimited('verify:client', 2), false);
});

test('rate-limit keys use the first forwarded address only', () => {
  assert.equal(
    buildRateLimitKey(
      { headers: { 'x-forwarded-for': '203.0.113.1, 10.0.0.2' } },
      'challenge',
    ),
    'challenge:203.0.113.1',
  );
  assert.equal(
    buildRateLimitKey({ ip: '192.0.2.4', headers: {} }, 'verify'),
    'verify:192.0.2.4',
  );
});

test('allowed packages are trimmed, de-duplicated, and environment-scoped', () => {
  const environment = {
    HIMEMO_ALLOWED_ANDROID_PACKAGES:
      'org.example.production, org.example.shared',
    HIMEMO_ALLOWED_ANDROID_DEV_PACKAGES:
      'org.example.dev,org.example.shared',
  };

  assert.deepEqual(getAllowedPackages({}, environment), [
    'org.example.production',
    'org.example.shared',
  ]);
  assert.deepEqual(
    getAllowedPackages({ allowDevelopment: true }, environment),
    ['org.example.production', 'org.example.shared', 'org.example.dev'],
  );
  assert.equal(isDevelopmentPackage('org.example.dev'), true);
  assert.equal(isDevelopmentPackage('org.example.production'), false);
});

test('request timestamp must be numeric, fresh, and inside challenge bounds', () => {
  const issuedAtSeconds = NOW_MS / 1000;
  const expiresAtSeconds = issuedAtSeconds + 60;

  assert.equal(
    verifyRequestTimestamp({
      requestTimestampMillis: `${NOW_MS + 1_000}`,
      issuedAtSeconds,
      expiresAtSeconds,
      nowMs: NOW_MS + 2_000,
    }),
    true,
  );
  assert.equal(
    verifyRequestTimestamp({
      requestTimestampMillis: `${NOW_MS}suffix`,
      issuedAtSeconds,
      expiresAtSeconds,
      nowMs: NOW_MS,
    }),
    false,
  );
  assert.equal(
    verifyRequestTimestamp({
      requestTimestampMillis: `${NOW_MS - 16_000}`,
      issuedAtSeconds,
      expiresAtSeconds,
      nowMs: NOW_MS,
    }),
    false,
  );
  assert.equal(
    verifyRequestTimestamp({
      requestTimestampMillis: `${NOW_MS + 76_000}`,
      issuedAtSeconds,
      expiresAtSeconds,
      nowMs: NOW_MS + 76_000,
    }),
    false,
  );
  assert.equal(
    verifyRequestTimestamp({
      requestTimestampMillis: `${NOW_MS}`,
      issuedAtSeconds,
      expiresAtSeconds,
      nowMs: NOW_MS + 91_000,
    }),
    false,
  );
});

test('string list normalization drops non-string verdicts', () => {
  assert.deepEqual(normalizeStringList(['A', null, 7, 'B']), ['A', 'B']);
  assert.deepEqual(normalizeStringList('A'), []);
});
