const { chromium, devices } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '../..');
const outputDir = path.join(rootDir, 'store-assets', 'app-store');
const googlePlayOutputDir = path.join(rootDir, 'store-assets', 'google-play');
const port = process.env.STORE_ASSET_PORT || '4174';
const baseUrl = `http://127.0.0.1:${port}`;
const googlePlayOnly = process.argv.includes('--google-play-only');

const deviceTargets = [
  {
    id: 'iphone-6-9',
    label: 'iPhone 6.9',
    viewport: { width: 440, height: 956 },
    deviceScaleFactor: 3,
    output: { width: 1320, height: 2868 },
  },
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

const googlePlayPhoneTarget = {
  id: 'iphone-google-play-phone',
  label: 'Google Play phone',
  viewport: { width: 430, height: 764 },
  deviceScaleFactor: 3,
  output: { width: 1080, height: 1920 },
};

const googlePlayTabletTargets = [
  {
    id: 'seven-inch-tablet',
    label: 'Google Play 7-inch tablet',
    viewport: { width: 1024, height: 576 },
    deviceScaleFactor: 1,
    output: { width: 1920, height: 1080 },
  },
  {
    id: 'ten-inch-tablet',
    label: 'Google Play 10-inch tablet',
    viewport: { width: 1366, height: 768 },
    deviceScaleFactor: 1,
    output: { width: 2560, height: 1440 },
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
        title: '鍵で開くプライベート領域',
        subtitle: '名前や保存先IDは見せず、一致した領域だけを開きます。',
      },
      insights: {
        title: '書いた量をグラフで確認',
        subtitle: '件数、連続記録、月ごとの推移をまとめて見返せます。',
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
        title: 'Unlock only the matching profile',
        subtitle: 'Names and vault IDs stay hidden while each space uses its own key.',
      },
      insights: {
        title: 'Track writing activity',
        subtitle: 'Review streaks, note counts, and monthly trends at a glance.',
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
      await activateTabIndex(page, 0);
      await openPrivateProfileUnlockDialog(page, locale);
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
  if (googlePlayOnly) {
    fs.rmSync(googlePlayOutputDir, { recursive: true, force: true });
    fs.mkdirSync(googlePlayOutputDir, { recursive: true });
    const server = await ensureServer();
    const browser = await chromium.launch({
      args: [
        '--force-renderer-accessibility',
        '--use-fake-device-for-media-stream',
        '--use-fake-ui-for-media-stream',
      ],
    });
    try {
      await renderGooglePlayFeatureGraphics(browser);
      await renderGooglePlayPhoneScreenshots(browser);
      await renderGooglePlayTabletScreenshots(browser);
    } finally {
      await browser.close();
      if (server) {
        server.kill();
      }
    }
    return;
  }

  fs.rmSync(outputDir, { recursive: true, force: true });
  fs.rmSync(googlePlayOutputDir, { recursive: true, force: true });
  fs.mkdirSync(outputDir, { recursive: true });
  fs.mkdirSync(googlePlayOutputDir, { recursive: true });
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
    await renderGooglePlayFeatureGraphics(browser);
    await renderGooglePlayPhoneScreenshots(browser);
    await renderGooglePlayTabletScreenshots(browser);
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

async function renderGooglePlayPhoneScreenshots(browser) {
  const rawRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'himemo-google-play-phone-'));
  try {
    for (const locale of locales) {
      const outputRoot = path.join(
        googlePlayOutputDir,
        locale.id,
        'phone-screenshots',
      );
      fs.mkdirSync(outputRoot, { recursive: true });
      for (const scene of scenes) {
        const rawPath = path.join(rawRoot, `${locale.id}-${scene.id}.png`);
        await captureRaw(browser, googlePlayPhoneTarget, locale, scene, rawPath);
        await renderGooglePlayPhonePromo(
          browser,
          locale,
          scene,
          rawPath,
          path.join(outputRoot, `${scene.id}.png`),
        );
        console.log(`google-play/${locale.id}/phone-screenshots/${scene.id}`);
      }
    }
  } finally {
    fs.rmSync(rawRoot, { recursive: true, force: true });
  }
}

async function renderGooglePlayPhonePromo(browser, locale, scene, rawPath, outputPath) {
  const target = googlePlayPhoneTarget;
  const context = await browser.newContext({
    viewport: target.output,
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const caption = locale.captions[scene.key];
  const imageData = fs.readFileSync(rawPath).toString('base64');

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
              radial-gradient(circle at 18% 12%, rgba(231, 132, 143, 0.22), transparent 32%),
              radial-gradient(circle at 78% 72%, rgba(11, 99, 173, 0.14), transparent 34%),
              linear-gradient(165deg, #f9fbff 0%, #e9f2f4 52%, #f7efe9 100%);
          }
          .wrap {
            width: 100%;
            height: 100%;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 82px 74px 0;
          }
          .brand {
            font-size: 24px;
            font-weight: 700;
            color: #526073;
            margin-bottom: 20px;
          }
          h1 {
            width: 100%;
            margin: 0;
            text-align: center;
            font-size: ${locale.id === 'ja' ? 54 : 50}px;
            line-height: 1.09;
            letter-spacing: 0;
            font-weight: 820;
          }
          p {
            width: 100%;
            margin: 18px 0 34px;
            text-align: center;
            font-size: ${locale.id === 'ja' ? 27 : 25}px;
            line-height: 1.34;
            font-weight: 500;
            color: #4b5a6c;
          }
          .device {
            width: 760px;
            border-radius: 68px;
            padding: 20px;
            background: #172033;
            box-shadow: 0 34px 82px rgba(30, 42, 64, 0.24);
          }
          img {
            display: block;
            width: 100%;
            border-radius: 48px;
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

async function renderGooglePlayTabletScreenshots(browser) {
  const rawRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'himemo-google-play-tablet-'));
  try {
    for (const target of googlePlayTabletTargets) {
      for (const locale of locales) {
        const outputRoot = path.join(
          googlePlayOutputDir,
          locale.id,
          `${target.id}-screenshots`,
        );
        fs.mkdirSync(outputRoot, { recursive: true });
        for (const scene of scenes) {
          const rawPath = path.join(rawRoot, `${target.id}-${locale.id}-${scene.id}.png`);
          await captureRaw(browser, target, locale, scene, rawPath);
          await renderGooglePlayTabletPromo(
            browser,
            target,
            locale,
            scene,
            rawPath,
            path.join(outputRoot, `${scene.id}.png`),
          );
          console.log(`google-play/${locale.id}/${target.id}-screenshots/${scene.id}`);
        }
      }
    }
  } finally {
    fs.rmSync(rawRoot, { recursive: true, force: true });
  }
}

async function renderGooglePlayTabletPromo(browser, target, locale, scene, rawPath, outputPath) {
  const context = await browser.newContext({
    viewport: target.output,
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const caption = locale.captions[scene.key];
  const imageData = fs.readFileSync(rawPath).toString('base64');
  const isLarge = target.id === 'ten-inch-tablet';
  const scale = target.output.width / 1920;
  const titleSize = Math.round((locale.id === 'ja' ? 46 : 50) * scale);
  const subtitleSize = Math.round((locale.id === 'ja' ? 25 : 23) * scale);
  const deviceWidth = Math.round(target.output.width * 0.62);
  const framePadding = Math.round(14 * scale);

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
              radial-gradient(circle at 16% 18%, rgba(231, 132, 143, 0.22), transparent 34%),
              radial-gradient(circle at 86% 72%, rgba(11, 99, 173, 0.16), transparent 36%),
              linear-gradient(145deg, #f9fbff 0%, #e9f2f4 54%, #f7efe9 100%);
          }
          .wrap {
            width: 100%;
            height: 100%;
            display: grid;
            grid-template-columns: 0.9fr 1.35fr;
            align-items: center;
            gap: ${Math.round(58 * scale)}px;
            padding: ${Math.round(74 * scale)}px ${Math.round(92 * scale)}px;
          }
          .copy {
            min-width: 0;
          }
          .brand {
            font-size: ${Math.round(23 * scale)}px;
            font-weight: 700;
            color: #526073;
            margin-bottom: ${Math.round(24 * scale)}px;
          }
          h1 {
            margin: 0;
            font-size: ${titleSize}px;
            line-height: 1.1;
            letter-spacing: 0;
            font-weight: 820;
          }
          p {
            margin: ${Math.round(22 * scale)}px 0 0;
            font-size: ${subtitleSize}px;
            line-height: 1.36;
            font-weight: 500;
            color: #4b5a6c;
          }
          .device {
            justify-self: end;
            width: ${deviceWidth}px;
            border-radius: ${Math.round((isLarge ? 46 : 38) * scale)}px;
            padding: ${framePadding}px;
            background: #172033;
            box-shadow: 0 ${Math.round(32 * scale)}px ${Math.round(82 * scale)}px rgba(30, 42, 64, 0.24);
          }
          img {
            display: block;
            width: 100%;
            border-radius: ${Math.round((isLarge ? 30 : 24) * scale)}px;
          }
        </style>
      </head>
      <body>
        <main class="wrap">
          <section class="copy">
            <div class="brand">HiMemo</div>
            <h1>${escapeHtml(caption.title)}</h1>
            <p>${escapeHtml(caption.subtitle)}</p>
          </section>
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

async function renderGooglePlayFeatureGraphics(browser) {
  const appIconData = fs
    .readFileSync(path.join(rootDir, 'assets', 'app-icon.png'))
    .toString('base64');
  const copies = {
    ja: {
      title: 'すばやく残せる、プライベートなメモ',
      subtitle: '複数プロファイルをロックして、日々の記録を安全に整理。',
    },
    en: {
      title: 'Fast private notes with profile lock',
      subtitle: 'Capture, separate, back up, and sync your personal records.',
    },
  };

  for (const locale of locales) {
    const copy = copies[locale.id];
    const context = await browser.newContext({
      viewport: { width: 1024, height: 500 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await page.setContent(`
      <!doctype html>
      <html lang="${locale.id}">
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              width: 1024px;
              height: 500px;
              overflow: hidden;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              color: #172033;
              background:
                radial-gradient(circle at 18% 14%, rgba(231, 132, 143, 0.24), transparent 32%),
                radial-gradient(circle at 84% 70%, rgba(11, 99, 173, 0.14), transparent 34%),
                linear-gradient(150deg, #f8fbff 0%, #e9f2f5 58%, #f8eee9 100%);
            }
            .wrap {
              width: 100%;
              height: 100%;
              display: grid;
              grid-template-columns: 1fr 300px;
              align-items: center;
              gap: 48px;
              padding: 58px 76px;
            }
            .brand {
              font-size: 30px;
              font-weight: 700;
              color: #526073;
              margin-bottom: 34px;
            }
            h1 {
              margin: 0;
              max-width: 560px;
              font-size: 56px;
              line-height: 1.07;
              letter-spacing: 0;
              font-weight: 820;
            }
            p {
              margin: 28px 0 0;
              max-width: 560px;
              color: #4b5a6c;
              font-size: 25px;
              line-height: 1.35;
              font-weight: 520;
            }
            .icon-card {
              position: relative;
              width: 300px;
              height: 300px;
              display: grid;
              place-items: center;
            }
            .icon-card::before {
              content: "";
              position: absolute;
              inset: 16px 8px 2px 8px;
              border-radius: 68px;
              background: rgba(255, 255, 255, 0.62);
              border: 2px solid rgba(141, 160, 180, 0.30);
              box-shadow: 0 32px 82px rgba(30, 42, 64, 0.20);
              transform: rotate(-3deg);
            }
            .icon-card img {
              position: relative;
              width: 230px;
              height: 230px;
              object-fit: cover;
              border-radius: 52px;
              box-shadow: 0 24px 54px rgba(11, 99, 173, 0.22);
            }
          </style>
        </head>
        <body>
          <main class="wrap">
            <section>
              <div class="brand">HiMemo</div>
              <h1>${escapeHtml(copy.title)}</h1>
              <p>${escapeHtml(copy.subtitle)}</p>
            </section>
            <div class="icon-card" aria-hidden="true">
              <img src="data:image/png;base64,${appIconData}" alt="">
            </div>
          </main>
        </body>
      </html>
    `);
    const outputPath = path.join(googlePlayOutputDir, locale.id, 'feature-graphic.png');
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    await page.screenshot({ path: outputPath, fullPage: false });
    await context.close();
    console.log(`google-play/${locale.id}/feature-graphic`);
  }
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

async function openPrivateProfileUnlockDialog(page, locale) {
  const names = locale.id === 'ja'
    ? [/プライベートプロファイルを開く/, /Unlock private profile/]
    : [/Unlock private profile/, /プライベートプロファイルを開く/];
  let opened = false;
  for (const name of names) {
    const button = page.getByRole('button', { name }).first();
    if (await button.count()) {
      await button.click({ force: true });
      opened = true;
      break;
    }
  }
  if (!opened) {
    const size = page.viewportSize();
    await page.mouse.click(size.width - 42, 56);
  }
  await page.waitForTimeout(700);
  const passwordInput = page.locator('[data-key="private-profile-unlock-password-input"]').first();
  if (await passwordInput.count()) {
    await passwordInput.fill(locale.id === 'ja' ? 'himemo-key' : 'private-key');
  } else {
    const textBox = page.getByRole('textbox').first();
    if (await textBox.count()) {
      await textBox.fill(locale.id === 'ja' ? 'himemo-key' : 'private-key');
    }
  }
  await page.waitForTimeout(700);
}

async function ensureDemoNotes(page, locale) {
  await activateTabIndex(page, 0);
  const seededNote = locale.id === 'ja'
    ? /買い物メモ|共有会の準備|日記|週末の予定/
    : /Shopping list|Sharing meeting prep|Journal|Weekend plan/;
  await page.getByText(seededNote).first().waitFor({ timeout: 15000 });
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
