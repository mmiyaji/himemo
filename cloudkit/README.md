# CloudKit Schema

HiMemo manages the expected CloudKit schema in this directory so schema changes are reviewed with code changes.

Authoritative files:

- `expected-schema.json`: the record types and fields required by the app code.
- `../ios/Runner/AppDelegate.swift`: the native CloudKit field names used at runtime.

The app uses the CloudKit private database in container `iCloud.org.ruhenheim.himemo`.
Sync records are stored in the custom zone `HiMemoSyncZone`; the app creates this zone if it is missing.

## Current Record Types

`HiMemoSyncBundle`

- `bundleAsset`: Asset
- `deviceId`: String
- `noteCount`: Int(64)
- `attachmentCount`: Int(64)
- `exportedAt`: Date/Time
- `bundleSize`: Int(64) - optional metadata for encrypted bundle payload bytes. The app retries uploads without this field when an older Production schema has not deployed it yet.
- `bundleKind`: String — `full` または `delta`。デルタ同期の履歴ウォークが「どこからリプレイすれば全ノートが揃うか」を判定するために使う。未設定のレコードはレガシーのフルスナップショットとして扱われる。

### bundleKind 追加時の iCloud (CloudKit Dev) 修正ポイント

1. CloudKit Console → `iCloud.org.ruhenheim.himemo` → **Development** 環境 → Record Types → `HiMemoSyncBundle` に `bundleKind` (String) フィールドを追加する。
   - クエリ条件には使用しないため Queryable/Sortable インデックスは不要（一覧は既存クエリのまま、判定はレコード読み出し後に行う）。
2. `python tools/cloudkit/check_expected_schema.py` を実行して `expected-schema.json` と一致することを確認する。
3. 動作確認後、CloudKit Console の **Deploy Schema Changes** で Production に反映する（デルタバンドルをアップロードする前に必須。フィールド未定義のまま Production でアップロードすると保存エラーになる）。

`HiMemoSyncAttachment`

- `attachmentAsset`: Asset
- `contentHash`: String
- `attachmentType`: String
- `attachmentLabel`: String
- `attachmentSize`: Int(64)
- `exportedAt`: Date/Time

## Codemagic

Use the `cloudkit-schema-export` workflow to export the current Development and Production schemas as artifacts:

```sh
xcrun cktool export-schema \
  --team-id "$APPLE_TEAM_ID" \
  --container-id "iCloud.org.ruhenheim.himemo" \
  --environment production \
  --output-file build/cloudkit/production-schema.ckdb
```

The workflow requires these secure environment variables:

- `APPLE_TEAM_ID`
- `CLOUDKIT_MANAGEMENT_TOKEN`

`cktool import-schema` can apply a checked schema file to the Development environment, but Apple documents Production deployment through CloudKit Console's "Deploy Schema Changes" flow. Keep Production deployment manual unless Apple adds a supported non-interactive production deploy command.

## Change Process

1. Update `expected-schema.json`.
2. Update app code that reads or writes the affected record type.
3. Run:

   ```sh
   python tools/cloudkit/check_expected_schema.py
   ```

   To validate exported CloudKit schemas against the checked manifest, pass the exported `.ckdb` files:

   ```sh
   python tools/cloudkit/check_expected_schema.py \
     build/cloudkit/development-schema.ckdb \
     build/cloudkit/production-schema.ckdb
   ```

4. Create or update the schema in CloudKit Development.
5. Export Development schema with Codemagic and keep the artifact for review.
6. Deploy schema changes to Production from CloudKit Console.
7. Test TestFlight sync against Production.
