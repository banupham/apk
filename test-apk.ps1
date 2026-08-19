param(
    [string]$Apk = "$env:USERPROFILE\Downloads\app-debug.apk",
    [string]$Avd = "poc_api30_atd",
    [int]$BootTimeoutSeconds = 300,
    [switch]$ColdBoot,
    [switch]$Headless,
    [switch]$StopAfter
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
$packageName = 'com.banupham.virtualizationtest'

function Invoke-AdbCapture {
    param([string[]]$Arguments)

    # Windows PowerShell 5.1 converts native stderr into NativeCommandError
    # records when using 2>&1. Start-Process redirection keeps adb stderr as
    # plain text so expected install failures can be handled without noisy
    # PowerShell error metadata.
    $stdoutFile = [IO.Path]::GetTempFileName()
    $stderrFile = [IO.Path]::GetTempFileName()

    try {
        $processArgs = @(
            foreach ($arg in $Arguments) {
                if ($arg -match '[\s"]') {
                    '"' + ($arg -replace '"', '\"') + '"'
                } else {
                    $arg
                }
            }
        )

        $process = Start-Process -FilePath $script:adb `
            -ArgumentList $processArgs `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = [IO.File]::ReadAllText($stdoutFile)
        $stderr = [IO.File]::ReadAllText($stderrFile)
        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { $parts += $stdout.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { $parts += $stderr.TrimEnd() }
        $text = $parts -join [Environment]::NewLine

        [pscustomobject]@{
            Output = $text
            ExitCode = $process.ExitCode
        }
    }
    finally {
        Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "===== ANDROID VM APK TEST ====="
Write-Host "ANDROID_HOME=$env:ANDROID_HOME"
Write-Host "AVD=$Avd"
Write-Host "APK=$Apk"
Write-Host "REQUESTED_BOOT_MODE=$(if ($ColdBoot) { 'COLD_BOOT' } else { 'QUICK_BOOT_OR_REUSE' })"
Write-Host "HEADLESS=$([bool]$Headless)"

if (-not (Test-Path $adb)) { Fail "adb.exe not found: $adb" }
if (-not (Test-Path $emu)) { Fail "emulator.exe not found: $emu" }
if (-not (Test-Path $Apk)) { Fail "APK not found: $Apk" }

Write-Host "===== [1] ACCELERATION ====="
$accel = (& $emu -accel-check 2>&1 | Out-String)
Write-Host $accel.Trim()
if ($LASTEXITCODE -ne 0 -or $accel -notmatch 'installed and usable') {
    Fail 'Hardware acceleration is not reported as usable.'
}

Write-Host "===== [2] DEVICE / BOOT ====="
$devices = (& $adb devices | Out-String)
$deviceReady = $devices -match '(?m)^emulator-\d+\s+device\s*$'
$actualBootMode = 'REUSE'

if ($ColdBoot -and $deviceReady) {
    Write-Host 'ColdBoot requested. Stopping running emulator first.'
    & $adb emu kill 2>$null | Out-Null
    $stopDeadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        $stillRunning = (& $adb devices | Out-String) -match '(?m)^emulator-\d+\s+device\s*$'
    } until (-not $stillRunning -or (Get-Date) -gt $stopDeadline)
    if ($stillRunning) { Fail 'Running emulator did not stop in time.' }
    $deviceReady = $false
}

$bootWatch = [Diagnostics.Stopwatch]::StartNew()
if (-not $deviceReady) {
    $emuArgs = @('-avd', $Avd, '-no-audio')
    if ($ColdBoot) {
        $emuArgs += '-no-snapshot-load'
        $actualBootMode = 'COLD_BOOT'
    } else {
        $actualBootMode = 'QUICK_BOOT'
    }
    if ($Headless) { $emuArgs += '-no-window' }

    Write-Host "Starting AVD: $Avd"
    Write-Host "BOOT_MODE=$actualBootMode"
    Start-Process -FilePath $emu -ArgumentList $emuArgs | Out-Null
} else {
    Write-Host 'Reusing running emulator.'
    Write-Host 'BOOT_MODE=REUSE'
}

$deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
$serial = $null
$boot = ''
do {
    Start-Sleep -Seconds 1
    $serialLine = (& $adb devices | Select-String '^emulator-\d+\s+device$' | Select-Object -First 1)
    if ($serialLine) {
        $serial = (($serialLine.ToString() -split '\s+')[0]).Trim()
        $boot = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
    } else {
        $boot = ''
    }
    Write-Host '.' -NoNewline
} until ($boot -eq '1' -or (Get-Date) -gt $deadline)
Write-Host ''
$bootWatch.Stop()

if ($boot -ne '1' -or -not $serial) { Fail "AVD did not finish booting within $BootTimeoutSeconds seconds." }

Write-Host ("BOOT_READY_SECONDS={0:N1}" -f $bootWatch.Elapsed.TotalSeconds)
Write-Host "SERIAL=$serial"
Write-Host (& $adb devices | Out-String).Trim()

Write-Host "===== [3] GUEST INFO ====="
$qemu = (& $adb -s $serial shell getprop ro.kernel.qemu | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
Write-Host "QEMU=$qemu"
Write-Host "API=$api"
Write-Host "ABI=$abi"
if ($qemu -ne '1') { Fail 'Connected Android target is not reporting QEMU.' }

Write-Host "===== [4] INSTALL APK ====="
$installResult = Invoke-AdbCapture @('-s', $serial, 'install', '-r', $Apk)
$install = $installResult.Output
Write-Host $install.Trim()

if ($installResult.ExitCode -ne 0 -or $install -notmatch '(?m)^Success\s*$') {
    if ($install -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match') {
        Write-Host 'Detected debug-signature mismatch from a previous build.'
        Write-Host "Uninstalling old test package: $packageName"

        $uninstallResult = Invoke-AdbCapture @('-s', $serial, 'uninstall', $packageName)
        Write-Host $uninstallResult.Output.Trim()
        if ($uninstallResult.ExitCode -ne 0 -or $uninstallResult.Output -notmatch '(?m)^Success\s*$') {
            Fail 'Old package could not be removed after signature mismatch.'
        }

        Write-Host 'Retrying clean APK install.'
        $installResult = Invoke-AdbCapture @('-s', $serial, 'install', $Apk)
        $install = $installResult.Output
        Write-Host $install.Trim()
    }
}

if ($installResult.ExitCode -ne 0 -or $install -notmatch '(?m)^Success\s*$') {
    Fail 'APK installation failed.'
}

Write-Host "===== [5] LAUNCH APP ====="
$launch = (& $adb -s $serial shell am start -W -n "$packageName/.MainActivity" 2>&1 | Out-String)
Write-Host $launch.Trim()
if ($LASTEXITCODE -ne 0 -or $launch -match 'Error:|Exception') {
    Fail 'Application launch failed.'
}

$packagePath = (& $adb -s $serial shell pm path $packageName 2>&1 | Out-String).Trim()
if ($packagePath -notmatch '^package:') { Fail 'Package verification failed after launch.' }

$totalTime = [regex]::Match($launch, '(?m)^TotalTime:\s*(\d+)').Groups[1].Value

Write-Host "===== RESULT ====="
Write-Host 'PASS'
Write-Host "AVD=$Avd"
Write-Host "SERIAL=$serial"
Write-Host "BOOT_MODE=$actualBootMode"
Write-Host "API=$api"
Write-Host "ABI=$abi"
if ($totalTime) { Write-Host "APP_TOTAL_TIME_MS=$totalTime" }
Write-Host "PACKAGE=$packagePath"

if ($StopAfter) {
    Write-Host "===== [6] STOP / SAVE QUICK BOOT STATE ====="
    & $adb -s $serial emu kill 2>$null | Out-Null
    Write-Host 'Emulator stop requested. Quick Boot state will be available on the next normal start when supported.'
}

exit 0
