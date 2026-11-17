# Drift WebAssembly assets

These files are the official assets for Drift 2.35.3, the version pinned in
`pubspec.lock`:
https://github.com/simolus3/drift/releases/tag/drift-2.35.3

SHA-256:
- drift_worker.js: a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a
- sqlite3.wasm: efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37

Both assets must be updated together whenever the pinned Drift version changes.
The host must serve `.wasm` files as `application/wasm`.

Drift and sqlite3.dart are distributed under the MIT licenses included here.
SQLite itself is in the public domain; see https://sqlite.org/copyright.html.
