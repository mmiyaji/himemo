const { chromium, devices } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '../..');
const outputDir = path.join(rootDir, 'store-assets', 'app-store');
const port = process.env.STORE_ASSET_PORT || '4174';
const baseUrl = `http://127.0.0.1:${port}`;

const deviceTargets = [
  {
    id: 'iphone-6-7',
    label: 'iPhone 6.7',
    viewport: { width: 414, height: 896 },
    deviceScaleFactor: 3,
    output: { width: 1242, height: 2688 },
  },
  {
    id: 'ipad-12-9',
    label: 'iPad 12.9',
    viewport: { width: 1024, height: 1366 },
    deviceScaleFactor: 2,
    output: { width: 2048, height: 2732 },
  },
];

const locales = [
  {
    id: 'ja',
    locale: 'ja-JP',
    captions: {
      notes: {
        title: 'すばやく残せるメモ',
        subtitle: '日常の記録やアイデアを、すぐに一覧へ。',
      },
      quick: {
        title: '1行目がそのままタイトル',
        subtitle: '軽い入力で、あとから探しやすいメモに。',
      },
      private: {
        title: 'プライベート領域を分ける',
        subtitle: '必要なプロファイルだけを開いて管理できます。',
      },
      profileLock: {
        title: '複数プロファイルをロック',
        subtitle: '名前や保存先IDを隠したまま、別々の鍵で管理。',
      },
      insights: {
        title: '記録を振り返る',
        subtitle: '日々のメモをカレンダーとまとめで確認。',
      },
      settings: {
        title: '日付ごとに見返す',
        subtitle: 'カレンダーで、その日のメモを振り返れます。',
      },
    },
  },
  {
    id: 'en',
    locale: 'en-US',
    captions: {
      notes: {
        title: 'Capture notes fast',
        subtitle: 'Keep daily thoughts, ideas, and logs in one place.',
      },
      quick: {
        title: 'First line becomes the title',
        subtitle: 'Lightweight notes that are easy to find later.',
      },
      private: {
        title: 'Separate private spaces',
        subtitle: 'Open only the profile you need, when you need it.',
      },
      profileLock: {
        title: 'Lock multiple profiles',
        subtitle: 'Keep names and vault IDs hidden behind separate keys.',
      },
      insights: {
        title: 'Review your writing',
        subtitle: 'See notes by day and track your memo activity.',
      },
      settings: {
        title: 'Review notes by day',
        subtitle: 'Use the calendar to revisit what you wrote.',
      },
    },
  },
];

const scenes = [
  { id: '01-notes', key: 'notes', prepare: async () => {} },
  {
    id: '02-quick-memo',
    key: 'quick',
    prepare: async (page, locale) => {
      await openAddNote(page);
      const quickButton = page.getByRole('button', {
        name: locale.id === 'ja' ? /クイックメモ/ : /Quick memo/,
      });
      if (await quickButton.count()) {
        await quickButton.first().click();
        const memoInput = page.getByLabel(locale.id === 'ja' ? 'メモ' : 'Memo');
        if (await memoInput.count()) {
          await memoInput.fill(
            locale.id === 'ja'
              ? '旅の持ち物\n充電器\n折りたたみ傘\n小さなノート'
              : 'Trip packing\nCharger\nCompact umbrella\nSmall notebook',
          );
        }
      }
      await page.waitForTimeout(500);
    },
  },
  {
    id: '03-private-profile',
    key: 'private',
    prepare: async (page) => {
      await activateTabIndex(page, 3);
      await page.waitForTimeout(700);
    },
  },
  {
    id: '04-profile-lock',
    key: 'profileLock',
    prepare: async (page, locale) => {
      await seedPrivateProfiles(page, locale);
      await activateTabIndex(page, 3);
      await page.waitForTimeout(700);
    },
  },
  {
    id: '05-insights',
    key: 'insights',
    prepare: async (page) => {
      await activateTabIndex(page, 2);
      await page.waitForTimeout(500);
    },
  },
  {
    id: '06-calendar',
    key: 'settings',
    prepare: async (page) => {
      await activateTabIndex(page, 1);
      await page.waitForTimeout(500);
    },
  },
];

