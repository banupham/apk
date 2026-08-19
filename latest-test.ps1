param(
    [string]$Repo = "banupham/apk",
    [string]$Apk = "$env:USERPROFILE\Downloads\app-debug.apk",
    [string]$TestScript = "$env:USERPROFILE\Downloads\test-apk.ps1",
    [switch]$ColdBoot,
    [switch]$Headless,
    [switch]$StopAfter
)

$ErrorActionPreference = 'Stop'

$apkUrl = "https://github.com/$Repo/releases/download/latest-test/app-debug.apk"
$testUrl = "https://raw.githubusercontent.com/$Repo/main/test-apk.ps1"

Write-Host "===== LATEST APK -> VM TEST ====="
Write-Host "REPO=$Repo"
Write-Host "APK_URL=$apkUrl"
Write-Host "APK=$Apk"
Write-Host "TEST_SCRIPT=$TestScript"

Write-Host "===== [1] DOWNLOAD LATEST APK ====="
Invoke-WebRequest -Uri $apkUrl -OutFile $Apk -UseBasicParsing
$apkFile = Get-Item $Apk
$apkHash = (Get-FileHash $Apk -Algorithm SHA256).Hash
Write-Host "APK_BYTES=$($apkFile.Length)"
Write-Host "APK_SHA256=$apkHash"

Write-Host "===== [2] REFRESH TEST SCRIPT ====="
Invoke-WebRequest -Uri $testUrl -OutFile $TestScript -UseBasicParsing
Unblock-File $TestScript

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
