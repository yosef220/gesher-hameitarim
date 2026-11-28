# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
# גשר המיתרים: מריץ במחשב Windows את הבדיקות המקומיות של גל 6, בלי בנייה של המוצר.
#   רגיל:            23 בדיקות PowerShell של מרכז הבקרה, ההודעות, הדיאלוגים וההתקנה, ובדיקות פייתון של הגל
#                    (כולל בדיקת ה-WebView עם JDK אם נמצא).
#   -Wide:           בנוסף כל בדיקות ה-PowerShell שב-tests\windows\shell וכל בדיקות הפייתון שאין להן ארגומנט חובה.
#   -Wide -Baseline: את אותן בדיקות מריץ גם על main נקי (עותק עבודה זמני), ומדפיס רק הבדלים. בדיקה שעוברת
#                    ב-main ונכשלת כאן היא משהו שהגל שבר. בדיקה שנכשלת בשניהם היא של הסביבה.
# כל בדיקה רצה בתהליך משלה עם מגבלת זמן, והיומנים נשמרים ב-OutDir. הסקריפט לא משנה קבצים בריפו.
# שימוש:  powershell -ExecutionPolicy Bypass -File tools\ui\run-local-checks.ps1 [-Wide [-Baseline]] [-OutDir DIR] [-TimeoutSeconds 300]
param(
    [string] $OutDir = (Join-Path $env:TEMP 'gesher-local-checks'),
    [int] $TimeoutSeconds = 300,
    [switch] $Wide,
    [switch] $Baseline
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path $OutDir).Path
Get-ChildItem $OutDir -Filter '*.log' -ErrorAction SilentlyContinue | Remove-Item -Force

$powerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
$python = (Get-Command python -ErrorAction SilentlyContinue)
$git = (Get-Command git -ErrorAction SilentlyContinue)
$javac = (Get-Command javac -ErrorAction SilentlyContinue)
$javaHome = $null
if ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\javac.exe'))) { $javaHome = $env:JAVA_HOME }
elseif ($javac) { $javaHome = Split-Path -Parent (Split-Path -Parent $javac.Source) }

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
    'tools/tests/test_portable_package.py'
)

# git כותב ל-stderr גם בהצלחה, וב-PowerShell 5.1 עם Stop זה זורק חריגה: מריצים אותו תחת Continue.
function Invoke-GitQuiet([string[]] $arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & git @arguments 2>&1 | Out-Null } finally { $ErrorActionPreference = $previous }
}

