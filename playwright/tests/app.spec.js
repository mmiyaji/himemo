const { test, expect } = require('@playwright/test');
const { resetV2App, waitForV2Ready } = require('../support/v2-app');

test('can complete onboarding and create a quick memo', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await expect(page.getByRole('button', { name: 'Add note' }).first()).toBeVisible();
  await openEditor(page, 'Quick memo');

  const memoInput = editorTextInput(page);
  await expect(memoInput).toBeVisible();
  const memoInputBox = await memoInput.boundingBox();
  expect(memoInputBox).not.toBeNull();
  expect(memoInputBox.height).toBeGreaterThan(90);
  expect(memoInputBox.height).toBeLessThan(180);
  await memoInput.click();
  await memoInput.fill('Shopping list\nMilk\nEggs');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('Shopping list');
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
  await paragraphInput.fill('Trip journal\nDay one was quiet and clear.');

  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expect(page.locator('flutter-view')).toContainText('one was quiet and clear.');
});

test('note list swipe actions reveal pin share and delete controls', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await openEditor(page, 'Quick memo');
  const memoInput = editorTextInput(page);
  await memoInput.click();
  await memoInput.fill('Swipe actions note\nSwipe body');
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();

  await expectNoteCard(page, /Swipe actions note/);
  await expect(page.getByRole('button', { name: /Share|共有/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: /Delete|削除/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: /^Pin$|固定/ })).toHaveCount(0);
  await page.addStyleTag({
    content: 'flt-semantics { pointer-events: none !important; }',
  });
  await swipeNoteTile(page, /Swipe actions note/, 'left');
  await expect(page.getByRole('button', { name: /Share|共有/ }).first()).toBeVisible();
  await expect(page.getByRole('button', { name: /Delete|削除/ }).first()).toBeVisible();

  await swipeNoteTile(page, /Swipe actions note/, 'right');
  await expect(page.getByRole('button', { name: /^Pin$|固定/ }).first()).toBeVisible();
});

test('dark app lock screen renders with a continuous background', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await resetV2App(page, { preferences: { 'settings.theme_mode': 'dark' } });
  await configurePinFromSettings(page, '2468');
  const lockNow = await findRoleButtonByScrolling(page, /Lock the app now/);
  await lockNow.click();
  await expect(page.getByRole('textbox', { name: 'PIN', exact: true })).toBeVisible();

  await page.screenshot({
    path: testInfo.outputPath('dark-app-lock-screen.png'),
    fullPage: false,
  });
});

test('dark app shell uses dark brand icon', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await resetV2App(page, { preferences: { 'settings.theme_mode': 'dark' } });
  await expect(
    page.getByRole('button', { name: 'Add note' }).first(),
  ).toBeVisible({
    timeout: 15000,
  });

  await page.screenshot({
    path: testInfo.outputPath('dark-app-brand-icon.png'),
    fullPage: false,
  });
});

test('setting an unlock PIN enables lock now in settings', async ({ page }) => {
  await resetV2App(page);
  await page.evaluate(() => { location.hash = '#/settings'; });
  await expandSettingsSection(page, /App security/);
  await expect(page.getByRole('button', { name: 'Lock the app now', exact: true })).toHaveCount(0);
  await configurePinFromSettings(page, '2468', { sectionOpen: true });
  const lockNow = await findRoleButtonByScrolling(page, /Lock the app now/);
  await expect(lockNow).toBeEnabled();

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
  await paragraphInput.fill('Draft note\nKeep this around');
  await page.waitForTimeout(700);
  await page.getByRole('button', { name: 'Cancel' }).click();
  await clickAddNote(page);
  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();
  await expect(page.locator('flutter-view')).toContainText('Draft note');
});

test('tags can be added to a note and found from search', async ({ page }) => {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await clickAddNote(page);
  const discardDraft = page.getByRole('button', { name: /Discard|破棄/ });
  if (await discardDraft.count()) {
    await discardDraft.click();
  }
  await selectEditorMode(page, 'Quick memo');
  const memoInput = editorTextInput(page);
  await memoInput.click();
  await memoInput.fill('Tagged note\nAlpha body');

  const tagInput = page.getByLabel(/Add a tag|タグを追加/);
  await tagInput.fill('alpha');
  await tagInput.press('Enter');

  await expect(page.getByRole('button', { name: 'Create note' })).toBeEnabled();
  await page.getByRole('button', { name: 'Create note' }).click();
  await expectNoteCard(page, /Tagged note Alpha body/);

  await page.getByRole('textbox', { name: /^(Search|検索)$/ }).fill('alpha');
  await expectNoteCard(page, /Tagged note Alpha body/);
});

test('core note create cancel save search tags and sync settings stay stable on mobile', async ({
  page,
}) => {
  await runCoreNoteStress(page);
});

