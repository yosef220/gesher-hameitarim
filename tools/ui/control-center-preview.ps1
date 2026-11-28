# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
# גשר המיתרים: צילומי מסך של מרכז הבקרה ושל הדיאלוגים שלו, לביקורת העיצוב.
# טוען את ה-XAML של המוצר (tools/package) דרך New-PanelView, ממלא אותו בנתוני דוגמה ומצייר
# אותו ל-PNG, בכל מצב (בהיר, כהה, ניגודיות גבוהה), בעברית ובאנגלית, ובשני גדלים של חלון.
# זה לא מריץ את הלוגיקה של מרכז הבקרה: המצבים (מערכת פועלת, שירותי Google מופעלים וכו')
# נקבעים כאן באותם מאפיינים שהלוגיקה משנה. ב-CI: ‏.github/workflows/hameitarim-design.yml.
# רץ ב-Windows PowerShell 5.1 (STA).
param([Parameter(Mandatory = $true)][string] $OutDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$package = Join-Path $repo 'tools\package'
. (Join-Path $package 'gesher-ui.ps1')
. (Join-Path $package 'gesher-panel-view.ps1')
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path $OutDir).Path

# סמל לדוגמה: ריבוע מעוגל בצבע, עם האות הראשונה. לא הסמלים האמיתיים של האפליקציות.
function New-SampleIcon([string] $color, [string] $letter) {
    $visual = [System.Windows.Media.DrawingVisual]::new()
    $context = $visual.RenderOpen()
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $context.DrawRoundedRectangle($brush, $null, [System.Windows.Rect]::new(0, 0, 96, 96), 22, 22)
    $text = [System.Windows.Media.FormattedText]::new($letter, [Globalization.CultureInfo]::InvariantCulture,
        [System.Windows.FlowDirection]::LeftToRight, [System.Windows.Media.Typeface]::new('Segoe UI Semibold'), 48,
        [System.Windows.Media.Brushes]::White, 1.0)
    $context.DrawText($text, [System.Windows.Point]::new((96 - $text.Width) / 2, (96 - $text.Height) / 2))
    $context.Close()
    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(96, 96, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $bitmap.Freeze()
    return $bitmap
}

# מצייר את החלון כולו (כולל ההיפוך של RTL שעל החלון עצמו), וחותך לגודל התוכן: אזור הלקוח
# בלי השטח של שורת הכותרת של Windows, שהיה נשאר ריק בתחתית.
function Save-Visual($window, [string] $name) {
    $window.UpdateLayout()
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    $full = [System.Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($window.ActualWidth), [int][Math]::Ceiling($window.ActualHeight),
        96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $full.Render($window)
    $content = $window.Content
    $width = [Math]::Min($full.PixelWidth, [int][Math]::Ceiling($content.ActualWidth))
    $height = [Math]::Min($full.PixelHeight, [int][Math]::Ceiling($content.ActualHeight))
    $bitmap = [System.Windows.Media.Imaging.CroppedBitmap]::new($full, [System.Windows.Int32Rect]::new(0, 0, $width, $height))
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $OutDir "$name.png"))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    "צולם: $name.png ($width x $height)"
}

function Show-Offscreen($window, [double] $width, [double] $height) {
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'Manual'
    $window.Left = -12000; $window.Top = 0
    if ($width) { $window.Width = $width }
    if ($height) { $window.Height = $height }
    $window.Show()
    $window.UpdateLayout()
}

function Get-SampleApps([string] $language) {
    $he = $language -eq 'he'
    $apps = @(
        @{ Label = $(if ($he) { 'מוביט' } else { 'Moovit' }); Package = 'com.tranzmate'; Color = '#E8473B'; Letter = 'M' }
        @{ Label = $(if ($he) { 'בנק לדוגמה' } else { 'Sample Bank' }); Package = 'il.example.bank'; Color = '#1F7A5A'; Letter = 'B' }
        @{ Label = $(if ($he) { 'הודעות' } else { 'Messages' }); Package = 'org.example.messages'; Color = '#2E8BC0'; Letter = 'H'; Proxy = 'socks5://127.0.0.1:1080' }
        @{ Label = 'com.gesher.camera'; Package = 'com.gesher.camera'; Color = '#7D8A9D'; Letter = 'C'; NoLaunch = $true }
        @{ Label = $(if ($he) { 'מזגן חכם' } else { 'Smart AC' }); Package = 'com.example.aircon'; Color = '#D98A1E'; Letter = 'A' }
        @{ Label = $(if ($he) { 'נגן מוזיקה' } else { 'Music Player' }); Package = 'org.example.music'; Color = '#6B4FBB'; Letter = 'P' }
    )
    foreach ($app in $apps) {
        $proxyText = if ($app.Proxy) { Get-GesherText 'cp_proxy_app_value' @($app.Proxy) } else { '' }
        [pscustomobject]@{
            Package = $app.Package
            Label = $app.Label
            PackageVisibility = if ($app.Label -ceq $app.Package) { 'Collapsed' } else { 'Visible' }
            IconImage = New-SampleIcon $app.Color $app.Letter
            SeparateWindows = ($app.Package -eq 'org.example.messages')
            LaunchVisibility = if ($app.NoLaunch) { 'Collapsed' } else { 'Visible' }
            ProxyText = $proxyText
            ProxyVisibility = if ($proxyText) { 'Visible' } else { 'Collapsed' }
        }
    }
}

