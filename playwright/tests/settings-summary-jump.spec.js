const { test, expect } = require('@playwright/test');
const { resetV2App } = require('../support/v2-app');

test.describe('settings sections and summary jumps', () => {
  test('mobile settings use sections without a duplicate status overview', async ({ page }) => {
    await openSettings(page);
    await expect(page.getByText('Current status', { exact: true })).toHaveCount(0);
    await openSection(page, /Sync and security/);
    await expect(page.getByRole('button', { name: 'Sync now', exact: true })).toBeVisible();
    await openSection(page, /Private profiles/);
    await expect(page.getByRole('button', { name: 'Exit admin mode', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sync now', exact: true })).toHaveCount(0);
  });

  test('extended color theme sheet keeps its header above scrolled choices', async ({ page }) => {
    await openSettings(page, { colorTheme: 'moegi' });
    await openSection(page, /Appearance and language/);
    await page.getByRole('button', { name: /Extended themes \(\d+ total\)/ }).click();
    const sheetTitle = page.getByText('Extended themes', { exact: true }).last();
    await expect(sheetTitle).toBeVisible();
    await page.mouse.move(220, 560);
    await page.mouse.wheel(0, 1260);
    const selectedThemeCard = page.getByRole('button', { name: /Moegi/ });
    await expect(selectedThemeCard).toBeVisible();
    const titleBox = await sheetTitle.boundingBox();
    const selectedBox = await selectedThemeCard.boundingBox();
    expect(titleBox).not.toBeNull();
    expect(selectedBox).not.toBeNull();
    expect(selectedBox.y).toBeGreaterThan(titleBox.y + titleBox.height);
  });

  test.describe('desktop viewport', () => {
    test.use({ viewport: { width: 1280, height: 900 } });
    test('current status links expand and align their current sections', async ({ page }) => {
      await openSettings(page);
      await openSummaryAndExpect(page, /Profile Admin mode active/, /Private profiles/, 'Exit admin mode');
      await openSummaryAndExpect(page, /App lock Disabled/, /App security/, 'Set PIN');
      await openSummaryAndExpect(page, /Sync Automatic iCloud sync/, /Sync and security/, 'Sync now');
    });
  });
});

async function openSettings(page, options = {}) {
  await resetV2App(page, {
    preferences: options.colorTheme ? { 'settings.color_theme': options.colorTheme } : {},
  });
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Sync and security');
}

async function openSection(page, name) {
  const heading = page.getByRole('button', { name }).first();
  await heading.scrollIntoViewIfNeeded();
  await heading.click();
}

async function clickSummary(page, name) {
  const summary = page.getByRole('button', { name }).first();
  await summary.scrollIntoViewIfNeeded();
  await expect(summary).toBeVisible();
  try {
    await summary.click({ force: true });
  } catch (error) {
    if (!/outside of the viewport|not attached|detached/i.test(String(error))) {
      throw error;
    }
    await summary.focus();
    await summary.press('Enter');
  }
}

async function openSummaryAndExpect(page, summary, heading, expandedText) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await clickSummary(page, summary);
    try {
      await expectSectionExpanded(page, heading, expandedText);
      return;
    } catch (error) {
      lastError = error;
      await page.waitForTimeout(180);
    }
  }
  throw lastError;
}

async function expectSectionExpanded(page, heading, expandedText) {
  await expect(page.locator('flutter-view')).toContainText(expandedText);

  await expect
    .poll(
      async () => {
        const box = await stableSectionBoundingBox(page, heading, expandedText);
        if (!box) {
          return false;
        }
        return box.y >= 50 && box.y <= 430;
      },
      { timeout: 7000 },
    )
    .toBe(true);
}

async function stableSectionBoundingBox(page, heading, expandedText) {
  const first = await sectionBoundingBox(page, heading, expandedText);
  if (!first) {
    return null;
  }
  await waitForAnimationFrames(page, 2);
  const second = await sectionBoundingBox(page, heading, expandedText);
  if (!second) {
    return null;
  }
  const stable =
    Math.abs(first.y - second.y) <= 1 &&
    Math.abs(first.height - second.height) <= 1;
  return stable ? second : null;
}

async function waitForAnimationFrames(page, count) {
  await page.evaluate(
    (frames) =>
      new Promise((resolve) => {
        const tick = () => {
          frames -= 1;
          if (frames <= 0) {
            resolve();
            return;
          }
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      }),
    count,
  );
}

async function sectionBoundingBox(page, heading, expandedText) {
  const headingPattern = regexPayload(heading);
  return page.evaluate(
    ({ headingPattern, expandedText }) => {
      const headingRegex = new RegExp(
        headingPattern.source,
        headingPattern.flags,
      );
      const candidates = Array.from(
        document.querySelectorAll('flt-semantics'),
      )
        .map((node) => {
          const rect = node.getBoundingClientRect();
          const text = [
            node.textContent || '',
            node.getAttribute('aria-label') || '',
          ].join('\n');
          return {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
            area: rect.width * rect.height,
            text,
          };
        })
        .filter((candidate) => {
          if (!headingRegex.test(candidate.text)) {
            return false;
          }
          if (!candidate.text.includes(expandedText)) {
            return false;
          }
          if (candidate.width <= 0 || candidate.height <= 0) {
            return false;
          }
          return candidate.x > 0 && candidate.width < window.innerWidth;
        })
        .sort(
          (left, right) =>
            left.area - right.area || right.text.length - left.text.length,
        );
      const match = candidates[0];
      if (!match) {
        return null;
      }
      return {
        x: match.x,
        y: match.y,
        width: match.width,
        height: match.height,
      };
    },
    { headingPattern, expandedText },
  );
}

function regexPayload(pattern) {
  if (pattern instanceof RegExp) {
    return {
      source: pattern.source,
      flags: pattern.flags.replace(/[gy]/g, ''),
    };
  }
  return { source: escapeRegExp(pattern), flags: '' };
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