async function main() {
  fs.rmSync(outputDir, { recursive: true, force: true });
  fs.mkdirSync(outputDir, { recursive: true });
  const server = await ensureServer();
  const browser = await chromium.launch({
    args: [
      '--force-renderer-accessibility',
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
    ],
  });

  try {
    for (const target of deviceTargets) {
      for (const locale of locales) {
        const rawDir = path.join(outputDir, target.id, locale.id, 'raw');
        const promoDir = path.join(outputDir, target.id, locale.id, 'promo');
        fs.mkdirSync(rawDir, { recursive: true });
        fs.mkdirSync(promoDir, { recursive: true });

        for (const scene of scenes) {
          const rawPath = path.join(rawDir, `${scene.id}.png`);
          await captureRaw(browser, target, locale, scene, rawPath);
          await renderPromo(browser, target, locale, scene, rawPath, path.join(promoDir, `${scene.id}.png`));
          console.log(`${target.id}/${locale.id}/${scene.id}`);
        }
      }
    }
  } finally {
    await browser.close();
    if (server) {
      server.kill();
    }
  }
}

async function captureRaw(browser, target, locale, scene, outputPath) {
  const context = await browser.newContext({
    ...devices['Desktop Chrome'],
    viewport: target.viewport,
    deviceScaleFactor: target.deviceScaleFactor,
    isMobile: target.id.startsWith('iphone'),
    hasTouch: true,
    locale: locale.locale,
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  await waitForApp(page);
  await completeOnboarding(page, locale);
  await ensureDemoNotes(page, locale);
  await scene.prepare(page, locale);
  await page.mouse.move(0, 0);
  await page.waitForTimeout(700);
  await page.screenshot({ path: outputPath, fullPage: false });
  await context.close();
}

async function renderPromo(browser, target, locale, scene, rawPath, outputPath) {
  const context = await browser.newContext({
    viewport: target.output,
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const caption = locale.captions[scene.key];
  const imageData = fs.readFileSync(rawPath).toString('base64');
  const isPhone = target.id.startsWith('iphone');
  const appScale = isPhone ? 0.78 : 0.74;
  const appWidth = Math.round(target.output.width * appScale);
  const topPad = isPhone ? 170 : 190;
  const fontScale = isPhone ? 1 : 1.25;

  await page.setContent(`
    <!doctype html>
    <html lang="${locale.id}">
      <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; }
          body {
            margin: 0;
            width: ${target.output.width}px;
            height: ${target.output.height}px;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            color: #172033;
            background:
              radial-gradient(circle at 18% 12%, rgba(109, 149, 198, 0.24), transparent 30%),
              linear-gradient(165deg, #f9fbff 0%, #e9f2f4 52%, #f7efe9 100%);
          }
          .wrap {
            width: 100%;
            height: 100%;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: ${topPad}px ${isPhone ? 86 : 140}px 0;
          }
          .brand {
            font-size: ${Math.round(30 * fontScale)}px;
            font-weight: 700;
            color: #526073;
            margin-bottom: ${isPhone ? 44 : 56}px;
          }
          h1 {
            width: 100%;
            margin: 0;
            text-align: center;
            font-size: ${Math.round(67 * fontScale)}px;
            line-height: 1.08;
            letter-spacing: 0;
            font-weight: 800;
          }
          p {
            width: 100%;
            margin: ${isPhone ? 30 : 38}px 0 ${isPhone ? 76 : 96}px;
            text-align: center;
            font-size: ${Math.round(33 * fontScale)}px;
            line-height: 1.36;
            font-weight: 500;
            color: #4b5a6c;
          }
          .device {
            width: ${appWidth}px;
            border-radius: ${isPhone ? 72 : 42}px;
            padding: ${isPhone ? 22 : 18}px;
            background: #172033;
            box-shadow: 0 36px 90px rgba(30, 42, 64, 0.24);
          }
          img {
            display: block;
            width: 100%;
            border-radius: ${isPhone ? 52 : 26}px;
          }
        </style>
      </head>
      <body>
        <main class="wrap">
          <div class="brand">HiMemo</div>
          <h1>${escapeHtml(caption.title)}</h1>
          <p>${escapeHtml(caption.subtitle)}</p>
          <div class="device">
            <img src="data:image/png;base64,${imageData}" alt="">
          </div>
        </main>
      </body>
    </html>
  `);
  await page.screenshot({ path: outputPath, fullPage: false });
  await context.close();
}

async function ensureServer() {
  try {
    const response = await fetch(baseUrl);
    if (response.ok) {
      return null;
    }
  } catch (_) {
    // Start a fresh server below.
  }

  await runCommand('.\\.fvm\\flutter_sdk\\bin\\flutter.bat', [
    'build',
    'web',
    '--no-wasm-dry-run',
    '--dart-define=HIMEMO_HIDE_FLAVOR_BANNER=true',
    '-t',
    'lib/main_development.dart',
  ]);

  const server = spawn('npx', ['--yes', 'serve', '-s', 'build/web', '-l', port], {
    cwd: rootDir,
    shell: true,
    stdio: 'ignore',
  });

  const startedAt = Date.now();
  while (Date.now() - startedAt < 300000) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    try {
      const response = await fetch(baseUrl);
      if (response.ok) {
        return server;
      }
    } catch (_) {
      // Keep waiting.
    }
  }
  server.kill();
  throw new Error('Timed out waiting for web server.');
}

function runCommand(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: rootDir,
      shell: true,
      stdio: 'inherit',
    });
    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with ${code}`));
      }
    });
  });
}

async function waitForApp(page) {
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
    localStorage.setItem(
      'flutter.store_assets.seed_demo_notes.v1',
      JSON.stringify(true),
    );
  });
  await page.reload();
  await page.waitForFunction(
    () => document.querySelector('flutter-view'),
    null,
    { timeout: 20000 },
  );
  await page.waitForTimeout(1200);
}

async function completeOnboarding(page, locale) {
  const isJa = locale.id === 'ja';
  const skipNames = isJa ? ['スキップ', 'Skip'] : ['Skip', 'スキップ'];
  const nextNames = isJa ? ['次へ', 'Next'] : ['Next', '次へ'];
  const finishNames = isJa ? ['セットアップ完了', 'Finish setup'] : ['Finish setup', 'セットアップ完了'];
  const setPinNames = isJa ? ['PIN を設定', 'Set PIN'] : ['Set PIN', 'PIN を設定'];
  const saveNames = isJa ? ['保存', 'Save'] : ['Save', '保存'];

  if (!(await hasButton(page, nextNames))) {
    return;
  }
  if (await hasButton(page, skipNames)) {
    await clickByNames(page, skipNames);
    await page.waitForTimeout(900);
    return;
  }
  for (let i = 0; i < 3; i += 1) {
    await clickByNames(page, nextNames);
    await page.waitForTimeout(250);
  }
  await clickByNames(page, setPinNames);
  const pinInput = page.getByRole('textbox').first();
  await pinInput.fill('1234');
  await clickByNames(page, saveNames);
  await page.waitForTimeout(350);
  await clickByNames(page, finishNames);
  await page.waitForTimeout(900);
}

async function clickByNames(page, names) {
  for (const name of names) {
    const button = page.getByRole('button', { name });
    if (await button.count()) {
      await button.first().click();
      return;
    }
    const text = page.getByText(name).first();
    if (await text.count()) {
      await text.click();
      return;
    }
  }
  throw new Error(`Button not found: ${names.join(', ')}`);
}

async function hasButton(page, names) {
  for (const name of names) {
    if (await page.getByRole('button', { name }).count()) {
      return true;
    }
  }
  return false;
}

async function activateTabIndex(page, index) {
  const pathsByIndex = ['notes', 'calendar', 'insights', 'settings'];
  await page.goto(`${baseUrl}/#/${pathsByIndex[index]}`, {
    waitUntil: 'domcontentloaded',
  });
  await page.waitForFunction(
    () => document.querySelector('flutter-view'),
    null,
    { timeout: 20000 },
  );
  await page.waitForTimeout(700);
}