test.describe('desktop viewport', () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test('core note create cancel save search tags and sync settings stay stable on desktop', async ({
    page,
  }) => {
    await runCoreNoteStress(page);
  });
});

async function runCoreNoteStress(page) {
  await page.goto('/');
  await waitForApp(page);
  await completeOnboarding(page);

  await openEditor(page, 'Quick memo');
  const cancelledInput = editorTextInput(page);
  await cancelledInput.click();
  await cancelledInput.fill('Cancelled note\nDo not keep this');
  await page.getByRole('button', { name: /Cancel|キャンセル/ }).click();
  await expect(page.locator('flutter-view')).not.toContainText('Do not keep this');

  await openFreshEditor(page, 'Rich memo');
  const savedInput = page.getByRole('textbox').first();
  await savedInput.click();
  await page.keyboard.press('ControlOrMeta+A');
  await savedInput.fill('Stress saved note\nBody survives cycles');
  const tagInput = page.getByLabel(/Add a tag|タグを追加/);
  await tagInput.fill('archive-cycle');
  await tagInput.press('Enter');
  await page.getByRole('button', { name: /Create note|ノートを作成/ }).click();
  await expectNoteCard(page, /Stress saved note Body survives cycles/);

  await page.getByRole('textbox', { name: /^(Search|検索)$/ }).fill('archive-cycle');
  await expectNoteCard(page, /Stress saved note Body survives cycles/);
  await page.getByRole('button', { name: /Filters|詳細/ }).click();
  await expect(page.getByRole('checkbox', { name: /Pinned only|固定/ })).toBeVisible();
  await dismissOpenDialog(page);

  await page.getByRole('textbox', { name: /^(Search|検索)$/ }).fill('');
  await page.waitForTimeout(200);
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Sync and security');
  await openSettingsGroup(page, /Sync and security/);
  const syncNow = await findRoleButtonByScrolling(page, /^Sync now$/);
  await syncNow.click();
  await expect(syncNow).toBeEnabled();
  await expect(page.locator('flutter-view')).toContainText('Automatic iCloud sync');

}

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
  await expect(page.getByRole('alertdialog')).toContainText(/00:0[1-9]/, {
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

  await activateTabIndex(page, 4);
  await expandSettingsSection(page, /Private profiles|プライベートプロファイル/);
  await page.getByRole('button', { name: /Add profile|プロファイルを追加/ }).click();
  const addProfileDialog = page.getByRole('alertdialog');
  await expect(addProfileDialog).toContainText(/Add private profile|プライベートプロファイルを追加/);
  const profileNameInput = addProfileDialog.getByLabel(/Profile name|プロフィール名/);
  await fillInputReliably(page, profileNameInput, 'Private profile');
  await fillInputReliably(
    page,
    addProfileDialog.getByLabel(/Profile password|プロフィールパスワード/),
    'profile-pass-123',
  );
  await fillInputReliably(
    page,
    addProfileDialog.getByLabel(/Confirm password|パスワードを確認/),
    'profile-pass-123',
  );
  await addProfileDialog.getByRole('button', { name: /^Add$|^追加$/ }).click();
  await expect(page.locator('flutter-view')).toContainText(
    /Viewing Private profile|Private profile を表示中/,
  );
  await page
    .getByRole('button', {
      name: /Viewing .*|Switch private access|.+ を表示中/,
    })
    .click();
  await page.getByRole('button', { name: /Lock|閉じる/ }).click();

  await activateTabIndex(page, 0);
  await clickAddNote(page);
  await expect(page.getByRole('switch', { name: /Save to private profile|プライベートプロファイルに保存/ })).toHaveCount(0);
  await page.getByRole('button', { name: /Cancel|キャンセル/ }).click();

  await page.getByRole('button', {
    name: /Unlock private profile|プライベートプロファイルを開く|Switch private access/,
  }).click();
  await expect(page.getByRole('alertdialog')).toContainText(
    /Unlock private profile|プライベートプロファイルを開く/,
  );
  const unlockDialog = page.getByRole('alertdialog');
  await unlockDialog.getByRole('textbox', { name: /^(Password|パスワード)$/ }).fill('profile-pass-123');
  await unlockDialog.getByRole('button', { name: /^(Unlock|開く)$/ }).click();
  await expect(page.locator('flutter-view')).toContainText(/Viewing Private profile|Private profile を表示中/);
});

