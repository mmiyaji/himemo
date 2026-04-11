const { test, expect } = require('@playwright/test');

test('can create a note by using the first line as the title', async ({ page }) => {
  await page.goto('/');
  await enableSemantics(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();

  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.locator('flutter-view')).toContainText('New note');

  await page.getByLabel('Memo').fill(
    'Shopping list\nMilk\nEggs',
  );
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('Shopping list');
  await expect(page.locator('flutter-view')).toContainText('Milk');
  await expect(page.locator('flutter-view')).toContainText('Eggs');
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
