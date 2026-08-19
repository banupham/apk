param(
    [string]$Repo = "banupham/apk",
    [string]$Apk = "$env:USERPROFILE\Downloads\app-debug.apk",
    [string]$TestScript = "$env:USERPROFILE\Downloads\test-apk.ps1",
    [switch]$ColdBoot,
    [switch]$Headless,
    [switch]$StopAfter,
    [switch]$SkipSelfUpdate
)

$ErrorActionPreference = 'Stop'

$cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$headers = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

# Bootstrap into a freshly downloaded copy of this runner. This prevents an
# old local latest-test.ps1 from continuing to orchestrate newer test scripts.
if (-not $SkipSelfUpdate) {
    Write-Host "===== SELF REFRESH ====="
    $selfUrl = "https://raw.githubusercontent.com/$Repo/main/latest-test.ps1?v=$cacheBust"
    $tempSelf = Join-Path $env:TEMP ("latest-test-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))

    try {
        Invoke-WebRequest -Uri $selfUrl -Headers $headers -OutFile $tempSelf -UseBasicParsing
        Unblock-File $tempSelf

        $selfText = Get-Content $tempSelf -Raw
        if ($selfText -notmatch 'SELF_REFRESH_V4' -or $selfText -notmatch 'SkipSelfUpdate') {
            throw 'Downloaded latest-test.ps1 is stale or incomplete; expected self-refresh runner was not found.'
        }

        Write-Host 'PIPELINE_SCRIPT_VERSION=SELF_REFRESH_V4'

        $selfArgs = @{
            Repo = $Repo
            Apk = $Apk
            TestScript = $TestScript
            SkipSelfUpdate = $true
        }
        if ($ColdBoot) { $selfArgs['ColdBoot'] = $true }
        if ($Headless) { $selfArgs['Headless'] = $true }
        if ($StopAfter) { $selfArgs['StopAfter'] = $true }

        & $tempSelf @selfArgs
        $childExitCode = $LASTEXITCODE
        exit $childExitCode
    }
    finally {
        Remove-Item $tempSelf -Force -ErrorAction SilentlyContinue
    }
}

$apkUrl = "https://github.com/$Repo/releases/download/latest-test/app-debug.apk?v=$cacheBust"
$testUrl = "https://raw.githubusercontent.com/$Repo/main/test-apk.ps1?v=$cacheBust"

Write-Host "===== LATEST APK -> VM TEST ====="
Write-Host 'PIPELINE_SCRIPT_VERSION=SELF_REFRESH_V4'
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