test.describe('localized surfaces english', () => {
  test.use({ locale: 'en-US' });

  test('settings, calendar, and insights render in English', async ({ page }) => {
    await page.goto('/');
    await waitForApp(page);
    await completeOnboarding(page);

    await activateTabIndex(page, 4);
    await expect(page.locator('flutter-view')).toContainText('Appearance and language');
    await expect(page.locator('flutter-view')).toContainText('Notes and organization');
    await expect(page.locator('flutter-view')).toContainText('Private profiles');
    await expect(page.locator('flutter-view')).toContainText('App security');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('Calendar');
    await expect(page.getByRole('button', { name: 'Today' })).toBeVisible();

    await activateTabIndex(page, 2);
    await expect(page.locator('flutter-view')).toContainText('Writing activity');
    await expect(page.locator('flutter-view')).toContainText(
      /Current streak|Your writing activity will appear here/,
    );
  });
});

test.describe('localized surfaces japanese', () => {
  test.use({ locale: 'ja-JP' });

  test('settings, calendar, and insights render in Japanese', async ({ page }) => {
    await page.goto('/');
    await waitForApp(page);
    await completeOnboarding(page);

    await activateTabIndex(page, 4);
    await expect(page.locator('flutter-view')).toContainText('外観と言語');
    await expect(page.locator('flutter-view')).toContainText('メモと整理');
    await expect(page.locator('flutter-view')).toContainText('プライベートプロファイル');
    await expect(page.locator('flutter-view')).toContainText('アプリ保護');

    await activateTabIndex(page, 1);
    await expect(page.locator('flutter-view')).toContainText('カレンダー');
    await expect(page.getByRole('button', { name: '今日' })).toBeVisible();

    await activateTabIndex(page, 2);
    await expect(page.locator('flutter-view')).toContainText(/記録のまとめ|記録|Writing activity/);
  });
});

async function completeOnboarding(page) {
  await page.waitForTimeout(1200);
  const nextCount =
    (await page.getByRole('button', { name: 'Next' }).count()) +
    (await page.getByRole('button', { name: '次へ' }).count());
  if (!nextCount) {
    await waitForV2Ready(page);
    return;
  }

  for (let i = 0; i < 4; i += 1) {
    const nextButton =
      (await page.getByRole('button', { name: 'Next' }).count())
        ? page.getByRole('button', { name: 'Next' })
        : page.getByRole('button', { name: '次へ' });
    await nextButton.click();
    await page.waitForTimeout(250);
  }

  await expect(page.locator('flutter-view')).toContainText(
    /App lock is optional|起動ロックは必要に応じて/,
  );
  const setPinButton =
    (await page.getByRole('button', { name: 'Set PIN' }).count())
      ? page.getByRole('button', { name: 'Set PIN' })
      : page.getByRole('button', { name: 'PIN を設定' });
  await setPinButton.click();
  const pinInput = page.getByRole('textbox').first();
  await pinInput.click();
  await pinInput.fill('1234');
  const saveButton =
    (await page.getByRole('button', { name: 'Save' }).count())
      ? page.getByRole('button', { name: 'Save' })
      : page.getByRole('button', { name: '保存' });
  await saveButton.click();
  await expect(page.locator('flutter-view')).toContainText(/App unlock PIN saved\.|アプリ解除 PIN を保存しました。/);
  const finishButton =
    (await page.getByRole('button', { name: 'Start taking notes' }).count())
      ? page.getByRole('button', { name: 'Start taking notes' })
      : page.getByRole('button', { name: 'メモを始める' });
  await finishButton.click();
  await waitForV2Ready(page);
}

function editorTextInput(page) {
  return page.getByLabel(/Use the first line as the title|1行目をタイトルとして使います/);
}

async function openEditor(page, mode) {
  await clickAddNote(page);
  await expect(page.getByRole('button', { name: /Create note|ノートを作成/ })).toBeVisible();
  await selectEditorMode(page, mode);
}

async function openFreshEditor(page, mode) {
  await clickAddNote(page);
  const discardDraft = page.getByRole('button', { name: /Discard|破棄/ });
  if (await discardDraft.count()) {
    await discardDraft.click();
  }
  await expect(page.getByRole('button', { name: /Create note|ノートを作成/ })).toBeVisible();
  await selectEditorMode(page, mode);
}