# המצבים שהלוגיקה מציגה (Update-DeviceView, Update-MicrogView, Update-StoreView, Update-PanelUpdateView)
function Set-SampleState($window, [bool] $running, [bool] $microg, [bool] $store) {
    $window.FindName('DeviceIndicator').Background = Get-PanelBrush $window $(if ($running) { 'String' } else { 'InkDisabled' })
    $window.FindName('DeviceStatusText').Text = Get-GesherText $(if ($running) { 'cp_device_running' } else { 'cp_device_stopped' })
    $window.FindName('BtnToggleDevice').Content = Get-GesherText $(if ($running) { 'cp_btn_stop' } else { 'cp_btn_start' })
    $window.FindName('MicrogBadge').Background = Get-PanelBrush $window $(if ($microg) { 'String' } else { 'InkDisabled' })
    $window.FindName('MicrogBadgeText').Text = Get-GesherText $(if ($microg) { 'cp_microg_enabled' } else { 'cp_microg_disabled' })
    foreach ($name in 'BtnGoogleLogin', 'BtnMicrogSettings', 'BtnDisableMicrog') { $window.FindName($name).Visibility = if ($microg) { 'Visible' } else { 'Collapsed' } }
    $window.FindName('BtnEnableMicrog').Visibility = if ($microg) { 'Collapsed' } else { 'Visible' }
    $window.FindName('StoreBadge').Background = Get-PanelBrush $window $(if ($store) { 'String' } else { 'InkDisabled' })
    $window.FindName('StoreBadgeText').Text = Get-GesherText $(if ($store) { 'cp_store_installed' } else { 'cp_store_not_installed' })
    $window.FindName('BtnInstallStore').Visibility = if ($store) { 'Collapsed' } else { 'Visible' }
    $window.FindName('BtnOpenStore').Visibility = if ($store) { 'Visible' } else { 'Collapsed' }
    $window.FindName('UpdateVersionText').Text = Get-GesherText 'cp_update_installed' @('1.0.0')
    $window.FindName('UpdateStatusText').Text = Get-GesherText 'cp_update_current'
    $window.FindName('AutomaticUpdateChecks').IsChecked = $true
    $window.FindName('AutomaticUpdateInstall').IsChecked = $true
}

function New-Dashboard([string] $language, [string] $theme) {
    $script:GesherUiLanguage = $language
    $script:PanelThemeOverride = $theme
    $flow = if ($language -eq 'he') { 'RightToLeft' } else { 'LeftToRight' }
    $window = New-PanelView 'dashboard' @{ PanelFlowDirection = [System.Windows.FlowDirection]$flow }
    return $window
}

function Update-Layout($window) {
    $layout = $window.FindName('PanelLayout'); $scroll = $window.FindName('PanelScroll')
    $window.UpdateLayout()
    $layout.Height = [Math]::Max($layout.MinHeight, $scroll.ActualHeight)
    $window.UpdateLayout()
}

# 1. מרכז הבקרה: כל מצב, כל שפה, בגודל הרגיל ובגודל המינימלי
$shots = @(
    @{ Language = 'he'; Theme = 'light'; Width = 1000; Height = 780 }
    @{ Language = 'he'; Theme = 'dark'; Width = 1000; Height = 780 }
    @{ Language = 'he'; Theme = 'contrast'; Width = 1000; Height = 780 }
    @{ Language = 'en'; Theme = 'light'; Width = 1000; Height = 780 }
    @{ Language = 'he'; Theme = 'light'; Width = 800; Height = 600 }
    @{ Language = 'en'; Theme = 'dark'; Width = 800; Height = 600 }
)
foreach ($shot in $shots) {
    $window = New-Dashboard $shot.Language $shot.Theme
    try {
        Show-Offscreen $window $shot.Width $shot.Height
        Set-SampleState $window $true $true $false
        $list = $window.FindName('AppsList')
        $list.ItemsSource = @(Get-SampleApps $shot.Language)
        $list.SelectedIndex = 1
        Update-Layout $window
        Save-Visual $window ("panel-{0}-{1}-{2}x{3}" -f $shot.Language, $shot.Theme, $shot.Width, $shot.Height)
    } finally { $window.Close() }
}

