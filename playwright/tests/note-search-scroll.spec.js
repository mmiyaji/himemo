const { test, expect } = require('@playwright/test');

test('note detail search jumps across media without reverse scroll motion', async ({
  page,
}) => {
  await page.goto('/');
  await seedScrollableNote(page);
  await expectNoteCard(page, /Search scroll memo/);
  await page.getByRole('button', { name: /Search scroll memo/ }).click();
  await expect(
    page.getByRole('button', { name: /Search in note|メモ内を検索/ }),
  ).toBeVisible();
  await page.getByRole('button', { name: /Search in note|メモ内を検索/ }).click();
  const detailSearchInput = page.getByLabel(/Search in this note|このメモ内を検索/);
  await detailSearchInput.click();
  await detailSearchInput.pressSequentially('ump-target');
  await expect(detailSearchInput).toHaveValue('ump-target');

  const nextMatch = page.getByRole('button', { name: /Next match|次の一致へ/ }).first();
  await expect(nextMatch).toBeEnabled();
  await nextMatch.click();

  const downwardMotion = await sampleSearchJumpMotion(
    page,
    () => nextMatch.click(),
    'Bottom jump-target',
  );
  await expect(page.locator('flutter-view')).toContainText('Bottom jump-target');
  expectMotionHasNoReverseStep(downwardMotion, 'down');

  const previousMatch = page
    .getByRole('button', { name: /Previous match|前の一致へ/ })
    .first();
  const upwardMotion = await sampleSearchJumpMotion(
    page,
    () => previousMatch.click(),
    'Top jump-target',
  );
  expectMotionHasNoReverseStep(upwardMotion, 'up');
});

async function seedScrollableNote(page) {
  const createdAt = new Date().toISOString();
  const note = {
    id: 'e2e-note-search-scroll',
    vaultId: 'everyday',
    title: 'Search scroll memo',
    body: 'Top jump-target\n\nBottom jump-target',
    createdAt,
    updatedAt: null,
    deletedAt: null,
    archivedAt: null,
    deviceId: 'e2e',
    contentHash: 'e2e-note-search-scroll',
    attachments: [
      {
        type: 'photo',
        label: 'himemo-e2e-search-jump.png',
        filePath: null,
        previewBytesBase64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        durationMs: null,
      },
    ],
    blocks: [
      { type: 'paragraph', text: 'Top jump-target', attachment: null },
      {
        type: 'photo',
        text: null,
        attachment: {
          type: 'photo',
          label: 'himemo-e2e-search-jump.png',
          filePath: null,
          previewBytesBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
          durationMs: null,
        },
      },
      {
        type: 'paragraph',
        text: [
          'Filler before the lower match',
          'More filler keeps the lower match below the media preview',
          'Bottom jump-target',
        ].join('\n'),
        attachment: null,
      },
    ],
    tags: [],
    isPinned: false,
    revision: 1,
    syncState: 'localOnly',
    editorMode: 'rich',
    location: null,
  };
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
  await page.evaluate((seedNote) => {
    localStorage.setItem('flutter.app.onboarding_completed', JSON.stringify(true));
    localStorage.setItem('flutter.app.onboarding_completed_version', JSON.stringify(2));
    localStorage.setItem('flutter.release_notes.last_seen', JSON.stringify('1.0.0+46'));
    localStorage.setItem(
      'flutter.notes.entries.v1',
      JSON.stringify(JSON.stringify([seedNote])),
    );
  }, note);
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

async function sampleSearchJumpMotion(page, action, targetText) {
  await page.evaluate((text) => {
    window.__himemoSearchJumpSamples = [];
    window.__himemoSearchJumpSampling = true;
    const findTargetY = () => {
      const candidates = Array.from(document.querySelectorAll('flt-semantics'));
      const target = candidates.find((element) =>
        (element.innerText || '').includes(text),
      );
      return target ? target.getBoundingClientRect().top : null;
    };
    const startedAt = performance.now();
    const sample = () => {
      window.__himemoSearchJumpSamples.push({
        t: performance.now() - startedAt,
        y: findTargetY(),
      });
      if (performance.now() - startedAt < 900) {
        requestAnimationFrame(sample);
      } else {
        window.__himemoSearchJumpSampling = false;
      }
    };
    requestAnimationFrame(sample);
  }, targetText);
  await action();
  await expect
    .poll(
      () => page.evaluate(() => window.__himemoSearchJumpSampling === false),
      { timeout: 2000 },
    )
    .toBe(true);
  return page.evaluate(() => window.__himemoSearchJumpSamples || []);
}

function expectMotionHasNoReverseStep(samples, direction) {
  const values = samples
    .map((sample) => sample.y)
    .filter((value) => typeof value === 'number' && Number.isFinite(value));
  expect(values.length).toBeGreaterThan(4);
  const tolerance = 6;
  for (let index = 1; index < values.length; index += 1) {
    const delta = values[index] - values[index - 1];
    if (direction === 'down') {
      expect(delta).toBeLessThanOrEqual(tolerance);
    } else {
      expect(delta).toBeGreaterThanOrEqual(-tolerance);
    }
  }
}
