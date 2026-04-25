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

  await expect(page.locator('flutter-view')).toContainText('one was quiet and clear.');
});

test('advanced search stays folded until needed', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await page.getByRole('button', { name: /Filters|詳細/ }).click();
  await expect(page.getByRole('checkbox', { name: /Pinned only|固定したノートだけ/ })).toBeVisible();
  await page.getByRole('checkbox', { name: /Pinned only|固定したノートだけ/ }).click();
  await expect(page.locator('flutter-view')).toContainText(/Filters|詳細条件/);
});

test('new note draft restores after closing editor', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await page.getByRole('button', { name: 'Add note' }).click();
  await page.getByRole('button', { name: 'Rich memo' }).click();
  const paragraphInputs = page.getByRole('textbox');
  await paragraphInputs.first().click();
  await paragraphInputs.first().pressSequentially('Draft note\nKeep this around');
  await page.waitForTimeout(700);
  await page.getByRole('button', { name: 'Cancel' }).click();
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();
  await expect(page.locator('flutter-view')).toContainText('Draft note');
});

test('tags can be added to a note and found from search', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await page.getByRole('button', { name: 'Add note' }).click();
  await page.getByRole('button', { name: 'Quick memo' }).click();
  await page.getByLabel('Memo').pressSequentially('Tagged note\nAlpha body');

  const tagInput = page.getByLabel(/Add a tag|タグを追加/);
  await tagInput.fill('alpha');
  await tagInput.press('Enter');

  await page.getByRole('button', { name: 'Create note' }).click();
  await expect(page.locator('flutter-view')).toContainText('Tagged note');

  await page.getByLabel(/Search|検索/).fill('alpha');
  await expect(page.locator('flutter-view')).toContainText('Tagged note');
});

test('private profile unlock and relock work from the app bar', async ({
  page,
}) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await activateTabIndex(page, 3);
  await page.getByRole('button', { name: /Add profile|プロファイルを追加/ }).click();
  await page.getByLabel(/Profile name|プロフィール名/).fill('Cover profile');
  await page.getByLabel(/Profile password|プロフィールパスワード/).fill('cover-pass-123');
  await page.getByLabel(/Confirm password|パスワードを確認/).fill('cover-pass-123');
  await page.getByRole('button', { name: /Add|追加/ }).click();
  await expect(page.locator('flutter-view')).toContainText(
    /Private profile added\.|プロファイルを追加しました。|Profile 1/,
  );

  await activateTabIndex(page, 0);
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByRole('checkbox', { name: /Save to private profile|プライベートプロファイルに保存/ })).toHaveCount(0);
  await page.getByRole('button', { name: /Cancel|キャンセル/ }).click();

  await page.getByRole('button', {
    name: /Unlock private profile|プライベートプロファイルを開く|Switch private access/,
  }).click();
  await page.getByLabel(/Profile password|プロフィールパスワード/).fill('cover-pass-123');
  await page.getByRole('button', { name: /Unlock|開く/ }).click();
  await expect(page.locator('flutter-view')).toContainText(
    /Private profile unlocked\.|プライベートプロファイルを開きました。/,
  );
  const unlockedAccessButton = page.getByRole('button', {
    name: /Viewing .*|Switch private access|.+ を表示中/,
  });
  await expect(unlockedAccessButton).toHaveCount(1);

  await unlockedAccessButton.click();
  await page.getByRole('button', { name: /Lock|閉じる/ }).click();
  await expect(page.locator('flutter-view')).not.toContainText(
    /Private profile unlocked\.|プライベートプロファイルを開きました。/,
  );
  await expect(
    page.getByRole('button', {
      name: /Unlock private profile|プライベートプロファイルを開く/,
    }),
  ).toHaveCount(1);
});

test.describe('localized surfaces english', () => {
  test.use({ locale: 'en-US' });

  test('settings, calendar, and insights render in English', async ({ page }) => {
    await page.goto('/');
    await waitForApp(page);
    await completeOnboarding(page);

    await activateTabIndex(page, 3);
    await expect(page.locator('flutter-view')).toContainText('Manage access, sync, and display policy.');
    await expect(page.locator('flutter-view')).toContainText('Add profile');
    await expect(page.locator('flutter-view')).toContainText('Enter admin mode');
    await expect(page.locator('flutter-view')).toContainText('App security');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('Review notes grouped by day');
    await expect(page.getByRole('button', { name: 'Today' })).toBeVisible();

    await activateTabIndex(page, 2);
    await expect(page.locator('flutter-view')).toContainText('Writing activity');
    await expect(page.locator('flutter-view')).toContainText('Current streak');
    await expect(page.locator('flutter-view')).toContainText('This month');
  });
});