# מריץ תהליך אחד עם מגבלת זמן. מחזיר שם, תוצאה ושניות.
function Invoke-Check([string] $name, [string] $exe, [string] $arguments, [string] $workDir, [string] $logDir) {
    $log = Join-Path $logDir (($name -replace '[\\/: "]', '_') + '.log')
    $info = [System.Diagnostics.ProcessStartInfo]::new($exe)
    $info.Arguments = $arguments
    $info.WorkingDirectory = $workDir
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

# הבדיקות המהירות של הגל, על ההעתק הנוכחי
$rows = [System.Collections.Generic.List[object]]::new()
foreach ($name in $shellChecks) {
    $path = Join-Path $repo "tests\windows\shell\$name.ps1"
    if (-not (Test-Path -LiteralPath $path)) { $rows.Add([pscustomobject]@{ Check = $name; Result = 'חסר קובץ'; Seconds = 0 }); continue }
    Write-Host "מריץ $name ..."
    $rows.Add((Invoke-Check $name $powerShell "-NoProfile -ExecutionPolicy Bypass -File `"$path`"" $repo $OutDir))
}
if ($python) {
    foreach ($relative in $pythonChecks) {
        Write-Host "מריץ $relative ..."
        $rows.Add((Invoke-Check $relative $python.Source "`"$(Join-Path $repo $relative)`"" $repo $OutDir))
    }
    Write-Host 'מריץ tools/i18n/generate.py --check ...'
    $rows.Add((Invoke-Check 'tools/i18n/generate.py --check' $python.Source "`"$(Join-Path $repo 'tools\i18n\generate.py')`" --check" $repo $OutDir))
    if ($javaHome) {
        Write-Host 'מריץ tools/test_webview_owned_responses.py (מארח ה-WebView, כולל פריט 18) ...'
        $rows.Add((Invoke-Check 'tools/test_webview_owned_responses.py' $python.Source "`"$(Join-Path $repo 'tools\test_webview_owned_responses.py')`" --java-home `"$javaHome`"" $repo $OutDir))
    } else {
        $rows.Add([pscustomobject]@{ Check = 'tools/test_webview_owned_responses.py'; Result = 'דולג: JDK לא נמצא'; Seconds = 0 })
    }
} else {
    $rows.Add([pscustomobject]@{ Check = 'בדיקות פייתון'; Result = 'דולג: Python לא מותקן'; Seconds = 0 })
}

''
$rows | Format-Table -AutoSize | Out-String -Width 200
$failed = @($rows | Where-Object { $_.Result -ne 'עבר' })
"עברו: $(@($rows | Where-Object { $_.Result -eq 'עבר' }).Count) מתוך $($rows.Count). יומנים ב: $OutDir"
if ($failed.Count) { "לא עברו: " + (($failed | ForEach-Object { $_.Check }) -join ', ') }

# מצב רחב: כל הבדיקות שאין להן ארגומנט חובה, על ההעתק הזה ועל main נקי
$wideFailed = 0
if ($Wide) {
    if (-not $python) { throw 'מצב -Wide דורש Python.' }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'tests\windows\shell') -Filter '*.ps1' -File) {
        $list.Add([pscustomobject]@{ Kind = 'ps1'; Rel = ('tests/windows/shell/' + $file.Name) })
    }
    foreach ($dir in @('tools', 'tools\tests')) {
        $path = Join-Path $repo $dir
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $path -Filter 'test_*.py' -File) {
            $text = [IO.File]::ReadAllText($file.FullName)
            if ($text.Contains('required=True') -or $text.Contains('--java-home')) { continue }
            $list.Add([pscustomobject]@{ Kind = 'py'; Rel = (($dir -replace '\\', '/') + '/' + $file.Name) })
        }
    }
    function Invoke-Wide([string] $root, [string] $logDir, [string] $label) {
        $results = @{}
        $n = 0
        foreach ($item in $list) {
            $n++
            $full = Join-Path $root ($item.Rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full)) { $results[$item.Rel] = 'חסר קובץ'; continue }
            Write-Host "[$label $n/$($list.Count)] $($item.Rel)"
            if ($item.Kind -eq 'ps1') {
                $r = Invoke-Check $item.Rel $powerShell "-NoProfile -ExecutionPolicy Bypass -File `"$full`"" $root $logDir
            } else {
                $r = Invoke-Check $item.Rel $python.Source "`"$full`"" $root $logDir
            }
            $results[$item.Rel] = $r.Result
        }
        return $results
    }
    $wideLogs = Join-Path $OutDir 'wide-wave6'
    $null = New-Item -ItemType Directory -Force -Path $wideLogs
    $here = Invoke-Wide $repo $wideLogs 'כאן'
    $hereFailed = @($here.Keys | Where-Object { $here[$_] -ne 'עבר' } | Sort-Object)
    ''
    "מצב רחב, כאן: עברו $(@($here.Keys | Where-Object { $here[$_] -eq 'עבר' }).Count) מתוך $($here.Count)."
    $wideFailed = $hereFailed.Count
    if ($Baseline) {
        if (-not $git) { throw 'מצב -Baseline דורש git.' }
        $baseRoot = Join-Path $env:TEMP 'gesher-baseline-main'
        if (Test-Path -LiteralPath $baseRoot) {
            Invoke-GitQuiet @('-C', $repo, 'worktree', 'remove', '--force', $baseRoot)
            if (Test-Path -LiteralPath $baseRoot) { Remove-Item -Recurse -Force -LiteralPath $baseRoot }
        }
        Invoke-GitQuiet @('-C', $repo, 'fetch', 'origin', 'main')
        Invoke-GitQuiet @('-C', $repo, 'worktree', 'add', '--detach', $baseRoot, 'origin/main')
        if (-not (Test-Path -LiteralPath $baseRoot)) { throw 'לא ניתן היה ליצור עותק עבודה של main.' }
        try {
            $baseLogs = Join-Path $OutDir 'wide-main'
            $null = New-Item -ItemType Directory -Force -Path $baseLogs
            $there = Invoke-Wide $baseRoot $baseLogs 'main'
        } finally {
            Invoke-GitQuiet @('-C', $repo, 'worktree', 'remove', '--force', $baseRoot)
        }
        $regressions = @($hereFailed | Where-Object { $there[$_] -eq 'עבר' })
        $same = @($hereFailed | Where-Object { $there[$_] -ne 'עבר' })
        ''
        "נכשלות כאן וגם ב-main (של הסביבה, לא של הגל): $($same.Count)"
        if ($same.Count) { $same | ForEach-Object { "   $_  [כאן: $($here[$_]) | main: $($there[$_])]" } }
        "נכשלות כאן ועוברות ב-main (הגל שבר): $($regressions.Count)"
        if ($regressions.Count) { $regressions | ForEach-Object { "   $_  [כאן: $($here[$_])]" } }
        $wideFailed = $regressions.Count
    } elseif ($hereFailed.Count) {
        'נכשלו: ' + ($hereFailed -join ', ')
    }
}

if ($git) { "קומיט: " + (& git -C $repo rev-parse --short HEAD) }
exit $(if ($failed.Count -or $wideFailed) { 1 } else { 0 })
