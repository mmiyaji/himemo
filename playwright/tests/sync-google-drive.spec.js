const { test, expect } = require('@playwright/test');

test.describe('fake Google Drive sync', () => {
  test.use({ locale: 'en-US' });

  test('connects, exposes sync controls, and survives repeated status refreshes', async ({
    page,
  }) => {
    await seedApp(page, []);
    await createNoteThroughUi(
      page,
      'Sync E2E primary\nUploaded through the simulator',
    );

    await openSyncSettings(page);
    await connectGoogleDriveSimulator(page);

    await expect(page.locator('flutter-view')).toContainText(
      /Sync now|Send|Re-upload|Get/,
    );

    for (let index = 0; index < 4; index += 1) {
      await clickButton(
        page,
        /Check cloud backup status|Refresh remote|Check remote|^Check$/,
      );
      await expect(page.locator('flutter-view')).toContainText(
        /Google Drive|No remote bundle|completed|No usable sync bundle/i,
      );
    }

    await expect(page.locator('flutter-view')).not.toContainText(
      /Could not access the sql\.js|TypeError|RangeError|Assertion failed/,
    );
  });

  test('empty remote download and rapid disabled-state clicks stay recoverable', async ({
    page,
  }) => {
    await seedApp(page, []);
    await openSyncSettings(page);
    await connectGoogleDriveSimulator(page);

    await clickButton(page, /Get cloud backup|Download bundle|^Get$/);
    await expect(page.locator('flutter-view')).toContainText(
      /Backup and sync|Sync details/,
      { timeout: 20_000 },
    );

    for (let index = 0; index < 6; index += 1) {
      const upload = page
        .getByRole('button', { name: /Send this device backup|Upload bundle|^Send$/ })
        .first();
      if ((await upload.count()) && (await upload.isEnabled())) {
        await upload.click();
      }
      await page.waitForTimeout(80);
    }

    await expect(page.locator('flutter-view')).toContainText(/Backup and sync/);
    await expect(page.getByRole('alertdialog')).toHaveCount(0);
    await expect(page.locator('flutter-view')).not.toContainText(
      /TypeError|RangeError|Assertion failed|Exception/,
    );
  });
});

async function seedApp(page, notes) {
  await page.goto('/');
  await page.evaluate(async (seedNotes) => {
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
    localStorage.setItem('flutter.app.onboarding_completed', JSON.stringify(true));
    localStorage.setItem('flutter.app.onboarding_completed_version', JSON.stringify(2));
    localStorage.setItem('flutter.settings.locale', JSON.stringify('english'));
    localStorage.setItem('flutter.release_notes.last_seen', JSON.stringify('1.0.0+46'));
    localStorage.setItem(
      'flutter.notes.entries.v1',
      JSON.stringify(JSON.stringify(seedNotes)),
    );
  }, notes);
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Backup and sync', {
    timeout: 15_000,
  });
}

async function createNoteThroughUi(page, text) {
  await page.goto('/');
  const addNote = page.getByRole('button', { name: 'Add note' }).first();
  await expect(addNote).toBeVisible({ timeout: 15_000 });
  await addNote.click();
  const discardDraft = page.getByRole('button', { name: /Discard|破棄/ });
  if (await discardDraft.count()) {
    await discardDraft.click();
  }
  const input = page.getByLabel(
    /Use the first line as the title|1行目をタイトルとして使います/,
  );
  await expect(input).toBeVisible();
  await input.click();
  await input.pressSequentially(text);
  await page.getByRole('button', { name: /Create note|ノートを作成/ }).click();
  await expect(page.locator('flutter-view')).toContainText('Sync E2E primary');
}

async function openSyncSettings(page) {
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Backup and sync', {
    timeout: 15_000,
  });
  await clickSettingsSummary(page, /Sync Off|Sync Google Drive|Sync/);
  await expect(page.locator('flutter-view')).toContainText('Selected target');
}

async function connectGoogleDriveSimulator(page) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await clickButton(page, /Google Drive.*sync target/);
    const connect = page.getByRole('button', { name: /Connect simulator/ });
    try {
      await expect(connect.first()).toBeVisible({ timeout: 3000 });
      break;
    } catch (error) {
      if (attempt === 2) {
        throw error;
      }
    }
  }
  await clickButton(page, /Connect simulator/);
  await expect(page.locator('flutter-view')).toContainText(
    /Google Drive app-data sync is connected|Connected as fake-google-drive@example\.test|Sync now|Send/,
    { timeout: 15_000 },
  );
  await clickButton(
    page,
    /Sync details[\s\S]*Review status|同期詳細[\s\S]*状態/,
  );
  await expect(page.locator('flutter-view')).toContainText(
    /Sync now|Check|Send|Get|Re-upload/,
    { timeout: 10_000 },
  );
}

async function clickSettingsSummary(page, name) {
  const summary = page.getByRole('button', { name }).first();
  await summary.scrollIntoViewIfNeeded();
  await expect(summary).toBeVisible();
  await summary.click();
}

async function clickButton(page, name) {
  for (let attempt = 0; attempt < 16; attempt += 1) {
    const button = page.getByRole('button', { name }).first();
    try {
      if ((await button.count()) && (await button.isVisible())) {
        await button.scrollIntoViewIfNeeded();
        await expect(button).toBeEnabled({ timeout: 1000 });
        await button.click();
        return;
      }
    } catch (error) {
      if (!/not attached|detached|Target closed/i.test(String(error))) {
        throw error;
      }
    }
    await page.mouse.wheel(0, 360);
    await page.waitForTimeout(120);
  }
  const button = page.getByRole('button', { name }).first();
  await expect(button).toHaveCount(1);
  await button.click();
}

async function closeDialog(page) {
  const close = page.getByRole('button', { name: /Close|OK|Dismiss/ }).last();
  if (await close.count()) {
    await close.click();
    await expect(page.getByRole('alertdialog')).toHaveCount(0);
    return;
  }
  await page.keyboard.press('Escape');
  await expect(page.getByRole('alertdialog')).toHaveCount(0);
}
