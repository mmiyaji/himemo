const { defineConfig } = require('@playwright/test');
const path = require('path');

module.exports = defineConfig({
  testDir: './v2-secrets',
  timeout: 90_000,
  use: { baseURL: 'http://127.0.0.1:4188', serviceWorkers: 'block' },
  webServer: {
    command: 'node node_modules/serve/build/main.js -s -l tcp://127.0.0.1:4188 --no-port-switching build/v2-web-secrets-probe',
    cwd: path.resolve(__dirname, '..'),
    url: 'http://127.0.0.1:4188',
    reuseExistingServer: false,
    timeout: 60_000,
  },
});
