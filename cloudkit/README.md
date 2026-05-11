# CloudKit Schema

HiMemo manages the expected CloudKit schema in this directory so schema changes are reviewed with code changes.

Authoritative files:

- `expected-schema.json`: the record types and fields required by the app code.
- `../ios/Runner/AppDelegate.swift`: the native CloudKit field names used at runtime.

The app uses the CloudKit private database in container `iCloud.org.ruhenheim.himemo`.

## Current Record Types

`HiMemoSyncBundle`

- `bundleAsset`: Asset
- `deviceId`: String
- `noteCount`: Int(64)
- `attachmentCount`: Int(64)
- `exportedAt`: Date/Time

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