test.describe('localized surfaces japanese', () => {
  test.use({ locale: 'ja-JP' });

  test('settings, calendar, and insights render in Japanese', async ({ page }) => {
    await page.goto('/');
    await waitForApp(page);
    await completeOnboarding(page);

    await activateTabIndex(page, 3);
    await expect(page.locator('flutter-view')).toContainText('アクセス、同期、表示ポリシーを管理します。');
    await expect(page.locator('flutter-view')).toContainText('プロファイルを追加');
    await expect(page.locator('flutter-view')).toContainText('管理者モードへ移行');
    await expect(page.locator('flutter-view')).toContainText('アプリ保護');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('日付ごとにノートを振り返り');
    await expect(page.getByRole('button', { name: '今日' })).toBeVisible();

    await activateTabIndex(page, 2);
    await expect(page.locator('flutter-view')).toContainText('記録のまとめ');
    await expect(page.locator('flutter-view')).toContainText('連続記録');
    await expect(page.locator('flutter-view')).toContainText('今月');
  });
});

async function completeOnboarding(page) {
  await page.waitForTimeout(1200);
  const nextCount =
    (await page.getByRole('button', { name: 'Next' }).count()) +
    (await page.getByRole('button', { name: '次へ' }).count());
  if (!nextCount) {
    return;
  }

  for (let i = 0; i < 3; i += 1) {
    const nextButton =
      (await page.getByRole('button', { name: 'Next' }).count())
        ? page.getByRole('button', { name: 'Next' })
        : page.getByRole('button', { name: '次へ' });
    await nextButton.click();
    await page.waitForTimeout(250);
  }

  await expect(page.locator('flutter-view')).toContainText(
    /Finish the basics|最初に基本だけ設定/,
  );
  const setPinButton =
    (await page.getByRole('button', { name: 'Set PIN' }).count())
      ? page.getByRole('button', { name: 'Set PIN' })
      : page.getByRole('button', { name: 'PIN を設定' });
  await setPinButton.click();
  const pinInput = page.getByRole('textbox').first();
  await pinInput.click();
  await pinInput.pressSequentially('1234');
  const saveButton =
    (await page.getByRole('button', { name: 'Save' }).count())
      ? page.getByRole('button', { name: 'Save' })
      : page.getByRole('button', { name: '保存' });
  await saveButton.click();
  await expect(page.locator('flutter-view')).toContainText(/App unlock PIN saved\.|アプリ解除 PIN を保存しました。/);
  const finishButton =
    (await page.getByRole('button', { name: 'Finish setup' }).count())
      ? page.getByRole('button', { name: 'Finish setup' })
      : page.getByRole('button', { name: 'セットアップ完了' });
  await finishButton.click();
}

async function waitForApp(page) {
  await expect
    .poll(
      async () =>
        (await page.getByRole('button', { name: 'Add note' }).count()) +
        (await page.getByRole('button', { name: 'Next' }).count()) +
        (await page.getByRole('button', { name: 'Skip' }).count()) +
        (await page.getByRole('button', { name: '次へ' }).count()) +
        (await page.getByRole('button', { name: 'スキップ' }).count()),
      { timeout: 15000 },
    )
    .toBeGreaterThan(0);
}

async function activateNav(page, labels) {
  for (const label of labels) {
    const tab = page.getByRole('tab', { name: label });
    if (await tab.count()) {
      await tab.click();
      return;
    }
    const button = page.getByRole('button', { name: label });
    if (await button.count()) {
      await button.click();
      return;
    }
    const text = page.getByText(label, { exact: true });
    if (await text.count()) {
      await text.first().click();
      return;
    }
  }
  throw new Error(`Unable to activate navigation: ${labels.join(', ')}`);
}

async function activateTabIndex(page, index) {
  await page.getByRole('tab').nth(index).click();
}
