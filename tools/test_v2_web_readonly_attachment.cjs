'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.resolve('build/v2-web-readonly-attachment-probe');
const types = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
};
const server = http.createServer((request, response) => {
  const relative = decodeURIComponent(
    new URL(request.url, 'http://localhost').pathname,
  ).replace(/^\/+/, '') || 'index.html';
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) return response.writeHead(403).end();
  fs.readFile(file, (error, data) =>
    error
      ? response.writeHead(404).end()
      : response
          .writeHead(200, {
            'Content-Type': types[path.extname(file)] || 'application/octet-stream',
          })
          .end(data),
  );
});

(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ acceptDownloads: true });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error') pageErrors.push(`console error: ${message.text()}`);
    });
    page.on('requestfailed', (request) => pageErrors.push(`request failed: ${request.url()} ${request.failure()?.errorText}`));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
    await page.locator('flt-semantics-placeholder').evaluate((element) => element.click());
    await page.waitForFunction(
      () => document.documentElement.hasAttribute('data-fixture-ready') ||
        document.documentElement.hasAttribute('data-fixture-error'),
      null,
      { timeout: 90000 },
    );
    const fixtureError = await page.evaluate(() =>
      document.documentElement.getAttribute('data-fixture-error'),
    );
    if (fixtureError) {
      console.error('Fixture failure:', fixtureError);
      console.error('Page errors:', pageErrors);
      throw new Error('Synthetic fixture initialization failed.');
    }
    await page.getByText('Private stale attachment', { exact: true }).waitFor({ timeout: 30000 });
    await page.screenshot({ path: '.codex/v2-web-temp/readonly-attachment.png' });
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: '添付をダウンロード' }).click();
    const download = await downloadPromise;
    assert.equal(download.suggestedFilename(), 'synthetic-attachment.png');
    const saved = await download.path();
    assert.ok(saved);
    const expected = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      'base64',
    );
    assert.deepEqual(fs.readFileSync(saved), expected);
    await page.getByRole('button', { name: 'Reverify synthetic ADMIN' }).click();
    await page.getByText('メモを選択してください').waitFor({ timeout: 30000 });
    assert.equal(await page.getByText('Private stale attachment').count(), 0);
    for (const forbidden of ['編集', '削除', 'インポート']) {
      assert.equal(await page.getByRole('button', { name: forbidden, exact: true }).count(), 0);
    }
    assert.equal(pageErrors.length, 0, pageErrors.join('\n'));
    console.log('Synthetic V2 fixture image rendered; readonly download bytes match exactly.');
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
