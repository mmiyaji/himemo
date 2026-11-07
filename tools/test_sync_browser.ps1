param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$flutterVersion = (Get-Content -LiteralPath (Join-Path $repoRoot '.fvmrc') -Raw | ConvertFrom-Json).flutter
$flutterRoot = "D:\Flutter\versions\$flutterVersion"
$testAssetsPath = Join-Path $repoRoot 'test\canvaskit'
$markerPath = Join-Path $testAssetsPath '.codex-test-assets'
if (Test-Path -LiteralPath $testAssetsPath) {
  throw "Temporary test asset directory already exists: $testAssetsPath"
}

# Flutter 3.47's test server uses Windows separators before checking a URL
# prefix containing '/'. Its test-root static fallback can serve the same
# installed assets without modifying the shared SDK or downloading a renderer.
$testExitCode = 1
try {
  New-Item -ItemType Directory -Path (Join-Path $testAssetsPath 'chromium') | Out-Null
  Set-Content -LiteralPath $markerPath -Value 'temporary-browser-test-assets'
  foreach ($relativePath in @('canvaskit.js', 'canvaskit.wasm', 'chromium\canvaskit.js', 'chromium\canvaskit.wasm')) {
    Copy-Item -LiteralPath (Join-Path $flutterRoot "bin\cache\flutter_web_sdk\canvaskit\$relativePath") -Destination (Join-Path $testAssetsPath $relativePath)
  }
  Push-Location -LiteralPath $repoRoot
  try {
    & (Join-Path $flutterRoot 'bin\flutter.bat') test --platform chrome --timeout 2m test/sync_attachment_browser_test.dart
    $testExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }
} finally {
  if (Test-Path -LiteralPath $markerPath) {
    $resolvedTestAssetsPath = (Resolve-Path -LiteralPath $testAssetsPath).Path
    $expectedTestAssetsPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'test\canvaskit'))
    if ($resolvedTestAssetsPath -ne $expectedTestAssetsPath) {
      throw 'Refusing to remove a temporary asset directory outside the expected test path.'
    }
    Remove-Item -LiteralPath $resolvedTestAssetsPath -Recurse -Force
  }
}
exit $testExitCode