async function clickAddNote(page) {
  const addNote = page.getByRole('button', { name: 'Add note' }).first();
  await expect(addNote).toBeVisible();
  await addNote.click();
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

async function configurePinFromSettings(page, pin, { sectionOpen = false } = {}) {
  if (!sectionOpen) {
    await page.evaluate(() => { location.hash = '#/settings'; });
    await expandSettingsSection(page, /App security/);
  }
  const setPin = await findRoleButtonByScrolling(page, /^Set PIN$/);
  await setPin.click();
  const dialog = page.getByRole('alertdialog');
  await fillInputReliably(page, dialog.getByRole('textbox').nth(0), pin);
  await fillInputReliably(page, dialog.getByRole('textbox').nth(1), pin);
  await dialog.getByRole('button', { name: 'Save PIN', exact: true }).click();
  await expect(dialog).toHaveCount(0);
}

async function waitForApp(page) {
  await resetV2App(page, { onboarded: false, locale: null });
  await expect.poll(async () =>
    (await page.getByRole('button', { name: /^(Next|次へ|Skip|スキップ)$/ }).count()) +
    (await page.getByRole('button', { name: 'Add note' }).count()),
  { timeout: 30000 }).toBeGreaterThan(0);
}

async function activateNav(page, labels) {
  const labelPattern = new RegExp(labels.map(escapeRegExp).join('|'));
  const tab = page.getByRole('tab', { name: labelPattern });
  try {
    await expect(tab.first()).toBeVisible({ timeout: 5000 });
    await tab.first().click();
    return;
  } catch (_) {
    // Fall through to non-tab fallbacks used by desktop/alternate semantics.
  }

  for (const label of labels) {
    const button = page.getByRole('button', { name: new RegExp(`^${escapeRegExp(label)}$`) });
    if (await button.count()) {
      await button.first().click();
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
  const labelsByIndex = [
    ['Notes', 'ノート'],
    ['Calendar', 'カレンダー'],
    ['Insights', '記録', 'インサイト'],
    ['Tags', 'タグ'],
    ['Settings', '設定'],
  ];
  const labels = labelsByIndex[index];
  if (labels) {
    await activateNav(page, labels);
    return;
  }
  const tabs = page.getByRole('tab');
  if ((await tabs.count()) > index) {
    await tabs.nth(index).click();
    return;
  }
  const semanticTabs = page.locator('flt-semantics[role="tab"]');
  if ((await semanticTabs.count()) > index) {
    await semanticTabs.nth(index).click();
    return;
  }
  await page.getByRole('tab').nth(index).click();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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

async function swipeNoteTile(page, name, direction) {
  const noteTile = await visibleNoteTile(page, name);
  const box = await noteTile.boundingBox();
  expect(box).not.toBeNull();
  const y = box.y + box.height / 2;
  const startX = direction === 'left' ? box.x + box.width - 28 : box.x + 28;
  const endX = direction === 'left' ? box.x + box.width - 330 : box.x + 300;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  await page.mouse.move(endX, y, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(220);
}

async function visibleNoteTile(page, name) {
  const button = page.getByRole('button', { name }).first();
  if ((await button.count()) && (await button.isVisible())) {
    return button;
  }
  const group = page.getByRole('group', { name }).first();
  await expect(group).toBeVisible();
  return group;
}

async function dismissOpenDialog(page) {
  const closeButton = page.getByRole('button', { name: /Close|閉じる/ });
  if (await closeButton.count()) {
    await clickDialogButton(page, closeButton.first());
    await expectNoAlertDialog(page);
    return;
  }
  const cancelButton = page.getByRole('button', { name: /Cancel|キャンセル/ });
  if (await cancelButton.count()) {
    await clickDialogButton(page, cancelButton.last());
    await expectNoAlertDialog(page);
    return;
  }
  const dismissButton = page.getByRole('button', { name: /Dismiss/ });
  if (await dismissButton.count()) {
    await clickDialogButton(page, dismissButton.first());
    await expectNoAlertDialog(page);
    return;
  }
  await page.keyboard.press('Escape');
  await expectNoAlertDialog(page);
}

async function clickDialogButton(page, button) {
  const box = await button.boundingBox({ timeout: 1000 }).catch(() => null);
  if (box) {
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  } else {
    await button.click({ force: true });
  }
}

async function expectNoAlertDialog(page) {
  try {
    await expect(page.getByRole('alertdialog')).toHaveCount(0, {
      timeout: 1500,
    });
  } catch (error) {
    await page.keyboard.press('Escape');
    await expect(page.getByRole('alertdialog')).toHaveCount(0);
  }
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

async function findRoleButtonByScrolling(page, name, options = {}) {
  const { requireEnabled = true } = options;
  const button = page.getByRole('button', { name });
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const first = button.first();
    if ((await button.count()) && (await first.isVisible())) {
      await first.scrollIntoViewIfNeeded();
      if (requireEnabled) {
        await expect(first).toBeEnabled();
      }
      return first;
    }
    await page.mouse.wheel(0, 420);
    await page.waitForTimeout(150);
  }
  await expect(button).toHaveCount(1);
  return button.first();
}

async function fillInputReliably(page, input, value) {
  await expect(input).toBeVisible();
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await input.click();
    await page.keyboard.press('ControlOrMeta+A');
    await input.fill(value);
    try {
      await expect(input).toHaveValue(value, { timeout: 1200 });
      return;
    } catch (error) {
      if (attempt === 3) {
        throw error;
      }
      await page.waitForTimeout(150);
    }
  }
}
