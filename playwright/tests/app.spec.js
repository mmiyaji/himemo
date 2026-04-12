const { test, expect } = require('@playwright/test');

test('can create a note by using the first line as the title', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();

  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.locator('flutter-view')).toContainText('New note');

  await page.getByRole('textbox', { name: 'Memo' }).fill('Shopping list\nMilk\nEggs');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('Shopping list');
  await expect(page.locator('flutter-view')).toContainText('Milk');
  await expect(page.locator('flutter-view')).toContainText('Eggs');
});

test('can create a rich memo with embedded media blocks', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await page.getByRole('button', { name: 'Add note' }).click();
  await page.getByRole('button', { name: 'Rich memo' }).click();

  const textBlocks = page.getByRole('textbox', { name: 'Paragraph' });
  await textBlocks.last().fill('Trip journal');
  await page.getByRole('button', { name: 'Add text' }).click();
  await textBlocks.nth(1).fill('Day one was quiet and clear.');
  await page.keyboard.press('Tab');

  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('Day one was quiet and clear.');
  await page.getByText('Day one was quiet and clear.').first().click();
  await expect(page.locator('flutter-view')).toContainText('Day one was quiet and clear.');
});

async function completeOnboarding(page) {
  await page.waitForTimeout(1400);
  const nextButton = page.getByRole('button', { name: 'Next' });
  if (!(await nextButton.count())) {
    return;
  }

  for (let i = 0; i < 3; i += 1) {
    await page.getByRole('button', { name: 'Next' }).click();
    await page.waitForTimeout(300);
  }

  await expect(page.locator('flutter-view')).toContainText('Set initial keys');
  await page.getByRole('button', { name: 'Set PIN' }).click();
  await page.locator('input[aria-label="PIN"]').fill('1234');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.locator('flutter-view')).toContainText('App unlock PIN saved.');
  const finishButton = page
    .getByRole('button', { name: 'Finish setup' })
    .or(page.getByRole('button', { name: 'Start' }));
  await finishButton.first().click();
}

async function waitForApp(page) {
  await expect
    .poll(
      async () =>
        (await page.getByRole('button', { name: 'Add note' }).count()) +
        (await page.getByRole('button', { name: 'Next' }).count()) +
        (await page.getByRole('button', { name: 'Skip' }).count()),
      { timeout: 15000 },
    )
    .toBeGreaterThan(0);
}
