param(
    [Parameter(Mandatory = $true)][string] $InstallerPath,
    [Parameter(Mandatory = $true)][string] $Version,
    [string] $UpstreamTag = 'v0.2.0',
    [string] $UpstreamRepository = 'gesher-runtime/gesher',
    # עותק של אותו מתקין בריפו שלנו, כ-pre-release שהמעדכן מתעלם ממנו. ‏upstream כבר לא ציבורי.
    [string] $FixtureRepository = 'yosef220/gesher-hameitarim',
    [string] $FixtureTag = 'fixture-gesher-0.2.0'
)

# גשר המיתרים: התקנה במקום Gesher. מתקינים את Gesher 0.2.0, הגרסה שפורסמה תחת
# Apache 2.0, מתקינים בו אפליקציה ושומרים נתונים והגדרה, ואז מתקינים מעליו את
# גשר המיתרים ובודקים שהכל נשמר, ושהשם, הקיצורים ומקור העדכונים התחלפו.
# רץ ב-CI על מכונת Windows נקייה, אחרי שההתקנה הרגילה הוסרה. צריך את gh ו-GH_TOKEN.

$ErrorActionPreference = 'Stop'
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $repoRoot 'tools/package/gesher-update.ps1')

$app = Join-Path $env:LOCALAPPDATA 'Programs\Gesher'
$profileRoot = Join-Path $env:LOCALAPPDATA 'Gesher'
$programs = [Environment]::GetFolderPath('Programs')
$appId = '{6A1F3C2E-5B7D-4E8A-9C0F-1D2E3F4A5B6C}_is1'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
$package = 'com.gesher.lifecycle'
$summary = if ($env:GITHUB_STEP_SUMMARY) { $env:GITHUB_STEP_SUMMARY } else { $null }
function Pass([string] $Message) {
    $line = "PASS  שדרוג מ-Gesher: $Message"
    if ($summary) { $line | Tee-Object -Append $summary } else { $line }
}
function Invoke-GesherApp([string[]] $Arguments) {
    $out = & (Join-Path $app 'gesher-app.cmd') @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}
function Wait-Uninstalled {
    for ($i = 0; $i -lt 90 -and (Test-Path (Join-Path $app 'unins000.exe')); $i++) { Start-Sleep 1 }
    if (Test-Path (Join-Path $app 'unins000.exe')) { throw 'ההסרה לא הסתיימה תוך 90 שניות' }
}

if ((Test-Path $app) -or (Test-Path $profileRoot)) { throw "המכונה לא נקייה: $app או $profileRoot כבר קיימים" }

# 1. המתקין של Gesher 0.2.0, מדף הגרסאות של upstream, ואם הוא כבר לא זמין, מהעותק בריפו שלנו.
# הוא מאומת מול ה-SHA-256 שמפורסם באותו דף. בלי אף מקור, השלב לא נכשל, אבל גם לא מדווח
# שהשדרוג נבדק: הוא מסמן אזהרה ואומר במפורש שהשדרוג לא נבדק.
$work = Join-Path ([IO.Path]::GetTempPath()) ('gesher-upgrade-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$release = $null; $sourceRepository = $null; $sourceTag = $null; $reasons = @()
foreach ($candidate in @(@($UpstreamRepository, $UpstreamTag), @($FixtureRepository, $FixtureTag))) {
    for ($attempt = 1; $attempt -le 3 -and -not $release; $attempt++) {
        $json = gh api "repos/$($candidate[0])/releases/tags/$($candidate[1])" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { $release = $json | ConvertFrom-Json; $sourceRepository = $candidate[0]; $sourceTag = $candidate[1] }
        elseif ($json -match 'HTTP 404|Not Found') { break }
        else { Start-Sleep ([Math]::Pow(2, $attempt)) }
    }
    if ($release) { break }
    $reasons += "$($candidate[0])@$($candidate[1]): $($json.Trim())"
}
if (-not $release) {
    $message = "השדרוג מ-Gesher 0.2.0 לא נבדק: אין מתקין של Gesher 0.2.0 באף מקור (" + ($reasons -join ' | ') + ")"
    "::warning::$message"
    $line = "SKIP  שדרוג מ-Gesher: $message"
    if ($summary) { $line | Tee-Object -Append $summary } else { $line }
    exit 0
}
$assets = @($release.assets | Where-Object { $_.name -cmatch '\Agesher-setup-[0-9.]+\.exe\z' })
if ($assets.Count -ne 1) { throw "ב-$sourceRepository@$sourceTag אין מתקין אחד בדיוק (נמצאו $($assets.Count))" }
$asset = $assets[0]
$old = Join-Path $work $asset.name
for ($attempt = 1; $attempt -le 4; $attempt++) {
    gh release download $sourceTag --repo $sourceRepository --pattern $asset.name --dir $work --clobber 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0 -and (Test-Path $old)) { break }
    Start-Sleep ([Math]::Pow(2, $attempt))
}
if (-not (Test-Path $old)) { throw "ההורדה של $($asset.name) נכשלה" }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $old).Hash.ToLowerInvariant()
if ([string] $asset.digest -cne "sha256:$hash") { throw "ה-SHA-256 של $($asset.name) ($hash) שונה מזה שבדף הגרסה ($($asset.digest))" }
Pass "המתקין של Gesher $UpstreamTag ירד מ-$sourceRepository@$sourceTag ואומת (sha256:$hash)"

