# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
# מיתר: צילומי מסך של העמוד הראשון באשף ההתקנה, בעברית ובאנגלית, לביקורת העיצוב.
# בונה מתקין קטן עם אותן הגדרות אשף ואותו קוד של InitializeWizard כמו tools/package/gesher.iss (השורה הקבועה
# "מבוסס על Gesher" בעמוד הפתיחה), מריץ אותו, מצלם את החלון וסוגר אותו בלי להתקין כלום.
# שני מצבים: "default" בדיוק כמו gesher.iss (בלי DisableWelcomePage), ו-"welcome" עם DisableWelcomePage=no,
# כדי לדעת אם עמוד הפתיחה מוצג בכלל. רץ ב-Windows PowerShell 5.1. ב-CI: ‏.github/workflows/hameitarim-design.yml.
param([Parameter(Mandatory = $true)][string] $OutDir)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$package = Join-Path $repo 'tools\package'
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc) -or -not (Test-Path (Join-Path (Split-Path $iscc) 'Languages\Hebrew.isl'))) {
    choco upgrade innosetup --no-progress -y | Out-Null
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('welcome-preview-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path $OutDir).Path
"גרסת Inno Setup: $((Get-Item $iscc).VersionInfo.ProductVersion)"

function New-Installer([string] $Name, [string] $ExtraSetup) {
    $iss = @"
[Setup]
AppName={cm:setup_app_name}
AppVersion=1.2.0
AppPublisher=Meitar
DefaultDirName={localappdata}\GesherWelcomePreview
PrivilegesRequired=lowest
WizardStyle=modern
SetupIconFile=$package\gesher.ico
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no
UsePreviousLanguage=no
$ExtraSetup
OutputDir=$work
OutputBaseFilename=$Name

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"; LicenseFile: "$package\license.en.rtf"
Name: "he"; MessagesFile: "compiler:Languages\Hebrew.isl"; LicenseFile: "$package\license.he.rtf"

#include "$package\ui-messages.iss"

[Code]
procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel2.Caption := CustomMessage('brand_tagline') + #13#10#13#10 + WizardForm.WelcomeLabel2.Caption;
end;
"@
    $path = Join-Path $work "$Name.iss"
    [IO.File]::WriteAllText($path, $iss, (New-Object Text.UTF8Encoding $true))
    & $iscc /Qp $path | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ISCC נכשל בקוד $LASTEXITCODE ($Name)" }
    Join-Path $work "$Name.exe"
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class WelcomeShot {
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

$variants = [ordered]@{ 'default' = ''; 'welcome' = 'DisableWelcomePage=no' }
foreach ($variant in $variants.Keys) {
    $name = "welcome-$variant"
    $setup = New-Installer $name $variants[$variant]
    foreach ($language in 'he', 'en') {
        $before = @(Get-Process -Name "$name*" -ErrorAction SilentlyContinue | ForEach-Object Id)
        $null = Start-Process $setup -ArgumentList "/LANG=$language" -PassThru
        $window = $null
        for ($i = 0; $i -lt 60 -and -not $window; $i++) {
            Start-Sleep -Milliseconds 500
            $window = Get-Process -Name "$name*" -ErrorAction SilentlyContinue |
                Where-Object { $before -notcontains $_.Id -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle } |
                Select-Object -First 1
        }
        if (-not $window) { throw "חלון האשף לא הופיע ($variant, $language)" }
        Start-Sleep -Seconds 2
        $path = Join-Path $OutDir "first-page-$variant-$language.png"
        [WelcomeShot]::Save($window.MainWindowHandle, $path)
        "צולם: $path ('$($window.MainWindowTitle)')"
        Get-Process -Name "$name*" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
}
