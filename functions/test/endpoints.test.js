const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { test } = require('node:test');

const {
  issuePlayIntegrityChallengeV2,
  verifyPlayIntegrityV2,
} = require('../index');

class TestResponse extends EventEmitter {
  constructor() {
    super();
    this.headers = {};
    this.statusCode = 200;
    this.body = undefined;
  }

  set(name, value) {
    this.headers[name] = value;
    return this;
  }

  status(statusCode) {
    this.statusCode = statusCode;
    return this;
  }

  json(body) {
    this.body = body;
    this.emit('finish');
    return this;
  }
}

function makeRequest({ method = 'POST', body = {} } = {}) {
  return {
    body,
    headers: {},
    ip: '192.0.2.20',
    method,
    header: () => undefined,
  };
}

for (const [name, endpoint] of [
  ['issue challenge', issuePlayIntegrityChallengeV2],
  ['verify integrity', verifyPlayIntegrityV2],
]) {
  test(`${name} endpoint rejects non-POST requests`, async () => {
    const response = new TestResponse();

    await endpoint(makeRequest({ method: 'GET' }), response);

    assert.equal(response.statusCode, 405);
    assert.equal(response.headers.Allow, 'POST');
    assert.equal(response.body.ok, false);
    assert.equal(response.body.error.code, 'method-not-allowed');
  });

  test(`${name} endpoint requires Firebase App Check`, async () => {
    const response = new TestResponse();

    await endpoint(makeRequest(), response);

    assert.equal(response.statusCode, 401);
    assert.equal(response.body.ok, false);
    assert.equal(response.body.error.code, 'app-check-required');
  });
}
