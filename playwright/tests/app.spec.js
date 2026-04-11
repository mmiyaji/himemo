const { test, expect } = require('@playwright/test');

test('web shell navigation works with Flutter semantics enabled', async ({
  page,
}) => {
  await page.goto('/');
  await enableSemantics(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();
  await expect(page.locator('flutter-view')).toContainText('Daily View');

  await page.getByRole('tab', { name: 'Settings' }).click();
  await expect(page.locator('flutter-view')).toContainText(
    'Manage lock profiles, sync, and display policy.',
  );
  await expect(page.locator('flutter-view')).toContainText('Dark');

  await page.getByRole('tab', { name: 'Notes' }).click();
  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();

  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.locator('flutter-view')).toContainText('New note');
  await expect(page.getByRole('button', { name: 'Cancel' })).toBeVisible();
  await page.getByRole('button', { name: 'Cancel' }).click();

  await page.getByRole('tab', { name: 'Calendar' }).click();
  await expect(page.locator('flutter-view')).toContainText(
    'Review notes grouped by day',
  );
});

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', {
    state: 'attached',
    timeout: 15000,
  });
  await page.locator('flt-semantics-placeholder').evaluate((element) => {
    element.click();
  });
  await page.waitForSelector('flt-semantics[role="button"]', { timeout: 15000 });
}
