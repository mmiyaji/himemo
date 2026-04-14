# Play Integrity Server API

HiMemo では Android の `Play Integrity` token を backend で decode し、同期や鍵操作の直前に検証します。

## 提供中の API

- `issuePlayIntegrityChallengeV2`
  - URL: `https://asia-northeast1-himemo-app-2026.cloudfunctions.net/issuePlayIntegrityChallengeV2`
  - 役割: 短寿命 challenge を発行する
- `verifyPlayIntegrityV2`
  - URL: `https://verifyplayintegrityv2-4yz7jselhq-an.a.run.app`
  - 役割: Play Integrity token を decode して challenge / package / verdict を検証する
- region: `asia-northeast1`
- file: [C:\Users\mail\Documents\git\himemo\functions\index.js](C:\Users\mail\Documents\git\himemo\functions\index.js)

## 改善した点

従来は client が自前生成した `requestHash` をそのまま backend が照合していました。現在は次の方式です。

1. backend が短寿命 challenge を発行
2. Android がその challenge を nonce として Play Integrity token を要求
3. backend が challenge 署名、期限、package、operation を検証
4. decode 済み token の `requestHash` または `nonce` が challenge と一致することを確認
5. verdict を評価して高リスク操作の許可を返す

これにより、client 側だけで成立する任意の `requestHash` よりは強い検証になります。

## コストを抑える設定

この関数は常時起動を避ける設定にしています。

- `minInstances: 0`
- `maxInstances: 3`
- `memory: 128MiB`
- `timeoutSeconds: 10` or `15`

加えて、challenge 発行側には簡易 rate limit を入れています。

## Secret

- secret name: `PLAY_INTEGRITY_CHALLENGE_SECRET`

設定例:

```powershell
cd C:\Users\mail\Documents\git\himemo
firebase functions:secrets:set PLAY_INTEGRITY_CHALLENGE_SECRET --project himemo-app-2026
```

## 許可 package

既定では本番 package だけを受け付けます。

- `org.ruhenheim.himemo`

開発 package を使う場合は環境変数で明示的に許可します。

- `HIMEMO_ALLOWED_ANDROID_DEV_PACKAGES`
  - 例: `org.ruhenheim.himemo.dev`

本番側 package を追加したい場合:

- `HIMEMO_ALLOWED_ANDROID_PACKAGES`

## Challenge 発行

`POST /issuePlayIntegrityChallengeV2`

```json
{
  "packageName": "org.ruhenheim.himemo",
  "operation": "sync-upload"
}
```

レスポンス例:

```json
{
  "ok": true,
  "challenge": "eyJwYWNrYWdlTmFtZSI6Im9yZy5ydWhlbmhlaW0uaGltZW1vIiwiLi4uIn0.sig",
  "expiresInSeconds": 60
}
```

## 検証

`POST /verifyPlayIntegrityV2`

```json
{
  "packageName": "org.ruhenheim.himemo",
  "operation": "sync-upload",
  "challenge": "eyJwYWNrYWdlTmFtZSI6Im9yZy5ydWhlbmhlaW0uaGltZW1vIiwiLi4uIn0.sig",
  "integrityToken": "eyJhbGciOiJFUzI1NiIs..."
}
```

レスポンス例:

```json
{
  "ok": true,
  "verdictOk": true,
  "packageMatches": true,
  "requestChallengeMatches": true,
  "requestHashMatches": false,
  "nonceMatches": true,
  "appIntegrity": {
    "appRecognitionVerdict": "PLAY_RECOGNIZED",
    "packageName": "org.ruhenheim.himemo",
    "certificateDigests": [],
    "versionCode": "1"
  },
  "deviceIntegrity": {
    "verdicts": ["MEETS_DEVICE_INTEGRITY"],
    "requiresDeviceIntegrity": true
  },
  "accountDetails": {
    "appLicensingVerdict": "LICENSED"
  },
  "requestDetails": {
    "requestHash": null,
    "nonce": "ZXlKd1lXTnJZV2RsVG1GdFpTSTZJbTl5Wnk1eWRXaGxibWhsYVcwdWFHbHRaVzF2Li4u",
    "timestampMillis": "1713090000000"
  }
}
```

## 判定ルール

本番 package では次を満たしたときだけ `verdictOk == true` です。

- package が一致
- challenge が一致
- `appRecognitionVerdict == PLAY_RECOGNIZED`
- `deviceRecognitionVerdict` に `MEETS_DEVICE_INTEGRITY` 以上が含まれる
- `appLicensingVerdict == LICENSED`

開発 package は `MEETS_BASIC_INTEGRITY` まで許容できますが、明示的に許可した場合だけ使う想定です。

## デプロイ

```powershell
cd C:\Users\mail\Documents\git\himemo\functions
npm install
cd ..
firebase deploy --only functions --project himemo-app-2026
```

## Flutter 側

challenge 発行と検証 client:

- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart)
- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_service.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_service.dart)

Android bridge:

- [C:\Users\mail\Documents\git\himemo\android\app\src\main\kotlin\org\ruhenheim\himemo\MainActivity.kt](C:\Users\mail\Documents\git\himemo\android\app\src\main\kotlin\org\ruhenheim\himemo\MainActivity.kt)

現在の高リスク適用箇所:

- Google Drive への同期 upload
- sync key import

## 今後の強化候補

- App Check 連携
- Cloud Armor か前段の rate limit 強化
- 証明書 digest の allowlist
- backend 側の操作別ログとアラート
