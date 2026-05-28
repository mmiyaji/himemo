const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sourceDir = path.join(root, 'node_modules', 'sql.js', 'dist');
const targetDir = path.join(root, 'web', 'vendor', 'sqljs');
const files = ['sql-wasm.js', 'sql-wasm.wasm'];

fs.mkdirSync(targetDir, { recursive: true });

for (const file of files) {
  const source = path.join(sourceDir, file);
  const target = path.join(targetDir, file);
  if (!fs.existsSync(source)) {
    throw new Error(`Missing sql.js asset: ${source}`);
  }
  fs.copyFileSync(source, target);
}
