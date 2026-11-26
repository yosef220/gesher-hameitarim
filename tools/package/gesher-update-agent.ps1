# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
# גשר המיתרים: סוכן העדכונים שרץ ברקע. קובץ חדש בפרויקט הזה.
#
# ‏gesher-app מפעיל אותו בלי חלון כשמשתמש פותח אפליקציה מתפריט התחל או מקובץ APK,
# ולכל היותר פעם ביום. כך מתעדכן גם מי שאף פעם לא פותח את מרכז הבקרה.
#
# הוא פועל לפי ההגדרות של מרכז הבקרה (updates\update-settings.json):
#   1. בודק אם יצאה גרסה חדשה, כשהבדיקה האוטומטית פעילה ועברו 24 שעות מהבדיקה הקודמת.
#   2. מוריד אותה ומאמת אותה כמו מרכז הבקרה: גודל, SHA-256 וגרסת המתקין.
#   3. מחכה שלא תהיה אפליקציה פתוחה. המכשיר נכבה לבד 10 דקות אחרי שהאפליקציה האחרונה
#      נסגרת. המתקין עוצר את המכשיר, ולכן מתקינים רק כשהוא כבוי ומרכז הבקרה סגור.
#   4. מריץ את המתקין בשקט, ומדווח על הצלחה רק כשהגרסה המותקנת היא באמת הגרסה החדשה.
#
# כשההתקנה האוטומטית כבויה הוא לא עושה כלום: מרכז הבקרה מציע את העדכון ומחכה לאישור.
# גרסה שההתקנה האוטומטית שלה נכשלה לא מותקנת שוב לבד, ומרכז הבקרה עדיין מציע אותה.
# הוא לא מציג חלונות. מה שקרה נרשם ב-logs\update-agent.log שבפרופיל.
# ‏GESHER_UPDATE_AGENT=0 מכבה אותו לגמרי.

param(
    [int] $LauncherProcessId = 0,
    [string] $LauncherStart = '',
    [int] $PollSeconds = 60,
    [int] $MaxWaitMinutes = 720,
    [int] $InstallTimeoutMinutes = 30
)

function Write-UpdateAgentLog([string] $Message) {
    try {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $script:AgentLog))
        $info = New-Object IO.FileInfo $script:AgentLog
        if ($info.Exists -and $info.Length -gt 131072) {
            [IO.File]::Copy($script:AgentLog, $script:AgentLog + '.old', $true)
            [IO.File]::Delete($script:AgentLog)
        }
        $line = (Get-UpdateAgentNow).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) + ' ' + $Message + [Environment]::NewLine
        [IO.File]::AppendAllText($script:AgentLog, $line, (New-Object Text.UTF8Encoding $false))
    } catch { }
}

function Get-UpdateAgentNow { return [DateTime]::UtcNow }

function Wait-UpdateAgentPoll { Start-Sleep -Seconds $script:AgentPollSeconds }

# תהליך חי, ואם ידוע זמן היצירה שלו, אותו תהליך: מספר תהליך שחזר לשימוש לא נחשב.
# כשאי אפשר לקרוא את זמן היצירה (תהליך של משתמש אחר), מניחים שהוא חי. עדיף לחכות.
function Test-UpdateAgentProcess([int] $Id, [string] $Start = '') {
    if ($Id -le 0) { return $false }
    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    try {
        if (-not $Start) { return $true }
        $expected = 0L
        if (-not [long]::TryParse($Start, [ref] $expected)) { return $true }
        return $process.StartTime.ToFileTimeUtc() -eq $expected
    } catch { return $true } finally { $process.Dispose() }
}

