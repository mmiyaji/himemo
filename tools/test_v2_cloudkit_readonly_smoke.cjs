'use strict';
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');

const root = path.resolve('build/v2-cloudkit-readonly-probe');
const types = {'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.json':'application/json', '.css':'text/css'};
const server = http.createServer((request, response) => {
  const relative = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) return response.writeHead(403).end();
  fs.readFile(file, (error, data) => error ? response.writeHead(404).end() : response.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'}).end(data));
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true});
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://cdn.apple-cloudkit.com/**', route => route.abort());
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached', timeout:30000});
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByText('CloudKitの開発環境に読み取り専用で接続します。').waitFor();
    await page.getByRole('button', {name:/CloudKit環境/}).click();
    await page.getByRole('menuitem', {name:'本番環境（読み取り専用）'}).click();
    await page.getByText('CloudKit本番環境・読み取り専用').waitFor();
    for (const name of ['編集', '削除', 'インポート', '設定変更']) {
      assert.equal(await page.getByRole('button', {name, exact:true}).count(), 0);
    }
    await page.getByRole('button', {name:'Appleに接続'}).click();
    await page.getByText('CloudKit APIトークンを入力してください。').waitFor();
    assert.equal(errors.length, 0, errors.join('\n'));
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0);
    console.log('Standalone read-only entry starts; no mutation controls, persistent secrets or page errors.');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
