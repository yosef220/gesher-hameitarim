# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
param(
    # תג הגרסה, למשל v1.0.0. ריק: הגרסה האחרונה שפורסמה (releases/latest).
    [string] $Tag = '',
    [string] $Destination = 'installer',
    [string] $Repository = $env:GITHUB_REPOSITORY,
    # גם הגרסה הניידת (gesher-<גרסה>-portable.zip), באותן בדיקות.
    [switch] $IncludePortable,
    # מספר של ריצת CI (ci.yml) במקום גרסה שפורסמה, למשל של product-candidate: ה-artifact
    # gesher-setup שעבודת האריזה שלה העלתה.
    [string] $RunId = ''
)

# גשר המיתרים: מוריד את המתקין של גרסה שפורסמה, כמו שמשתמש מוריד אותו, ובודק שהוא הקובץ
# שפורסם: ה-SHA-256 שלו שווה גם ל-digest ש-GitHub חישב לקובץ שהועלה, וגם לשורה שלו
# ב-SHA256SUMS.txt של אותה גרסה. עם -RunId: המתקין מריצת CI, שנבדק מול SHA256SUMS.txt שבאותו
# artifact. מדפיס ל-GITHUB_OUTPUT את path, ‏version ו-tag, ועם -IncludePortable גם את portable.
# צריך את gh ו-GH_TOKEN.

$ErrorActionPreference = 'Stop'
if (-not $Repository) { throw 'חסר שם הריפו (GITHUB_REPOSITORY)' }
if ($RunId) {
    if ($RunId -notmatch '^\d+$') { throw "מספר ריצה לא תקין: $RunId" }
    $null = New-Item -ItemType Directory -Force $Destination
    gh run download $RunId --repo $Repository --name gesher-setup --dir $Destination
    if ($LASTEXITCODE -ne 0) { throw "אין artifact בשם gesher-setup בריצה $RunId" }
    $setup = @(Get-ChildItem -LiteralPath $Destination -Filter 'gesher-setup-*.exe')
    # בבנייה של CI שאינה תג, הגרסה היא הגרסה האחרונה ועוד מספר הריצה (tools/ci/release_version.py).
    if ($setup.Count -ne 1 -or $setup[0].Name -notmatch '^gesher-setup-(\d+(?:\.\d+){2,3})\.exe$') {
        throw "בריצה $RunId אין בדיוק מתקין אחד בשם gesher-setup-<גרסה>.exe: $(($setup | ForEach-Object Name) -join ', ')"
    }
    $version = $Matches[1]
    $names = @($setup[0].Name)
    if ($IncludePortable) { $names += "gesher-$version-portable.zip" }
    $sums = Get-Content -LiteralPath (Join-Path $Destination 'SHA256SUMS.txt')
    $paths = @{}
    foreach ($name in $names) {
        $path = (Resolve-Path -LiteralPath (Join-Path $Destination $name)).Path
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $listed = $null
        foreach ($line in $sums) {
            if ($line -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($name))\s*$") { $listed = $Matches[1].ToLowerInvariant() }
        }
        if ($listed -ne $actual) { throw "ה-SHA-256 של $name ($actual) לא תואם ל-SHA256SUMS.txt של הריצה ($listed)" }
        Write-Host "PASS  $name מריצה $($RunId): sha256:$actual, זהה ל-SHA256SUMS.txt של אותו artifact"
        if ($env:GITHUB_STEP_SUMMARY) { "הקובץ שנבדק: ``$name`` מריצת CI $RunId, ‏sha256:``$actual``" >> $env:GITHUB_STEP_SUMMARY }
        $paths[$name] = $path
    }
    if ($env:GITHUB_OUTPUT) {
        "path=$($paths[$names[0]])" >> $env:GITHUB_OUTPUT
        if ($IncludePortable) { "portable=$($paths["gesher-$version-portable.zip"])" >> $env:GITHUB_OUTPUT }
        "version=$version" >> $env:GITHUB_OUTPUT
        "tag=run-$RunId" >> $env:GITHUB_OUTPUT
    }
    return
}
$endpoint = if ($Tag) { "repos/$Repository/releases/tags/$Tag" } else { "repos/$Repository/releases/latest" }
$release = gh api $endpoint | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $release.tag_name) { throw "לא נמצאה גרסה ($endpoint)" }
if ($release.draft -or $release.prerelease) { throw "$($release.tag_name) היא טיוטה או pre-release, ולא גרסה שמשתמשים מורידים" }
$Tag = $release.tag_name
if ($Tag -notmatch '^v(\d+\.\d+\.\d+)$') { throw "התג $Tag לא בצורה vX.Y.Z" }
$version = $Matches[1]
$names = @("gesher-setup-$version.exe")
if ($IncludePortable) { $names += "gesher-$version-portable.zip" }

$null = New-Item -ItemType Directory -Force $Destination
$downloadArguments = @('release', 'download', $Tag, '--repo', $Repository, '--dir', $Destination, '--clobber', '--pattern', 'SHA256SUMS.txt')
foreach ($name in $names) { $downloadArguments += @('--pattern', $name) }
gh @downloadArguments
if ($LASTEXITCODE -ne 0) { throw "ההורדה מ-$Tag נכשלה" }
$sums = Get-Content -LiteralPath (Join-Path $Destination 'SHA256SUMS.txt')

$paths = @{}
foreach ($name in $names) {
    $assets = @($release.assets | Where-Object { $_.name -ceq $name })
    if ($assets.Count -ne 1) { throw "ב-$Tag אין בדיוק קובץ אחד בשם $name" }
    if ($assets[0].digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "ל-$name אין digest של SHA-256 ב-GitHub" }
    $published = $Matches[1]
    $path = (Resolve-Path -LiteralPath (Join-Path $Destination $name)).Path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $published) { throw "ה-SHA-256 של $name הוא $actual, ו-GitHub פרסם $published" }
    $listed = $null
    foreach ($line in $sums) {
        if ($line -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($name))\s*$") { $listed = $Matches[1].ToLowerInvariant() }
    }
    if (-not $listed) { throw "$name לא מופיע ב-SHA256SUMS.txt של $Tag" }
    if ($listed -ne $actual) { throw "ב-SHA256SUMS.txt כתוב $listed ל-$name, והקובץ שהורד הוא $actual" }
    Write-Host "PASS  $name מ-$($Tag): sha256:$actual, זהה ל-digest של GitHub ול-SHA256SUMS.txt"
    if ($env:GITHUB_STEP_SUMMARY) { "הקובץ שנבדק: ``$name`` מ-$Tag, ‏sha256:``$actual``" >> $env:GITHUB_STEP_SUMMARY }
    $paths[$name] = $path
}

if ($env:GITHUB_OUTPUT) {
    "path=$($paths["gesher-setup-$version.exe"])" >> $env:GITHUB_OUTPUT
    if ($IncludePortable) { "portable=$($paths["gesher-$version-portable.zip"])" >> $env:GITHUB_OUTPUT }
    "version=$version" >> $env:GITHUB_OUTPUT
    "tag=$Tag" >> $env:GITHUB_OUTPUT
}
