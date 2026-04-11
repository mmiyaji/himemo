const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './playwright/tests',
  timeout: 60_000,
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'on-first-retry',
    viewport: { width: 430, height: 932 },
    launchOptions: {
      args: ['--force-renderer-accessibility'],
    },
  },
  webServer: {
    command: 'npm run web:serve:test',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: true,
    timeout: 300_000,
  },
  projects: [
    {
      name: 'chromium',
    },
  ],
});