# 1ב. העמודה הצדדית נגללת, ובצילום הרגיל נחתכים הסעיפים התחתונים (מצלמה, קישורים בתוך אתרים,
# רשת עם "חשבונות" ו"פרוקסי"). כאן היא גלולה עד הסוף.
foreach ($shot in @(
        @{ Language = 'he'; Theme = 'light' }, @{ Language = 'he'; Theme = 'dark' }, @{ Language = 'en'; Theme = 'light' })) {
    $window = New-Dashboard $shot.Language $shot.Theme
    try {
        Show-Offscreen $window 1000 780
        Set-SampleState $window $true $true $false
        $list = $window.FindName('AppsList')
        $list.ItemsSource = @(Get-SampleApps $shot.Language)
        Update-Layout $window
        $rail = $window.FindName('RailScroll')
        $rail.ScrollToEnd()
        $window.UpdateLayout()
        Save-Visual $window ("panel-{0}-{1}-rail-end" -f $shot.Language, $shot.Theme)
    } finally { $window.Close() }
}

# 2. מצבים של הרשימה: מערכת כבויה, חיפוש בלי תוצאה, גרירה, ורשימה ריקה
foreach ($language in 'he', 'en') {
    $window = New-Dashboard $language 'light'
    try {
        Show-Offscreen $window 1000 780
        Set-SampleState $window $false $false $true
        $list = $window.FindName('AppsList')
        $list.ItemsSource = @(Get-SampleApps $language)
        $search = $window.FindName('AppsSearch')
        $search.Text = 'zzz'
        $list.Items.Filter = [Predicate[object]]{ param($item) $false }
        Update-Layout $window
        Save-Visual $window "panel-$language-states-search"
        $search.Text = ''
        $list.Items.Filter = $null
        $window.FindName('DropOverlay').Visibility = 'Visible'
        Update-Layout $window
        Save-Visual $window "panel-$language-states-drop"
        $window.FindName('DropOverlay').Visibility = 'Collapsed'
        $list.ItemsSource = @()
        Update-Layout $window
        Save-Visual $window "panel-$language-states-empty"
    } finally { $window.Close() }
}

