const { test, expect } = require("@playwright/test");

const monkeySeeds = [1101, 1102, 1103, 1104, 1105];

test.describe("monkey interaction coverage", () => {
  for (const seed of monkeySeeds) {
    test(`home/editor/settings monkey seed ${seed}`, async ({ page }) => {
      test.setTimeout(90_000);
      const failures = [];
      page.on("pageerror", (error) => failures.push(`pageerror: ${error}`));
      page.on("console", (message) => {
        if (message.type() === "error") {
          failures.push(`console error: ${message.text()}`);
        }
      });

      await page.goto("/");
      await seedMonkeyNotes(page, seed);
      await waitForHomeReady(page);

      const rng = mulberry32(seed);
      const trace = [];
      for (let step = 0; step < 70; step += 1) {
        const action = chooseAction(rng);
        trace.push(action);
        await runAction(page, rng, action, seed, step);
        await page.waitForTimeout(25);
        await dismissTransientDialog(page);
        await expectNoRawFlutterError(page, seed, trace);
      }

      expect(failures, `seed ${seed} trace: ${trace.join(" -> ")}`).toEqual([]);
      await expect(page.locator("flutter-view")).toBeVisible();
    });
  }
});

function chooseAction(rng) {
  const roll = rng();
  if (roll < 0.18) return "search";
  if (roll < 0.32) return "toggle-filters";
  if (roll < 0.46) return "nav";
  if (roll < 0.58) return "open-cancel-editor";
  if (roll < 0.68) return "create-note";
  if (roll < 0.78) return "toggle-layout";
  if (roll < 0.9) return "tag-chip";
  return "escape";
}

async function runAction(page, rng, action, seed, step) {
  switch (action) {
    case "search":
      await maybeFillSearch(page, rng, seed, step);
      break;
    case "toggle-filters":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /Filters/ }),
      ]);
      break;
    case "nav":
      await clickRandomNav(page, rng);
      break;
    case "open-cancel-editor":
      await openEditorAndCancel(page, rng, seed, step);
      break;
    case "create-note":
      await createQuickNote(page, rng, seed, step);
      break;
    case "toggle-layout":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /List layout|Grid layout/ }),
      ]);
      break;
    case "tag-chip":
      await clickRandomVisible(
        page,
        rng,
        page.getByRole("button", { name: /^#/ }),
      );
      break;
    case "escape":
      await page.keyboard.press("Escape");
      break;
    default:
      break;
  }
}

async function maybeFillSearch(page, rng, seed, step) {
  const search = page.getByRole("textbox", { name: /Search/ });
  if ((await search.count()) === 0) return;
  const values = [
    "",
    "alpha",
    "bulk",
    "monkey",
    `seed-${seed}`,
    `step-${step}`,
  ];
  await search.first().click();
  await search.first().fill(values[Math.floor(rng() * values.length)]);
}

async function clickRandomNav(page, rng) {
  const tabs = [
    page.getByRole("tab", { name: /Notes/ }),
    page.getByRole("tab", { name: /Calendar/ }),
    page.getByRole("tab", { name: /Insights/ }),
    page.getByRole("tab", { name: /Settings/ }),
  ];
  const visibleTabs = [];
  for (const tab of tabs) {
    if ((await tab.count()) > 0 && (await tab.first().isVisible())) {
      visibleTabs.push(tab.first());
    }
  }
  if (visibleTabs.length > 0) {
    await visibleTabs[Math.floor(rng() * visibleTabs.length)].click();
    return true;
  }
  return clickFirstVisible(page, [
    page.getByRole("button", { name: /Notes|Calendar|Insights|Settings/ }),
  ]);
}

async function openEditorAndCancel(page, rng, seed, step) {
  const opened = await openQuickEditor(page);
  if (!opened) return;
  if (rng() > 0.35) {
    const input = editorTextInput(page);
    if ((await input.count()) > 0) {
      await input.first().click();
      await input.first().fill(`Monkey discard ${seed}-${step}\nbody`);
    }
  }
  await clickFirstVisible(page, [
    page.getByRole("button", { name: /Cancel/ }),
    page.getByRole("button", { name: /Discard/ }),
  ]);
}

async function createQuickNote(page, rng, seed, step) {
  const opened = await openQuickEditor(page);
  if (!opened) return;
  const input = editorTextInput(page);
  if ((await input.count()) > 0) {
    await input.first().click();
    await input
      .first()
      .fill(`Monkey saved ${seed}-${step}\n${randomWords(rng)}`);
  }
  const create = page.getByRole("button", { name: /Create note/ });
  if ((await create.count()) > 0 && (await create.first().isEnabled())) {
    await create.first().click();
  } else {
    await page.keyboard.press("Escape");
  }
}

