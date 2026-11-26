# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
param(
    [Parameter(Mandatory = $true)][string] $InstallerPath,
    [Parameter(Mandatory = $true)][string] $PortableZipPath,
    [Parameter(Mandatory = $true)][string] $Version,
    [string] $OutDir = 'install-env-results/non-ntfs',
    # אפליקציה לכל כונן, מ-tests/e2e/apps.json: כל התקנה היא התקנה חדשה, ולא "כבר מותקן".
    [string] $ExfatApp = 'com.ath0.rpn',
    [string] $Fat32App = 'org.billthefarmer.currency',
    [switch] $SkipPortable
)

# גשר המיתרים: כונן שאינו NTFS, כמו דיסק-און-קי או כרטיס זיכרון (שלב 3.3 בתוכנית העבודה).
#
#   - issues #306 ו-#456: התקנה של APK מכונן FAT32 או exFAT נכשלה ב-"close failed: EINVAL",
#     כי Windows לא מחזיר שם את FileIdInfo. התיקון הוא #313. כאן: גשר מותקן כרגיל, ומתקינים
#     ממנו אפליקציה שהקובץ שלה יושב על כונן exFAT, ועוד אחת מכונן FAT32. כל אחת מותקנת,
#     מקומפלת ב-dex2oat ונפתחת עד שה-Activity מוכנה (‏--headless).
#   - issue #417: גרסה ניידת על דיסק-און-קי. כאן: הבדיקה הקיימת של הגרסה הניידת
#     (tests/windows/shell/PortableRuntimeChecks.ps1) רצה כשכל תיקיית העבודה שלה, כולל
#     App ו-Data, על כונן exFAT.
#
# הכוננים הם קובצי VHDX שמחוברים למכונה, ולא דיסק-און-קי אמיתי: מערכת הקבצים זהה, אבל אין
# כאן ניתוק פיזי ולא מהירות של USB. רץ כמנהל (יצירת הכוננים), אחרי שאין התקנה של גשר.

$ErrorActionPreference = 'Stop'
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$PortableZipPath = [IO.Path]::GetFullPath($PortableZipPath)
$OutDir = [IO.Path]::GetFullPath($OutDir)
$null = [IO.Directory]::CreateDirectory($OutDir)
$summary = $env:GITHUB_STEP_SUMMARY
$script:Failed = 0
function Write-Line([string] $Line) {
    Write-Host $Line
    if ($summary) { Add-Content -LiteralPath $summary -Value $Line -Encoding utf8 }
}
function Fail([string] $Line) { Write-Line "FAIL  $Line"; $script:Failed++ }

