# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
param(
    [Parameter(Mandatory = $true)][string] $InstallerPath,
    [Parameter(Mandatory = $true)][string] $OutDir,
    # שמות החבילות מ-tests/e2e/apps.json, מופרדים בפסיק (הכל עובר כמחרוזת אחת בשורת הפקודה).
    [Parameter(Mandatory = $true)][string] $Apps,
    [Parameter(Mandatory = $true)][ValidateSet('on', 'off', 'any')][string] $ShortNames,
    # אפליקציה נוספת מ-apps.json שמותקנת מקובץ בשם עברי בתיקיית ההורדות. ריק: בלי הבדיקה הזאת.
    [string] $DownloadsApp = '',
    [string] $PathFile = ''
)

# גשר המיתרים: הסשן של המשתמש שנוצר ב-HebrewUserChecks.ps1. רץ בשם המשתמש הזה, עם הסביבה
# שנבנתה מהפרופיל שלו.
#
#   1. בודק את הסביבה: מי אני, ושהנתיבים שלי (פרופיל, AppData, ‏TEMP ותפריט התחל) הם מה שהבדיקה
#      צריכה. אצל משתמש בשם עברי הם בעברית. כשהסביבה לא כזאת, הסשן עוצר עם קוד 2, ולא בודק את גשר.
#   2. מריץ את tests/e2e/run-e2e.ps1 על האפליקציות שהתבקשו: התקנה של המתקין, התקנה של כל
#      אפליקציה, הפעלה עד הפריים הראשון, קלט, סגירה, ההפעלה דרך הקישור לקובצי ‎.apk ודרך הקיצור
#      בתפריט התחל.
#   3. מתקין אפליקציה נוספת מקובץ בשם עברי בתיקיית ההורדות (Downloads\אפליקציה מהאינטרנט.apk),
#      כמו משתמש שמוריד APK מהדפדפן.
#   4. בודק את מה ש-#355 שבר: ש-dex2oat קומפל כל אפליקציה (base.vdex בתיקיית הקוד שלה, תחת
#      הפרופיל), ושאין בלוגים "dex2oat failed". רושם מה הריצה קיבלה בפועל: נתיב ASCII דרך השם
#      הקצר, או הנתיב בעברית. ‏profman רץ רק כשהמכשיר פנוי ויש פרופיל חדש, ולכן הוא נרשם אם רץ,
#      ולא נדרש.
#
# הכל נכתב ל-session.log ול-report.json בתיקיית התוצאות. קוד יציאה: 0 הצליח, 1 כשל של גשר,
# 2 כשל של הסביבה או של הבדיקה עצמה.

$ErrorActionPreference = 'Stop'
$null = [IO.Directory]::CreateDirectory($OutDir)
$log = Join-Path $OutDir 'session.log'
$reportPath = Join-Path $OutDir 'report.json'
$script:Lines = [Collections.Generic.List[string]]::new()
$script:Report = [ordered]@{ lines = $script:Lines }

function Write-Session([string] $Line) {
    Add-Content -LiteralPath $log -Value ((Get-Date).ToString('HH:mm:ss') + ' ' + $Line) -Encoding utf8
}
# שורה של סיכום: גם בלוג, וגם ברשימה שהסקריפט שמריץ מעביר לסיכום של הריצה ב-CI.
function Add-Result([string] $Line) {
    Write-Session $Line
    $script:Lines.Add($Line)
}
function Save-Report {
    $json = $script:Report | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($reportPath, $json, [Text.UTF8Encoding]::new($false))
}
function Test-NonAscii([string] $Text) { return [bool]($Text -match '[^\x00-\x7F]') }

