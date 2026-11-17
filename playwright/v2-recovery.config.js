const { defineConfig } = require('@playwright/test');
const path = require('path');

module.exports = defineConfig({
  testDir: './v2-recovery',
  timeout: 90_000,
  use: {
    baseURL: 'http://127.0.0.1:4189',
    serviceWorkers: 'block',
    launchOptions: { args: ['--force-renderer-accessibility'] },
  },
  webServer: {
    command: 'node node_modules/serve/build/main.js -l tcp://127.0.0.1:4189 --no-port-switching build/v2-web-recovery-suite',
    cwd: path.resolve(__dirname, '..'),
    url: 'http://127.0.0.1:4189',
    reuseExistingServer: false,
    timeout: 60_000,
  },
});
