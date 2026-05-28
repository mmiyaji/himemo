const { test, expect } = require("@playwright/test");

test.describe("non-sync abnormal and performance coverage", () => {
  test("recovers from malformed legacy notes and keeps the editor usable", async ({
    page,
  }) => {
    await page.goto("/");
    await seedMalformedLegacyNotes(page);
    await waitForHomeReady(page);
    await expectNoRawFlutterError(page);

    await openQuickMemo(page);
    const input = editorTextInput(page);
    await input.click();
    await input.pressSequentially(
      "Recovered after corrupt legacy\nstill writable",
    );
    const createNote = page.getByRole("button", { name: "Create note" });
    await expect(createNote).toBeEnabled();
    await expect
      .poll(() =>
        page.evaluate(() =>
          localStorage.getItem("flutter.notes.entries.v1.corrupt"),
        ),
      )
      .toBe('"{\\"not\\":\\"a note list\\"}"');
    await expectNoRawFlutterError(page);
  });

  test("search remains responsive with a large non-sync note set", async ({
    page,
  }) => {
    test.setTimeout(90_000);
    await page.goto("/");
    const notes = createLargeNoteSet(240);
    await seedLegacyNotes(page, notes);
    await waitForHomeReady(page);
    await expectNoteCard(page, /Bulk performance note 000/);

    const searchInput = page.getByRole("textbox", { name: "Search" });
    await expect(searchInput).toBeVisible();
    const startedAt = await page.evaluate(() => performance.now());
    await searchInput.click();
    await searchInput.pressSequentially("rare-needle");
    await expect(searchInput).toHaveValue("rare-needle");
    await expectNoteCard(page, /Perf target 217 rare-needle/);
    const elapsedMs = await page.evaluate(
      (start) => performance.now() - start,
      startedAt,
    );

    expect(elapsedMs).toBeLessThan(8_000);
    await expectNoRawFlutterError(page);
  });
});

function createLargeNoteSet(count) {
  const createdAt = new Date("2026-05-28T10:00:00.000Z").toISOString();
  return Array.from({ length: count }, (_, index) => {
    const isTarget = index === 217;
    const title = isTarget
      ? "Perf target 217 rare-needle"
      : `Bulk performance note ${String(index).padStart(3, "0")}`;
    const repeatedBody = Array.from(
      { length: 14 },
      (__, line) =>
        `Line ${line} for note ${index} with ordinary searchable content and tag bucket ${
          index % 12
        }.`,
    ).join("\n");
    return {
      id: `e2e-non-sync-perf-${index}`,
      vaultId: "everyday",
      title,
      body: isTarget ? `${repeatedBody}\nrare-needle body match` : repeatedBody,
      createdAt,
      updatedAt: null,
      deletedAt: null,
      archivedAt: null,
      deviceId: "e2e",
      contentHash: `e2e-non-sync-perf-${index}`,
      attachments: [],
      blocks: [
        {
          type: "paragraph",
          text: isTarget
            ? `${repeatedBody}\nrare-needle body match`
            : repeatedBody,
          attachment: null,
        },
      ],
      tags: [`bucket-${index % 12}`, isTarget ? "rare-needle" : "bulk"],
      isPinned: index % 17 === 0,
      revision: 1,
      syncState: "localOnly",
      editorMode: "rich",
      location: null,
    };
  });
}

async function seedMalformedLegacyNotes(page) {
  await resetBrowserState(page);
  await page.evaluate(() => {
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
      JSON.stringify('{"not":"a note list"}'),
    );
  });
  await page.reload();
}

async function seedLegacyNotes(page, notes) {
  await resetBrowserState(page);
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

async function openQuickMemo(page) {
  const addNote = page.getByRole("button", { name: "Add note" }).first();
  await expect(addNote).toBeVisible();
  await addNote.click();
  await expect(page.getByRole("button", { name: "Create note" })).toBeVisible();
  const modeButton = page.getByRole("button", {
    name: /Quick memo|Rich memo/,
  });
  await expect(modeButton).toBeVisible();
  if (!(await modeButton.innerText()).includes("Quick memo")) {
    await modeButton.click();
    await page.getByRole("menuitem", { name: "Quick memo" }).click();
  }
}

function editorTextInput(page) {
  return page.getByLabel("Use the first line as the title");
}

async function expectNoteCard(page, name) {
  await expect
    .poll(
      async () =>
        (await page.getByRole("button", { name }).count()) +
        (await page.getByRole("group", { name, includeHidden: true }).count()),
      { timeout: 8_000 },
    )
    .toBeGreaterThan(0);
}

async function expectNoRawFlutterError(page) {
  await expect(page.locator("flutter-view")).not.toContainText(
    /FormatException|TypeError|RangeError|HimemoDecryptionException|Exception:/,
  );
}
