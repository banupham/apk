param(
    [string]$Repo = "banupham/apk",
    [string]$LatestRunner = "$env:USERPROFILE\Downloads\latest-test.ps1"
)

$ErrorActionPreference = 'Stop'

if (-not $env:ANDROID_HOME) {
    $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
}

$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    throw "adb.exe not found: $adb"
}

$cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$latestUrl = "https://raw.githubusercontent.com/$Repo/main/latest-test.ps1?v=$cacheBust"
$headers = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

Write-Host "===== INDEPENDENT EMULATOR DETECTOR RUNNER ====="
Write-Host "REPO=$Repo"

Write-Host "===== [1] REFRESH PIPELINE RUNNER ====="
Invoke-WebRequest -Uri $latestUrl -Headers $headers -OutFile $LatestRunner -UseBasicParsing
Unblock-File $LatestRunner

Write-Host "===== [2] CLEAR DETECTOR LOG ====="
& $adb logcat -c

Write-Host "===== [3] DOWNLOAD / INSTALL / LAUNCH APK ====="
& $LatestRunner
if ($LASTEXITCODE -ne 0) {
    throw "APK pipeline failed with exit code $LASTEXITCODE"
}

$serialLine = (& $adb devices | Select-String '^emulator-\d+\s+device$' | Select-Object -First 1)
if (-not $serialLine) {
    throw 'No ready emulator found after APK launch.'
}
$serial = (($serialLine.ToString() -split '\s+')[0]).Trim()
Write-Host "SERIAL=$serial"

Start-Sleep -Seconds 1

Write-Host "===== [4] APP-LEVEL DETECTOR REPORT ====="
$log = (& $adb -s $serial logcat -d -s 'EmulatorDetector:I' '*:S' | Out-String)
Write-Host $log.Trim()

$summary = [regex]::Match($log, 'STRICT_RESULT=(PASS|FAIL)\s+SCORE=(\d+)\s+DETECTED=(\d+)')
if (-not $summary.Success) {
    throw 'Detector summary was not found in logcat. Make sure the latest APK containing EmulatorDetector is published.'
}

$result = $summary.Groups[1].Value
$score = $summary.Groups[2].Value
$detected = $summary.Groups[3].Value

Write-Host "===== DETECTOR RESULT ====="
Write-Host "STRICT_RESULT=$result"
Write-Host "SCORE=$score"
Write-Host "DETECTED_SIGNALS=$detected"

if ($result -eq 'PASS') {
    exit 0
}
exit 2
