# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
# גשר המיתרים: מריץ במחשב Windows את בדיקות ה-PowerShell של מרכז הבקרה, של ההודעות ושל
# הדיאלוגים, ואת בדיקות הפייתון הקטנות שלא צריכות בנייה. לא צריך בנייה של המוצר.
# כל בדיקה רצה בתהליך משלה (Windows PowerShell 5.1, כמו בחלק מה-CI) עם מגבלת זמן, והיומנים שלה
# נשמרים ב-OutDir. בסוף נכתבת טבלה: עבר, נכשל או פג הזמן. הסקריפט לא משנה קבצים בריפו.
# שימוש:  powershell -ExecutionPolicy Bypass -File tools\ui\run-local-checks.ps1 [-OutDir DIR] [-TimeoutSeconds 300]
param(
    [string] $OutDir = (Join-Path $env:TEMP 'gesher-local-checks'),
    [int] $TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path $OutDir).Path
Get-ChildItem $OutDir -Filter '*.log' -ErrorAction SilentlyContinue | Remove-Item -Force

$powerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
$python = (Get-Command python -ErrorAction SilentlyContinue)
$git = (Get-Command git -ErrorAction SilentlyContinue)

# בדיקות PowerShell שנוגעות בקבצים ששונו בגל 6 (מרכז הבקרה, ההודעות, הדיאלוגים, ההתקנה)
$shellChecks = @(
    'Issue32And33Contracts', 'UiLocalizationChecks', 'PreferredLanguagesChecks', 'InstallErrorChecks',
    'CameraImagePickerChecks', 'PortableProfileChecks', 'PortableModeChecks',
    'ControlPanelPresentationChecks', 'ControlPanelActionChecks', 'ControlPanelProxyChecks',
    'ControlPanelRequestChecks', 'ControlPanelRefreshChecks', 'ControlPanelStartupChecks',
    'ControlPanelRecoveryChecks', 'ControlPanelIdleChecks', 'ControlPanelLogsChecks',
    'ControlPanelLaunchChecks', 'ControlPanelIconCacheChecks', 'ControlPanelNativeCacheChecks',
    'ControlPanelSpecialAccessChecks', 'ControlPanelUpdateChecks', 'ControlPanelVirtualizationChecks',
    'UpdateAgentChecks'
)
$pythonChecks = @(
    'tools/tests/test_dialog_bidi.py', 'tools/tests/test_host_account_commands.py',
    'tools/tests/test_web_intent_fallback.py', 'tools/tests/test_bluetooth_le_audio.py',
    'tools/tests/test_location_mode.py', 'tools/tests/test_panel_resize.py',
    'tools/tests/test_portable_package.py', 'tools/test_portable_launcher.py'
)

function Invoke-Check([string] $name, [string] $exe, [string] $arguments) {
    $log = Join-Path $OutDir ($name -replace '[\\/:]', '_') + '.log'
    $info = [System.Diagnostics.ProcessStartInfo]::new($exe)
    $info.Arguments = $arguments
    $info.WorkingDirectory = $repo
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    $result = 'פג הזמן'
    if ($process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.WaitForExit()
        $result = if ($process.ExitCode -eq 0) { 'עבר' } else { "נכשל (קוד $($process.ExitCode))" }
    } else {
        try { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null } catch { }
    }
    [IO.File]::WriteAllText($log, ($out.Result + "`r`n" + $err.Result), [Text.UTF8Encoding]::new($false))
    $process.Dispose()
    [pscustomobject]@{ Check = $name; Result = $result; Seconds = [int]$watch.Elapsed.TotalSeconds }
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($name in $shellChecks) {
    $path = Join-Path $repo "tests\windows\shell\$name.ps1"
    if (-not (Test-Path -LiteralPath $path)) { $rows.Add([pscustomobject]@{ Check = $name; Result = 'חסר קובץ'; Seconds = 0 }); continue }
    Write-Host "מריץ $name ..."
    $rows.Add((Invoke-Check $name $powerShell "-NoProfile -ExecutionPolicy Bypass -File `"$path`""))
}
if ($python) {
    foreach ($relative in $pythonChecks) {
        Write-Host "מריץ $relative ..."
        $rows.Add((Invoke-Check $relative $python.Source "`"$(Join-Path $repo $relative)`""))
    }
    Write-Host 'מריץ tools/i18n/generate.py --check ...'
    $rows.Add((Invoke-Check 'tools/i18n/generate.py --check' $python.Source "`"$(Join-Path $repo 'tools\i18n\generate.py')`" --check"))
} else {
    $rows.Add([pscustomobject]@{ Check = 'בדיקות פייתון'; Result = 'דולג: Python לא מותקן'; Seconds = 0 })
}

''
$rows | Format-Table -AutoSize | Out-String -Width 200
$failed = @($rows | Where-Object { $_.Result -ne 'עבר' })
"עברו: $(@($rows | Where-Object { $_.Result -eq 'עבר' }).Count) מתוך $($rows.Count). יומנים ב: $OutDir"
if ($failed.Count) { "לא עברו: " + (($failed | ForEach-Object { $_.Check }) -join ', ') }
if ($git) { "קומיט: " + (& git -C $repo log --oneline -1) }
exit $(if ($failed.Count) { 1 } else { 0 })
