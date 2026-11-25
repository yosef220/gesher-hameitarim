param([string] $PackageDirectory = (Join-Path $PSScriptRoot '../../../tools/package'))

# גשר המיתרים: בדיקות לסוכן העדכונים שרץ ברקע (tools/package/gesher-update-agent.ps1) ולחיבור
# שלו ב-gesher-app (Wait-GesherUpdateInstall ו-Start-GesherUpdateAgentIfDue). רצות הפונקציות
# האמיתיות של הסוכן ושל מנגנון העדכונים, כולל האימות של המתקין שהורד. מוחלפים רק הגבולות:
# הרשת, גרסת המתקין שנקראת מקובץ ה-EXE, הפעלת המתקין, השעון וההמתנה בין סבבים.
# ההתקנה האמיתית נבדקת בשלב החבילה של ה-CI.

$ErrorActionPreference = 'Stop'
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
$agentPath = Join-Path $PackageDirectory 'gesher-update-agent.ps1'
$tokens = $null; $parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($agentPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. (Join-Path $PackageDirectory 'gesher-runtime-files.ps1')
. (Join-Path $PackageDirectory 'gesher-update.ps1')
# בהרצה כ-dot-source הסוכן מגדיר את הפונקציות שלו בלבד, ולא מתחיל לרוץ.
. $agentPath
$realLaunchRunning = ${function:Test-UpdateAgentLaunchRunning}
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

$script:Checks = 0
function Assert-Agent([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:Checks++
}

$script:Payload = [Text.Encoding]::UTF8.GetBytes('Gesher HaMeitarim update agent installer fixture')
$sha = [Security.Cryptography.SHA256]::Create()
try { $script:PayloadHash = ([BitConverter]::ToString($sha.ComputeHash($script:Payload))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }

function New-ReleaseMetadata([string] $Version) {
    [PSCustomObject]@{
        tag_name = "v$Version"
        html_url = "https://github.com/yosef220/gesher-hameitarim/releases/tag/v$Version"
        draft = $false
        prerelease = $false
        assets = @([PSCustomObject]@{
            name = "gesher-setup-$Version.exe"
            browser_download_url = "https://github.com/yosef220/gesher-hameitarim/releases/download/v$Version/gesher-setup-$Version.exe"
            size = $script:Payload.Length
            state = 'uploaded'
            digest = "sha256:$script:PayloadHash"
        })
    }
}

# הגבולות שמוחלפים.
function Invoke-GesherUpdateMetadataRequest {
    param([Threading.CancellationToken] $CancellationToken = [Threading.CancellationToken]::None)
    $script:MetadataCalls++
    switch ($script:MetadataMode) {
        'missing' { return $null }
        'timeout' { throw [TimeoutException]::new('GitHub request timed out') }
        default { return (New-ReleaseMetadata $script:ReleaseVersion | ConvertTo-Json -Depth 8) }
    }
}
function Invoke-GesherUpdateDownload {
    param([uri] $Uri, [string] $Path, [long] $ExpectedSize,
        [Threading.CancellationToken] $CancellationToken = [Threading.CancellationToken]::None)
    $script:DownloadCalls++
    switch ($script:DownloadMode) {
        'fail' { [IO.File]::WriteAllBytes($Path, $script:Payload[0..4]); throw [IO.IOException]::new('Connection ended during download') }
        'corrupt' { [IO.File]::WriteAllBytes($Path, [byte[]]::new($script:Payload.Length)) }
        default { [IO.File]::WriteAllBytes($Path, $script:Payload) }
    }
}
function Get-GesherUpdateInstallerVersion([string] $Path) { return $script:ReleaseVersion }
function New-FixtureProcess([int] $ExitCode, [bool] $Finishes) {
    $process = [PSCustomObject]@{ ExitCode = $ExitCode; Finishes = $Finishes; Disposed = $false }
    $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $this.Finishes }
    $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
    return $process
}
function Start-GesherUpdateProcess {
    param([string] $Path, $Arguments, [string] $WorkingDirectory)
    $script:ProcessCalls++
    $script:StartedArguments = @($Arguments) -join ' '
    $script:StartedPath = $Path
    # מנעול ההתקנה מוחזק בזמן שהמתקין רץ, ו-gesher-app מחכה לו.
    $probe = $null
    $script:LockHeldDuringInstall = [Threading.Mutex]::TryOpenExisting($script:InstallLockName, [ref] $probe)
    if ($probe) { $probe.Dispose() }
    $script:DeviceRunningDuringInstall = Test-UpdateAgentDeviceRunning
    if ($script:InstallWritesVersion) { Set-InstalledVersion $script:InstallWritesVersion }
    $script:LastProcess = New-FixtureProcess $script:InstallExitCode $script:InstallFinishes
    return $script:LastProcess
}
function Get-UpdateAgentNow { return $script:Now }
function Wait-UpdateAgentPoll {
    $script:Polls++
    $script:Now = $script:Now.AddSeconds($script:AgentPollSeconds)
    & $script:OnPoll
}
function Test-UpdateAgentLaunchRunning {
    $script:LaunchChecks++
    if ($script:LaunchRunning.Count -eq 0) { return $false }
    $next = $script:LaunchRunning[0]
    $script:LaunchRunning = @($script:LaunchRunning | Select-Object -Skip 1)
    return [bool] $next
}

function Set-InstalledVersion([string] $Version) {
    [IO.File]::WriteAllText((Join-Path $script:AgentInstall 'gesher-version.ini'), "[Gesher]`r`nVersion=$Version`r`n", (New-Object Text.UTF8Encoding $false))
}
function Save-Preferences([bool] $Checks, [bool] $Install, $Last) {
    Save-GesherUpdatePreferences -StateDirectory $script:AgentState -Preferences ([PSCustomObject]@{
        AutomaticChecks = $Checks; AutomaticInstall = $Install; LastCheckUtc = $Last
    })
}
function Get-SettingsPath { return (Join-Path $script:AgentState 'update-settings.json') }
function Set-SettingsAge([double] $Hours) {
    [IO.File]::SetLastWriteTimeUtc((Get-SettingsPath), [DateTime]::UtcNow.AddHours(-$Hours))
}
function Get-AgentLog {
    if (-not [IO.File]::Exists($script:AgentLog)) { return '' }
    return [IO.File]::ReadAllText($script:AgentLog)
}
function Get-DevicePath([string] $Name) { return (Join-Path (Join-Path $script:AgentRoot 'data/system') $Name) }
$self = [Diagnostics.Process]::GetCurrentProcess()
$script:SelfStart = $self.StartTime.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
$self.Dispose()
function Set-DeviceRunning([bool] $Running) {
    $path = Get-DevicePath 'gesher-device'
    if ($Running) {
        [IO.File]::WriteAllText($path, "device=gesher-test`nsystem_server=$PID`nsystem_server.start=$script:SelfStart`n")
    } elseif ([IO.File]::Exists($path)) {
        [IO.File]::Delete($path)
    }
}

function Reset-AgentCase {
    $script:CaseNumber++
    $case = Join-Path $script:TestRoot ([string] $script:CaseNumber)
    $script:AgentInstall = Join-Path $case 'install'
    $script:AgentRoot = Join-Path $case 'profile'
    $null = New-Item -ItemType Directory -Force -Path $script:AgentInstall
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:AgentRoot 'data/system')
    $script:AgentState = Join-Path $script:AgentRoot 'updates'
    $script:AgentDownloads = Join-Path $script:AgentState 'agent'
    $script:AgentLog = Join-Path $script:AgentRoot 'logs/update-agent.log'
    $suffix = [guid]::NewGuid().ToString('N')
    $script:PanelName = 'Local\GesherAgentTest.ControlPanel.' + $suffix
    $script:InstallLockName = 'Local\GesherAgentTest.UpdateInstall.' + $suffix
    $script:LauncherProcessId = 0
    $script:LauncherStart = ''
    $script:AgentPollSeconds = 60
    $script:AgentMaxWaitMinutes = 30
    $script:AgentInstallTimeoutMinutes = 30
    $script:Now = [DateTime]::new(2026, 12, 1, 9, 0, 0, [DateTimeKind]::Utc)
    $script:Polls = 0
    $script:OnPoll = {}
    $script:MetadataCalls = 0
    $script:MetadataMode = 'release'
    $script:ReleaseVersion = '0.2.1'
    $script:DownloadCalls = 0
    $script:DownloadMode = 'complete'
    $script:ProcessCalls = 0
    $script:StartedArguments = $null
    $script:InstallExitCode = 0
    $script:InstallWritesVersion = '0.2.1'
    $script:InstallFinishes = $true
    $script:LockHeldDuringInstall = $null
    $script:DeviceRunningDuringInstall = $null
    $script:LaunchRunning = @()
    $script:LaunchChecks = 0
    Set-InstalledVersion '0.2.0'
}

$script:CaseNumber = 0
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('gesher-update-agent ' + [char]0x05D2 + ' ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $script:TestRoot
$panel = $null
try {
    # שמות המנעולים: קבועים לפרופיל ברירת המחדל, ייחודיים לכל פרופיל אחר, ושונים זה מזה.
    $appData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    $defaultProfile = Join-Path $appData 'Gesher'
    Assert-Agent ((Get-GesherUpdateLockName $defaultProfile 'UpdateAgent') -ceq 'Local\Gesher.UpdateAgent') 'The default profile agent lock name changed'
    Assert-Agent ((Get-GesherUpdateLockName $defaultProfile 'UpdateInstall') -ceq 'Local\Gesher.UpdateInstall') 'The default profile install lock name changed'
    $otherLock = Get-GesherUpdateLockName (Join-Path $script:TestRoot 'other') 'UpdateInstall'
    Assert-Agent ($otherLock -cmatch '\ALocal\\Gesher\.UpdateInstall\.[0-9A-F]{64}\z') "A custom profile has no unique install lock: $otherLock"
    Assert-Agent ($otherLock -cne (Get-GesherUpdateLockName (Join-Path $script:TestRoot 'other') 'UpdateAgent')) 'The agent and install locks share a name'

    # 1. הבדיקה האוטומטית כבויה: אין פנייה לרשת, הורדה שחיכתה נמחקת, וחותמת הזמן מתעדכנת.
    Reset-AgentCase
    Save-Preferences $false $true $null
    Set-SettingsAge 30
    $stale = Join-Path $script:AgentDownloads ('gesher-update-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $stale
    [IO.File]::WriteAllBytes((Join-Path $stale 'gesher-setup-0.2.1.exe'), $script:Payload)
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'ChecksDisabled') 'Disabled checks did not stop the agent'
    Assert-Agent ($script:MetadataCalls -eq 0) 'Disabled checks still contacted the release feed'
    Assert-Agent (-not [IO.Directory]::Exists($script:AgentDownloads)) 'Disabled checks left a waiting download'
    Assert-Agent (([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc((Get-SettingsPath))).TotalMinutes -lt 5) 'The settings stamp was not refreshed'
    Assert-Agent ((Get-AgentLog).Contains('כבויה')) 'The log does not say the checks are disabled'

    # 2. ההתקנה האוטומטית כבויה: מרכז הבקרה מטפל בעדכון, והסוכן לא עושה כלום.
    Reset-AgentCase
    Save-Preferences $true $false $null
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'InstallDisabled') 'Disabled automatic installation did not stop the agent'
    Assert-Agent ($script:MetadataCalls -eq 0 -and $script:ProcessCalls -eq 0) 'Disabled automatic installation still checked or installed'

    # 3. עוד לא עבר יום מהבדיקה הקודמת ואין הורדה שמחכה: אין פנייה לרשת.
    Reset-AgentCase
    Save-Preferences $true $true ($script:Now.AddHours(-3).ToString('o'))
    Set-SettingsAge 30
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'NotDue') 'A recent check was repeated'
    Assert-Agent ($script:MetadataCalls -eq 0) 'A check that is not due contacted the release feed'
    Assert-Agent (([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc((Get-SettingsPath))).TotalMinutes -lt 5) 'A not-due run did not refresh the settings stamp'

    # 4. הגרסה המותקנת עדכנית: נבדק פעם אחת, וזמן הבדיקה נשמר.
    Reset-AgentCase
    $script:ReleaseVersion = '0.2.0'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Current') 'A current installation was not reported as current'
    Assert-Agent ($script:MetadataCalls -eq 1 -and $script:DownloadCalls -eq 0) 'A current installation downloaded something'
    $saved = Get-GesherUpdatePreferences -StateDirectory $script:AgentState
    Assert-Agent ([bool] $saved.LastCheckUtc -and ([DateTimeOffset]::Parse($saved.LastCheckUtc)).UtcDateTime -eq $script:Now) 'The check time was not saved'
    Assert-Agent ($saved.AutomaticChecks -and $saved.AutomaticInstall) 'Saving the check time changed the preferences'
    Assert-Agent ((Get-AgentLog).Contains('0.2.0')) 'The log does not name the installed version'

    # 5. אין גרסה מפורסמת, ובדיקה שנכשלה: הזמן נשמר לפני הבדיקה, כך שלא מנסים בכל הפעלה.
    Reset-AgentCase
    $script:MetadataMode = 'missing'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'NoRelease') 'A missing release was not reported'
    Reset-AgentCase
    $script:MetadataMode = 'timeout'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'CheckFailed') 'A failed check was not reported'
    Assert-Agent ([bool] (Get-GesherUpdatePreferences -StateDirectory $script:AgentState).LastCheckUtc) 'A failed check did not save its time'
    Assert-Agent ((Get-AgentLog).Contains('timed out')) 'The log does not keep the check error'

    # 6. גרסה חדשה כשאין אפליקציה פתוחה: הורדה, אימות, התקנה שקטה, ודיווח לפי הגרסה המותקנת.
    Reset-AgentCase
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'An available update was not installed'
    Assert-Agent ($script:DownloadCalls -eq 1 -and $script:ProcessCalls -eq 1) 'The update was not downloaded and installed once'
    Assert-Agent ($script:StartedArguments.StartsWith('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=')) "The installer did not run silently: $script:StartedArguments"
    Assert-Agent ($script:StartedArguments.Contains([IO.Path]::GetFullPath($script:AgentInstall))) 'The installer did not target the installation directory'
    Assert-Agent ($script:LockHeldDuringInstall -eq $true) 'The install lock was not held while the installer ran'
    Assert-Agent ($script:DeviceRunningDuringInstall -eq $false) 'The installer ran while the device was running'
    Assert-Agent ($script:LastProcess.Disposed) 'The installer process handle was not released'
    Assert-Agent ((Get-GesherInstalledVersion $script:AgentInstall) -ceq '0.2.1') 'The fixture installer did not update the version'
    Assert-Agent (-not [IO.Directory]::Exists($script:AgentDownloads)) 'The installed download was not removed'
    Assert-Agent ($script:Polls -eq 1) "Idle was not confirmed by two observations one poll apart ($script:Polls polls)"
    Assert-Agent ($script:LaunchChecks -ge 3) 'The final launch check under the install lock did not run'
    $probe = $null
    Assert-Agent (-not [Threading.Mutex]::TryOpenExisting($script:InstallLockName, [ref] $probe)) 'The install lock outlived the installation'
    if ($probe) { $probe.Dispose() }
    Assert-Agent ((Get-AgentLog).Contains('הותקן') -and (Get-AgentLog).Contains('אומתה')) 'The log does not record verification and installation'

    # 7. אפליקציה פתוחה: ממתינים עד שהמכשיר נכבה, ורק אז מתקינים.
    Reset-AgentCase
    Set-DeviceRunning $true
    $script:OnPoll = { if ($script:Polls -eq 3) { Set-DeviceRunning $false } }
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'The update was not installed after the apps closed'
    Assert-Agent ($script:Polls -eq 4) "The agent did not wait for the device ($script:Polls polls)"
    Assert-Agent ($script:DeviceRunningDuringInstall -eq $false) 'The installer ran while an app was open'
    Assert-Agent ((Get-AgentLog).Contains('יש אפליקציה פתוחה')) 'The log does not say that it waited for an app'

    # 8. אפליקציה שנשארת פתוחה: ההורדה נשמרת, והריצה הבאה משתמשת בה אחרי אימות מחדש.
    Reset-AgentCase
    Set-DeviceRunning $true
    $script:AgentMaxWaitMinutes = 5
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Deferred') 'A long-running app did not defer the installation'
    Assert-Agent ($script:ProcessCalls -eq 0) 'The installer ran while an app stayed open'
    Assert-Agent (@(Get-UpdateAgentDownloadDirectories).Count -eq 1) 'The verified download was not kept for the next run'
    Set-DeviceRunning $false
    $script:DownloadCalls = 0
    $script:MetadataCalls = 0
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'The kept download was not installed'
    Assert-Agent ($script:DownloadCalls -eq 0 -and $script:MetadataCalls -eq 1) 'The kept download was downloaded again, or not re-verified against the release'
    Assert-Agent ((Get-AgentLog).Contains('כבר הורדה')) 'The log does not say the download was reused'

    # 9. הורדה שמורה שהשתנתה: לא משמשת. מורידים מחדש.
    Reset-AgentCase
    Set-DeviceRunning $true
    $script:AgentMaxWaitMinutes = 0
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Deferred') 'The download was not kept'
    $kept = @(Get-UpdateAgentDownloadDirectories)[0]
    [IO.File]::WriteAllBytes((Join-Path $kept 'gesher-setup-0.2.1.exe'), [byte[]]::new($script:Payload.Length))
    Set-DeviceRunning $false
    $script:AgentMaxWaitMinutes = 30
    $script:DownloadCalls = 0
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'A changed download blocked the update'
    Assert-Agent ($script:DownloadCalls -eq 1) 'A changed download was installed instead of downloaded again'
    Assert-Agent (-not [IO.Directory]::Exists($kept)) 'The changed download was not removed'
    Assert-Agent ((Get-AgentLog).Contains('לא עברה אימות')) 'The log does not record the failed verification'

    # 10. הורדה שנכשלה או שלא עוברת אימות: לא מותקנת, ולא נשאר ממנה כלום.
    Reset-AgentCase
    $script:DownloadMode = 'fail'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'DownloadFailed') 'A failed download was not reported'
    Assert-Agent (-not [IO.Directory]::Exists($script:AgentDownloads)) 'A failed download left files'
    Reset-AgentCase
    $script:DownloadMode = 'corrupt'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'DownloadFailed') 'A corrupt download was not rejected'
    Assert-Agent ($script:ProcessCalls -eq 0) 'A corrupt download was installed'

    # 11. התקנה שנכשלה: לא מדווחת כהצלחה, והגרסה הזאת לא מותקנת שוב לבד. גרסה חדשה יותר כן.
    Reset-AgentCase
    $script:InstallExitCode = 5
    $script:InstallWritesVersion = $null
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'InstallFailed') 'A failed installer exit was reported as success'
    Assert-Agent ((Get-AgentLog).Contains('ההתקנה נכשלה') -and (Get-AgentLog).Contains('5')) 'The log does not keep the installer exit code'
    Save-Preferences $true $true $null
    $script:ProcessCalls = 0
    $script:DownloadCalls = 0
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'PreviouslyFailed') 'A failed version was installed again automatically'
    Assert-Agent ($script:ProcessCalls -eq 0 -and $script:DownloadCalls -eq 0) 'A failed version was downloaded or installed again'
    Save-Preferences $true $true $null
    $script:ReleaseVersion = '0.2.2'
    $script:InstallExitCode = 0
    $script:InstallWritesVersion = '0.2.2'
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'A newer version after a failure was not installed'
    Assert-Agent ($null -eq (Get-UpdateAgentFailedVersion)) 'A successful installation kept the failure record'

    # 12. קוד יציאה 0 בלי שהגרסה השתנתה: לא הצלחה.
    Reset-AgentCase
    $script:InstallWritesVersion = $null
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'InstallFailed') 'An installer that changed nothing was reported as success'
    Assert-Agent ((Get-AgentLog).Contains('0.2.0')) 'The log does not name the version that is still installed'

    # 13. מתקין שלא מסתיים: הסוכן מפסיק לחכות ולא מוחק את ההורדה שבשימוש.
    Reset-AgentCase
    $script:InstallFinishes = $false
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'InstallerRunning') 'A running installer was not reported'
    Assert-Agent (@(Get-UpdateAgentDownloadDirectories).Count -eq 1) 'The download was removed while the installer still ran'

    # 14. מרכז הבקרה פתוח: ממתינים עד שהוא נסגר.
    Reset-AgentCase
    $panel = New-Object Threading.Mutex($false, $script:PanelName)
    $script:OnPoll = { if ($script:Polls -eq 2 -and $script:panel) { $script:panel.Dispose(); $script:panel = $null; $script:PanelClosed = $true } }
    $script:PanelClosed = $false
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'The update was not installed after the control panel closed'
    Assert-Agent ($script:PanelClosed -and $script:Polls -eq 3) "The agent did not wait for the control panel ($script:Polls polls)"
    Assert-Agent ((Get-AgentLog).Contains('מרכז הבקרה פתוח')) 'The log does not say that it waited for the control panel'
    if ($panel) { $panel.Dispose(); $panel = $null }

    # 15. ההפעלה שהתחילה את הסוכן עוד רצה: ממתינים. זמן יצירה אחר הוא תהליך אחר.
    Reset-AgentCase
    $script:LauncherProcessId = $PID
    $script:LauncherStart = $script:SelfStart
    Assert-Agent ((Get-UpdateAgentBusyReason) -ceq 'launcher') 'A running launcher was not seen'
    $script:LauncherStart = '1'
    Assert-Agent ($null -eq (Get-UpdateAgentBusyReason)) 'A reused process id was taken for the launcher'

    # 16. הפעלה שמתחילה רגע לפני ההתקנה נראית בבדיקה האחרונה, כשהמנעול כבר מוחזק.
    Reset-AgentCase
    $script:LaunchRunning = @($false, $false, $true)
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'Installed') 'A launch at the last moment blocked the update for good'
    Assert-Agent ($script:Polls -eq 2 -and $script:LaunchChecks -eq 6) "A launch at the last moment did not restart the wait ($script:Polls polls, $script:LaunchChecks checks)"

    # 17. ההתקנה האוטומטית כובתה בזמן ההמתנה: לא מתקינים, וההורדה נמחקת.
    Reset-AgentCase
    Set-DeviceRunning $true
    $script:OnPoll = { if ($script:Polls -eq 1) { Save-Preferences $true $false $null; Set-DeviceRunning $false } }
    Assert-Agent ((Invoke-UpdateAgent) -ceq 'InstallDisabled') 'Turning off automatic installation during the wait was ignored'
    Assert-Agent ($script:ProcessCalls -eq 0) 'The update was installed after automatic installation was turned off'
    Assert-Agent (-not [IO.Directory]::Exists($script:AgentDownloads)) 'The download stayed after automatic installation was turned off'

    # 18. זיהוי המכשיר: קובץ המצב עם זמן יצירה, וקובץ ready לבד, כמו במרכז הבקרה.
    Reset-AgentCase
    Assert-Agent (-not (Test-UpdateAgentDeviceRunning)) 'A device without files was taken as running'
    Set-DeviceRunning $true
    Assert-Agent (Test-UpdateAgentDeviceRunning) 'A running device was not seen'
    [IO.File]::WriteAllText((Get-DevicePath 'gesher-device'), "system_server=$PID`nsystem_server.start=1`nbinderd=0`n")
    Assert-Agent (-not (Test-UpdateAgentDeviceRunning)) 'A reused process id in the device state was taken as a running device'
    Set-DeviceRunning $false
    [IO.File]::WriteAllText((Get-DevicePath 'gesher-device.ready'), [string] $PID)
    Assert-Agent (Test-UpdateAgentDeviceRunning) 'A ready file with a live system server was not seen'
    # תהליך שכבר הסתיים: מספר שאף תהליך חי לא נושא.
    $exited = New-Object Diagnostics.ProcessStartInfo
    $exited.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $exited.Arguments = '-NoProfile -NonInteractive -Command exit'
    $exited.UseShellExecute = $false
    $exited.CreateNoWindow = $true
    $exited.RedirectStandardOutput = $true
    $exited.RedirectStandardError = $true
    $finished = [Diagnostics.Process]::Start($exited)
    $null = $finished.StandardOutput.ReadToEnd()
    $null = $finished.StandardError.ReadToEnd()
    $finished.WaitForExit()
    $deadId = $finished.Id
    $finished.Dispose()
    if (-not (Get-Process -Id $deadId -ErrorAction SilentlyContinue)) {
        [IO.File]::WriteAllText((Get-DevicePath 'gesher-device.ready'), [string] $deadId)
        Assert-Agent (-not (Test-UpdateAgentDeviceRunning)) 'A ready file left by a crashed device was taken as running'
    }

    # 19. הניקוי לא נוגע במה שלא שייך לסוכן: הורדות של מרכז הבקרה ותיקייה עם קבצים אחרים.
    Reset-AgentCase
    $panelDownload = Join-Path $script:AgentState ('downloads/gesher-update-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $panelDownload
    [IO.File]::WriteAllBytes((Join-Path $panelDownload 'gesher-setup-0.2.1.exe'), $script:Payload)
    $foreign = Join-Path $script:AgentDownloads ('gesher-update-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $foreign
    [IO.File]::WriteAllText((Join-Path $foreign 'notes.txt'), 'keep')
    Clear-UpdateAgentDownloads
    Assert-Agent ([IO.File]::Exists((Join-Path $panelDownload 'gesher-setup-0.2.1.exe'))) 'The agent removed a control panel download'
    Assert-Agent ([IO.File]::Exists((Join-Path $foreign 'notes.txt'))) 'The agent removed a file that is not its download'

    # 20. החיבור ב-gesher-app: מתי הסוכן מופעל.
    Reset-AgentCase
    $stubInstall = Join-Path $script:TestRoot 'stub install'
    $null = New-Item -ItemType Directory -Force -Path $stubInstall
    $marker = Join-Path $script:TestRoot 'agent-started.txt'
    $stub = "param([int] `$LauncherProcessId, [string] `$LauncherStart)`n[IO.File]::WriteAllText('" + $marker.Replace("'", "''") + "', ([string] `$LauncherProcessId + ' ' + `$LauncherStart + ' ' + [string] `$env:GESHER_LAUNCH_DETACH + '|' + [string] `$env:GESHER_LAUNCH_ERROR_FILE))`n"
    [IO.File]::WriteAllText((Join-Path $stubInstall 'gesher-update-agent.ps1'), $stub)
    $hostPath = if ($onWindows) { '' } else { [string] (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) }
    $savedDetach = $env:GESHER_LAUNCH_DETACH
    $savedAgent = $env:GESHER_UPDATE_AGENT
    function Test-GesherOutputUnread { return $true }
    try {
        $env:GESHER_UPDATE_AGENT = $null
        $env:GESHER_LAUNCH_DETACH = $null
        Assert-Agent (-not (Start-GesherUpdateAgentIfDue $script:AgentRoot $stubInstall $hostPath)) 'The agent started for a launch that is not from the Start menu'
        $savedError = $env:GESHER_LAUNCH_ERROR_FILE
        $env:GESHER_LAUNCH_ERROR_FILE = Join-Path $script:TestRoot 'launch-error.txt'
        $env:GESHER_LAUNCH_DETACH = '1'
        $env:GESHER_UPDATE_AGENT = '0'
        Assert-Agent (-not (Start-GesherUpdateAgentIfDue $script:AgentRoot $stubInstall $hostPath)) 'GESHER_UPDATE_AGENT=0 did not turn the agent off'
        $env:GESHER_UPDATE_AGENT = $null
        Save-Preferences $true $true $null
        Assert-Agent (-not (Start-GesherUpdateAgentIfDue $script:AgentRoot $stubInstall $hostPath)) 'The agent started although the settings changed today'
        Assert-Agent (-not (Start-GesherUpdateAgentIfDue $script:AgentRoot (Join-Path $script:TestRoot 'missing') $hostPath)) 'The agent started without its script'
        if ($onWindows -or $hostPath) {
            Set-SettingsAge 30
            Assert-Agent (Start-GesherUpdateAgentIfDue $script:AgentRoot $stubInstall $hostPath) 'The agent did not start after a day without a check'
            $deadline = [DateTime]::UtcNow.AddSeconds(60)
            while (-not [IO.File]::Exists($marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Assert-Agent ([IO.File]::Exists($marker)) 'The started agent did not run'
            $started = ([IO.File]::ReadAllText($marker)).Split(' ')
            Assert-Agent ($started[0] -ceq [string] $PID -and $started[1] -ceq $script:SelfStart) "The agent did not get its launcher: $started"
            Assert-Agent ($started[2] -ceq '|') "The agent inherited the launch environment: $($started[2])"
            [IO.File]::Delete($marker)
            Set-SettingsAge 1
            $null = New-Item -ItemType Directory -Force -Path $script:AgentDownloads
            Assert-Agent (Start-GesherUpdateAgentIfDue $script:AgentRoot $stubInstall $hostPath) 'The agent did not start for a waiting download'
            $deadline = [DateTime]::UtcNow.AddSeconds(60)
            while (-not [IO.File]::Exists($marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Assert-Agent ([IO.File]::Exists($marker)) 'The agent started for a waiting download did not run'
        }
    } finally {
        $env:GESHER_LAUNCH_DETACH = $savedDetach
        $env:GESHER_UPDATE_AGENT = $savedAgent
        $env:GESHER_LAUNCH_ERROR_FILE = $savedError
        Remove-Item Function:\Test-GesherOutputUnread
    }

    # 21. מנעול ההתקנה: gesher-app מחכה לו, ויודע אם הגרסה השתנתה בזמן ההמתנה.
    Reset-AgentCase
    $lockProfile = Join-Path $script:TestRoot ('lock profile ' + [guid]::NewGuid().ToString('N'))
    Assert-Agent (-not (Wait-GesherUpdateInstall $lockProfile $script:AgentInstall)) 'A launch waited without an installation'
    $lockName = Get-GesherUpdateLockName $lockProfile 'UpdateInstall'
    $holder = [PowerShell]::Create()
    try {
        $null = $holder.AddScript({
            param($Name, $Install, $Ready)
            $lock = New-Object Threading.Mutex($true, $Name)
            $null = $Ready.Set()
            Start-Sleep -Milliseconds 700
            [IO.File]::WriteAllText((Join-Path $Install 'gesher-version.ini'), "[Gesher]`r`nVersion=0.2.1`r`n")
            [IO.File]::SetLastWriteTimeUtc((Join-Path $Install 'gesher-version.ini'), [DateTime]::UtcNow.AddMinutes(1))
            $lock.ReleaseMutex()
            $lock.Dispose()
        }.ToString())
        $ready = New-Object Threading.ManualResetEvent($false)
        $null = $holder.AddArgument($lockName).AddArgument($script:AgentInstall).AddArgument($ready)
        $handle = $holder.BeginInvoke()
        Assert-Agent ($ready.WaitOne(15000)) 'The fixture installation did not take the lock'
        $waited = [Diagnostics.Stopwatch]::StartNew()
        Assert-Agent (Wait-GesherUpdateInstall $lockProfile $script:AgentInstall) 'A launch during an installation did not see the new version'
        Assert-Agent ($waited.ElapsedMilliseconds -ge 300) 'A launch did not wait for the installation to finish'
        $holder.EndInvoke($handle)
        $ready.Dispose()
    } finally { $holder.Dispose() }

    # 22. הקוד שבודק אילו הפעלות רצות (Windows בלבד): תהליך שמריץ gesher-app.ps1 מתיקיית ההתקנה.
    if ($onWindows) {
        Reset-AgentCase
        Assert-Agent (-not (& $realLaunchRunning)) 'A launch was seen where none runs'
        $appScript = Join-Path $script:AgentInstall 'gesher-app.ps1'
        $probeCommand = "Start-Sleep -Seconds 30 # " + $appScript
        $probeProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Command', ('"' + $probeCommand + '"')) -WindowStyle Hidden -PassThru
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            $seen = $false
            while (-not $seen -and [DateTime]::UtcNow -lt $deadline) { $seen = & $realLaunchRunning; if (-not $seen) { Start-Sleep -Milliseconds 200 } }
            Assert-Agent $seen 'A running gesher-app.ps1 of this installation was not seen'
        } finally { Stop-Process -Id $probeProcess.Id -Force -ErrorAction SilentlyContinue }
    }
} finally {
    if ($panel) { $panel.Dispose() }
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

"PASS: סוכן העדכונים שרץ ברקע ($script:Checks בדיקות)"
