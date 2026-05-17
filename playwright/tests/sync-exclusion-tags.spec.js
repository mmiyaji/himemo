const { test, expect } = require('@playwright/test');

test.describe('sync exclusion tags', () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test('note detail actions can add and remove the built-in exclusion tag', async ({
    page,
  }) => {
    await seedNotes(page, [
      createNote({
        id: 'e2e-sync-exclusion-detail',
        title: 'Sync exclusion detail',
        body: 'Toggle from note actions',
        syncState: 'pendingUpload',
      }),
    ]);

    await openNoteFromList(page, /Sync exclusion detail/);
    await openNoteActions(page);
    await page
      .getByRole('menuitem', {
        name: /Exclude from cloud sync|同期対象外にする/,
      })
      .click();

    await expect(page.locator('flutter-view')).toContainText(
      /#Local only|#この端末のみ/,
    );

    await openNoteActions(page);
    await page
      .getByRole('menuitem', {
        name: /Allow cloud sync|同期対象に戻す/,
      })
      .click();

    await expect(page.locator('flutter-view')).not.toContainText(
      /#Local only|#この端末のみ/,
    );
  });

  test('editing an existing note can add and remove the exclusion tag', async ({
    page,
  }) => {
    await seedNotes(page, [
      createNote({
        id: 'e2e-sync-exclusion-editor',
        title: 'Sync exclusion editor',
        body: 'Tag is added after the note already exists',
        syncState: 'pendingUpload',
      }),
    ]);

    await openNoteFromList(page, /Sync exclusion editor/);
    await page.getByRole('button', { name: /Edit note|メモを編集/ }).click();
    await addEditorTag(page, 'sync:excluded');
    await page.getByRole('button', { name: /Save changes|変更を保存/ }).click();

    await expect(page.locator('flutter-view')).toContainText(
      /#Local only|#この端末のみ/,
    );

    await page.getByRole('button', { name: /Edit note|メモを編集/ }).click();
    await deleteChipByText(page, 'Local only');
    await page.getByRole('button', { name: /Save changes|変更を保存/ }).click();

    await expect(page.locator('flutter-view')).toContainText(
      /Sync exclusion editor/,
    );
    await expect(page.locator('flutter-view')).not.toContainText(
      /#Local only|#この端末のみ/,
    );
  });
});

function createNote(overrides = {}) {
  const createdAt = '2026-05-17T00:00:00.000Z';
  return {
    id: 'e2e-sync-exclusion-note',
    vaultId: 'everyday',
    title: 'Sync exclusion note',
    body: 'Body',
    createdAt,
    updatedAt: createdAt,
    deletedAt: null,
    archivedAt: null,
    deviceId: 'e2e-device',
    contentHash: null,
    attachments: [],
    blocks: [
      {
        type: 'paragraph',
        text: overrides.body ?? 'Body',
        attachment: null,
      },
    ],
    tags: [],
    isPinned: false,
    revision: 1,
    syncState: 'localOnly',
    editorMode: 'rich',
    location: null,
    ...overrides,
  };
}

async function seedNotes(page, notes) {
  await page.goto('/');
  await page.evaluate(async () => {
    localStorage.clear();
    sessionStorage.clear();
    if (indexedDB.databases) {
      const databases = await indexedDB.databases();
      await Promise.all(
        databases
          .map((database) => database.name)
          .filter(Boolean)
          .map(
            (name) =>
              new Promise((resolve) => {
                const request = indexedDB.deleteDatabase(name);
                request.onsuccess = request.onerror = request.onblocked = resolve;
              }),
          ),
      );
    }
  });
  await page.evaluate((seedNotes) => {
    localStorage.setItem('flutter.app.onboarding_completed', JSON.stringify(true));
    localStorage.setItem('flutter.app.onboarding_completed_version', JSON.stringify(2));
    localStorage.setItem('flutter.release_notes.last_seen', JSON.stringify('1.0.0+46'));
    localStorage.setItem(
      'flutter.notes.entries.v1',
      JSON.stringify(JSON.stringify(seedNotes)),
    );
  }, notes);
  await page.reload();
  await waitForReadySurface(page);
}

async function waitForReadySurface(page) {
  await expect
    .poll(
      async () =>
        (await page.getByRole('button', { name: 'Add note' }).count()) +
        (await page.getByRole('button', { name: 'ノートを追加' }).count()) +
        (await page.getByText(/Settings|設定/).count()),
      { timeout: 15_000 },
    )
    .toBeGreaterThan(0);
}

async function openNoteFromList(page, title) {
  await expectNoteCard(page, title);
  const noteButton = page.getByRole('button', { name: title }).first();
  if (await noteButton.count()) {
    await noteButton.click();
    return;
  }
  await page.getByText(title).first().click();
}

async function expectNoteCard(page, name) {
  await expect
    .poll(
      async () =>
        (await page.getByRole('button', { name }).count()) +
        (await page.getByRole('group', { name, includeHidden: true }).count()) +
        (await page.getByText(name).count()),
      { timeout: 5_000 },
    )
    .toBeGreaterThan(0);
}

async function openNoteActions(page) {
  const actionButton = page.getByRole('button', {
    name: /Note actions|メモ操作/,
  });
  await expect(actionButton).toBeVisible();
  await actionButton.click();
}

async function openSettingsGroup(page, name) {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const groupButton = page.getByRole('button', { name });
    if (await groupButton.count()) {
      await groupButton.first().click();
      return;
    }
    await page.mouse.wheel(0, 420);
    await page.waitForTimeout(150);
  }
  throw new Error(`Unable to open settings group: ${name}`);
}

async function addEditorTag(page, tag) {
  const tagInput = page.getByLabel(/Add a tag|タグを追加/);
  await tagInput.fill(tag);
  await tagInput.press('Enter');
}

async function deleteChipByText(page, text) {
  const chipButton = page.getByRole('button', { name: new RegExp(text) });
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const count = await chipButton.count();
    for (let index = 0; index < count; index += 1) {
      const candidate = chipButton.nth(index);
      if (!(await candidate.isVisible())) {
        continue;
      }
      const box = await candidate.boundingBox();
      if (!box || box.x < 250) {
        continue;
      }
      await candidate.click();
      await page.waitForTimeout(200);
      if ((await page.locator('flutter-view').getByText(text).count()) === 0) {
        return;
      }
    }
    const deleteButton = page.getByRole('button', { name: /Delete|削除|Remove|削除/ });
    if (await deleteButton.count()) {
      const button = deleteButton.first();
      const box = await button.boundingBox();
      if (box) {
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      } else {
        await button.click({ force: true });
      }
      await page.waitForTimeout(200);
      if ((await page.locator('flutter-view').getByText(text).count()) === 0) {
        return;
      }
    }
  }
  throw new Error(`Unable to delete chip: ${text}`);
}
