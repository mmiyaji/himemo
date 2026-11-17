'use strict';
const {chromium} = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const root = path.resolve('build/v2-main-route-check');
const types = {'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json'};
const server = http.createServer((request, response) => {
  const rel = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
  const file = path.resolve(root, rel);
  if (!file.startsWith(root + path.sep)) return response.writeHead(403).end();
  fs.readFile(file, (error, data) => error ? response.writeHead(404).end() : response.writeHead(200, {'Content-Type':types[path.extname(file)] || 'application/octet-stream'}).end(data));
});
(async () => {
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true});
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://cdn.apple-cloudkit.com/**', route => route.fulfill({status:200,contentType:'application/javascript',body:`
      let endSession;
      window.testSignOut = () => endSession();
      window.CloudKit = {
        configure(config) { window.testEnvironment = config.containers[0].environment; },
        getDefaultContainer() { return {
          privateCloudDatabase: {saveRecordZones() { throw Error('write attempted'); }, newRecordsBatch() { throw Error('write attempted'); }},
          async setUpAuth() { return {userRecordName:'mock-account'}; },
          async fetchCurrentUserIdentity() { return {userRecordName:'mock-account'}; },
          whenUserSignsOut() { return new Promise(resolve => { endSession = resolve; }); }
        }; }
      };`}));
    await page.goto(`http://127.0.0.1:${server.address().port}/#/sync-v2-web-readonly`);
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:30000});
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByText('メモへ', {exact:true}).waitFor({timeout:30000});
    await page.getByText('メモへ', {exact:true}).click();
    try { await page.getByText('CloudKit開発環境・読み取り専用').waitFor({timeout:10000}); }
    catch (error) { console.log('URL', page.url(), 'screen', (await page.locator('body').innerText()).slice(0,1500)); throw error; }
    await page.getByRole('button',{name:'Appleに接続'}).click();
    await page.getByText('CloudKit APIトークンを入力してください。').waitFor();
    const tokenField = page.getByLabel('CloudKit APIトークン');
    await tokenField.click();
    await page.keyboard.type('mock-token');
    const tokenInput = await tokenField.evaluate(element => ({
      tag: element.tagName,
      role: element.getAttribute('data-semantics-role'),
      value: element.value,
      focused: document.activeElement === element,
    }));
    assert.equal(tokenInput.tag, 'INPUT');
    assert.equal(tokenInput.role, 'text-field');
    assert.equal(tokenInput.value, 'mock-token');
    assert.equal(tokenInput.focused, true);
    await page.getByRole('button',{name:'Appleに接続'}).click();
    try { await page.getByText('SYNC復旧コードを入力してください。').waitFor({timeout:10000}); }
    catch (error) { console.log('screen', (await page.locator('body').innerText()).slice(0,1200), 'errors', errors); throw error; }
    assert.equal(await page.evaluate(() => window.testEnvironment), 'development');
    assert.equal(await page.evaluate(() => typeof window.himemoCloudKitV2), 'object');
    await page.evaluate(() => window.testSignOut());
    await page.getByText('Apple接続が終了しました。').waitFor();
    assert.equal(await page.locator('#himemo-v2-readonly-auth').evaluate(e => getComputedStyle(e).display), 'none');
    assert.equal(await page.evaluate(() => sessionStorage.length), 0);
    await page.getByRole('button',{name:'設定に戻る'}).click();
    await page.waitForURL(/settings/);
    assert.equal(await page.locator('#himemo-v2-readonly-auth').count(), 0);
    assert.equal(errors.length, 0, errors.join('\n'));
    console.log('Main app read-only route: mock sign-in/sign-out, SDK bridge, and return to settings passed.');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode=1; });
