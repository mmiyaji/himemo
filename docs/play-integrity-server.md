# Play Integrity Server

HiMemo の `Play Integrity` 検証は、Android のクラウド同期を最初に有効化するときだけ実行します。通常のオフラインメモ利用、既存ノートの閲覧・編集、既に有効化済みの同期処理には毎回の検証を掛けません。

## 目的

- 同期を有効化する端末が Google Play 配布の正規アプリかを確認する
- 改変端末や不正クライアントによる初回同期設定を防ぎやすくする
- オフライン中心のメモ体験を邪魔しない

## デプロイ済み API

- Challenge 発行
  - `https://issueplayintegritychallengev2-4yz7jselhq-an.a.run.app`
- 検証
  - `https://verifyplayintegrityv2-4yz7jselhq-an.a.run.app`
- region
  - `asia-northeast1`
- 実装
  - [C:\Users\mail\Documents\git\himemo\functions\index.js](C:\Users\mail\Documents\git\himemo\functions\index.js)

## セキュリティ方針

### App Check を必須にする

両 endpoint とも `Firebase App Check` を必須にしています。Flutter Android 側では Firebase 初期化後に App Check を有効化します。

- production
  - `AndroidProvider.playIntegrity`
- development
  - `AndroidProvider.debug`

関連実装:

- [C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart](C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart)
- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart)

### server-issued / one-time challenge

challenge は backend が署名付きで発行し、Firestore に一時保存します。

- challenge は `60 秒` の短寿命
- challenge は `packageName` と `operation` に束縛
- challenge は `App Check appId` に束縛
- 検証時に Firestore transaction で消費し、再利用できない

これで client が任意の `requestHash` を作る方式はやめています。

### freshness 検証

decode 後の `requestDetails.timestampMillis` を確認し、次を満たさない token は拒否します。

- challenge 発行時刻より極端に古くない
- challenge の期限外でない
- 現在時刻から見て古すぎない

### package / verdict 条件

本番では次を必須にしています。

- `packageName == org.ruhenheim.himemo`
- `appRecognitionVerdict == PLAY_RECOGNIZED`
- `appLicensingVerdict == LICENSED`
- `MEETS_DEVICE_INTEGRITY` 以上

development package を backend で許可する場合は、環境変数で明示します。

## Functions のコスト設定

コストを抑えるため、関数設定は最小寄りです。

- `minInstances: 0`
- `maxInstances: 3`
- `memory: 128MiB`
- `timeoutSeconds: 10` または `15`
- `cors: false`

加えて、endpoint ごとに簡易 rate limit を入れています。

## Firestore 使用

collection:

- `playIntegrityChallenges`

保存内容:

- `packageName`
- `operation`
- `appId`
- `issuedAt`
- `expiresAt`

challenge は検証時に transaction で削除します。期限切れ challenge は発行時に軽く掃除します。

## Secret

- secret 名
  - `PLAY_INTEGRITY_CHALLENGE_SECRET`

設定例:

```powershell
cd C:\Users\mail\Documents\git\himemo
firebase functions:secrets:set PLAY_INTEGRITY_CHALLENGE_SECRET --project himemo-app-2026
```

## 許可 package

本番の既定値:

- `org.ruhenheim.himemo`

development package を backend で許可したい場合だけ、環境変数で明示します。

- `HIMEMO_ALLOWED_ANDROID_DEV_PACKAGES`
  - 例: `org.ruhenheim.himemo.dev`

## リクエスト例

### Challenge

`POST /issuePlayIntegrityChallengeV2`

```json
{
  "packageName": "org.ruhenheim.himemo",
  "operation": "sync.enable"
}
```

レスポンス:

```json
{
  "ok": true,
  "challenge": "eyJjaGFsbGVuZ2VJZCI6Ii4uLiJ9.sig",
  "expiresInSeconds": 60
}
```

### Verify

`POST /verifyPlayIntegrityV2`

```json
{
  "packageName": "org.ruhenheim.himemo",
  "operation": "sync.enable",
  "challenge": "eyJjaGFsbGVuZ2VJZCI6Ii4uLiJ9.sig",
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
  "freshnessOk": true,
  "deviceIntegrity": {
    "verdicts": ["MEETS_DEVICE_INTEGRITY"],
    "requiresDeviceIntegrity": true
  }
}
```

## Flutter 側の流れ

1. App Check token を取得
2. backend に challenge を要求
3. challenge を `requestHash` として Play Integrity token を取得
4. backend に token と challenge を送る
5. backend が `App Check / one-time challenge / freshness / verdict` を検証
6. 成功したら同期有効化を許可

関連実装:

- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart)
- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_service.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_service.dart)
- [C:\Users\mail\Documents\git\himemo\android\app\src\main\kotlin\org\ruhenheim\himemo\MainActivity.kt](C:\Users\mail\Documents\git\himemo\android\app\src\main\kotlin\org\ruhenheim\himemo\MainActivity.kt)

## デプロイ

```powershell
cd C:\Users\mail\Documents\git\himemo\functions
npm install
cd ..
firebase deploy --only functions --project himemo-app-2026
```

## 今後の強化候補

- Firestore TTL policy の有効化
- Cloud Armor など前段の rate limit 強化
- `certificateDigests` の allowlist 化
- 同期有効化成功イベントの監査ログ追加
