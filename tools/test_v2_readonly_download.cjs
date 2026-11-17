'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require('playwright');

// This exercises the browser's real Blob URL download path with synthetic
// already-received bytes. It deliberately needs neither CloudKit nor Apple ID.
(async () => {
  const browser = await chromium.launch({ headless: true });
  const output = fs.mkdtempSync(path.join(os.tmpdir(), 'himemo-v2-download-'));
  try {
    const context = await browser.newContext({ acceptDownloads: true });
    const page = await context.newPage();
    await page.setContent('<!doctype html><button id="download">download</button>');
    await page.evaluate(() => {
      window.receivedBytes = new Uint8Array([0, 1, 2, 127, 128, 254, 255]);
      window.activeObjectUrls = new Set();
      document.querySelector('#download').addEventListener('click', () => {
        const blob = new Blob([window.receivedBytes], { type: 'application/octet-stream' });
        const url = URL.createObjectURL(blob);
        window.activeObjectUrls.add(url);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = 'synthetic-attachment.bin';
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
        setTimeout(() => {
          if (window.activeObjectUrls.delete(url)) URL.revokeObjectURL(url);
        }, 1000);
      });
    });
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#download').click();
    const download = await downloadPromise;
    assert.equal(download.suggestedFilename(), 'synthetic-attachment.bin');
    const savedPath = await download.path();
    assert.ok(savedPath);
    assert.deepEqual(fs.readFileSync(savedPath), Buffer.from([0, 1, 2, 127, 128, 254, 255]));
    await page.waitForFunction(() => window.activeObjectUrls.size === 0, null, { timeout: 3000 });
    assert.equal(await page.evaluate(() => window.activeObjectUrls.size), 0);
    console.log('Mock attachment download bytes match; the Blob URL is revoked after download starts.');
  } finally {
    await browser.close();
    fs.rmSync(output, { recursive: true, force: true });
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
