$ErrorActionPreference = 'Stop'

$sdkRoot = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} else {
    'D:\Android\Sdk'
}

$adb = Join-Path $sdkRoot 'platform-tools\adb.exe'
$emulator = Join-Path $sdkRoot 'emulator\emulator.exe'
$avdName = if ($env:HIMEMO_ANDROID_AVD) {
    $env:HIMEMO_ANDROID_AVD
} else {
    'Pixel_7_API_34'
}

if (-not (Test-Path $adb)) {
    throw "adb.exe was not found at $adb"
}

if (-not (Test-Path $emulator)) {
    throw "emulator.exe was not found at $emulator"
}

$devices = & $adb devices | Select-String -Pattern 'device$'
if (-not $devices) {
    Start-Process -FilePath $emulator -ArgumentList @('-avd', $avdName, '-no-snapshot-load', '-no-boot-anim') -WindowStyle Hidden
}

$deadline = (Get-Date).AddMinutes(4)
do {
    Start-Sleep -Seconds 3
    $bootedDevices = & $adb devices | Select-String -Pattern 'device$'
    foreach ($line in $bootedDevices) {
        $deviceId = ($line.ToString() -split '\s+')[0]
        $bootCompleted = & $adb -s $deviceId shell getprop sys.boot_completed 2>$null
        if ($bootCompleted -match '1') {
            Write-Host "Android emulator is ready: $deviceId"
            exit 0
        }
    }
} while ((Get-Date) -lt $deadline)

throw "Timed out waiting for Android emulator '$avdName' to boot."
