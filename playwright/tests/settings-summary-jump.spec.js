const { test, expect } = require('@playwright/test');

test.describe('settings summary jumps', () => {
  test('mobile summary items expand and align each target section', async ({
    page,
  }) => {
    await openSettings(page);

    await clickSummary(page, /Theme Light/);
    await expectSectionExpanded(
      page,
      /Appearance/,
      'Choose the font used across notes',
    );

    await clickSummary(page, /Sync Off/);
    await expectSectionExpanded(page, /Backup and sync/, 'Selected target');

    await clickSummary(page, /Memo Rich memo/);
    await expectSectionExpanded(page, /Memo settings/, 'Quick memo');

    await clickSummary(page, /Storage/);
    await expectSectionExpanded(page, /Storage/, 'Saved notes on this device');

    await clickSummary(page, /App lock Disabled/);
    await expectSectionExpanded(page, /App security/, 'Set PIN');

    await clickSummary(page, /Profile Normal notes/);
    await expectSectionExpanded(page, /Private profiles/, 'Add profile');
  });

  test('mobile summary jump remains aligned when another long section is already open', async ({
    page,
  }) => {
    await openSettings(page);

    await clickSummary(page, /Theme Light/);
    await expectSectionExpanded(
      page,
      /Appearance/,
      'Choose the font used across notes',
    );

    await clickSummary(page, /Sync Off/);
    await expectSectionExpanded(page, /Backup and sync/, 'Selected target');

    await clickSummary(page, /App lock Disabled/);
    await expectSectionExpanded(page, /App security/, 'Session status');
  });

  test('extended color theme sheet keeps its header above scrolled choices', async ({
    page,
  }) => {
    await openSettings(page, { colorTheme: 'moegi' });

    await clickSummary(page, /Theme Light/);
    await expectSectionExpanded(
      page,
      /Appearance/,
      'Choose the font used across notes',
    );

    await page
      .getByRole('button', { name: /Extended themes \(\d+ total\)/ })
      .click();
    const sheetTitle = page.getByText('Extended themes').last();
    await expect(sheetTitle).toBeVisible();

    await page.mouse.move(220, 560);
    await page.mouse.wheel(0, 1260);
    await page.waitForTimeout(250);

    const titleBoxAfter = await sheetTitle.boundingBox();
    expect(titleBoxAfter).not.toBeNull();
    await expect(sheetTitle).toBeVisible();

    const selectedThemeCard = page.getByRole('button', { name: /Moegi/ });
    await expect(selectedThemeCard).toBeVisible();
    const selectedBox = await selectedThemeCard.boundingBox();
    expect(selectedBox).not.toBeNull();
    expect(selectedBox.y).toBeGreaterThan(
      titleBoxAfter.y + titleBoxAfter.height,
    );
  });

  test.describe('desktop viewport', () => {
    test.use({ viewport: { width: 1280, height: 900 } });

    test('desktop summary items work after several sections are expanded', async ({
      page,
    }) => {
      await openSettings(page);

      await clickSummary(page, /Profile Normal notes/);
      await expectSectionExpanded(
        page,
        /Private profiles/,
        'Enter admin mode',
      );

      await clickSummary(page, /Theme Light/);
      await expectSectionExpanded(
        page,
        /Appearance/,
        'Choose the font used across notes',
      );

      await clickSummary(page, /Sync Off/);
      await expectSectionExpanded(page, /Backup and sync/, 'Selected target');
    });
  });
});

async function openSettings(page, options = {}) {
  await page.goto('/');
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
                request.onsuccess =
                  request.onerror =
                  request.onblocked =
                    resolve;
              }),
          ),
      );
    }
    localStorage.setItem('flutter.app.onboarding_completed', 'true');
    localStorage.setItem('flutter.app.onboarding_completed_version', '2');
    localStorage.setItem('flutter.settings.locale', '"english"');
    localStorage.setItem('flutter.release_notes.last_seen', '"1.0.0+46"');
  });
  if (options.colorTheme) {
    await page.evaluate((colorTheme) => {
      localStorage.setItem('flutter.settings.color_theme', JSON.stringify(colorTheme));
    }, options.colorTheme);
  }
  await page.goto('/#/settings');
  await expect(page.locator('flutter-view')).toContainText('Profile', {
    timeout: 15000,
  });
  await expect(
    page.getByRole('button', { name: /Profile Normal notes/ }),
  ).toBeVisible();
}

async function clickSummary(page, name) {
  const summary = page.getByRole('button', { name }).first();
  await summary.scrollIntoViewIfNeeded();
  await expect(summary).toBeVisible();
  await summary.click();
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
