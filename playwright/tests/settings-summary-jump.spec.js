const { test, expect } = require('@playwright/test');

test.describe('settings summary jumps', () => {
  test('mobile summary items expand and align each target section', async ({
    page,
  }) => {
    await openSettings(page);

    await clickSummary(page, /Theme Light/);
    await expectSectionExpanded(
      page,
      /Appearance/,
      'Choose the font used across notes',
    );

    await clickSummary(page, /Sync Off/);
    await expectSectionExpanded(page, /Backup and sync/, 'Selected target');

    await clickSummary(page, /App lock Disabled/);
    await expectSectionExpanded(page, /App security/, 'Set PIN');

    await clickSummary(page, /Profile Normal notes/);
    await expectSectionExpanded(page, /Private profiles/, 'Add profile');
  });

  test('mobile summary jump remains aligned when another long section is already open', async ({
    page,
  }) => {
    await openSettings(page);

    await clickSummary(page, /Theme Light/);
    await expectSectionExpanded(
      page,
      /Appearance/,
      'Choose the font used across notes',
    );

    await clickSummary(page, /Sync Off/);
    await expectSectionExpanded(page, /Backup and sync/, 'Selected target');

    await clickSummary(page, /App lock Disabled/);
    await expectSectionExpanded(page, /App security/, 'Session status');
  });

  test.describe('desktop viewport', () => {
    test.use({ viewport: { width: 1280, height: 900 } });

    test('desktop summary items work after several sections are expanded', async ({
      page,
    }) => {
      await openSettings(page);

      await clickSummary(page, /Profile Normal notes/);
      await expectSectionExpanded(page, /Private profiles/, 'Enter admin mode');

      await clickSummary(page, /Theme Light/);
      await expectSectionExpanded(
        page,
        /Appearance/,
        'Choose the font used across notes',
      );

      await clickSummary(page, /Sync Off/);
      await expectSectionExpanded(page, /Backup and sync/, 'Selected target');
    });
  });
});

async function openSettings(page) {
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
    localStorage.setItem('flutter.app.onboarding_completed', 'true');
    localStorage.setItem('flutter.app.onboarding_completed_version', '2');
    localStorage.setItem('flutter.settings.locale', '"english"');
    localStorage.setItem('flutter.release_notes.last_seen', '"1.0.0+46"');
  });
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Profile', {
    timeout: 15000,
  });
  await expect(page.getByRole('button', { name: /Profile Normal notes/ })).toBeVisible();
}

async function clickSummary(page, name) {
  const summary = page.getByRole('button', { name }).first();
  await summary.scrollIntoViewIfNeeded();
  await expect(summary).toBeVisible();
  await summary.click();
}

async function expectSectionExpanded(page, heading, expandedText) {
  const section = await visibleSection(page, heading);
  await expect(section).toBeVisible();
  await expect(page.locator('flutter-view')).toContainText(expandedText);

  await expect
    .poll(
      async () => {
        const box = await section.boundingBox();
        return box ? box.y : Number.POSITIVE_INFINITY;
      },
      { timeout: 5000 },
    )
    .toBeLessThanOrEqual(430);

  const box = await section.boundingBox();
  expect(box).not.toBeNull();
  expect(box.y).toBeGreaterThanOrEqual(50);
}

async function visibleSection(page, heading) {
  const button = page.getByRole('button', { name: heading }).first();
  if ((await button.count()) && (await button.isVisible())) {
    return button;
  }

  const group = page.getByRole('group', { name: heading }).first();
  await expect(group).toBeVisible();
  return group;
}
