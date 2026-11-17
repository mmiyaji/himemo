const { test, expect } = require('@playwright/test');
const fs = require('fs');

async function openFixture(context, phase, expected) {
  const page = await context.newPage();
  await page.goto(`/?phase=${phase}`);
  await expect(page).toHaveTitle(expected, { timeout: 45_000 });
  return page;
}

async function openRecovery(context) {
  const page = await context.newPage();
  await page.goto('/recovery/');
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached', timeout: 45_000 });
  await placeholder.evaluate((element) => element.click());
  return page;
}

async function legacyIndexed(page) {
  return Buffer.from(await page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('moor_databases');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    try {
      const blob = await new Promise((resolve, reject) => {
        const request = db.transaction('moor_databases').objectStore('moor_databases').get('himemo_sync_v2_web');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      return Array.from(new Uint8Array(await blob.arrayBuffer()));
    } finally { db.close(); }
  }));
}

async function downloadCopy(page, index) {
  const pending = page.waitForEvent('download');
  await page.getByRole('button', { name: '書き出す' }).nth(index).click();
  const download = await pending;
  const buffer = fs.readFileSync(await download.path());
  expect(buffer.subarray(0, 16).toString('binary')).toBe('SQLite format 3\0');
  expect(buffer.includes(Buffer.from('v2-browser-persistence-fixture'))).toBe(false);
  return buffer;
}

test('explicitly exports each encrypted copy without modifying any source', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block', acceptDownloads: true });
  try {
    let page = await openFixture(context, 'write', 'V2_STORAGE_WRITE_OK');
    const marker = await page.evaluate(() => localStorage.getItem('himemo.sync-v2.backend.himemo_sync_v2_web_wasm.v1'));
    await page.close();
    page = await openFixture(context, 'legacy-write', 'V2_STORAGE_LEGACY_OK');
    const legacyLocal = Buffer.from(await page.evaluate(() => Array.from(localStorage.getItem('moor_db_str_himemo_sync_v2_web'), (ch) => ch.charCodeAt(0))));
    await page.close();
    page = await openFixture(context, 'legacy-indexed-write', 'V2_STORAGE_LEGACY_INDEXED_OK');
    const legacyDb = await legacyIndexed(page);
    await page.close();

    const recovery = await openRecovery(context);
    await expect(recovery.getByRole('group', { name: /旧ブラウザー保存領域/ })).toBeVisible({ timeout: 45_000 });
    await expect(recovery.getByRole('group', { name: /旧IndexedDB/ })).toBeVisible();
    await expect(recovery.getByRole('group', { name: /新IndexedDB/ })).toBeVisible();
    await expect(recovery.getByRole('button', { name: '書き出す' })).toHaveCount(3);
    expect(await downloadCopy(recovery, 0)).toEqual(legacyLocal);
    expect(await downloadCopy(recovery, 1)).toEqual(legacyDb);
    const wasmFirst = await downloadCopy(recovery, 2);
    const wasmSecond = await downloadCopy(recovery, 2);
    expect(wasmSecond).toEqual(wasmFirst);
    expect(await legacyIndexed(recovery)).toEqual(legacyDb);
    expect(await recovery.evaluate(() => localStorage.getItem('himemo.sync-v2.backend.himemo_sync_v2_web_wasm.v1'))).toBe(marker);
    expect(await recovery.locator('body').innerText()).not.toContain('v2-browser-persistence-fixture');
    await recovery.close();
    page = await openFixture(context, 'migrate', 'V2_STORAGE_MIGRATE_OK');
    await page.close();
  } finally { await context.close(); }
});

test('recovery refuses to inspect while another tab owns the database', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const holder = await openFixture(context, 'hold', 'V2_STORAGE_LOCK_HELD');
    const recovery = await openRecovery(context);
    await expect(recovery.getByText('V2を開いている他のタブを閉じ、この画面で再確認してください。')).toBeVisible({ timeout: 45_000 });
    await expect(recovery.getByRole('button', { name: '書き出す' })).toHaveCount(0);
    await holder.close();
    await recovery.getByRole('button', { name: '再確認' }).click();
    await expect(recovery.getByRole('button', { name: '書き出す' })).toHaveCount(1, { timeout: 45_000 });
  } finally { await context.close(); }
});

test('recovery refuses access if Web Locks are unavailable', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const page = await context.newPage();
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'locks', { configurable: true, value: undefined });
    });
    await page.goto('/recovery/');
    const placeholder = page.locator('flt-semantics-placeholder');
    await placeholder.waitFor({ state: 'attached', timeout: 45_000 });
  await placeholder.evaluate((element) => element.click());
    await expect(page.getByText('確認できませんでした。このブラウザーでは安全に読み出せない可能性があります。')).toBeVisible({ timeout: 45_000 });
    await expect(page.getByRole('button', { name: '書き出す' })).toHaveCount(0);
  } finally { await context.close(); }
});
