# גשר המיתרים: צילומי מסך של דף הרישיון באשף ההתקנה, בעברית ובאנגלית, לביקורת העיצוב.
# בונה מתקין קטן עם אותן הגדרות אשף, אותן שפות ואותם קובצי רישיון כמו tools/package/gesher.iss,
# מריץ אותו, מצלם את החלון כשהוא בדף הרישיון וסוגר אותו בלי להתקין כלום.
# רץ ב-Windows PowerShell 5.1 (System.Drawing). ב-CI: ‏.github/workflows/hameitarim-design.yml.
param([Parameter(Mandatory = $true)][string] $OutDir)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$package = Join-Path $repo 'tools\package'
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc) -or -not (Test-Path (Join-Path (Split-Path $iscc) 'Languages\Hebrew.isl'))) {
    choco upgrade innosetup --no-progress -y | Out-Null
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('license-preview-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path $OutDir).Path

$iss = @"
[Setup]
AppName={cm:setup_app_name}
AppVersion=0.0.0
AppPublisher=Gesher HaMeitarim
DefaultDirName={localappdata}\GesherLicensePreview
PrivilegesRequired=lowest
WizardStyle=modern
SetupIconFile=$package\gesher.ico
WizardSmallImageFile=$package\small-55x55.bmp,$package\small-83x80.bmp,$package\small-110x106.bmp
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no
UsePreviousLanguage=no
OutputDir=$work
OutputBaseFilename=license-preview

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"; LicenseFile: "$package\license.en.rtf"
Name: "he"; MessagesFile: "compiler:Languages\Hebrew.isl"; LicenseFile: "$package\license.he.rtf"

#include "$package\ui-messages.iss"
"@
$issPath = Join-Path $work 'license-preview.iss'
[IO.File]::WriteAllText($issPath, $iss, (New-Object Text.UTF8Encoding $true))
& $iscc /Qp $issPath | Out-Host
if ($LASTEXITCODE -ne 0) { throw "ISCC נכשל בקוד $LASTEXITCODE" }
$setup = Join-Path $work 'license-preview.exe'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class LicenseShot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);
    public static void Save(IntPtr hwnd, string path) {
        RECT r;
        if (!GetWindowRect(hwnd, out r)) throw new InvalidOperationException("GetWindowRect");
        using (Bitmap bitmap = new Bitmap(r.Right - r.Left, r.Bottom - r.Top)) {
            using (Graphics g = Graphics.FromImage(bitmap)) {
                IntPtr dc = g.GetHdc();
                bool ok = PrintWindow(hwnd, dc, 2);
                g.ReleaseHdc(dc);
                if (!ok) throw new InvalidOperationException("PrintWindow");
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}
'@

foreach ($language in 'he', 'en') {
    $before = @(Get-Process -Name 'license-preview*' -ErrorAction SilentlyContinue | ForEach-Object Id)
    $null = Start-Process $setup -ArgumentList "/LANG=$language" -PassThru
    $window = $null
    for ($i = 0; $i -lt 60 -and -not $window; $i++) {
        Start-Sleep -Milliseconds 500
        $window = Get-Process -Name 'license-preview*' -ErrorAction SilentlyContinue |
            Where-Object { $before -notcontains $_.Id -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle } |
            Select-Object -First 1
    }
    if (-not $window) { throw "חלון האשף לא הופיע ($language)" }
    Start-Sleep -Seconds 2
    $path = Join-Path $OutDir "license-page-$language.png"
    [LicenseShot]::Save($window.MainWindowHandle, $path)
    "צולם: $path ('$($window.MainWindowTitle)')"
    Get-Process -Name 'license-preview*' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
}
