# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
param(
    # תג הגרסה, למשל v1.0.0. ריק: הגרסה האחרונה שפורסמה (releases/latest).
    [string] $Tag = '',
    [string] $Destination = 'installer',
    [string] $Repository = $env:GITHUB_REPOSITORY
)

# גשר המיתרים: מוריד את המתקין של גרסה שפורסמה, כמו שמשתמש מוריד אותו, ובודק שהוא הקובץ
# שפורסם: ה-SHA-256 שלו שווה גם ל-digest ש-GitHub חישב לקובץ שהועלה, וגם לשורה שלו
# ב-SHA256SUMS.txt של אותה גרסה. מדפיס את הנתיב ל-GITHUB_OUTPUT (path, version, tag).
# צריך את gh ו-GH_TOKEN.

$ErrorActionPreference = 'Stop'
if (-not $Repository) { throw 'חסר שם הריפו (GITHUB_REPOSITORY)' }
$endpoint = if ($Tag) { "repos/$Repository/releases/tags/$Tag" } else { "repos/$Repository/releases/latest" }
$release = gh api $endpoint | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $release.tag_name) { throw "לא נמצאה גרסה ($endpoint)" }
if ($release.draft -or $release.prerelease) { throw "$($release.tag_name) היא טיוטה או pre-release, ולא גרסה שמשתמשים מורידים" }
$Tag = $release.tag_name
if ($Tag -notmatch '^v(\d+\.\d+\.\d+)$') { throw "התג $Tag לא בצורה vX.Y.Z" }
$version = $Matches[1]
$name = "gesher-setup-$version.exe"
$assets = @($release.assets | Where-Object { $_.name -ceq $name })
if ($assets.Count -ne 1) { throw "ב-$Tag אין בדיוק מתקין אחד בשם $name" }
if ($assets[0].digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "ל-$name אין digest של SHA-256 ב-GitHub" }
$published = $Matches[1]

$null = New-Item -ItemType Directory -Force $Destination
gh release download $Tag --repo $Repository --pattern $name --pattern 'SHA256SUMS.txt' --dir $Destination --clobber
if ($LASTEXITCODE -ne 0) { throw "ההורדה של $name מ-$Tag נכשלה" }
$path = (Resolve-Path -LiteralPath (Join-Path $Destination $name)).Path
$actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $published) { throw "ה-SHA-256 של $name הוא $actual, ו-GitHub פרסם $published" }
$listed = $null
foreach ($line in Get-Content -LiteralPath (Join-Path $Destination 'SHA256SUMS.txt')) {
    if ($line -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($name))\s*$") { $listed = $Matches[1].ToLowerInvariant() }
}
if (-not $listed) { throw "$name לא מופיע ב-SHA256SUMS.txt של $Tag" }
if ($listed -ne $actual) { throw "ב-SHA256SUMS.txt כתוב $listed ל-$name, והקובץ שהורד הוא $actual" }

Write-Host "PASS  המתקין של $($Tag): $name, sha256:$actual, זהה ל-digest של GitHub ול-SHA256SUMS.txt"
if ($env:GITHUB_OUTPUT) {
    "path=$path" >> $env:GITHUB_OUTPUT
    "version=$version" >> $env:GITHUB_OUTPUT
    "tag=$Tag" >> $env:GITHUB_OUTPUT
}
if ($env:GITHUB_STEP_SUMMARY) {
    "המתקין שנבדק: ``$name`` מ-$Tag, ‏sha256:``$actual``" >> $env:GITHUB_STEP_SUMMARY
}
