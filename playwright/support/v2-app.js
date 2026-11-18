const { expect } = require('@playwright/test');

async function resetV2App(page, { onboarded = true, locale = 'english', preferences = {} } = {}) {
  // Leave the Flutter document first so its SQLite worker releases IndexedDB.
  await page.goto('/favicon.png');
  await page.evaluate(async ({ onboarded, locale, preferences }) => {
    localStorage.clear();
    sessionStorage.clear();
    const databases = await indexedDB.databases();
    await Promise.all(databases.filter((db) => db.name).map((db) => new Promise((resolve, reject) => {
      const request = indexedDB.deleteDatabase(db.name);
      request.onsuccess = resolve;
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error(`Database remains open: ${db.name}`));
    })));
    const values = {
      'app.onboarding_completed': onboarded,
      'app.onboarding_completed_version': onboarded ? 2 : 0,
      'release_notes.last_seen': '1.0.0+46',
      ...(locale ? { 'settings.locale': locale } : {}),
      ...preferences,
    };
    for (const [key, value] of Object.entries(values)) {
      localStorage.setItem(`flutter.${key}`, JSON.stringify(value));
    }
  }, { onboarded, locale, preferences });
  await page.goto(onboarded ? '/#/settings' : '/');
  await expect(page.locator('flutter-view')).toBeVisible({ timeout: 30_000 });
  if (onboarded) {
    await waitForV2Ready(page, '#/notes');
    await expect(page.getByRole('button', { name: 'Add note' }).first()).toBeVisible();
  }
}

async function waitForV2Ready(page, returnHash = '#/notes') {
  // Onboarding completion still performs an asynchronous router.go('/notes').
  // Wait for the shell, then navigate through it so that redirect has finished.
  const tab = page.getByRole('tab', { name: /^(Settings|設定)$/ });
  const sidebar = page.getByRole('button', { name: /^(Settings|設定)$/ });
  await expect.poll(async () => (await tab.count()) + (await sidebar.count()), { timeout: 30000 }).toBeGreaterThan(0);
  await page.keyboard.press('Escape');
  if (await tab.count()) await tab.click();
  else await sidebar.first().click();
  await expect(page.locator('flutter-view')).toContainText(/Automatic iCloud sync|iCloudで自動同期/, { timeout: 30_000 });
  await page.evaluate((hash) => { location.hash = hash; }, returnHash);
  await expect.poll(() => page.evaluate(() => location.hash)).toBe(returnHash);
}

async function createNotesThroughUi(page, notes) {
  for (const note of notes) {
    await page.getByRole('button', { name: 'Add note' }).first().click();
    const create = page.getByRole('button', { name: 'Create note', exact: true });
    await expect(create).toBeVisible();
    const rich = note.editorMode === 'rich' || note.blocks?.some((block) => block.attachment);
    const mode = rich ? 'Rich memo' : 'Quick memo';
    const modeButton = page.getByRole('button', { name: /Quick memo|Rich memo/ });
    if (!(await modeButton.innerText()).includes(mode)) {
      await modeButton.click();
      await page.getByRole('menuitem', { name: mode, exact: true }).click();
    }
    const paragraphs = note.blocks?.filter((block) => block.type === 'paragraph') || [];
    const hasPhoto = note.blocks?.some((block) => block.type === 'photo');
    const body = hasPhoto ? paragraphs[0]?.text || '' : note.body;
    const firstInput = page.getByRole('textbox').first();
    await firstInput.fill(`${note.title}\n${body || ''}`);
    if (hasPhoto) {
      await page.getByRole('button', { name: 'Import from files', exact: true }).click();
      const chooser = page.waitForEvent('filechooser');
      await page.getByRole('menuitem', { name: 'Pick photo', exact: true }).click();
      const image = note.blocks.find((block) => block.type === 'photo').attachment;
      await (await chooser).setFiles({
        name: image.label || 'fixture.png',
        mimeType: 'image/png',
        buffer: Buffer.from(image.previewBytesBase64, 'base64'),
      });
      const tail = page.getByRole('textbox', { name: '', exact: true }).last();
      await tail.fill(paragraphs.slice(1).map((block) => block.text).join('\n\n'));
    }
    for (const tag of note.tags || []) {
      const input = page.getByLabel('Add a tag', { exact: true });
      await input.fill(tag);
      await input.press('Enter');
    }
    await expect(create).toBeEnabled();
    await create.click();
    await expect(create).toHaveCount(0);
  }
}

module.exports = { resetV2App, waitForV2Ready, createNotesThroughUi };
