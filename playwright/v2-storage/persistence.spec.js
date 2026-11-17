const { test, expect, chromium } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');

test('encrypted v2 inbox survives a fresh browser page', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const firstPage = await context.newPage();
    await firstPage.goto('http://127.0.0.1:4187/?phase=write');
    await expect(firstPage).toHaveTitle('V2_STORAGE_WRITE_OK', { timeout: 45_000 });
    await firstPage.close();

    const secondPage = await context.newPage();
    await secondPage.goto('http://127.0.0.1:4187/?phase=read');
    await expect(secondPage).toHaveTitle('V2_STORAGE_READ_OK', { timeout: 45_000 });
  } finally {
    await context.close();
  }
});

test('encrypted v2 data survives a full browser restart', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'himemo-v2-web-'));
  let context;
  try {
    context = await chromium.launchPersistentContext(directory, { headless: true, serviceWorkers: 'block' });
    let page = await context.newPage();
    await page.goto('http://127.0.0.1:4187/?phase=write');
    await expect(page).toHaveTitle('V2_STORAGE_WRITE_OK', { timeout: 45_000 });
    await context.close();
    context = await chromium.launchPersistentContext(directory, { headless: true, serviceWorkers: 'block' });
    page = await context.newPage();
    await page.goto('http://127.0.0.1:4187/?phase=read');
    await expect(page).toHaveTitle('V2_STORAGE_READ_OK', { timeout: 45_000 });
  } finally {
    if (context) await context.close();
    const resolved = path.resolve(directory);
    if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('himemo-v2-web-')) {
      throw new Error('Unexpected temporary profile path');
    }
    fs.rmSync(resolved, { recursive: true, force: true });
  }
});

test('legacy database migration retries after failure without deleting the original', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const open = async (phase, expectedTitle) => {
    const page = await context.newPage();
    page.on('console', (message) => { if (message.text().includes('Web storage probe')) console.log(`[${phase}] ${message.text()}`); });
    await page.goto(`http://127.0.0.1:4187/?phase=${phase}`);
    await expect(page).toHaveTitle(expectedTitle, { timeout: 45_000 });
    return page;
  };
  try {
    const legacy = await open('legacy-write', 'V2_STORAGE_LEGACY_OK');
    const key = 'moor_db_str_himemo_sync_v2_web';
    const original = await legacy.evaluate((name) => localStorage.getItem(name), key);
    expect(original).toBeTruthy();
    await legacy.close();

    const unrelated = await open('other-db', 'V2_STORAGE_OTHER_OK');
    await unrelated.close();

    const failed = await context.newPage();
    await failed.addInitScript(() => {
      const originalGet = Storage.prototype.getItem;
      window.originalStorageGet = originalGet;
      Storage.prototype.getItem = function(key) {
        if (key === 'moor_db_str_himemo_sync_v2_web') throw new Error('simulated migration read failure');
        return originalGet.call(this, key);
      };
    });
    await failed.goto('http://127.0.0.1:4187/?phase=migrate');
    await expect(failed).toHaveTitle('V2_STORAGE_MIGRATION_ERROR', { timeout: 45_000 });
    expect(await failed.evaluate((name) => window.originalStorageGet.call(localStorage, name), key)).toBe(original);
    await failed.close();

    const migrated = await open('migrate', 'V2_STORAGE_MIGRATE_OK');
    expect(await migrated.evaluate((name) => localStorage.getItem(name), key)).toBe(original);
    const migrationMarker = 'himemo.sync-v2.migration.himemo_sync_v2_web_wasm.v1';
    await migrated.evaluate((name) => localStorage.setItem(name, 'pending'), migrationMarker);
    await migrated.close();

    const interrupted = await open('read', 'V2_STORAGE_RECOVERY_REQUIRED');
    expect(await interrupted.evaluate((name) => localStorage.getItem(name), key)).toBe(original);
    await interrupted.evaluate((name) => localStorage.removeItem(name), migrationMarker);
    await interrupted.close();
    const reopened = await open('read', 'V2_STORAGE_READ_OK');
    expect(await reopened.evaluate((name) => localStorage.getItem(name), key)).toBe(original);
  } finally {
    await context.close();
  }
});

test('copies and retains a legacy IndexedDB snapshot', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const digest = (page) => page.evaluate(async () => {
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
      if (!blob) throw new Error('missing legacy snapshot');
      return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())));
    } finally { db.close(); }
  });
  try {
    const oldPage = await context.newPage();
    await oldPage.goto('http://127.0.0.1:4187/?phase=legacy-indexed-write');
    await expect(oldPage).toHaveTitle('V2_STORAGE_LEGACY_INDEXED_OK', { timeout: 45_000 });
    const original = await digest(oldPage);
    await oldPage.close();
    const migrated = await context.newPage();
    await migrated.goto('http://127.0.0.1:4187/?phase=migrate');
    await expect(migrated).toHaveTitle('V2_STORAGE_MIGRATE_OK', { timeout: 45_000 });
    expect(await digest(migrated)).toEqual(original);
  } finally {
    await context.close();
  }
});

