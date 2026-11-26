# Copyright (C) 2026 The Gesher Authors; SPDX-License-Identifier: Apache-2.0
# Presentation only. Call on the WPF dispatcher; caller owns events and lifetime.

# גשר המיתרים: המצב של הממשק לפי Windows. ניגודיות גבוהה קודמת לכל; אחריה ההגדרה
# "מצב ברירת המחדל של אפליקציות" (AppsUseLightTheme). $script:PanelThemeOverride קובע
# מצב לצילומי המסך של תהליך העיצוב (tools/ui/control-center-preview.ps1).
if (-not (Test-Path variable:script:PanelThemeOverride)) { $script:PanelThemeOverride = $null }
function Get-PanelTheme {
    if ($script:PanelThemeOverride -in 'light', 'dark', 'contrast') { return $script:PanelThemeOverride }
    try { if ([System.Windows.SystemParameters]::HighContrast) { return 'contrast' } } catch { }
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')
        if ($null -ne $key) {
            try { if ($key.GetValue('AppsUseLightTheme', 1) -eq 0) { return 'dark' } }
            finally { $key.Dispose() }
        }
    } catch { }
    return 'light'
}

# הצבעים של המצב והסגנונות המשותפים נכנסים ל-<Window.Resources> לפני הטעינה, כדי
# ש-StaticResource ממשאבי Gesher* יעבוד בכל חלון. הסדר: צבעים, סגנונות, ואז מה שבחלון עצמו.
function Add-PanelSharedResources([xml] $Document, [string] $Theme) {
    $presentation = 'http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    $root = $Document.DocumentElement
    $propertyName = $root.LocalName + '.Resources'
    $resources = $null
    foreach ($child in $root.ChildNodes) {
        if ($child.NodeType -eq [Xml.XmlNodeType]::Element -and $child.LocalName -ceq $propertyName) { $resources = $child }
    }
    if ($null -eq $resources) {
        $resources = $Document.CreateElement($propertyName, $presentation)
        [void]$root.PrependChild($resources)
    }
    if (-not $root.HasAttribute('xmlns:sys')) { $root.SetAttribute('xmlns:sys', 'clr-namespace:System;assembly=mscorlib') }
    $first = $resources.FirstChild
    foreach ($file in "gesher-tokens-$Theme.xaml", 'gesher-panel-styles.xaml') {
        [xml]$dictionary = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $file), [Text.Encoding]::UTF8)
        foreach ($node in @($dictionary.DocumentElement.ChildNodes)) {
            if ($node.NodeType -ne [Xml.XmlNodeType]::Element) { continue }
            [void]$resources.InsertBefore($Document.ImportNode($node, $true), $first)
        }
    }
}

# הגופנים של הממשק נטענים מעותק בתיקייה הזמנית, ולא מ-ui-fonts שבתיקיית ההתקנה: WPF
# מחזיק את הקובץ פתוח כל עוד החלון חי, וההתקנה של עדכון מחליפה את הקבצים כשמרכז הבקרה
# פתוח. השם של העותק נגזר מהגודל ומזמן הכתיבה של הקבצים, כך שגרסה חדשה מקבלת עותק חדש.
$script:PanelFontDirectory = $null
function Get-PanelFontDirectory {
    if ($null -ne $script:PanelFontDirectory) { return $script:PanelFontDirectory }
    $script:PanelFontDirectory = ''
    try {
        $source = Join-Path $PSScriptRoot 'ui-fonts'
        $files = @(Get-ChildItem -LiteralPath $source -Filter '*.ttf' -File -ErrorAction Stop | Sort-Object Name)
        if ($files.Count -eq 0) { return '' }
        $stamp = ($files | ForEach-Object { '{0}:{1}:{2}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc.Ticks }) -join '|'
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stamp))).Replace('-', '').Substring(0, 16) }
        finally { $sha.Dispose() }
        $target = Join-Path ([IO.Path]::GetTempPath()) ('gesher-hameitarim-ui-fonts\' + $digest)
        if (-not (Test-Path -LiteralPath (Join-Path $target '.complete'))) {
            [void][IO.Directory]::CreateDirectory($target)
            foreach ($file in $files) { [IO.File]::Copy($file.FullName, (Join-Path $target $file.Name), $true) }
            [IO.File]::WriteAllText((Join-Path $target '.complete'), $stamp)
        }
        $script:PanelFontDirectory = $target
    } catch { $script:PanelFontDirectory = '' }
    return $script:PanelFontDirectory
}

function Set-PanelFonts($View) {
    $directory = Get-PanelFontDirectory
    if (-not $directory) { return }
    $base = [Uri]::new($directory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
    foreach ($pair in @(@('PanelUiFont', 'GesherUiFontFamily'), @('PanelDisplayFont', 'GesherDisplayFontFamily'))) {
        $family = [string]$View.Resources[$pair[1]]
        if ($family) { $View.Resources[$pair[0]] = [System.Windows.Media.FontFamily]::new($base, './#' + $family) }
    }
}

function New-PanelView([ValidateSet('dashboard', 'confirm', 'message', 'proxy')] [string] $Name, [hashtable] $Resources) {
    $path = Join-Path $PSScriptRoot ("gesher-panel-{0}.xaml" -f $Name)
    $source = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    [xml]$document = $source
    $theme = Get-PanelTheme
    Add-PanelSharedResources $document $theme
    $reader = [System.Xml.XmlNodeReader]::new($document)
    try { $view = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    $view.Resources['PanelTheme'] = $theme
    Set-PanelFonts $view
    # במצב כהה המיתרים זוהרים בזהב ירושלים, כמו במסך הפתיחה
    $strings = $view.FindName('BridgeStrings')
    if ($strings -and $theme -eq 'dark') {
        $glow = [System.Windows.Media.Effects.DropShadowEffect]::new()
        $glow.Color = $view.Resources['GesherStringGlowColor']
        $glow.ShadowDepth = 0
        $glow.BlurRadius = 7
        $glow.Opacity = 0.55
        $strings.Effect = $glow
    }
    # Object resources reach template instances too, without parsing translated
    # braces, ampersands, tabs or Hebrew as XML or markup extensions.
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches($source, '\{DynamicResource Text_([A-Za-z0-9_]+)\}')) {
        $key = $match.Groups[1].Value
        if ($seen.Add($key)) {
            $view.Resources["Text_$key"] = [string](Get-GesherText $key)
        }
    }
    foreach ($key in $Resources.Keys) { $view.Resources[$key] = $Resources[$key] }
    return $view
}

# מברשת של תפקיד מהמצב שהחלון נטען בו, לקוד שמשנה מצב (נקודת "פועלת", תוויות).
function Get-PanelBrush($View, [string] $Role) {
    return $View.FindResource("Gesher${Role}Brush")
}
