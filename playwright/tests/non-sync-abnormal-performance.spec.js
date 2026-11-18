const { test, expect } = require("@playwright/test");
const { resetV2App, createNotesThroughUi } = require("../support/v2-app");

test.describe("v2 search performance coverage", () => {
  test("search remains responsive with a large v2 note set", async ({
    page,
  }) => {
    test.setTimeout(600_000);
    await page.goto("/");
    const notes = createLargeNoteSet(240);
    await resetV2App(page);
    await createNotesThroughUi(page, notes);
    await waitForHomeReady(page);
    await expectNoteCard(page, /Bulk performance note 239/);

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
      title,
      body: isTarget ? `${repeatedBody}\nrare-needle body match` : repeatedBody,
      tags: [`bucket-${index % 12}`, isTarget ? 'rare-needle' : 'bulk'],
      editorMode: 'rich',
    };
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