test('different legacy snapshots are kept and are never silently merged', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const legacyKey = 'moor_db_str_himemo_sync_v2_web';
  try {
    const local = await context.newPage();
    await local.goto('http://127.0.0.1:4187/?phase=legacy-write');
    await expect(local).toHaveTitle('V2_STORAGE_LEGACY_OK', { timeout: 45_000 });
    const localValue = await local.evaluate((key) => localStorage.getItem(key), legacyKey);
    await local.close();
    const indexed = await context.newPage();
    await indexed.goto('http://127.0.0.1:4187/?phase=legacy-indexed-write');
    await expect(indexed).toHaveTitle('V2_STORAGE_LEGACY_INDEXED_OK', { timeout: 45_000 });
    await indexed.close();
    const migrate = await context.newPage();
    await migrate.goto('http://127.0.0.1:4187/?phase=migrate');
    await expect(migrate).toHaveTitle('V2_STORAGE_RECOVERY_REQUIRED', { timeout: 45_000 });
    expect(await migrate.evaluate((key) => localStorage.getItem(key), legacyKey)).toBe(localValue);
    const indexedStillPresent = await migrate.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('moor_databases');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      try {
        return await new Promise((resolve, reject) => {
          const request = db.transaction('moor_databases').objectStore('moor_databases').get('himemo_sync_v2_web');
          request.onsuccess = () => resolve(Boolean(request.result));
          request.onerror = () => reject(request.error);
        });
      } finally { db.close(); }
    });
    expect(indexedStillPresent).toBe(true);
  } finally { await context.close(); }
});

test('v2 database is exclusive across tabs and isolated from preview', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const holder = await context.newPage();
    await holder.goto('http://127.0.0.1:4187/?phase=hold');
    await expect(holder).toHaveTitle('V2_STORAGE_LOCK_HELD', { timeout: 45_000 });

    const competing = await context.newPage();
    await competing.goto('http://127.0.0.1:4187/?phase=read');
    await expect(competing).toHaveTitle('V2_STORAGE_LOCKED', { timeout: 45_000 });
    await competing.close();

    const preview = await context.newPage();
    await preview.goto('http://127.0.0.1:4187/?phase=preview-write');
    await expect(preview).toHaveTitle('V2_STORAGE_PREVIEW_OK', { timeout: 45_000 });
    await preview.close();

    await holder.close();
    const reopened = await context.newPage();
    await reopened.goto('http://127.0.0.1:4187/?phase=read');
    await expect(reopened).toHaveTitle('V2_STORAGE_READ_OK', { timeout: 45_000 });
  } finally {
    await context.close();
  }
});

test('a new executor in the same tab waits for the previous close', async ({ page }) => {
  await page.goto('http://127.0.0.1:4187/?phase=same-tab-reopen');
  await expect(page).toHaveTitle('V2_STORAGE_SAME_TAB_OK', { timeout: 45_000 });
});

test('a same-tab reopen waits longer than five seconds for an in-flight close', async ({ page }) => {
  await page.goto('http://127.0.0.1:4187/?phase=same-tab-slow-close');
  await expect(page).toHaveTitle('V2_STORAGE_SAME_TAB_OK', { timeout: 45_000 });
});

test('an existing backend marker is not rewritten for every query', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const writer = await context.newPage();
    await writer.goto('http://127.0.0.1:4187/?phase=write');
    await expect(writer).toHaveTitle('V2_STORAGE_WRITE_OK', { timeout: 45_000 });
    await writer.close();
    const reader = await context.newPage();
    await reader.addInitScript(() => {
      const set = Storage.prototype.setItem;
      Storage.prototype.setItem = function(key, value) {
        if (key === 'himemo.sync-v2.backend.himemo_sync_v2_web_wasm.v1') {
          throw new Error('simulated marker quota');
        }
        return set.call(this, key, value);
      };
    });
    await reader.goto('http://127.0.0.1:4187/?phase=read');
    await expect(reader).toHaveTitle('V2_STORAGE_READ_OK', { timeout: 45_000 });
  } finally { await context.close(); }
});

test('the first backend marker write failure is reported without hiding it', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const page = await context.newPage();
    await page.addInitScript(() => {
      const set = Storage.prototype.setItem;
      Storage.prototype.setItem = function(key, value) {
        if (key === 'himemo.sync-v2.backend.himemo_sync_v2_web_wasm.v1') {
          throw new Error('simulated marker quota');
        }
        return set.call(this, key, value);
      };
    });
    await page.goto('http://127.0.0.1:4187/?phase=write');
    await expect(page).toHaveTitle('V2_STORAGE_MARKER_ERROR', { timeout: 45_000 });
    expect(await page.evaluate(() => localStorage.getItem('himemo.sync-v2.migration.himemo_sync_v2_web_wasm.v1'))).toBe('creating');
  } finally { await context.close(); }
});

