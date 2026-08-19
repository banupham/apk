param(
    [string]$Repo = "banupham/apk",
    [string]$Apk = "$env:USERPROFILE\Downloads\app-debug.apk",
    [string]$TestScript = "$env:USERPROFILE\Downloads\test-apk.ps1",
    [switch]$ColdBoot,
    [switch]$Headless,
    [switch]$StopAfter
)

$ErrorActionPreference = 'Stop'

$cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$apkUrl = "https://github.com/$Repo/releases/download/latest-test/app-debug.apk?v=$cacheBust"
$testUrl = "https://raw.githubusercontent.com/$Repo/main/test-apk.ps1?v=$cacheBust"
$headers = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

Write-Host "===== LATEST APK -> VM TEST ====="
Write-Host "REPO=$Repo"
Write-Host "APK_URL=$apkUrl"
Write-Host "APK=$Apk"
Write-Host "TEST_SCRIPT=$TestScript"

Write-Host "===== [1] DOWNLOAD LATEST APK ====="
Invoke-WebRequest -Uri $apkUrl -Headers $headers -OutFile $Apk -UseBasicParsing
$apkFile = Get-Item $Apk
$apkHash = (Get-FileHash $Apk -Algorithm SHA256).Hash
Write-Host "APK_BYTES=$($apkFile.Length)"
Write-Host "APK_SHA256=$apkHash"

Write-Host "===== [2] REFRESH TEST SCRIPT ====="
Invoke-WebRequest -Uri $testUrl -Headers $headers -OutFile $TestScript -UseBasicParsing
Unblock-File $TestScript

$testText = Get-Content $TestScript -Raw
if ($testText -notmatch 'Invoke-AdbCapture' -or
    $testText -notmatch 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' -or
    $testText -notmatch 'RedirectStandardError') {
    throw 'Downloaded test-apk.ps1 is stale or incomplete; expected clean signature-mismatch recovery code was not found.'
}
Write-Host 'TEST_SCRIPT_VERSION=SIGNATURE_RECOVERY_V3_CLEAN_STDERR'

Write-Host "===== [3] RUN VM TEST ====="
$argsForTest = @{
    Apk = $Apk
}
if ($ColdBoot) { $argsForTest['ColdBoot'] = $true }
if ($Headless) { $argsForTest['Headless'] = $true }
if ($StopAfter) { $argsForTest['StopAfter'] = $true }

& $TestScript @argsForTest
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "VM APK test failed with exit code $exitCode"
}

Write-Host "===== PIPELINE RESULT ====="
Write-Host "PASS"
Write-Host "APK_SHA256=$apkHash"
exit 0