async function openQuickEditor(page) {
  const addNote = page.getByRole("button", { name: "Add note" }).first();
  if ((await addNote.count()) === 0 || !(await addNote.isVisible())) {
    await ensureNotesTab(page);
  }
  if ((await addNote.count()) === 0 || !(await addNote.isVisible())) {
    return false;
  }
  await addNote.click();
  const create = page.getByRole("button", { name: /Create note/ });
  await expect(create.first()).toBeVisible({ timeout: 5_000 });
  const discardDraft = page.getByRole("button", { name: /Discard/ });
  if ((await discardDraft.count()) > 0) {
    await discardDraft.first().click();
  }
  return true;
}

async function ensureNotesTab(page) {
  const notesTab = page.getByRole("tab", { name: /Notes/ });
  if ((await notesTab.count()) > 0) {
    await notesTab.first().click();
  }
}

function editorTextInput(page) {
  return page.getByLabel("Use the first line as the title");
}

async function clickFirstVisible(page, locators) {
  for (const locator of locators) {
    const count = await locator.count();
    for (let index = 0; index < count; index += 1) {
      const item = locator.nth(index);
      if (await item.isVisible()) {
        await item.click();
        return true;
      }
    }
  }
  return false;
}

async function clickRandomVisible(page, rng, locator) {
  const visible = [];
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const item = locator.nth(index);
    if (await item.isVisible()) visible.push(item);
  }
  if (visible.length === 0) return false;
  await visible[Math.floor(rng() * visible.length)].click();
  return true;
}

async function dismissTransientDialog(page) {
  const dialog = page.getByRole("alertdialog");
  if ((await dialog.count()) === 0) return;
  await clickFirstVisible(page, [
    page.getByRole("button", { name: /Cancel|Close|OK/ }),
  ]);
  await page.keyboard.press("Escape");
}

async function expectNoRawFlutterError(page, seed, trace) {
  await expect(
    page.locator("flutter-view"),
    `seed ${seed} trace: ${trace.join(" -> ")}`,
  ).not.toContainText(
    /FormatException|TypeError|RangeError|Assertion failed|HimemoDecryptionException|Exception:/,
  );
}

async function seedMonkeyNotes(page, seed) {
  await resetBrowserState(page);
  const notes = Array.from({ length: 24 }, (_, index) =>
    createMonkeyNote(seed, index),
  );
  await page.evaluate((seedNotes) => {
    localStorage.setItem(
      "flutter.app.onboarding_completed",
      JSON.stringify(true),
    );
    localStorage.setItem(
      "flutter.app.onboarding_completed_version",
      JSON.stringify(2),
    );
    localStorage.setItem(
      "flutter.release_notes.last_seen",
      JSON.stringify("1.0.0+46"),
    );
    localStorage.setItem(
      "flutter.notes.entries.v1",
      JSON.stringify(JSON.stringify(seedNotes)),
    );
  }, notes);
  await page.reload();
}

function createMonkeyNote(seed, index) {
  const createdAt = new Date("2026-05-28T10:00:00.000Z").toISOString();
  return {
    id: `e2e-monkey-${seed}-${index}`,
    vaultId: "everyday",
    title: `Monkey note ${seed}-${index}`,
    body: `alpha bulk monkey seed-${seed} index-${index}`,
    createdAt,
    updatedAt: null,
    deletedAt: null,
    archivedAt: null,
    deviceId: "e2e",
    contentHash: `e2e-monkey-${seed}-${index}`,
    attachments: [],
    blocks: [
      {
        type: "paragraph",
        text: `alpha bulk monkey seed-${seed} index-${index}`,
        attachment: null,
      },
    ],
    tags: [`monkey-${index % 4}`, index % 2 === 0 ? "alpha" : "bulk"],
    isPinned: index % 5 === 0,
    revision: 1,
    syncState: "localOnly",
    editorMode: "rich",
    location: null,
  };
}

async function resetBrowserState(page) {
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
  });
}

async function waitForHomeReady(page) {
  await expect
    .poll(
      async () =>
        (await page.getByRole("button", { name: "Add note" }).count()) +
        (await page.getByRole("button", { name: "Next" }).count()) +
        (await page.getByRole("button", { name: "Skip" }).count()),
      { timeout: 20_000 },
    )
    .toBeGreaterThan(0);
}

function randomWords(rng) {
  const words = ["alpha", "bulk", "memo", "filter", "settings", "cancel"];
  return Array.from(
    { length: 6 },
    () => words[Math.floor(rng() * words.length)],
  ).join(" ");
}

function mulberry32(seed) {
  return function next() {
    let value = (seed += 0x6d2b79f5);
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}
