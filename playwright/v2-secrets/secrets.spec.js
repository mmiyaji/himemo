const { test, expect } = require('@playwright/test');
const crypto = require('crypto');

const account = 'web-probe-account';
const generation = 'web-secrets-probe';
const toUrl = (bytes) => bytes.toString('base64').replaceAll('+', '-').replaceAll('/', '_');
const syncBytes = Buffer.alloc(32, 17);
const adminBytes = Buffer.alloc(32, 73);
const syncCode = toUrl(Buffer.from(JSON.stringify({
  version: 1, account, generation, key: toUrl(syncBytes), format: 'himemo.sync.v2.recovery',
})));
const adminCode = 'himemo-admin-v2:' + toUrl(Buffer.from(JSON.stringify({
  generation, key: adminBytes.toString('base64'),
})));
const secrets = [
  syncCode,
  adminCode,
  syncBytes.toString('base64'),
  adminBytes.toString('base64'),
  'confidential-v2-browser-fixture',
];
const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex');

async function findPersistedSecret(page) {
  return page.evaluate(async ({ strings, rawSync, rawAdmin }) => {
    const encoder = new TextEncoder();
    const textNeedles = strings.map((text) => encoder.encode(text));
    const needles = [...textNeedles, new Uint8Array(rawSync), new Uint8Array(rawAdmin)];
    const contains = (haystack, needle) => {
      outer: for (let i = 0; i <= haystack.length - needle.length; i++) {
        for (let j = 0; j < needle.length; j++) if (haystack[i + j] !== needle[j]) continue outer;
        return true;
      }
      return false;
    };
    const inspect = async (value, location, seen = new WeakSet()) => {
      if (value == null) return null;
      let bytes;
      if (typeof value === 'string') bytes = encoder.encode(value);
      else if (value instanceof Blob) bytes = new Uint8Array(await value.arrayBuffer());
      else if (value instanceof ArrayBuffer) bytes = new Uint8Array(value);
      else if (ArrayBuffer.isView(value)) bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      else if (typeof value === 'object') {
        if (seen.has(value)) return null;
        seen.add(value);
        for (const [key, child] of Object.entries(value)) {
          const foundKey = await inspect(key, `${location}.key`, seen);
          if (foundKey) return foundKey;
          const found = await inspect(child, `${location}.${key}`, seen);
          if (found) return found;
        }
        return null;
      } else return null;
      return needles.some((needle) => contains(bytes, needle)) ? location : null;
    };
    for (const [name, storage] of [['localStorage', localStorage], ['sessionStorage', sessionStorage]]) {
      for (let i = 0; i < storage.length; i++) {
        const key = storage.key(i);
        if (await inspect(key, `${name}.key`) || await inspect(storage.getItem(key), `${name}.value`)) return name;
      }
    }
    for (const entry of await indexedDB.databases()) {
      if (!entry.name) continue;
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open(entry.name);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      try {
        for (const name of db.objectStoreNames) {
          const read = (method) => new Promise((resolve, reject) => {
            const request = db.transaction(name).objectStore(name)[method]();
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
          });
          const [keys, values] = await Promise.all([read('getAllKeys'), read('getAll')]);
          for (const value of [...keys, ...values]) {
            const found = await inspect(value, `IndexedDB:${entry.name}/${name}`);
            if (found) return found;
          }
        }
      } finally { db.close(); }
    }
    return null;
  }, { strings: secrets, rawSync: [...syncBytes], rawAdmin: [...adminBytes] });
}

test('memory-only sync and admin credentials are not persisted and clear independently', async ({ page }) => {
  await page.goto('/?phase=save');
  await expect(page).toHaveTitle('V2_SECRETS_ACTIVE', { timeout: 45_000 });
  await expect(page.locator('html')).toHaveAttribute('data-sync-code-hash', sha256(syncCode));
  await expect(page.locator('html')).toHaveAttribute('data-admin-code-hash', sha256(adminCode));
  expect(await findPersistedSecret(page)).toBeNull();

  await page.evaluate(() => document.documentElement.setAttribute('data-v2-secret-command', 'clear'));
  await expect(page).toHaveTitle('V2_SECRETS_CLEARED', { timeout: 45_000 });
  expect(await findPersistedSecret(page)).toBeNull();

  await page.goto('/?phase=verify');
  await expect(page).toHaveTitle('V2_SECRETS_RELOADED', { timeout: 45_000 });
  expect(await findPersistedSecret(page)).toBeNull();
});