# 3. דיאלוגים: הסרה, פרטי אפליקציה עם גישה מיוחדת, הודעת שגיאה, ופרוקסי
foreach ($theme in 'light', 'dark') {
    foreach ($language in 'he', 'en') {
        $script:GesherUiLanguage = $language
        $script:PanelThemeOverride = $theme
        $flow = [System.Windows.FlowDirection]$(if ($language -eq 'he') { 'RightToLeft' } else { 'LeftToRight' })
        $app = @(Get-SampleApps $language)[0]

        $dialog = New-PanelView 'confirm' @{ PanelFlowDirection = $flow }
        try {
            $dialog.Resources['PanelConfirmStyle'] = $dialog.Resources['DangerActionButton']
            $dialog.FindName('DialogTitle').Text = Get-GesherText 'cp_uninstall_title'
            $dialog.FindName('DialogSubTitle').Text = $app.Package; $dialog.FindName('DialogSubTitle').Visibility = 'Visible'
            $dialog.FindName('DialogMessage').Text = Get-GesherText 'cp_uninstall_confirm' @($app.Label)
            $dialog.FindName('DialogDetail').Text = Get-GesherText 'cp_uninstall_detail'; $dialog.FindName('DialogDetail').Visibility = 'Visible'
            $dialog.FindName('BtnConfirm').Content = Get-GesherText 'cp_btn_uninstall'
            $dialog.FindName('BtnCancel').Content = Get-GesherText 'cp_update_cancel'
            $icon = $dialog.FindName('AppIconImage'); $icon.Source = $app.IconImage; $icon.Visibility = 'Visible'
            $container = $dialog.FindName('IconContainer'); $container.Background = [System.Windows.Media.Brushes]::Transparent; $container.CornerRadius = [System.Windows.CornerRadius]::new(0)
            Show-Offscreen $dialog 0 0
            Save-Visual $dialog "dialog-$language-$theme-uninstall"
        } finally { $dialog.Close() }

        $dialog = New-PanelView 'confirm' @{ PanelFlowDirection = $flow }
        try {
            $dialog.FindName('DialogTitle').Text = $app.Label
            $dialog.FindName('DialogSubTitle').Text = $app.Package; $dialog.FindName('DialogSubTitle').Visibility = 'Visible'
            $dialog.FindName('DialogMessage').Text = (Get-GesherText 'cp_app_info_installed' @('2026-11-20 10:00')) + "`n" + (Get-GesherText 'cp_app_info_updated' @('2026-11-25 18:30'))
            $dialog.FindName('DialogDetail').Text = Get-GesherText 'cp_app_info_detail_list'; $dialog.FindName('DialogDetail').Visibility = 'Visible'
            $dialog.FindName('SwitchPanel').Visibility = 'Visible'
            $dialog.FindName('SwitchTitle').Text = Get-GesherText 'cp_access_title'
            foreach ($pair in @(@('cp_access_all_files', $true), @('cp_access_overlay', $false), @('cp_access_install', $false))) {
                $box = [System.Windows.Controls.CheckBox]::new()
                $box.Content = Get-GesherText $pair[0]; $box.IsChecked = $pair[1]
                $box.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2); $box.FontSize = 13
                [void]$dialog.FindName('SwitchList').Children.Add($box)
            }
            $dialog.FindName('BtnConfirm').Visibility = 'Collapsed'
            $dialog.FindName('BtnCancel').Content = Get-GesherText 'cp_app_info_close'
            $icon = $dialog.FindName('AppIconImage'); $icon.Source = $app.IconImage; $icon.Visibility = 'Visible'
            $container = $dialog.FindName('IconContainer'); $container.Background = [System.Windows.Media.Brushes]::Transparent; $container.CornerRadius = [System.Windows.CornerRadius]::new(0)
            Show-Offscreen $dialog 0 0
            Save-Visual $dialog "dialog-$language-$theme-details"
        } finally { $dialog.Close() }

        $dialog = New-PanelView 'message' @{ PanelFlowDirection = $flow; PanelMessageSymbol = '!' }
        try {
            $dialog.FindName('DialogMessage').Text = Get-GesherText 'cp_install_failed' @('example.apk')
            $dialog.FindName('BtnOk').Content = Get-GesherText 'cp_dialog_ok'
            $dialog.Resources['PanelBadgeBackground'] = Get-PanelBrush $dialog 'Danger'
            $dialog.Resources['PanelBadgeForeground'] = Get-PanelBrush $dialog 'OnDanger'
            Show-Offscreen $dialog 0 0
            Save-Visual $dialog "dialog-$language-$theme-message"
        } finally { $dialog.Close() }

        # הדיאלוג "אודות": שם המוצר, השורה "מבוסס על Gesher" והקרדיט ל-palmoni5, באותו מבנה כמו Show-ModernMessageDialog
        $dialog = New-PanelView 'message' @{ PanelFlowDirection = $flow; PanelMessageSymbol = 'i' }
        try {
            Set-PanelAboutText $dialog (Get-GesherText 'cp_about_body' @('1.2.0'))
            $dialog.FindName('BtnOk').Content = Get-GesherText 'cp_dialog_ok'
            $dialog.Resources['PanelBadgeBackground'] = Get-PanelBrush $dialog 'Brand'
            $dialog.Resources['PanelBadgeForeground'] = Get-PanelBrush $dialog 'OnBrand'
            Show-Offscreen $dialog 0 0
            Save-Visual $dialog "dialog-$language-$theme-about"
        } finally { $dialog.Close() }

        $dialog = New-PanelView 'proxy' @{ PanelFlowDirection = $flow }
        try {
            $dialog.FindName('DialogHeading').Text = Get-GesherText 'cp_proxy_app_title' @($app.Label)
            $dialog.FindName('DialogPackage').Text = $app.Package
            $dialog.FindName('DialogDetail').Text = Get-GesherText 'cp_proxy_app_desc'
            $mode = $dialog.FindName('DialogProxyMode')
            foreach ($key in 'cp_proxy_mode_inherit', 'cp_proxy_mode_windows', 'cp_proxy_mode_direct', 'cp_proxy_mode_server') {
                $item = [System.Windows.Controls.ComboBoxItem]::new(); $item.Content = Get-GesherText $key; [void]$mode.Items.Add($item)
            }
            $mode.SelectedIndex = 3
            $dialog.FindName('DialogProxyAddress').Text = 'socks5://127.0.0.1:1080'
            $dialog.FindName('BtnSave').Content = Get-GesherText 'cp_proxy_save'
            $dialog.FindName('BtnCancel').Content = Get-GesherText 'cp_update_cancel'
            Show-Offscreen $dialog 0 0
            Save-Visual $dialog "dialog-$language-$theme-proxy"
        } finally { $dialog.Close() }
    }
}
$script:PanelThemeOverride = $null
$files = @(Get-ChildItem $OutDir -Filter *.png)
if ($files.Count -lt 24) { throw "נוצרו רק $($files.Count) צילומים" }
"נוצרו $($files.Count) צילומים ב-$OutDir"
