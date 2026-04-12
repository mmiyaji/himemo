const { test, expect } = require('@playwright/test');

test('can create a note by using the first line as the title', async ({ page }) => {
  await page.goto('/');
  await enableSemantics(page);
  await dismissOnboardingIfNeeded(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();

  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.locator('flutter-view')).toContainText('New note');

  await page.getByLabel('Memo').fill('Shopping list\nMilk\nEggs');
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('Shopping list');
  await expect(page.locator('flutter-view')).toContainText('Milk');
  await expect(page.locator('flutter-view')).toContainText('Eggs');
});

async function dismissOnboardingIfNeeded(page) {
  await page.waitForTimeout(1400);
  const skipButton = page.getByRole('button', { name: 'Skip' });
  if (await skipButton.count()) {
    await skipButton.click();
  }
}

async function enableSemantics(page) {
  const addNoteButton = page.getByRole('button', { name: 'Add note' });
  const accessibilityButton = page.getByRole('button', {
    name: 'Enable accessibility',
  });
  const semanticsPlaceholder = page.locator('flt-semantics-placeholder');

  await expect
    .poll(
      async () =>
        (await addNoteButton.count()) +
        (await accessibilityButton.count()) +
        (await semanticsPlaceholder.count()),
      { timeout: 15000 },
    )
    .toBeGreaterThan(0);

  if (await addNoteButton.count()) {
    return;
  }

  if (await accessibilityButton.count()) {
    await accessibilityButton.evaluate((element) => {
      element.click();
    });
    await expect(page.getByRole('button', { name: 'Skip' })).toBeVisible({
      timeout: 15000,
    });
    return;
  }

  if (await semanticsPlaceholder.count()) {
    await semanticsPlaceholder.evaluate((element) => {
      element.click();
    });
  }

  await expect(
    page
        .getByRole('button', { name: 'Skip' })
        .or(page.getByRole('button', { name: 'Add note' })),
  ).toBeVisible({ timeout: 15000 });
}
