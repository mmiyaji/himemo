param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot '.env'
$flutter = 'D:\Flutter\versions\3.41.6\bin\flutter.bat'

if (-not (Test-Path -LiteralPath $flutter)) {
  $flutter = 'flutter'
}

if (Test-Path -LiteralPath $envPath) {
  Get-Content -LiteralPath $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) {
      return
    }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) {
      return
    }

    $name = $parts[0].Trim()
    $value = $parts[1].Trim()
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    if ($name.Length -gt 0) {
      Set-Item -Path "Env:$name" -Value $value
    }
  }
}

$defines = @()
$supportsDartDefines = $FlutterArgs.Count -gt 0 -and $FlutterArgs[0] -in @(
  'run',
  'build',
  'test',
  'drive'
)

if ($supportsDartDefines) {
  foreach ($name in @(
    'HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID',
    'HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
    'HIMEMO_APP_STORE_ID',
    'HIMEMO_BUILD_DATE',
    'HIMEMO_ENABLE_ADMOB',
    'HIMEMO_ADMOB_FORCE_TEST_ADS',
    'HIMEMO_ADMOB_ANDROID_INLINE_BANNER_AD_UNIT_ID',
    'HIMEMO_ADMOB_IOS_INLINE_BANNER_AD_UNIT_ID'
  )) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      $defines += "--dart-define=$name=$value"
    }
  }
}

& $flutter @FlutterArgs @defines
exit $LASTEXITCODE