# המכשיר פעיל כשאחד מהתהליכים שבקובץ המצב שלו חי (Device.java: מספר התהליך וזמן היצירה
# של binderd, ‏servicemanager ו-system_server). מכשיר שעוד עולה כבר כתב את הקובץ הזה.
# קובץ ready לבד, בלי קובץ מצב, נבדק כמו במרכז הבקרה: לפי התהליך שרשום בו.
function Test-UpdateAgentDeviceRunning {
    $system = Join-Path $script:AgentRoot 'data/system'
    $stateFile = Join-Path $system 'gesher-device'
    $readyFile = Join-Path $system 'gesher-device.ready'
    try {
        if ([IO.File]::Exists($stateFile)) {
            $state = @{}
            foreach ($line in [IO.File]::ReadAllLines($stateFile)) {
                if ($line -match '^\s*[#!]' -or $line -notmatch '=') { continue }
                $key, $value = $line -split '=', 2
                $state[$key.Trim()] = ($value -replace '\\(.)', '$1').Trim()
            }
            foreach ($name in 'system_server', 'servicemanager', 'binderd') {
                $id = 0
                if ([int]::TryParse([string] $state[$name], [ref] $id) -and (Test-UpdateAgentProcess $id ([string] $state["$name.start"]))) {
                    return $true
                }
            }
        }
        if ([IO.File]::Exists($readyFile)) {
            $id = 0
            if ([int]::TryParse(([IO.File]::ReadAllText($readyFile)).Trim(), [ref] $id) -and (Test-UpdateAgentProcess $id)) { return $true }
        }
        return $false
    } catch {
        # הקובץ נכתב ברגע זה: המכשיר עולה או נכבה. נבדק שוב בסבב הבא.
        return $true
    }
}

function Test-UpdateAgentPanelOpen {
    $panel = $null
    try { return [Threading.Mutex]::TryOpenExisting($script:PanelName, [ref] $panel) }
    catch { return $true }
    finally { if ($panel) { $panel.Dispose() } }
}