# 2. ההתקנה הקיימת: Gesher 0.2.0 עם אפליקציה, נתונים והגדרת עדכונים של המשתמש.
$p = Start-Process $old -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "ההתקנה של Gesher $UpstreamTag נכשלה (קוד $($p.ExitCode))" }
$oldVersion = Get-GesherInstalledVersion -InstallDirectory $app
if ($oldVersion -cne $UpstreamTag.TrimStart('v')) { throw "אחרי התקנת Gesher הגרסה המותקנת היא '$oldVersion'" }
$oldName = (Get-ItemProperty $uninstallKey).DisplayName
$oldPanel = Join-Path $programs 'Gesher Control Center.lnk'
if (-not (Test-Path $oldPanel)) { throw "Gesher לא יצר את הקיצור $oldPanel" }
$installed = Invoke-GesherApp @('install', (Join-Path $app 'lifecycle.apk'))
Write-Host $installed.Output
if ($installed.Code -ne 0) { throw "gesher-app install של Gesher נכשל (קוד $($installed.Code))" }
# הקיצור של האפליקציה בתפריט התחל. נבדק שהוא נשאר, אם Gesher 0.2.0 יצר אותו.
$appLink = Join-Path $programs 'Gesher Apps\Gesher Lifecycle.lnk'
$hadAppLink = Test-Path $appLink
$marker = Join-Path $profileRoot "data\data\$package\files\gesher-hameitarim-upgrade.txt"
$null = New-Item -ItemType Directory -Force -Path (Split-Path $marker)
[IO.File]::WriteAllText($marker, 'נתונים של אפליקציה מלפני השדרוג', [Text.UTF8Encoding]::new($false))
$updateState = Join-Path $profileRoot 'updates'
Save-GesherUpdatePreferences -StateDirectory $updateState -Preferences ([pscustomobject]@{
    AutomaticChecks = $false; AutomaticInstall = $true; LastCheckUtc = '2026-11-20T08:00:00.0000000Z'
})
# קיצור של מרכז הבקרה בשם העברי של Gesher, כמו אחרי התקנה בעברית. העתקה בקבצים
# של Unicode, כי WScript.Shell שומר שמות בדף הקוד של המכונה.
$oldHebrewPanel = Join-Path $programs 'לוח הבקרה של גשר.lnk'
Copy-Item -LiteralPath $oldPanel -Destination $oldHebrewPanel
$null = Invoke-GesherApp @('shutdown')
Pass "Gesher $oldVersion מותקן ('$oldName'), עם $package, נתונים שלה והגדרת עדכונים"