# --- 1. שני כוננים: exFAT (‏6GB, גם לגרסה הניידת) ו-FAT32 (‏1GB). ‏diskpart יוצר את הקובץ, וה-Storage
# של Windows מחבר, מאתחל ומפרמט. בסוף נבדקת מערכת הקבצים בפועל.
function New-TestDrive([string] $Name, [int] $SizeMb, [string] $FileSystem, [char] $Letter) {
    $directory = Join-Path $env:SystemDrive 'hameitarim-vhd'
    $null = [IO.Directory]::CreateDirectory($directory)
    $file = Join-Path $directory "$Name.vhdx"
    $script = Join-Path $directory "$Name.diskpart.txt"
    [IO.File]::WriteAllText($script, "create vdisk file=`"$file`" maximum=$SizeMb type=expandable`r`n", [Text.Encoding]::ASCII)
    $out = & diskpart /s $script 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "diskpart לא יצר את $file ($LASTEXITCODE): $out" }
    $disk = Mount-DiskImage -ImagePath $file -PassThru | Get-Disk
    $disk | Initialize-Disk -PartitionStyle MBR -PassThru | Out-Null
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $Letter
    $null = Format-Volume -Partition $partition -FileSystem $FileSystem -NewFileSystemLabel $Name -Confirm:$false -Force
    $volume = Get-Volume -DriveLetter $Letter
    if ($volume.FileSystem -ne $FileSystem) { throw "הכונן $($Letter): הוא $($volume.FileSystem), ולא $FileSystem" }
    Write-Line "PASS  כונן $($Letter): בפורמט $($volume.FileSystem), $([math]::Round($volume.Size / 1MB)) MB"
    return "$($Letter):\"
}

try {
    # תווית של FAT32 היא עד 11 תווים.
    $exfat = New-TestDrive 'EXFATUSB' 6144 'exFAT' 'U'
    $fat32 = New-TestDrive 'FAT32USB' 1024 'FAT32' 'V'
} catch {
    Write-Line "FAIL  סביבת הבדיקה: יצירת הכוננים נכשלה: $($_.Exception.Message)"
    Write-Host "::error::סביבת הבדיקה לא נוצרה, ולכן אין כאן תוצאה על גשר"
    exit 2
}

# --- 2. גשר מותקן כרגיל, כמו אצל משתמש.
$app = Join-Path $env:LOCALAPPDATA 'Programs\Gesher'
if (Test-Path -LiteralPath (Join-Path $app 'unins000.exe')) { throw "המכונה לא נקייה: גשר כבר מותקן ב-$app" }
Start-Process -FilePath $InstallerPath -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
if (-not (Test-Path -LiteralPath (Join-Path $app 'gesher-app.cmd'))) { Fail "ההתקנה: אין $app\gesher-app.cmd"; exit 1 }
Write-Line "PASS  ההתקנה: גשר $Version הותקן ב-$app"
$env:GESHER_APP_WINDOW = 'headless'
$profileRoot = Join-Path $env:LOCALAPPDATA 'Gesher'
# gesher-app עם גבול זמן: אפליקציה שלא מגיעה למצב פנוי לא תתקע את כל הבדיקה.
function Invoke-GesherApp([string[]] $Arguments, [string] $Log, [int] $TimeoutSeconds = 300) {
    $argumentLine = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process = Start-Process -FilePath (Join-Path $app 'gesher-app.cmd') -ArgumentList $argumentLine -NoNewWindow -PassThru `
        -RedirectStandardOutput "$Log.out" -RedirectStandardError "$Log.err"
    $null = $process.Handle
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        & (Join-Path $app 'gesher-app.cmd') shutdown 2>&1 | Out-Null
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $text = "$(Get-Content -Raw -LiteralPath "$Log.out" -ErrorAction SilentlyContinue)$(Get-Content -Raw -LiteralPath "$Log.err" -ErrorAction SilentlyContinue)"
    Set-Content -LiteralPath $Log -Value $text -Encoding utf8
    Remove-Item -LiteralPath "$Log.out", "$Log.err" -ErrorAction SilentlyContinue
    $tail = (($text -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
    $code = if ($finished) { $process.ExitCode } else { -1 }
    return [pscustomobject]@{ Code = $code; Output = $text; Tail = $tail; TimedOut = -not $finished }
}

# --- 3. התקנה ופתיחה של APK שיושב על הכונן (#306, ‏#456).
. (Join-Path $PSScriptRoot '..\e2e\apks.ps1')
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\e2e\apps.json') -Encoding utf8 | ConvertFrom-Json
foreach ($case in @(@($exfat, 'exFAT', $ExfatApp), @($fat32, 'FAT32', $Fat32App))) {
    $drive, $fileSystem, $package = $case
    $entry = @($manifest.apps | Where-Object { $_.package -ceq $package })
    if ($entry.Count -ne 1) { throw "$package לא מופיע ב-tests/e2e/apps.json" }
    $apkDirectory = Join-Path $drive 'apps'
    $null = [IO.Directory]::CreateDirectory($apkDirectory)
    $apk = Join-Path $apkDirectory "$package.apk"
    Get-PinnedApk $apk "$($package)_$($entry[0].versionCode).apk" $entry[0].sha256 (@(@($manifest.repo) + @($manifest.mirrors)) | Where-Object { $_ })
    $result = Invoke-GesherApp @('install', $apk) (Join-Path $OutDir "$fileSystem-install.log")
    if ($result.Code -ne 0 -or $result.Output -notmatch "installed $([regex]::Escape($package))") {
        Fail "התקנה מ-$($fileSystem): $package מ-$apk (קוד $($result.Code)): $($result.Tail)"
        continue
    }
    $vdex = @(Get-ChildItem -LiteralPath (Join-Path $profileRoot 'data\app') -Directory -Filter "$package-*" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'oat\x86_64\base.vdex' } | Where-Object { Test-Path -LiteralPath $_ })
    if (-not $vdex) { Fail "התקנה מ-$($fileSystem): $package הותקן, אבל dex2oat לא קומפל אותו (אין base.vdex)"; continue }
    Write-Line "PASS  התקנה מ-$($fileSystem): $package הותקן מ-$apk וקומפל"
    # פתיחה מהקובץ שעל הכונן, כמו לחיצה כפולה על APK בדיסק-און-קי: הקובץ נקרא שוב, והאפליקציה
    # נפתחת בלי חלון עד שה-Activity מוכנה, ואז נסגרת.
    $result = Invoke-GesherApp @($apk, '--headless') (Join-Path $OutDir "$fileSystem-launch.log")
    if ($result.TimedOut) { Fail "פתיחה מ-$($fileSystem): $package מ-$apk לא הסתיימה תוך 5 דקות: $($result.Tail)"; continue }
    if ($result.Code -ne 0) { Fail "פתיחה מ-$($fileSystem): $package מ-$apk (קוד $($result.Code)): $($result.Tail)"; continue }
    Write-Line "PASS  פתיחה מ-$($fileSystem): $package נפתח מ-$apk ונסגר בלי שגיאה"
}
& (Join-Path $app 'gesher-app.cmd') shutdown 2>&1 | Out-Null
$deviceLogs = Join-Path $profileRoot 'logs'
if (Test-Path -LiteralPath $deviceLogs) {
    Copy-Item -LiteralPath $deviceLogs -Destination (Join-Path $OutDir 'installed-device-logs') -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. הגרסה הניידת על exFAT (#417): הבדיקה הקיימת, כשתיקיית העבודה שלה על הכונן.
if (-not $SkipPortable) {
    $portableCheck = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\windows\shell\PortableRuntimeChecks.ps1'))
    $portableWork = Join-Path $exfat 'portable'
    $null = [IO.Directory]::CreateDirectory($portableWork)
    $portableLog = Join-Path $OutDir 'portable-exfat.log'
    $runnerTemp = $env:RUNNER_TEMP
    try {
        # PortableRuntimeChecks יוצר את תיקיית העבודה שלו תחת RUNNER_TEMP.
        $env:RUNNER_TEMP = $portableWork
        & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $portableCheck -ZipPath $PortableZipPath -InstallerPath $InstallerPath `
            -Version $Version -InstalledRuntimeDirectory $app 2>&1 | Tee-Object -FilePath $portableLog | Out-Host
        $code = $LASTEXITCODE
    } finally {
        $env:RUNNER_TEMP = $runnerTemp
    }
    $evidence = Get-ChildItem -LiteralPath $portableWork -Directory -Filter 'gesher-portable-runtime-*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($evidence) { Copy-Item -LiteralPath $evidence.FullName -Destination (Join-Path $OutDir 'portable-exfat-evidence') -Recurse -Force -ErrorAction SilentlyContinue }
    $passLine = Select-String -LiteralPath $portableLog -Pattern '^PASS: portable runtime' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($code -eq 0 -and $passLine) {
        Write-Line "PASS  גרסה ניידת על exFAT: $($passLine.Line.Trim()), כשהקבצים של App ו-Data על $portableWork"
    } else {
        $lastLines = (Get-Content -LiteralPath $portableLog -Tail 4 -ErrorAction SilentlyContinue) -join ' | '
        Fail "גרסה ניידת על exFAT (קוד $code): $lastLines"
    }
}

Write-Line "INFO  לא נבדק כאן: דיסק-און-קי פיזי (ניתוק באמצע, מהירות של USB), וכונן UDF."
if ($script:Failed) {
    Write-Host "::error::$($script:Failed) בדיקות של כונן שאינו NTFS נכשלו"
    exit 1
}
