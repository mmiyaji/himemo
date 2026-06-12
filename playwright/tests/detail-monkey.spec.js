const { test, expect } = require("@playwright/test");

const detailSeeds = [2101, 2102, 2103];

test.describe("detail monkey coverage", () => {
  for (const seed of detailSeeds) {
    test(`detail search/navigation monkey seed ${seed}`, async ({ page }) => {
      test.setTimeout(90_000);
      const failures = [];
      page.on("pageerror", (error) => failures.push(`pageerror: ${error}`));
      page.on("console", (message) => {
        if (message.type() === "error") {
          failures.push(`console error: ${message.text()}`);
        }
      });

      await page.goto("/");
      await seedDetailNotes(page, seed);
      await waitForHomeReady(page);
      await openSeedDetail(page, seed, 0);

      const rng = mulberry32(seed);
      const trace = [];
      for (let step = 0; step < 45; step += 1) {
        const action = chooseDetailAction(rng);
        trace.push(action);
        await runDetailAction(page, rng, action, seed, step);
        await page.waitForTimeout(40);
        await dismissTransientDialog(page);
        await expectNoRawFlutterError(page, seed, trace);
      }

      expect(failures, `seed ${seed} trace: ${trace.join(" -> ")}`).toEqual([]);
      await expect(page.locator("flutter-view")).toBeVisible();
    });
  }
});

function chooseDetailAction(rng) {
  const roll = rng();
  if (roll < 0.2) return "detail-search";
  if (roll < 0.34) return "next-match";
  if (roll < 0.48) return "previous-match";
  if (roll < 0.62) return "next-note";
  if (roll < 0.74) return "previous-note";
  if (roll < 0.86) return "edit-cancel";
  return "reopen-detail";
}

async function runDetailAction(page, rng, action, seed, step) {
  switch (action) {
    case "detail-search":
      await openDetailSearch(page);
      await fillDetailSearch(page, rng, seed, step);
      break;
    case "next-match":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /Next match/ }),
      ]);
      break;
    case "previous-match":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /Previous match/ }),
      ]);
      break;
    case "next-note":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /Next note/ }),
      ]);
      break;
    case "previous-note":
      await clickFirstVisible(page, [
        page.getByRole("button", { name: /Previous note/ }),
      ]);
      break;
    case "edit-cancel":
      await editAndCancel(page);
      break;
    case "reopen-detail":
      await reopenAnyDetail(page, seed, rng);
      break;
    default:
      break;
  }
}

async function openDetailSearch(page) {
  const input = page.getByLabel("Search in this note");
  if ((await input.count()) > 0 && (await input.first().isVisible())) return;
  await clickFirstVisible(page, [
    page.getByRole("button", { name: /Search in note/ }),
  ]);
}

async function fillDetailSearch(page, rng, seed, step) {
  const input = page.getByLabel("Search in this note");
  if ((await input.count()) === 0) return;
  const values = [
    "jump-target",
    "alpha",
    "bottom",
    `seed-${seed}`,
    `step-${step}`,
  ];
  await input.first().click();
  await input.first().fill(values[Math.floor(rng() * values.length)]);
}

async function editAndCancel(page) {
  const clicked = await clickFirstVisible(page, [
    page.getByRole("button", { name: /Edit note/ }),
  ]);
  if (!clicked) return;
  await closeEditorIfOpen(page);
}

async function closeEditorIfOpen(page) {
  const cancel = page.getByRole("button", { name: /Cancel/ });
  await page.keyboard.press("Escape");
  if ((await cancel.count()) > 0) {
    try {
      await cancel.first().click({ timeout: 1_000 });
    } catch (_) {
      await page.keyboard.press("Escape");
    }
  }
  await page.keyboard.press("Escape");
  const discard = page.getByRole("button", { name: /Discard/ });
  if ((await discard.count()) > 0 && (await discard.first().isVisible())) {
    try {
      await discard.first().click({ timeout: 1_000 });
    } catch (_) {
      await page.keyboard.press("Escape");
    }
  }
}

async function reopenAnyDetail(page, seed, rng) {
  await clickFirstVisible(page, [
    page.getByRole("button", { name: /Close/ }),
    page.getByRole("button", { name: /Cancel/ }),
  ]);
  await closeEditorIfOpen(page);
  await ensureNotesVisible(page);
  await openSeedDetail(page, seed, Math.floor(rng() * 5));
}

async function openSeedDetail(page, seed, index) {
  await closeEditorIfOpen(page);
  await ensureNotesVisible(page);
  await clearHomeSearch(page);
  const card = page.getByRole("button", {
    name: new RegExp(`Detail monkey ${seed}-${index}`),
  });
  if ((await card.count()) > 0) {
    await card.first().click();
    return;
  }
  const group = page.getByRole("group", {
    name: new RegExp(`Detail monkey ${seed}-${index}`),
  });
  await expect(group.first()).toBeVisible({ timeout: 8_000 });
  await group.first().click();
}

async function ensureNotesVisible(page) {
  const notesTab = page.getByRole("tab", { name: /Notes/ });
  if ((await notesTab.count()) > 0) {
    await notesTab.first().click();
  }
}

async function clearHomeSearch(page) {
  const search = page.getByRole("textbox", { name: /^Search/ });
  if ((await search.count()) > 0 && (await search.first().isVisible())) {
    await search.first().fill("");
  }
}

async function clickFirstVisible(page, locators) {
  for (const locator of locators) {
    const count = await locator.count();
    for (let index = 0; index < count; index += 1) {
      const item = locator.nth(index);
      try {
        if ((await item.isVisible()) && (await item.isEnabled({ timeout: 500 }))) {
          await item.click();
          return true;
        }
      } catch (error) {
        if (!/not attached|detached|Target closed|Timeout/i.test(String(error))) {
          throw error;
        }
      }
    }
  }
  return false;
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

async function seedDetailNotes(page, seed) {
  await resetBrowserState(page);
  const notes = Array.from({ length: 6 }, (_, index) =>
    createDetailNote(seed, index),
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

function createDetailNote(seed, index) {
  const createdAt = new Date("2026-05-28T10:00:00.000Z").toISOString();
  const body = [
    `Detail monkey ${seed}-${index} top jump-target seed-${seed}`,
    ...Array.from(
      { length: 24 },
      (_, line) => `alpha filler ${line} for detail note ${index}`,
    ),
    `Detail monkey ${seed}-${index} bottom jump-target`,
  ].join("\n");
  return {
    id: `e2e-detail-monkey-${seed}-${index}`,
    vaultId: "everyday",
    title: `Detail monkey ${seed}-${index}`,
    body,
    createdAt,
    updatedAt: null,
    deletedAt: null,
    archivedAt: null,
    deviceId: "e2e",
    contentHash: `e2e-detail-monkey-${seed}-${index}`,
    attachments: [],
    blocks: [
      {
        type: "paragraph",
        text: body,
        attachment: null,
      },
    ],
    tags: [`detail-${index % 3}`, "alpha"],
    isPinned: index === 0,
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

function mulberry32(seed) {
  return function next() {
    let value = (seed += 0x6d2b79f5);
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}
