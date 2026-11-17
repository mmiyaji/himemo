// End-to-end browser check for rich-block attachment insertion in the isolated
// V2 local preview. The only note and file content are synthetic test data.
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
    const password = 'synthetic-browser-92731';
    await page.mouse.click(700, 514);
    await page.keyboard.type(password);
    await page.mouse.click(700, 584);
    await page.keyboard.type(password);
    await page.mouse.click(792, 644);

    await page.getByText('復元コードを別々に保管').waitFor({ timeout: 120000 });
    await page.mouse.click(1356, 522);
    await page.mouse.click(1356, 611);
    await page.mouse.click(1300, 696);
    await page.getByRole('button', { name: '新しいメモ' }).waitFor({ timeout: 90000 });

    await page.getByRole('button', { name: '新しいメモ' }).click();
    const title = 'S';
    await page.mouse.click(800, 229);
    await page.keyboard.type(title);
    const firstParagraph = page.getByLabel('本文 1');
    await page.mouse.click(800, 281);
    await page.keyboard.type('LEFTRIGHT');
    assert.equal(await firstParagraph.inputValue(), 'LEFTRIGHT');
    await firstParagraph.press('Home');
    for (let i = 0; i < 4; i++) await firstParagraph.press('ArrowRight');
    const cursor = await firstParagraph.evaluate(element => ({
      value: element.value,
      start: element.selectionStart,
      end: element.selectionEnd,
    }));
    assert.deepEqual(cursor, { value: 'LEFTRIGHT', start: 4, end: 4 });

    const chooserPromise = page.waitForEvent('filechooser', { timeout: 30000 });
    await page.getByRole('button', { name: /添付/ }).click();
    const chooser = await chooserPromise;
    await chooser.setFiles({
      name: 'synthetic-attachment.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from('Synthetic attachment bytes 92731\n', 'utf8'),
    });

    await page.getByText(/synthetic-attachment\.txt/).waitFor();
    await page.screenshot({ path: 'artifacts/v2-local-attachment-insert-before-save.png' });

    await page.getByRole('button', { name: '保存', exact: true }).evaluate(element => element.click());
    await page.waitForTimeout(1500);
    await page.screenshot({ path: 'artifacts/v2-local-attachment-insert-after-save.png' });
    await page.mouse.click(180, 450);

    await page.getByLabel('本文 1').waitFor({ timeout: 30000 });
    await page.waitForTimeout(1000);
    assert.equal(await page.getByLabel('本文 1').inputValue(), 'LEFT');
    assert.equal(await page.getByLabel('本文 3').inputValue(), 'RIGHT');
    await page.getByText(/synthetic-attachment\.txt/).waitFor();
    await page.screenshot({ path: 'artifacts/v2-local-attachment-insert-reopened.png' });

    assert.deepEqual(failures, [], `Browser errors: ${failures.join('\n')}`);
    console.log('Local V2 rich attachment insertion, save, and reopen checks passed.');
  } catch (error) {
    await page.screenshot({ path: 'artifacts/v2-local-attachment-insert-failure.png' }).catch(() => {});
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