# 3. גשר המיתרים מעל Gesher.
$p = Start-Process $InstallerPath -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "ההתקנה של גשר המיתרים מעל Gesher נכשלה (קוד $($p.ExitCode))" }
$problems = @()
$newVersion = Get-GesherInstalledVersion -InstallDirectory $app
if ($newVersion -cne $Version) { $problems += "הגרסה המותקנת היא '$newVersion' ולא $Version" }
$list = Invoke-GesherApp @('list')
if ($list.Code -ne 0 -or $list.Output -notmatch "package:$([regex]::Escape($package)) ") { $problems += "האפליקציה $package לא ברשימה אחרי השדרוג: $($list.Output)" }
if (-not (Test-Path -LiteralPath $marker) -or [IO.File]::ReadAllText($marker) -cne 'נתונים של אפליקציה מלפני השדרוג') { $problems += 'הנתונים של האפליקציה לא נשמרו' }
$preferences = Get-GesherUpdatePreferences -StateDirectory $updateState
if ($preferences.AutomaticChecks) { $problems += 'השדרוג החזיר לפעולה את בדיקת העדכונים שהמשתמש כיבה' }
if ($preferences.LastCheckUtc -cne '2026-11-20T08:00:00.0000000Z') { $problems += "זמן הבדיקה האחרונה השתנה: $($preferences.LastCheckUtc)" }
if ($problems) { throw ($problems -join '; ') }
Pass "גשר המיתרים $newVersion הותקן במקום Gesher: האפליקציה, הנתונים שלה והגדרת העדכונים נשמרו"

$newPanel = Join-Path $programs 'Gesher HaMeitarim Control Center.lnk'
if (-not (Test-Path $newPanel)) { $problems += "אין קיצור $newPanel" }
foreach ($legacy in $oldPanel, $oldHebrewPanel) { if (Test-Path -LiteralPath $legacy) { $problems += "נשאר הקיצור הישן $legacy" } }
if ($hadAppLink -and -not (Test-Path $appLink)) { $problems += "הקיצור של האפליקציה נמחק: $appLink" }
$entries = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
    Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -match 'Gesher' })
if ($entries.Count -ne 1 -or $entries[0].PSChildName -cne $appId) { $problems += "צריכה להיות רשומת הסרה אחת, ונמצאו: $($entries.PSChildName -join ', ')" }
$entry = Get-ItemProperty $uninstallKey
if ($entry.DisplayName -cne "Gesher HaMeitarim $Version") { $problems += "השם בהוספה/הסרה של תוכניות הוא '$($entry.DisplayName)'" }
if ($entry.Publisher -cne 'Gesher HaMeitarim') { $problems += "המפרסם הוא '$($entry.Publisher)'" }
if ($problems) { throw ($problems -join '; ') }
$linkNote = if ($hadAppLink) { 'והקיצור של האפליקציה נשאר' } else { 'ל-Gesher 0.2.0 לא היה קיצור לאפליקציה, ולכן השמירה שלו לא נבדקה' }
Pass "השם התחלף (הוספה/הסרה של תוכניות: '$($entry.DisplayName)'), הקיצורים הישנים בעברית ובאנגלית נמחקו, $linkNote"

$updater = [IO.File]::ReadAllText((Join-Path $app 'gesher-update.ps1'))
if (-not $updater.Contains('https://api.github.com/repos/yosef220/gesher-hameitarim/releases/latest') -or $updater.Contains('gesher-runtime/gesher')) {
    throw 'מקור העדכונים אחרי השדרוג הוא לא הריפו של גשר המיתרים'
}
if (-not (Test-Path (Join-Path $app 'gesher-update-agent.ps1'))) { throw 'סוכן העדכונים לא הותקן' }
Pass 'מקור העדכונים הוא yosef220/gesher-hameitarim, וסוכן העדכונים מותקן'

$run = Invoke-GesherApp @('launch', $package)
Write-Host $run.Output
if ($run.Code -ne 0 -or $run.Output -notmatch 'LifecycleActivity onResume') { throw "האפליקציה ש-Gesher התקין לא נפתחה אחרי השדרוג (קוד $($run.Code))" }
$null = Invoke-GesherApp @('shutdown')
Pass "האפליקציה ש-Gesher התקין נפתחת בגשר המיתרים"

# 4. ניקוי: הסרה, כדי שהשלבים הבאים יתחילו ממכונה נקייה.
Start-Process (Join-Path $app 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -Wait
Wait-Uninstalled
if (Test-Path $profileRoot) { throw "ההסרה השאירה את $profileRoot" }
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Pass 'ההסרה אחרי השדרוג מוחקת את ההתקנה ואת הנתונים'