try {
    # --- 0. הכלים של ה-CI (pwsh ו-python) לפני ה-PATH שנבנה מהפרופיל.
    if ($PathFile -and (Test-Path -LiteralPath $PathFile)) {
        $extra = @(Get-Content -LiteralPath $PathFile -Encoding utf8 | Where-Object { $_ })
        $env:PATH = (($extra + @($env:PATH)) -join ';')
    }

    # --- 1. הסביבה.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $userName = [Environment]::UserName
    $userProfile = $env:USERPROFILE
    $knownLocal = [Environment]::GetFolderPath('LocalApplicationData')
    $temp = [IO.Path]::GetTempPath()
    $programs = [Environment]::GetFolderPath('Programs')
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $profileShort = $fso.GetFolder($userProfile).ShortPath
    $hasShortName = $profileShort -cne $userProfile
    $groups = (& whoami /groups /fo csv 2>$null | Out-String)
    $environment = [ordered]@{
        user = $userName
        sid = $identity.User.Value
        administrators_member = [bool]($groups -match 'S-1-5-32-544')
        user_profile = $userProfile
        user_profile_short = $profileShort
        has_short_name = $hasShortName
        local_app_data_env = $env:LOCALAPPDATA
        local_app_data_known_folder = $knownLocal
        temp = $temp
        start_menu_programs = $programs
        ansi_code_page = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
        os = (Get-CimInstance Win32_OperatingSystem).Caption
        powershell = $PSVersionTable.PSVersion.ToString()
    }
    $script:Report.environment = $environment
    foreach ($key in $environment.Keys) { Write-Session "סביבה: $key = $($environment[$key])" }

    $hebrewUser = Test-NonAscii $userName
    $problems = @()
    foreach ($pair in @(@('הפרופיל', $userProfile), @('LOCALAPPDATA', $env:LOCALAPPDATA),
                        @('LocalAppData של Windows', $knownLocal), @('תפריט התחל', $programs))) {
        if ((Test-NonAscii $pair[1]) -ne $hebrewUser) {
            $problems += "הנתיב של $($pair[0]) ($($pair[1])) לא תואם לשם המשתמש '$userName'"
        }
    }
    if ($env:LOCALAPPDATA -cne $knownLocal) {
        $problems += "LOCALAPPDATA ($env:LOCALAPPDATA) שונה מהתיקייה של Windows ($knownLocal): הסביבה לא נבנתה מהפרופיל"
    }
    # Windows נותן ל-TEMP לפעמים את הצורה הקצרה (8.3) של תיקיית המשתמש. מה שחשוב הוא שהיא
    # התיקייה הזמנית של המשתמש הזה, ולכן משווים את שתיהן בצורה הקצרה.
    $profileTemp = Join-Path $userProfile 'AppData\Local\Temp'
    if (-not (Test-Path -LiteralPath $profileTemp) -or
        $fso.GetFolder($temp).ShortPath -cne $fso.GetFolder($profileTemp).ShortPath) {
        $problems += "TEMP ($temp) היא לא התיקייה הזמנית של המשתמש ($profileTemp)"
    }
    if ($ShortNames -eq 'on' -and (-not $hasShortName -or (Test-NonAscii $profileShort))) {
        $problems += "ביקשנו שם קצר לתיקיית המשתמש, ואין: $profileShort"
    }
    if ($ShortNames -eq 'off' -and $hasShortName) {
        $problems += "ביקשנו תיקיית משתמש בלי שם קצר, ויש: $profileShort"
    }
    $script:Report.environment_problems = $problems
    if ($problems) {
        foreach ($problem in $problems) { Add-Result "FAIL  סביבת הבדיקה: $problem" }
        $script:Report.verdict = 'environment-fail'
        Save-Report
        exit 2
    }
    $shortText = if ($hasShortName) { "יש לה שם קצר ($profileShort)" } else { 'אין לה שם קצר' }
    Add-Result "PASS  סביבת הבדיקה: המשתמש '$userName', תיקיית המשתמש $userProfile ($shortText), דף הקוד של המערכת $($environment.ansi_code_page)"
    Save-Report

    # --- 2. ההתקנה והאפליקציות, דרך ה-e2e הרגיל של הפרויקט.
    $appList = @($Apps.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $e2eScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\e2e\run-e2e.ps1'))
    $e2eOut = Join-Path $OutDir 'e2e'
    $literal = { param([string] $Value) "'" + $Value.Replace("'", "''") + "'" }
    $only = ($appList | ForEach-Object { & $literal $_ }) -join ','
    $command = "& $(& $literal $e2eScript) -Setup $(& $literal $InstallerPath) -OutDir $(& $literal $e2eOut) -Only @($only); exit `$LASTEXITCODE"
    Write-Session "e2e: $command"
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1 |
        ForEach-Object { Write-Session "e2e | $_" }
    $e2eExit = $LASTEXITCODE
    $script:Report.e2e_exit = $e2eExit
    $e2eSummary = Join-Path $e2eOut 'summary.txt'
    $e2eLines = if (Test-Path -LiteralPath $e2eSummary) { @(Get-Content -LiteralPath $e2eSummary -Encoding utf8 | Where-Object { $_ -match '^(PASS|FAIL|KNOWN-FAIL) ' }) } else { @() }
    foreach ($line in $e2eLines) { Add-Result "      $line" }

    # --- 3. איפה גשר הותקן, ואיזה נתיב הריצה מקבלת.
    $app = Join-Path $env:LOCALAPPDATA 'Programs\Gesher'
    $profileRoot = Join-Path $env:LOCALAPPDATA 'Gesher'
    $installed = Test-Path -LiteralPath (Join-Path $app 'gesher-app.cmd')
    $productFailed = (-not $installed) -or ($e2eExit -ne 0)
    $runtimePaths = [ordered]@{ install = $app; profile = $profileRoot }
    if ($installed) {
        # מה הריצה מקבלת: אותה המרה ש-gesher-app.ps1 עושה ל-ANDROID_DATA ולנתיבי ההתקנה.
        . (Join-Path $app 'gesher-runtime-files.ps1')
        $runtimePaths.android_data = ConvertTo-GesherAndroidPath -Path (Join-Path $profileRoot 'data')
        $runtimePaths.android_install = ConvertTo-GesherAndroidPath -Path $app
    }
    $script:Report.runtime_paths = $runtimePaths
    if ($installed) {
        $route = "נתיב ASCII ($($runtimePaths.android_data))"
        if (Test-NonAscii $runtimePaths.android_data) { $route = "הנתיב בעברית ($($runtimePaths.android_data))" }
        Add-Result "PASS  ההתקנה: גשר הותקן ב-$app. הריצה מקבלת את הפרופיל כ$route"
    } else {
        Add-Result "FAIL  ההתקנה: אין $app\gesher-app.cmd אחרי המתקין"
    }

    # --- 4. התקנה מקובץ בשם עברי בתיקיית ההורדות, כמו משתמש שמוריד APK ולוחץ עליו. אפליקציה
    # שה-e2e לא התקין, כדי שזו תהיה התקנה חדשה, עם dex2oat, ולא "כבר מותקן".
    $downloadsPackage = $null
    if ($installed -and $DownloadsApp) {
        . (Join-Path $PSScriptRoot '..\e2e\apks.ps1')
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\e2e\apps.json') -Encoding utf8 | ConvertFrom-Json
        $entry = @($manifest.apps | Where-Object { $_.package -ceq $DownloadsApp })
        if ($entry.Count -ne 1) { throw "$DownloadsApp לא מופיע ב-tests/e2e/apps.json" }
        $downloads = Join-Path $userProfile 'Downloads'
        $null = [IO.Directory]::CreateDirectory($downloads)
        $hebrewApk = Join-Path $downloads 'אפליקציה מהאינטרנט.apk'
        Get-PinnedApk $hebrewApk "$($entry[0].package)_$($entry[0].versionCode).apk" $entry[0].sha256 (@(@($manifest.repo) + @($manifest.mirrors)) | Where-Object { $_ })
        $installOut = & (Join-Path $app 'gesher-app.cmd') install $hebrewApk 2>&1 | Out-String
        $installExit = $LASTEXITCODE
        Set-Content -LiteralPath (Join-Path $OutDir 'install-from-downloads.log') -Value $installOut -Encoding utf8
        & (Join-Path $app 'gesher-app.cmd') shutdown 2>&1 | Out-Null
        if ($installExit -eq 0 -and $installOut -match "installed $([regex]::Escape($DownloadsApp))") {
            Add-Result "PASS  התקנה מההורדות: $DownloadsApp הותקן מ-$hebrewApk"
            $downloadsPackage = $DownloadsApp
        } else {
            $productFailed = $true
            $firstLine = (($installOut -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
            Add-Result "FAIL  התקנה מההורדות: $DownloadsApp לא הותקן מ-$hebrewApk (קוד $installExit): $firstLine"
        }
    }

    # --- 5. מה ש-#355 שבר: הקומפילציה של dex2oat תחת פרופיל בנתיב של המשתמש, לכל אפליקציה.
    $logs = Join-Path $profileRoot 'logs'
    $serverLog = "$(Get-Content -Raw -LiteralPath (Join-Path $logs 'system_server.log') -Encoding utf8 -ErrorAction SilentlyContinue)"
    $dexoptLog = "$(Get-Content -Raw -LiteralPath (Join-Path $logs 'dexopt.log') -Encoding utf8 -ErrorAction SilentlyContinue)"
    $appRoot = Join-Path $profileRoot 'data\app'
    $appResults = @()
    foreach ($package in @($appList) + @($downloadsPackage | Where-Object { $_ })) {
        $codeDirs = @(Get-ChildItem -LiteralPath $appRoot -Directory -Filter "$package-*" -ErrorAction SilentlyContinue)
        $vdex = @($codeDirs | ForEach-Object { Join-Path $_.FullName 'oat\x86_64\base.vdex' } |
            Where-Object { (Test-Path -LiteralPath $_) -and (Get-Item -LiteralPath $_).Length -gt 0 })
        $failedLine = [regex]::Match($serverLog, "dexopt: $([regex]::Escape($package)): dex2oat failed[^\r\n]*")
        $profman = [regex]::Match($serverLog, "dexopt: $([regex]::Escape($package)): profman merged[^\r\n]*")
        $entry = [ordered]@{
            package = $package
            code_dirs = @($codeDirs | ForEach-Object { $_.FullName })
            vdex = @($vdex)
            dex2oat_failed = if ($failedLine.Success) { $failedLine.Value } else { $null }
            profman = if ($profman.Success) { $profman.Value } else { $null }
        }
        $appResults += $entry
        if ($vdex -and -not $failedLine.Success) {
            Add-Result "PASS  dex2oat: $package קומפל ($($vdex[0]))"
        } else {
            $productFailed = $true
            $why = if ($failedLine.Success) { $failedLine.Value } elseif (-not $codeDirs) { "אין תיקיית קוד תחת $appRoot" } else { 'אין base.vdex בתיקיית הקוד' }
            Add-Result "FAIL  dex2oat: $package לא קומפל: $why"
        }
        if ($profman.Success) { Add-Result "PASS  profman: $($profman.Value)" }
        else { Add-Result "INFO  profman: לא רץ על $package בבדיקה הזאת (הוא רץ רק כשהמכשיר פנוי ויש פרופיל חדש), ולכן לא נבדק" }
    }
    $script:Report.apps = $appResults
    # סימן לנתיב שעבר דרך דף קוד שאין בו עברית: רצף של סימני שאלה. סימן בלבד, לא הוכחה.
    $questionRuns = [regex]::Matches($serverLog + "`n" + $dexoptLog, '\?{3,}').Count
    $script:Report.question_mark_runs = $questionRuns
    if ($questionRuns) { Add-Result "INFO  בלוגים של המכשיר יש $questionRuns רצפים של '???'. ייתכן שנתיב עבר דרך דף קוד בלי עברית. כדאי לבדוק ב-gesher-logs" }

    $script:Report.verdict = if ($productFailed) { 'product-fail' } else { 'pass' }
    Save-Report
    exit $(if ($productFailed) { 1 } else { 0 })
} catch {
    Add-Result "FAIL  הבדיקה עצמה: $($_.Exception.Message) ($($_.InvocationInfo.PositionMessage -replace '\s+', ' '))"
    $script:Report.verdict = 'harness-fail'
    try { Save-Report } catch { }
    exit 2
}