# הפעלה שעוד לא סיימה לעלות, של כל אפליקציה: ‏gesher-launch.exe מתיקיית ההתקנה, או
# ‏PowerShell שמריץ את gesher-app.ps1 שלה. מכשיר שעולה עוד לא תמיד כתב את קובץ המצב שלו.
# כשאי אפשר לקרוא את רשימת התהליכים (WMI תקול), נשארות הבדיקות של המכשיר ושל ההפעלה שלנו.
function Test-UpdateAgentLaunchRunning {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $false }
    try {
        $install = [IO.Path]::GetFullPath($script:AgentInstall).TrimEnd([char[]] '\/')
        $appScript = Join-Path $install 'gesher-app.ps1'
        $filter = "Name = 'gesher-launch.exe' OR Name = 'powershell.exe' OR Name = 'pwsh.exe'"
        foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction Stop)) {
            if ($process.ProcessId -eq $PID) { continue }
            if ($process.Name -ieq 'gesher-launch.exe') {
                $path = [string] $process.ExecutablePath
                if ($path -and [string]::Equals([IO.Path]::GetDirectoryName($path).TrimEnd([char[]] '\/'), $install, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } elseif (([string] $process.CommandLine).IndexOf($appScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $true
            }
        }
    } catch { }
    return $false
}

# למה עוד אי אפשר להתקין: אפליקציה נפתחת ברגע זה, יש אפליקציה פתוחה (המכשיר פעיל), או
# שמרכז הבקרה פתוח. $null כשאין סיבה.
function Get-UpdateAgentBusyReason {
    if ($script:LauncherProcessId -gt 0 -and (Test-UpdateAgentProcess $script:LauncherProcessId $script:LauncherStart)) { return 'launcher' }
    if (Test-UpdateAgentLaunchRunning) { return 'launcher' }
    if (Test-UpdateAgentDeviceRunning) { return 'device' }
    if (Test-UpdateAgentPanelOpen) { return 'panel' }
    return $null
}

function Wait-UpdateAgentIdle([DateTime] $Deadline) {
    $quiet = 0
    $last = $null
    while ($true) {
        $reason = Get-UpdateAgentBusyReason
        if ($reason) {
            $quiet = 0
            if ($reason -ne $last) {
                $text = switch ($reason) {
                    'launcher' { 'ממתין שההפעלה של האפליקציה תסתיים.' }
                    'device' { 'ממתין: יש אפליקציה פתוחה. ההתקנה תתחיל כשהמכשיר ייכבה, 10 דקות אחרי שהאפליקציה האחרונה נסגרת.' }
                    default { 'ממתין: מרכז הבקרה פתוח.' }
                }
                Write-UpdateAgentLog $text
                $last = $reason
            }
        } else {
            # שתי בדיקות רצופות בלי סיבה לחכות, בהפרש של סבב אחד: מכשיר שנכבה רגע לפני
            # הפעלה חדשה לא נחשב פנוי.
            $quiet++
            if ($quiet -ge 2) { return $true }
        }
        if ((Get-UpdateAgentNow) -ge $Deadline) { return $false }
        Wait-UpdateAgentPoll
    }
}

# הורדות של הסוכן: תיקייה אחת לכל הורדה, updates\agent\gesher-update-<guid>, כמו
# ש-Receive-GesherUpdate יוצר. נמחקים רק המתקין, הקובץ החלקי שלו והתיקייה הריקה,
# אף פעם לא תיקייה שיש בה משהו אחר. ההורדות של מרכז הבקרה (updates\downloads) לא נוגעים.
function Get-UpdateAgentDownloadDirectories {
    if (-not [IO.Directory]::Exists($script:AgentDownloads)) { return @() }
    return @([IO.Directory]::GetDirectories($script:AgentDownloads) |
        Where-Object { (Split-Path -Leaf $_) -cmatch '\Agesher-update-[0-9a-f]{32}\z' })
}

function Remove-UpdateAgentDownloadDirectory([string] $Directory) {
    try {
        foreach ($file in [IO.Directory]::GetFiles($Directory)) {
            if ((Split-Path -Leaf $file) -cmatch '\Agesher-setup-[0-9.]+\.exe(\.partial)?\z') { [IO.File]::Delete($file) }
        }
        [IO.Directory]::Delete($Directory, $false)
    } catch { }
}

function Clear-UpdateAgentDownloads([string] $Keep = '') {
    foreach ($directory in Get-UpdateAgentDownloadDirectories) {
        if ($Keep -and [string]::Equals($directory, $Keep, [StringComparison]::OrdinalIgnoreCase)) { continue }
        Remove-UpdateAgentDownloadDirectory $directory
    }
    # תיקיית הסוכן קיימת רק כשיש הורדה שמחכה: gesher-app מפעיל אותו גם לפי זה.
    try {
        if ([IO.Directory]::Exists($script:AgentDownloads) -and
            [IO.Directory]::GetFileSystemEntries($script:AgentDownloads).Count -eq 0) {
            [IO.Directory]::Delete($script:AgentDownloads, $false)
        }
    } catch { }
}

# הורדה קודמת של אותה גרסה, שעוד לא הותקנה (למשל, כי אפליקציה נשארה פתוחה כל היום).
# היא מאומתת מחדש מול הנתונים העדכניים של הגרסה, ורק אז משמשת שוב.
function Find-UpdateAgentDownload([object] $Release) {
    foreach ($directory in Get-UpdateAgentDownloadDirectories) {
        $path = Join-Path $directory $Release.AssetName
        if (-not [IO.File]::Exists($path)) { continue }
        try {
            $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try { Assert-GesherUpdateInstaller -Path $path -Release $Release -Stream $stream } finally { $stream.Dispose() }
            return [pscustomobject]@{ Path = $path; Directory = $directory; Release = $Release }
        } catch {
            Write-UpdateAgentLog ('הורדה קודמת לא עברה אימות, ולא תשמש: ' + $_.Exception.Message)
        }
    }
    return $null
}

function Get-UpdateAgentFailedVersion {
    try {
        $path = Join-Path $script:AgentState 'agent-failed-version.txt'
        if (-not [IO.File]::Exists($path)) { return $null }
        return ConvertTo-GesherStableVersion ([IO.File]::ReadAllText($path).Trim())
    } catch { return $null }
}

function Set-UpdateAgentFailedVersion([string] $Version) {
    try {
        $null = [IO.Directory]::CreateDirectory($script:AgentState)
        $path = Join-Path $script:AgentState 'agent-failed-version.txt'
        if ($Version) { [IO.File]::WriteAllText($path, $Version, (New-Object Text.UTF8Encoding $false)) }
        elseif ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    } catch { }
}

# ‏gesher-app מפעיל את הסוכן לפי זמן השינוי של קובץ ההגדרות. בסוף כל ריצה הוא מתעדכן,
# כך שהסוכן לא מופעל שוב עד מחר, גם כשלא נבדק כלום (הבדיקה כבויה, או שעוד לא עבר יום).
function Update-UpdateAgentStamp {
    try {
        $path = Join-Path $script:AgentState 'update-settings.json'
        if ([IO.File]::Exists($path)) { [IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow) }
    } catch { }
}

# ריצה אחת. מחזירה מה קרה, במילה אחת, לבדיקות וליומן.
function Invoke-UpdateAgent {
    try {
        $preferences = Get-GesherUpdatePreferences -StateDirectory $script:AgentState
        if (-not $preferences.AutomaticChecks) {
            Clear-UpdateAgentDownloads
            Write-UpdateAgentLog 'בדיקת העדכונים האוטומטית כבויה במרכז הבקרה. לא נבדק כלום.'
            return 'ChecksDisabled'
        }
        if (-not $preferences.AutomaticInstall) {
            Clear-UpdateAgentDownloads
            Write-UpdateAgentLog 'ההתקנה האוטומטית כבויה במרכז הבקרה. מרכז הבקרה יציע את העדכון ויחכה לאישור.'
            return 'InstallDisabled'
        }
        $due = Test-GesherUpdateCheckDue -Preferences $preferences -Now ([DateTimeOffset] (Get-UpdateAgentNow))
        $pending = @(Get-UpdateAgentDownloadDirectories).Count -gt 0
        if (-not $due -and -not $pending) { return 'NotDue' }
        if ($due) {
            # כמו מרכז הבקרה: הזמן נשמר לפני הבדיקה, כך שרשת חסומה לא גורמת לניסיון בכל הפעלה.
            Save-GesherUpdatePreferences -StateDirectory $script:AgentState -Preferences ([pscustomobject]@{
                AutomaticChecks = $true; AutomaticInstall = $true
                LastCheckUtc = (Get-UpdateAgentNow).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            })
        }
        try { $check = Get-GesherUpdate -InstallDirectory $script:AgentInstall }
        catch {
            Write-UpdateAgentLog ('בדיקת העדכונים נכשלה: ' + $_.Exception.Message)
            return 'CheckFailed'
        }
        if ($check.Status -ne 'Available') {
            Clear-UpdateAgentDownloads
            $text = switch ($check.Status) {
                'Current' { 'אין עדכון: הגרסה המותקנת, ' + $check.CurrentVersion + ', היא העדכנית.' }
                'NoRelease' { 'אין עדכון: עוד לא פורסמה גרסה.' }
                default { 'אין עדכון: הגרסה המותקנת לא ידועה (התקנה שלא נעשתה מהמתקין).' }
            }
            Write-UpdateAgentLog $text
            return [string] $check.Status
        }
        $release = $check.Release
        if ((Get-UpdateAgentFailedVersion) -ceq $release.Version) {
            Clear-UpdateAgentDownloads
            Write-UpdateAgentLog ('גרסה ' + $release.Version + ' נכשלה בהתקנה אוטומטית קודמת, ולא תותקן שוב לבד. מרכז הבקרה מציע אותה.')
            return 'PreviouslyFailed'
        }
        $download = Find-UpdateAgentDownload $release
        Clear-UpdateAgentDownloads -Keep $(if ($download) { $download.Directory } else { '' })
        if ($download) {
            Write-UpdateAgentLog ('גרסה ' + $release.Version + ' כבר הורדה ואומתה. ממשיך ממנה.')
        } else {
            Write-UpdateAgentLog ('נמצאה גרסה ' + $release.Version + ' (מותקנת ' + $check.CurrentVersion + '). מוריד.')
            try { $download = Receive-GesherUpdate -Release $release -DestinationDirectory $script:AgentDownloads }
            catch {
                Clear-UpdateAgentDownloads
                Write-UpdateAgentLog ('ההורדה נכשלה: ' + $_.Exception.Message)
                return 'DownloadFailed'
            }
            Write-UpdateAgentLog 'ההורדה הסתיימה ואומתה: הגודל, ה-SHA-256 וגרסת המתקין תואמים לגרסה שפורסמה.'
        }
        # מנעול ההתקנה: ‏gesher-app שמתחיל לפתוח אפליקציה כשהוא מוחזק מחכה לסוף ההתקנה, ופותח
        # אותה מהגרסה החדשה. הבדיקה האחרונה נעשית כשהמנעול כבר מוחזק, כך שהפעלה שהתחילה
        # רגע לפני כן נראית בה, והפעלה שמתחילה אחריה מחכה.
        $deadline = (Get-UpdateAgentNow).AddMinutes($script:AgentMaxWaitMinutes)
        $lock = New-Object Threading.Mutex($false, $script:InstallLockName)
        $locked = $false
        try {
            while ($true) {
                if (-not (Wait-UpdateAgentIdle $deadline)) {
                    Write-UpdateAgentLog ('עדיין יש אפליקציה פתוחה אחרי ' + $script:AgentMaxWaitMinutes + ' דקות. ההורדה נשמרת, והניסיון הבא יהיה בהפעלה הבאה של אפליקציה.')
                    return 'Deferred'
                }
                try { $locked = $lock.WaitOne() } catch [Threading.AbandonedMutexException] { $locked = $true }
                if (-not (Get-UpdateAgentBusyReason)) { break }
                $lock.ReleaseMutex()
                $locked = $false
            }
            # ההגדרות נקראות שוב: אולי המשתמש כיבה את ההתקנה האוטומטית בזמן ההמתנה.
            $preferences = Get-GesherUpdatePreferences -StateDirectory $script:AgentState
            if (-not $preferences.AutomaticChecks -or -not $preferences.AutomaticInstall) {
                Clear-UpdateAgentDownloads
                Write-UpdateAgentLog 'ההתקנה האוטומטית כובתה בזמן ההמתנה. העדכון לא הותקן.'
                return 'InstallDisabled'
            }
            Write-UpdateAgentLog ('מתקין את גרסה ' + $release.Version + ' בשקט.')
            try { $process = Start-GesherUpdateInstaller -Download $download -InstallDirectory $script:AgentInstall -Silent }
            catch {
                Clear-UpdateAgentDownloads
                Set-UpdateAgentFailedVersion $release.Version
                Write-UpdateAgentLog ('המתקין לא הופעל: ' + $_.Exception.Message)
                return 'InstallFailed'
            }
            try {
                if (-not $process.WaitForExit($script:AgentInstallTimeoutMinutes * 60000)) {
                    # לא נמחק כלום בזמן שהמתקין רץ. ההורדה תנוקה בריצה הבאה.
                    Write-UpdateAgentLog ('המתקין עדיין רץ אחרי ' + $script:AgentInstallTimeoutMinutes + ' דקות. הסוכן מפסיק לחכות לו.')
                    return 'InstallerRunning'
                }
                $code = $process.ExitCode
            } finally { $process.Dispose() }
        } finally {
            if ($locked) { $lock.ReleaseMutex() }
            $lock.Dispose()
        }
        $installed = Get-GesherInstalledVersion -InstallDirectory $script:AgentInstall
        Clear-UpdateAgentDownloads
        if ($code -eq 0 -and $installed -ceq $release.Version) {
            Set-UpdateAgentFailedVersion ''
            Write-UpdateAgentLog ('העדכון הותקן: הגרסה המותקנת עכשיו היא ' + $installed + '.')
            return 'Installed'
        }
        Set-UpdateAgentFailedVersion $release.Version
        $shown = if ($installed) { $installed } else { 'לא ידועה' }
        Write-UpdateAgentLog ('ההתקנה נכשלה: קוד היציאה של המתקין ' + $code + ', והגרסה המותקנת ' + $shown + '.')
        return 'InstallFailed'
    } finally {
        Update-UpdateAgentStamp
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
if ($env:GESHER_UPDATE_AGENT -eq '0') { exit 0 }
Remove-Item Env:GESHER_LAUNCH_ERROR_FILE, Env:GESHER_LAUNCH_DETACH -ErrorAction SilentlyContinue
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $here 'gesher-runtime-files.ps1')
$script:AgentInstall = $here
$script:AgentRoot = Set-GesherProfileEnvironment $here
. (Join-Path $here 'gesher-update.ps1')
$script:AgentState = Join-Path $script:AgentRoot 'updates'
$script:AgentDownloads = Join-Path $script:AgentState 'agent'
$script:AgentLog = Join-Path $script:AgentRoot 'logs/update-agent.log'
$script:PanelName = Get-GesherControlPanelName $script:AgentRoot
$script:InstallLockName = Get-GesherUpdateLockName $script:AgentRoot 'UpdateInstall'
$script:LauncherProcessId = $LauncherProcessId
$script:LauncherStart = $LauncherStart
$script:AgentPollSeconds = [Math]::Max(1, $PollSeconds)
$script:AgentMaxWaitMinutes = [Math]::Max(0, $MaxWaitMinutes)
$script:AgentInstallTimeoutMinutes = [Math]::Max(1, $InstallTimeoutMinutes)

# סוכן אחד לכל פרופיל: הפעלה נוספת בזמן שהוא רץ יוצאת מיד.
$exitCode = 0
$mutex = New-Object Threading.Mutex($false, (Get-GesherUpdateLockName $script:AgentRoot 'UpdateAgent'))
$owned = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if ($owned) { $null = Invoke-UpdateAgent }
} catch {
    Write-UpdateAgentLog ('שגיאה: ' + $_.Exception.Message)
    $exitCode = 1
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $exitCode
