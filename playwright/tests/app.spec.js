const { test, expect } = require('@playwright/test');

test('can complete onboarding and create a quick memo', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.locator('flutter-view')).toContainText('New note');
  await page.getByRole('button', { name: 'Quick memo' }).click();

  const memoInput = page.getByLabel('Memo');
  await expect(memoInput).toBeVisible();
  const memoInputBox = await memoInput.boundingBox();
  expect(memoInputBox).not.toBeNull();
  expect(memoInputBox.height).toBeGreaterThan(220);
  await memoInput.click();
  await memoInput.pressSequentially('Shopping list\nMilk\nEggs');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('opping list');
  await expect(page.locator('flutter-view')).toContainText('Milk');
  await expect(page.locator('flutter-view')).toContainText('Eggs');
});

test('rich memo grows naturally as you type', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await page.getByRole('button', { name: 'Add note' }).click();
  await page.getByRole('button', { name: 'Rich memo' }).click();

  const paragraphInputs = page.getByRole('textbox');
  await paragraphInputs.first().click();
  await paragraphInputs
    .first()
    .pressSequentially('Trip journal\nDay one was quiet and clear.');

  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText(
    'one was quiet and clear.',
  );
});

async function completeOnboarding(page) {
  await page.waitForTimeout(1200);
  const nextButton = page.getByRole('button', { name: 'Next' });
  if (!(await nextButton.count())) {
    return;
  }

  for (let i = 0; i < 3; i += 1) {
    await page.getByRole('button', { name: 'Next' }).click();
    await page.waitForTimeout(250);
  }

  await expect(page.locator('flutter-view')).toContainText('Set initial keys');
  await page.getByRole('button', { name: 'Set PIN' }).click();
  const pinInput = page.getByRole('textbox').first();
  await pinInput.click();
  await pinInput.pressSequentially('1234');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.locator('flutter-view')).toContainText(
    'App unlock PIN saved.',
  );
  await page.getByRole('button', { name: 'Finish setup' }).click();
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
