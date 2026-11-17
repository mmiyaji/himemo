'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const files = new Map([
  ['/tools/cloudkit_v2_probe.html', ['tools/cloudkit_v2_probe.html','text/html; charset=utf-8']],
  ['/tools/cloudkit_v2_probe.js', ['tools/cloudkit_v2_probe.js','application/javascript; charset=utf-8']],
  ['/web/sync_v2_cloudkit.js', ['web/sync_v2_cloudkit.js','application/javascript; charset=utf-8']],
]);

test('probe explains missing configuration and uses read-only Apple connection', async () => {
  const server = http.createServer((request, response) => {
    const entry = files.get(new URL(request.url, 'http://localhost').pathname);
    if (!entry) { response.writeHead(404).end(); return; }
    response.writeHead(200, {'content-type':entry[1], 'cache-control':'no-store'});
    fs.createReadStream(path.join(root,entry[0])).pipe(response);
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true});
    const page = await browser.newPage();
    const consoleOutput = [];
    page.on('console', message => consoleOutput.push(message.text()));
    page.on('pageerror', error => consoleOutput.push(error.message));
    await page.route('https://cdn.apple-cloudkit.com/**', route => route.fulfill({status:200, contentType:'application/javascript',body:`
      window.CloudKit = {
        configure(config) { window.testEnvironment = config.containers[0].environment; },
        getDefaultContainer() { return {
          privateCloudDatabase: {
            async fetchRecords(id, options) { return {hasErrors:false, records:[{recordName:id,recordType:'HiMemoSyncV2Change',fields:{encryptedHeader:{value:'private-ciphertext'}}}]}; },
            saveRecords() { throw Error('write attempted'); },
            saveRecordZones() { throw Error('write attempted'); }
          },
          async setUpAuth() { return {userRecordName:'private-account'}; },
          async fetchCurrentUserIdentity() { return {userRecordName:'private-account'}; },
          whenUserSignsOut() { return new Promise(() => {}); }
        }; }
      };
    `}));
    await page.goto(`http://127.0.0.1:${server.address().port}/tools/cloudkit_v2_probe.html`);
    assert.match(await page.locator('#status').innerText(), /APIトークンを入力/);
    await page.locator('#connect').click();
    assert.match(await page.locator('#status').innerText(), /APIトークンを入力/);
    assert.equal(await page.locator('#environment').inputValue(), 'development');
    await page.locator('#token').fill('test-token-secret');
    await page.locator('#connect').click();
    await page.locator('#check:not([disabled])').waitFor();
    assert.equal(await page.locator('#token').inputValue(), '');
    assert.equal(await page.evaluate(() => window.testEnvironment), 'development');
    await page.locator('#check').click();
    await page.getByText('暗号化同期の登録情報を読み取れました。内容は表示していません。').waitFor();
    const body = await page.locator('body').innerText();
    assert.doesNotMatch(body, /test-token-secret|private-account|private-ciphertext/);
    assert.doesNotMatch(consoleOutput.join('\n'), /test-token-secret|private-account|private-ciphertext/);
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0);
    await page.locator('#disconnect').click();
    assert.match(await page.locator('#status').innerText(), /ローカル接続を解除/);
    assert.equal(await page.locator('#check').isDisabled(), true);

    const missing = await browser.newPage();
    await missing.route('https://cdn.apple-cloudkit.com/**', route => route.abort());
    await missing.goto(`http://127.0.0.1:${server.address().port}/tools/cloudkit_v2_probe.html`);
    await missing.locator('#token').fill('test-token-secret');
    await missing.locator('#connect').click();
    assert.match(await missing.locator('#status').innerText(), /CloudKitを読み込めません/);

    const signedOut = await browser.newPage();
    await signedOut.route('https://cdn.apple-cloudkit.com/**', route => route.fulfill({status:200, contentType:'application/javascript',body:`
      let current = null, resolveSignIn;
      const signIn = new Promise(resolve => { resolveSignIn = resolve; });
      window.CloudKit = {
        configure() {},
        getDefaultContainer() { return {
          privateCloudDatabase: {},
          async setUpAuth() {
            const button = document.createElement('button');
            button.textContent = 'Apple sign in';
            button.onclick = () => { current = {userRecordName:'private-account'}; resolveSignIn(current); };
            document.querySelector('#apple-sign-in-button').append(button);
            return null;
          },
          async fetchCurrentUserIdentity() { return current; },
          whenUserSignsIn() { return signIn; },
          whenUserSignsOut() { return new Promise(() => {}); }
        }; }
      };
    `}));
    await signedOut.goto(`http://127.0.0.1:${server.address().port}/tools/cloudkit_v2_probe.html`);
    await signedOut.locator('#token').fill('test-token-secret');
    await signedOut.locator('#connect').click();
    await signedOut.getByText('Appleのサインインボタンからサインインしてください。').waitFor();
    await signedOut.getByRole('button', {name:'Apple sign in'}).click();
    await signedOut.locator('#check:not([disabled])').waitFor();
    assert.doesNotMatch(await signedOut.locator('body').innerText(), /test-token-secret|private-account/);
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
