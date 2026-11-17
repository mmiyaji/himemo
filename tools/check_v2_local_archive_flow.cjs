// End-to-end archive lifecycle check against the isolated V2 local preview.
// All credentials and note contents are synthetic browser-test data.
const assert = require('node:assert/strict');
const { chromium } = require('@playwright/test');

(async () => {
  const base = new URL(process.argv[2] || 'http://127.0.0.1:29371/');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) {
    throw new Error('A local preview URL is required');
  }
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.setViewportSize({ width: 1440, height: 1100 });
  const failures = [];
  page.on('pageerror', error => failures.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') failures.push(message.text());
  });
  try {
    await page.goto(base.href, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.locator('flt-semantics-placeholder').waitFor({ timeout: 30000 });
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());

    await page.getByRole('button', { name: '新規登録' }).click();
    const password = 'arc927';
    const passwordInputs = page.locator('input[type="password"]');
    await passwordInputs.first().waitFor({ timeout: 10000 });
    await page.mouse.click(700, 520);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(password, { delay: 80 });
    const firstValue = await page.evaluate(() => document.activeElement?.value ?? null);
    await page.mouse.click(700, 588);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(password, { delay: 80 });
    const secondValue = await page.evaluate(() => document.activeElement?.value ?? null);
    assert.equal(firstValue, password, `First native input value: ${firstValue}`);
    assert.equal(secondValue, password, `Second native input value: ${secondValue}`);
    await page.getByRole('button', { name: '続ける' }).click();
    await page.getByText('復元コードを別々に保管').waitFor({ timeout: 120000 });
    assert.equal(await page.getByRole('checkbox').count(), 2);
    await page.mouse.click(1356, 522);
    await page.mouse.click(1356, 611);
    await page.getByRole('button', { name: 'クラウドに登録' }).click();
    await page.getByRole('button', { name: '新しいメモ' }).waitFor({ timeout: 90000 });

    const title = 'Synthetic archive lifecycle note.';
    await page.getByRole('button', { name: '新しいメモ' }).click();
    await page.mouse.click(800, 229);
    await page.keyboard.type(title);
    await page.mouse.click(800, 281);
    await page.keyboard.type('Synthetic archive lifecycle note.');
    await page.getByRole('button', { name: '保存', exact: true }).evaluate(element => element.click());
    await page.getByText(title).waitFor({ timeout: 30000 });
    await page.screenshot({ path: 'artifacts/v2-local-archive-in-list.png' });

    await page.getByText(title).click();
    const archiveButtons = page.getByRole('button', { name: 'アーカイブ' });
    await archiveButtons.last().waitFor({ timeout: 30000 });
    await archiveButtons.last().click();
    await page.getByText(title).waitFor({ state: 'detached', timeout: 30000 });
    await page.screenshot({ path: 'artifacts/v2-local-archive-removed-from-list.png' });

    const toggle = page.getByRole('button', { name: 'アーカイブ' });
    await toggle.click();
    await page.getByText(title).waitFor({ timeout: 30000 });
    await page.screenshot({ path: 'artifacts/v2-local-archive-in-archive-view.png' });
    await page.getByRole('button', { name: '解除' }).click();
    await page.getByText(title).waitFor({ state: 'detached', timeout: 30000 });
    await page.getByRole('button', { name: '一覧' }).click();
    await page.getByText(title).waitFor({ timeout: 30000 });
    await page.screenshot({ path: 'artifacts/v2-local-archive-restored-to-list.png' });
    assert.deepEqual(failures, [], `Browser errors: ${failures.join('\n')}`);
    console.log('Local V2 archive lifecycle passed: archive, list removal, archive view, unarchive, list restoration.');
  } catch (error) {
    await page.screenshot({ path: 'artifacts/v2-local-archive-failure.png' }).catch(() => {});
    console.error('Browser semantic text:', (await page.locator('flt-semantics-host').innerText().catch(() => '')).slice(0, 5000));
    throw error;
  } finally {
    await context.close();
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
