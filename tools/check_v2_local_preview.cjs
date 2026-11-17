// Runs the sample-only local V2 integration scenario in a fresh browser
// context. Serve build/web-v2-local-preview on localhost before running this.
const { chromium } = require('@playwright/test');

(async () => {
  const base = new URL(process.argv[2] || 'http://127.0.0.1:29371/');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) {
    throw new Error('A local preview URL is required');
  }
  base.searchParams.set('v2LocalSmoke', '1');
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    const failures = [];
    page.on('pageerror', error => failures.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error' || message.text().includes('Local V2 smoke failed:')) {
        failures.push(message.text());
      }
    });
    await page.goto(base.href, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForFunction(() => {
      const result = document.documentElement.getAttribute('data-v2-local-smoke');
      return result === 'passed' || result === 'failed';
    }, null, { timeout: 240000 });
    const result = await page.evaluate(() => document.documentElement.getAttribute('data-v2-local-smoke'));
    if (result !== 'passed' || failures.length) {
      throw new Error(`Local V2 smoke failed (${result}): ${failures.join('\n')}`);
    }
    console.log('Local V2 browser integration checks passed.');
    await context.close();
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