test('an unavailable previously chosen backend never falls back to an empty database', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const writer = await context.newPage();
    await writer.goto('http://127.0.0.1:4187/?phase=write');
    await expect(writer).toHaveTitle('V2_STORAGE_WRITE_OK', { timeout: 45_000 });
    const key = 'himemo.sync-v2.backend.himemo_sync_v2_web_wasm.v1';
    const actual = await writer.evaluate((name) => localStorage.getItem(name), key);
    expect(['indexedDb', 'opfs']).toContain(actual);
    const other = actual === 'indexedDb' ? 'opfs' : 'indexedDb';
    await writer.evaluate(([name, value]) => localStorage.setItem(name, value), [key, other]);
    await writer.close();

    const blocked = await context.newPage();
    await blocked.goto('http://127.0.0.1:4187/?phase=read');
    await expect(blocked).toHaveTitle('V2_STORAGE_BACKEND_UNAVAILABLE', { timeout: 45_000 });
    await blocked.evaluate(([name, value]) => localStorage.setItem(name, value), [key, actual]);
    await blocked.close();
    const reopened = await context.newPage();
    await reopened.goto('http://127.0.0.1:4187/?phase=read');
    await expect(reopened).toHaveTitle('V2_STORAGE_READ_OK', { timeout: 45_000 });
  } finally { await context.close(); }
});

test('v2 database fails closed without Web Locks', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const page = await context.newPage();
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'locks', { configurable: true, value: undefined });
    });
    await page.goto('http://127.0.0.1:4187/?phase=write');
    await expect(page).toHaveTitle('V2_STORAGE_NO_LOCKS', { timeout: 45_000 });
  } finally {
    await context.close();
  }
});

test('uncertain worker startup keeps the lock until the owning tab closes', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const failed = await context.newPage();
    await failed.addInitScript(() => {
      const send = MessagePort.prototype.postMessage;
      MessagePort.prototype.postMessage = function(message, ...rest) {
        if (message?.type === 'ServeDriftDatabase' && message.payload?.database === 'himemo_sync_v2_web_wasm') {
          throw new Error('injected worker-startup failure');
        }
        return send.call(this, message, ...rest);
      };
    });
    await failed.goto('http://127.0.0.1:4187/?phase=write');
    await expect(failed).toHaveTitle('V2_STORAGE_WORKER_UNCERTAIN', { timeout: 45_000 });
    const held = await failed.evaluate(async () => (await navigator.locks.query()).held);
    expect(held.filter((lock) => lock.name.includes('himemo_sync_v2_web_wasm'))).toHaveLength(1);

    const competing = await context.newPage();
    await competing.goto('http://127.0.0.1:4187/?phase=write');
    await expect(competing).toHaveTitle('V2_STORAGE_LOCKED', { timeout: 45_000 });
    await competing.close();
    await failed.close();

    const retry = await context.newPage();
    await retry.goto('http://127.0.0.1:4187/?phase=write');
    await expect(retry).toHaveTitle('V2_STORAGE_WRITE_OK', { timeout: 45_000 });
  } finally { await context.close(); }
});

test('v2 database rejects a browser without safe persistent storage', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  try {
    const page = await context.newPage();
    await page.addInitScript(() => {
      Object.defineProperty(window, 'SharedWorker', { configurable: true, value: undefined });
    });
    await page.goto('http://127.0.0.1:4187/?phase=write');
    await expect(page).toHaveTitle('V2_STORAGE_UNSUPPORTED', { timeout: 45_000 });
    const held = await page.evaluate(async () => (await navigator.locks.query()).held);
    expect(held.filter((lock) => lock.name.includes('himemo_sync_v2_web_wasm'))).toHaveLength(0);
  } finally {
    await context.close();
  }
});

test('failed database initialization releases its lock and preserves old data', async ({ browser }) => {
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const key = 'moor_db_str_himemo_sync_v2_web';
  try {
    const seed = await context.newPage();
    await seed.goto('http://127.0.0.1:4187/?phase=other-db');
    await expect(seed).toHaveTitle('V2_STORAGE_OTHER_OK', { timeout: 45_000 });
    await seed.evaluate((name) => localStorage.setItem(name, 'invalid sqlite fixture'), key);
    await seed.close();

    const failed = await context.newPage();
    await failed.goto('http://127.0.0.1:4187/?phase=migrate');
    await expect(failed).toHaveTitle('V2_STORAGE_CORRUPT_LEGACY', { timeout: 45_000 });
    expect(await failed.evaluate((name) => localStorage.getItem(name), key)).toBe('invalid sqlite fixture');
    const held = await failed.evaluate(async () => (await navigator.locks.query()).held);
    expect(held.filter((lock) => lock.name.includes('himemo_sync_v2_web_wasm'))).toHaveLength(0);
    await failed.close();

    const retry = await context.newPage();
    await retry.goto('http://127.0.0.1:4187/?phase=migrate');
    await expect(retry).toHaveTitle('V2_STORAGE_CORRUPT_LEGACY', { timeout: 45_000 });
    expect(await retry.evaluate((name) => localStorage.getItem(name), key)).toBe('invalid sqlite fixture');
  } finally {
    await context.close();
  }
});