async function openAddNote(page) {
  const addButton = page.getByRole('button', { name: /Add note|ノートを追加/ });
  if (await addButton.count()) {
    await addButton.first().click();
  } else {
    const size = page.viewportSize();
    await page.mouse.click(size.width - 36, size.height - 112);
  }
  await page.waitForTimeout(600);
}

async function ensureDemoNotes(page, locale) {
  await activateTabIndex(page, 0);
  const seededNote = locale.id === 'ja' ? /どうですか|日記|週末の予定/ : /Presentation idea|Journal|Weekend plan/;
  await page.getByText(seededNote).first().waitFor({ timeout: 8000 });
  await page.waitForTimeout(700);
}

async function seedPrivateProfiles(page, locale) {
  const profiles = [
    {
      id: 'store-work',
      name: locale.id === 'ja' ? '仕事用' : 'Work notes',
      createdAt: '2026-05-01T09:00:00.000',
    },
    {
      id: 'store-personal',
      name: locale.id === 'ja' ? '個人用' : 'Personal notes',
      createdAt: '2026-05-02T09:00:00.000',
    },
  ];
  await page.evaluate((payload) => {
    localStorage.setItem(
      'flutter.security.private_profiles.list.v1',
      JSON.stringify(payload),
    );
  }, JSON.stringify(profiles));
  await page.reload();
  await page.waitForFunction(
    () => document.querySelector('flutter-view'),
    null,
    { timeout: 20000 },
  );
  await page.waitForTimeout(1500);
}

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
