param(
    [string]$Apk = "$env:USERPROFILE\Downloads\app-debug.apk",
    [string]$Avd = "poc_api30_atd",
    [int]$BootTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

if (-not $env:ANDROID_HOME) {
    $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
}

$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$emu = Join-Path $env:ANDROID_HOME 'emulator\emulator.exe'

Write-Host "===== ANDROID VM APK TEST ====="
Write-Host "ANDROID_HOME=$env:ANDROID_HOME"
Write-Host "AVD=$Avd"
Write-Host "APK=$Apk"

if (-not (Test-Path $adb)) { Fail "adb.exe not found: $adb" }
if (-not (Test-Path $emu)) { Fail "emulator.exe not found: $emu" }
if (-not (Test-Path $Apk)) { Fail "APK not found: $Apk" }

Write-Host "===== [1] ACCELERATION ====="
$accel = (& $emu -accel-check 2>&1 | Out-String)
Write-Host $accel.Trim()
if ($LASTEXITCODE -ne 0 -or $accel -notmatch 'installed and usable') {
    Fail 'Hardware acceleration is not reported as usable.'
}

Write-Host "===== [2] DEVICE ====="
$devices = (& $adb devices | Out-String)
$deviceReady = $devices -match '(?m)^emulator-\d+\s+device\s*$'

$bootWatch = [Diagnostics.Stopwatch]::StartNew()
if (-not $deviceReady) {
    Write-Host "No ready emulator found. Starting AVD: $Avd"
    Start-Process -FilePath $emu -ArgumentList @(
        '-avd', $Avd,
        '-no-audio'
    ) | Out-Null
} else {
    Write-Host 'Reusing running emulator.'
}

$deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
do {
    Start-Sleep -Seconds 2
    $serialLine = (& $adb devices | Select-String '^emulator-\d+\s+device$' | Select-Object -First 1)
    if ($serialLine) {
        $boot = (& $adb shell getprop sys.boot_completed 2>$null | Out-String).Trim()
    } else {
        $boot = ''
    }
    Write-Host '.' -NoNewline
} until ($boot -eq '1' -or (Get-Date) -gt $deadline)
Write-Host ''
$bootWatch.Stop()

if ($boot -ne '1') { Fail "AVD did not finish booting within $BootTimeoutSeconds seconds." }

Write-Host ("BOOT_READY_SECONDS={0:N1}" -f $bootWatch.Elapsed.TotalSeconds)
Write-Host (& $adb devices | Out-String).Trim()

Write-Host "===== [3] GUEST INFO ====="
$qemu = (& $adb shell getprop ro.kernel.qemu | Out-String).Trim()
$api = (& $adb shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb shell getprop ro.product.cpu.abi | Out-String).Trim()
Write-Host "QEMU=$qemu"
Write-Host "API=$api"
Write-Host "ABI=$abi"
if ($qemu -ne '1') { Fail 'Connected Android target is not reporting QEMU.' }

Write-Host "===== [4] INSTALL APK ====="
$install = (& $adb install -r $Apk 2>&1 | Out-String)
Write-Host $install.Trim()
if ($LASTEXITCODE -ne 0 -or $install -notmatch '(?m)^Success\s*$') {
    Fail 'APK installation failed.'
}

Write-Host "===== [5] LAUNCH APP ====="
$launch = (& $adb shell am start -W -n 'com.banupham.virtualizationtest/.MainActivity' 2>&1 | Out-String)
Write-Host $launch.Trim()
if ($LASTEXITCODE -ne 0 -or $launch -match 'Error:|Exception') {
    Fail 'Application launch failed.'
}

$packagePath = (& $adb shell pm path com.banupham.virtualizationtest 2>&1 | Out-String).Trim()
if ($packagePath -notmatch '^package:') { Fail 'Package verification failed after launch.' }

$totalTime = [regex]::Match($launch, '(?m)^TotalTime:\s*(\d+)').Groups[1].Value

Write-Host "===== RESULT ====="
Write-Host 'PASS'
Write-Host "AVD=$Avd"
Write-Host "API=$api"
Write-Host "ABI=$abi"
if ($totalTime) { Write-Host "APP_TOTAL_TIME_MS=$totalTime" }
Write-Host "PACKAGE=$packagePath"
exit 0
