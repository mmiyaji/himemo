const { test, expect } = require('@playwright/test');

test('can complete onboarding and create a quick memo', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await expect(page.getByRole('button', { name: 'Add note' })).toBeVisible();
  await openEditor(page, 'Quick memo');

  const memoInput = editorTextInput(page);
  await expect(memoInput).toBeVisible();
  const memoInputBox = await memoInput.boundingBox();
  expect(memoInputBox).not.toBeNull();
  expect(memoInputBox.height).toBeGreaterThan(90);
  expect(memoInputBox.height).toBeLessThan(180);
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

  await openEditor(page, 'Rich memo');

  const paragraphInput = editorTextInput(page);
  await paragraphInput.click();
  await paragraphInput.pressSequentially('Trip journal\nDay one was quiet and clear.');

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

  await openEditor(page, 'Rich memo');
  const paragraphInput = editorTextInput(page);
  await paragraphInput.click();
  await paragraphInput.pressSequentially('Draft note\nKeep this around');
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
  const discardDraft = page.getByRole('button', { name: /Discard|破棄/ });
  if (await discardDraft.count()) {
    await discardDraft.click();
  }
  await selectEditorMode(page, 'Quick memo');
  const memoInput = editorTextInput(page);
  await memoInput.click();
  await memoInput.pressSequentially('Tagged note\nAlpha body');

  const tagInput = page.getByLabel(/Add a tag|タグを追加/);
  await tagInput.fill('alpha');
  await tagInput.press('Enter');

  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();
  await expectNoteCard(page, /Tagged note Alpha body/);

  await page.getByLabel(/Search|検索/).fill('alpha');
  await expectNoteCard(page, /Tagged note Alpha body/);
});

test('web audio recording can start and attach with microphone permission', async ({
  context,
  page,
}) => {
  await page.goto('/');
  await context.grantPermissions(['microphone'], {
    origin: new URL(page.url()).origin,
  });
  await waitForApp(page);
  await completeOnboarding(page);
  await expect
    .poll(
      async () =>
        page.evaluate(
          async () =>
            (await navigator.permissions.query({ name: 'microphone' })).state,
        ),
      { timeout: 10_000 },
    )
    .toBe('granted');

  await openEditor(page, 'Quick memo');
  await page.getByRole('button', { name: /Capture or record|撮影・録音/ }).click();
  await page.getByRole('menuitem', { name: 'Record audio' }).click();

  await expect(page.getByRole('alertdialog')).toContainText('Record audio memo');
  await page.getByRole('button', { name: 'Start recording' }).click();
  await expect(page.getByRole('button', { name: 'Stop and attach' })).toBeVisible({
    timeout: 20_000,
  });
  await expect(page.getByRole('alertdialog')).toContainText('00:01', {
    timeout: 10_000,
  });
  await page.getByRole('button', { name: 'Stop and attach' }).click();
  await expect(page.getByRole('alertdialog')).toHaveCount(0, { timeout: 20_000 });
  await expect(page.getByRole('button', { name: /Create note|ノートを作成/ })).toBeEnabled();
  await expect(page.getByRole('button', { name: /Remove block|ブロックを削除/ })).toBeVisible();
});

test('private profile unlock and relock work from the app bar', async ({
  page,
}) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await activateTabIndex(page, 3);
  await expandSettingsSection(page, /Private profiles|プライベートプロファイル/);
  await page.getByRole('button', { name: /Add profile|プロファイルを追加/ }).click();
  await page.getByLabel(/Profile name|プロフィール名/).fill('Cover profile');
  await page.getByLabel(/Profile password|プロフィールパスワード/).fill('cover-pass-123');
  await page.getByLabel(/Confirm password|パスワードを確認/).fill('cover-pass-123');
  await page.getByRole('button', { name: /Add|追加/ }).click();
  await expect(page.locator('flutter-view')).toContainText(
    /Viewing Cover profile|Cover profile を表示中/,
  );
  await page
    .getByRole('button', {
      name: /Viewing .*|Switch private access|.+ を表示中/,
    })
    .click();
  await page.getByRole('button', { name: /Lock|閉じる/ }).click();

  await activateTabIndex(page, 0);
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByRole('switch', { name: /Save to private profile|プライベートプロファイルに保存/ })).toHaveCount(0);
  await page.getByRole('button', { name: /Cancel|キャンセル/ }).click();

  await page.getByRole('button', {
    name: /Unlock private profile|プライベートプロファイルを開く|Switch private access/,
  }).click();
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
    await expect(page.locator('flutter-view')).toContainText('Appearance (language, font, and color)');
    await expect(page.locator('flutter-view')).toContainText('Memo settings');
    await expect(page.locator('flutter-view')).toContainText('Private profiles');
    await expect(page.locator('flutter-view')).toContainText('App security');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('Calendar');
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
    await expect(page.locator('flutter-view')).toContainText('表示（言語・フォント・カラー）');
    await expect(page.locator('flutter-view')).toContainText('メモ設定');
    await expect(page.locator('flutter-view')).toContainText('プライベートプロファイル');
    await expect(page.locator('flutter-view')).toContainText('アプリ保護');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('カレンダー');
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

function editorTextInput(page) {
  return page.getByLabel(/Use the first line as the title|1行目をタイトルとして使います/);
}

async function openEditor(page, mode) {
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByRole('button', { name: /Create note|ノートを作成/ })).toBeVisible();
  await selectEditorMode(page, mode);
}

async function selectEditorMode(page, mode) {
  const modeButton = page.getByRole('button', {
    name: /Quick memo|Rich memo|クイックメモ|リッチメモ/,
  });
  await expect(modeButton).toBeVisible();
  if ((await modeButton.innerText()).includes(mode)) {
    return;
  }
  await modeButton.click();
  await page.getByRole('menuitem', { name: mode }).click();
  await expect(modeButton).toContainText(mode);
}

async function expandSettingsSection(page, labelPattern) {
  const button = page.getByRole('button', { name: labelPattern });
  if (await button.count()) {
    await button.first().click();
    return;
  }
  const text = page.getByText(labelPattern).first();
  await text.click();
}

async function waitForApp(page) {
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
  await page.reload();
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

async function expectNoteCard(page, name) {
  await expect
    .poll(
      async () =>
        (await page.getByRole('button', { name }).count()) +
        (await page.getByRole('group', { name, includeHidden: true }).count()),
      { timeout: 5000 },
    )
    .toBeGreaterThan(0);
}
