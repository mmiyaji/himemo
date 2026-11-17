const { defineConfig } = require('@playwright/test');
const path = require('path');

module.exports = defineConfig({
  testDir: './v2-storage',
  timeout: 60_000,
  use: { baseURL: 'http://127.0.0.1:4187', serviceWorkers: 'block' },
  webServer: {
    command: 'node node_modules/serve/build/main.js -s -l tcp://127.0.0.1:4187 --no-port-switching build/v2-web-storage-probe',
    cwd: path.resolve(__dirname, '..'),
    url: 'http://127.0.0.1:4187',
    reuseExistingServer: true,
    timeout: 60_000,
  },
});
