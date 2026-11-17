// Development sandbox UI test. CloudKit is mocked; no Apple connection occurs.
const { chromium } = require('@playwright/test');
const assert = require('node:assert/strict');

const fakeSdk = `
(() => {
  let resolveSignOut;
  let resolveAccount;
  const signedOut = new Promise(resolve => { resolveSignOut = resolve; });
  window.__sandboxWrites = 0;
  window.__sandboxAccountRequested = false;
  window.__sandboxSignOut = () => resolveSignOut();
  window.__sandboxReleaseAccount = () => resolveAccount && resolveAccount({userRecordName:'sample-account'});
  const database = {
    async saveRecordZones() { window.__sandboxWrites++; throw new Error('Unexpected write'); },
    async saveRecords() { window.__sandboxWrites++; throw new Error('Unexpected write'); },
  };
  const container = {
    privateCloudDatabase: database,
    async setUpAuth() { return {userRecordName:'sample-account'}; },
    fetchCurrentUserIdentity() {
      window.__sandboxAccountRequested = true;
      return window.__sandboxHoldAccount
        ? new Promise(resolve => { resolveAccount = resolve; })
        : Promise.resolve({userRecordName:'sample-account'});
    },
    whenUserSignsIn() { return Promise.resolve({userRecordName:'sample-account'}); },
    whenUserSignsOut() { return signedOut; },
  };
  window.CloudKit = {
    configure(value) { window.__sandboxConfig = value; },
    getDefaultContainer() { return container; },
  };
})();
`;

async function waitState(page, expected) {
  await page.waitForFunction(value => document.documentElement.getAttribute('data-v2-sandbox-state') === value, expected, {timeout: 60000});
}

async function runScenario(browser, baseUrl, holdAccount) {
  const context = await browser.newContext({viewport:{width:1280,height:900},locale:'ja-JP'});
  try {
    const page = await context.newPage();
    const errors = [];
    let appleRequests = 0;
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (request.url().startsWith('https://cdn.apple-cloudkit.com/')) appleRequests++; });
    await page.addInitScript(value => { window.__sandboxHoldAccount = value; }, holdAccount);
    await page.route('https://cdn.apple-cloudkit.com/**', route => route.fulfill({status:200,contentType:'application/javascript',body:fakeSdk}));
    await page.goto(baseUrl, {waitUntil:'domcontentloaded', timeout:90000});
    await waitState(page, 'disconnected');
    await page.waitForTimeout(3000);
    assert.equal(appleRequests, 0, 'Apple SDK must not load before the user chooses to connect');
    // The Flutter canvas is tested at a fixed desktop viewport. Only a dummy
    // API token is entered, and the CDN request is fulfilled by the mock above.
    await page.mouse.click(490, 522);
    await page.keyboard.type('dummy-test-token');
    await page.mouse.click(625, 576);
    await waitState(page, 'connecting');
    await page.waitForFunction(() => window.__sandboxAccountRequested === true, null, {timeout:60000});
    const config = await page.evaluate(() => window.__sandboxConfig);
    assert.equal(config.containers[0].environment, 'development');
    assert.equal(config.containers[0].apiTokenAuth.persist, false);
    assert.equal(appleRequests, 1);
    if (!holdAccount) await waitState(page, 'connected');
    await page.evaluate(() => window.__sandboxSignOut());
    await waitState(page, 'disconnected');
    if (holdAccount) await page.evaluate(() => window.__sandboxReleaseAccount());
    await page.waitForTimeout(1000);
    assert.equal(await page.locator('html').getAttribute('data-v2-sandbox-state'), 'disconnected');
    assert.equal(await page.evaluate(() => window.__sandboxWrites), 0);
    assert.equal(await page.locator('#himemo-v2-sandbox-auth').evaluate(e => e.style.display), 'none');
    assert.deepEqual(errors, []);
  } finally {
    await context.close();
  }
}

(async () => {
  const base = new URL(process.argv[2] || 'http://127.0.0.1:31291/');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('A local preview URL is required');
  const browser = await chromium.launch({headless:true});
  try {
    await runScenario(browser, base.href, false);
    await runScenario(browser, base.href, true);
    console.log('Sandbox UI: explicit connection and sign-out cancellation passed (mock CloudKit).');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
