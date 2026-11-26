# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
param(
    [Parameter(Mandatory = $true)][string] $InstallerPath,
    # on: לתיקיית המשתמש יש שם קצר (8.3). off: אין לה. any: לא משנים את ההגדרה (משתמש ASCII לביקורת).
    [Parameter(Mandatory = $true)][ValidateSet('on', 'off', 'any')][string] $ShortNames,
    [string] $UserName = 'ישראל ישראלי',
    [string[]] $Apps = @('com.ath0.rpn', 'com.nononsenseapps.notepad'),
    # אפליקציה מ-tests/e2e/apps.json שמותקנת מקובץ בשם עברי בתיקיית ההורדות. ריק: בלי הבדיקה הזאת.
    [string] $DownloadsApp = 'org.billthefarmer.currency',
    [string] $OutDir = 'install-env-results',
    [int] $TimeoutMinutes = 40
)

# גשר המיתרים: התקנה והפעלה אצל משתמש Windows עם שם עברי (issue #355, שלב 3.3 בתוכנית העבודה).
#
# רץ כמנהל המכונה של ה-CI. יוצר משתמש מקומי חדש, ומריץ בשמו את HebrewUserSession.ps1: התקנה
# רגילה של המתקין (לתיקייה של המשתמש, AppData\Local\Programs\Gesher) והפעלה של אפליקציות
# אמיתיות מ-F-Droid דרך tests/e2e/run-e2e.ps1. כך הנתיבים של ההתקנה, של הפרופיל, של התיקייה
# הזמנית ושל תפריט התחל הם בעברית, כמו אצל משתמש ביתי. זה חל גם על הקוד הנייטיב שקורא את
# התיקיות של Windows (SHGetKnownFolderPath) ולא את משתני הסביבה, ולכן לא מספיק לשנות את
# LOCALAPPDATA של המשתמש של ה-CI.
#
# -ShortNames on:  לתיקיית המשתמש יש שם קצר (8.3), כמו בדרך כלל בכונן המערכת של Windows 10 ו-11.
#                  גשר מעביר לריצה נתיבי ASCII דרך השם הקצר (#454).
# -ShortNames off: לתיקיית המשתמש אין שם קצר. הריצה מקבלת את הנתיבים בעברית, ב-UTF-8 (#328).
# -ShortNames any: לא משנים כלום. משמש למשתמש ביקורת עם שם ASCII, באותה מכונה ובאותה בדיקה.
#
# המשתמש החדש הוא מנהל, כמו המשתמש הראשון במחשב ביתי, והתהליך שלו רץ עם האסימון המסונן של UAC,
# כמו תוכנה שנפתחת מסייר הקבצים.
#
# לפני שמסיקים משהו על גשר, נבדקת הסביבה עצמה: שהמשתמש נוצר, שהתהליך רץ בשמו, שהנתיבים שלו
# בעברית, ושהשם הקצר קיים או חסר לפי מה שהתבקש. כשל בסביבה מדווח ככזה (קוד יציאה 2), ולא ככשל
# של גשר (קוד יציאה 1).

$ErrorActionPreference = 'Stop'
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$OutDir = [IO.Path]::GetFullPath($OutDir)
$null = [IO.Directory]::CreateDirectory($OutDir)
$summary = $env:GITHUB_STEP_SUMMARY

function Write-Line([string] $Line) {
    Write-Host $Line
    if ($summary) { Add-Content -LiteralPath $summary -Value $Line -Encoding utf8 }
}
function Stop-WithEnvironmentFailure([string] $Message) {
    Write-Line "FAIL  סביבת הבדיקה: $Message"
    Write-Host "::error::סביבת הבדיקה לא נוצרה כמו שצריך: $Message"
    exit 2
}
function Test-NonAscii([string] $Text) { return [bool]($Text -match '[^\x00-\x7F]') }

# --- 0. מנהל, ומה המכונה.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal] $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Stop-WithEnvironmentFailure "הסקריפט רץ בלי הרשאות מנהל ($($identity.Name)), ולכן לא יכול ליצור משתמש" }
if ($identity.IsSystem) { Stop-WithEnvironmentFailure 'הסקריפט רץ כ-SYSTEM. ‏CreateProcessWithLogonW לא זמין מחשבון השירות הזה' }
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { Stop-WithEnvironmentFailure "אין מתקין ב-$InstallerPath" }
$os = Get-CimInstance Win32_OperatingSystem
$acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
Write-Host "המכונה: $($os.Caption) $($os.Version), דף הקוד של המערכת (ACP): $acp, מריץ: $($identity.Name)"

# --- 1. השמות הקצרים בכונן המערכת. ההגדרה חלה רק על שמות שנוצרים אחריה, ולכן היא נקבעת
# לפני שהמשתמש ותיקיית הפרופיל שלו נוצרים. בסוף נבדקת התיקייה עצמה.
$systemDrive = $env:SystemDrive
Write-Host "השמות הקצרים ב-$systemDrive לפני הבדיקה: $((& fsutil 8dot3name query $systemDrive 2>&1 | Out-String).Trim())"
if ($ShortNames -ne 'any') {
    # 2: ההגדרה נקבעת לכל כונן לחוד, ואז ההגדרה של כונן המערכת קובעת.
    & fsutil 8dot3name set 2 | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WithEnvironmentFailure "fsutil 8dot3name set 2 נכשל ($LASTEXITCODE)" }
    $flag = if ($ShortNames -eq 'on') { '0' } else { '1' }
    & fsutil 8dot3name set $systemDrive $flag | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WithEnvironmentFailure "fsutil 8dot3name set $systemDrive $flag נכשל ($LASTEXITCODE)" }
    Write-Host "השמות הקצרים ב-$systemDrive אחרי ההגדרה: $((& fsutil 8dot3name query $systemDrive 2>&1 | Out-String).Trim())"
}

# --- 2. תיקיית עבודה משותפת בכונן המערכת: עותק של הסקריפטים, המתקין והתוצאות. המשתמש החדש
# לא יכול לקרוא את תיקיית ה-CI של המשתמש שמריץ, ולכן הכל מועתק לכאן.
$safeName = if (Test-NonAscii $UserName) { 'hebrew-' + $ShortNames } else { 'ascii' }
$work = Join-Path "$systemDrive\" "hameitarim-install-env\$safeName"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
foreach ($relative in 'tests\e2e', 'tests\windows\graphics', 'tests\install-env') {
    $null = [IO.Directory]::CreateDirectory((Join-Path $work $relative))
    Copy-Item -Path (Join-Path $repoRoot "$relative\*") -Destination (Join-Path $work $relative) -Recurse -Force
}
$installerCopy = Join-Path $work ('installer\' + [IO.Path]::GetFileName($InstallerPath))
$null = [IO.Directory]::CreateDirectory((Split-Path -Parent $installerCopy))
Copy-Item -LiteralPath $InstallerPath -Destination $installerCopy
$results = Join-Path $work 'results'
$null = [IO.Directory]::CreateDirectory($results)
# pwsh ו-python מגיעים מה-PATH של המכונה, אבל ב-CI חלק מהכלים נוספים רק לסביבה של המשתמש
# שמריץ. הרשימה עוברת בקובץ, והסשן מוסיף אותה לפני ה-PATH שלו, בלי לגעת בשאר הסביבה שלו.
$pathFile = Join-Path $work 'path.txt'
$tools = foreach ($command in 'pwsh', 'python') {
    $found = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Stop-WithEnvironmentFailure "$command לא נמצא במכונה" }
    Split-Path -Parent $found.Source
}
[IO.File]::WriteAllLines($pathFile, [string[]]@($tools | Select-Object -Unique), [Text.UTF8Encoding]::new($false))
$pwsh = (Get-Command pwsh).Source

# --- 3. המשתמש. סיסמה אקראית שלא נכתבת לשום לוג.
$bytes = [byte[]]::new(24)
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$password = 'Gh1!' + [Convert]::ToBase64String($bytes)
if ($env:GITHUB_ACTIONS) { Write-Host "::add-mask::$password" }
$existing = Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' | Where-Object { $_.Name -ceq $UserName }
if ($existing) { Stop-WithEnvironmentFailure "המשתמש '$UserName' כבר קיים במכונה" }
try {
    $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
    $newAccount = $computer.Create('User', $UserName)
    $newAccount.SetPassword($password)
    $newAccount.SetInfo()
} catch {
    Write-Host "יצירת המשתמש דרך ADSI נכשלה ($($_.Exception.Message)). ניסיון עם net user"
    & net user $UserName $password /add /y | Out-Null
}
$account = Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' | Where-Object { $_.Name -ceq $UserName }
if (-not $account) { Stop-WithEnvironmentFailure "המשתמש '$UserName' לא נמצא אחרי היצירה" }
$sid = $account.SID
# מנהל, כמו המשתמש הראשון במחשב ביתי. אם זה לא מצליח, הבדיקה ממשיכה כמשתמש רגיל, והסשן
# מדווח מה היה בפועל (whoami /groups).
$administrators = ([Security.Principal.SecurityIdentifier] 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
try {
    ([ADSI]"WinNT://$env:COMPUTERNAME/$administrators,group").Add("WinNT://$env:COMPUTERNAME/$UserName,user")
} catch {
    & net localgroup $administrators $UserName /add | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "::warning::הוספת '$UserName' לקבוצה $administrators נכשלה. הבדיקה ממשיכה כמשתמש רגיל" }
}
# המשתמש החדש כותב לתיקיית העבודה, וקורא את כל השאר.
$acl = Get-Acl -LiteralPath $work
$rule = [Security.AccessControl.FileSystemAccessRule]::new(
    [Security.Principal.SecurityIdentifier] $sid, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $work -AclObject $acl
Write-Host "נוצר המשתמש '$UserName' ($sid)"

# --- 4. הסשן של המשתמש. CreateProcessWithLogonW עם הפרופיל שלו (LOGON_WITH_PROFILE) ועם
# סביבה ריקה מצד הקורא (NULL): Windows בונה לתהליך את הסביבה מהפרופיל של המשתמש החדש. כך
# TEMP, ‏LOCALAPPDATA ו-USERPROFILE שלו הם שלו, ולא של המשתמש שמריץ את ה-CI (Start-Process
# -Credential מעביר את הסביבה של הקורא). כשאין שולחן עבודה מפורש, התהליך מקבל את התחנה ואת
# שולחן העבודה של הקורא, ו-Windows נותן למשתמש החדש גישה אליהם. החלונות של האפליקציות נוצרים שם.
if (-not ('Hameitarim.LogonProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Hameitarim {
    public static class LogonProcess {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct StartupInfo {
            public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
            public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public short wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct ProcessInformation { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateProcessWithLogonW(string user, string domain, string password, int logonFlags,
            string application, StringBuilder commandLine, int creationFlags, IntPtr environment,
            string currentDirectory, ref StartupInfo startupInfo, out ProcessInformation information);
        [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr handle, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr handle, uint code);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

        const int LogonWithProfile = 1;
        const int CreateUnicodeEnvironment = 0x400, CreateNoWindow = 0x08000000;

        // קוד היציאה של התהליך, או -1 כשנגמר הזמן (והתהליך נעצר).
        public static long Run(string user, string password, string application, string commandLine,
                               string directory, int timeoutMs) {
            var startup = new StartupInfo();
            startup.cb = Marshal.SizeOf(typeof(StartupInfo));
            ProcessInformation information;
            if (!CreateProcessWithLogonW(user, ".", password, LogonWithProfile, application,
                    new StringBuilder(commandLine), CreateUnicodeEnvironment | CreateNoWindow, IntPtr.Zero,
                    directory, ref startup, out information)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            try {
                if (WaitForSingleObject(information.hProcess, (uint) timeoutMs) != 0) {
                    TerminateProcess(information.hProcess, 1);
                    return -1;
                }
                uint code;
                if (!GetExitCodeProcess(information.hProcess, out code)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return code;
            } finally {
                CloseHandle(information.hThread);
                CloseHandle(information.hProcess);
            }
        }
    }
}
'@
}

$session = Join-Path $work 'tests\install-env\HebrewUserSession.ps1'
$quote = { param([string] $Value) '"' + $Value + '"' }
$commandLine = (& $quote $pwsh) + ' -NoProfile -ExecutionPolicy Bypass -File ' + (& $quote $session) +
    ' -InstallerPath ' + (& $quote $installerCopy) + ' -OutDir ' + (& $quote $results) +
    ' -Apps ' + (& $quote ($Apps -join ',')) + ' -ShortNames ' + $ShortNames + ' -PathFile ' + (& $quote $pathFile)
if ($DownloadsApp) { $commandLine += ' -DownloadsApp ' + (& $quote $DownloadsApp) }
Write-Host "מריץ בשם '$UserName': $commandLine"
$started = Get-Date
try {
    $code = [Hameitarim.LogonProcess]::Run($UserName, $password, $pwsh, $commandLine, $work, $TimeoutMinutes * 60000)
} catch {
    Stop-WithEnvironmentFailure "הפעלת תהליך בשם '$UserName' נכשלה: $($_.Exception.Message)"
}
$elapsed = [int]((Get-Date) - $started).TotalSeconds

# --- 5. סיום: תהליכים שנשארו (המכשיר של גשר רץ ברקע), ואיסוף התוצאות והלוגים.
$leftovers = @(Get-CimInstance Win32_Process | Where-Object {
    try { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop).Sid -eq $sid } catch { $false }
})
foreach ($process in $leftovers) {
    Write-Host "עוצר תהליך שנשאר של המשתמש: $($process.Name) ($($process.ProcessId))"
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}
$profilePath = (Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }).LocalPath
if ($profilePath) {
    $gesherLogs = Join-Path $profilePath 'AppData\Local\Gesher\logs'
    if (Test-Path -LiteralPath $gesherLogs) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $results 'gesher-logs'))
        Copy-Item -Path (Join-Path $gesherLogs '*') -Destination (Join-Path $results 'gesher-logs') -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Copy-Item -Path (Join-Path $results '*') -Destination $OutDir -Recurse -Force

$report = Join-Path $results 'report.json'
$data = if (Test-Path -LiteralPath $report) { Get-Content -Raw -LiteralPath $report -Encoding utf8 | ConvertFrom-Json } else { $null }
$transcript = Join-Path $results 'session.log'
if (Test-Path -LiteralPath $transcript) {
    Write-Host "----- הלוג של הסשן של '$UserName' -----"
    Get-Content -LiteralPath $transcript -Encoding utf8 | ForEach-Object { Write-Host $_ }
    Write-Host '----- סוף הלוג -----'
}
if ($code -eq -1) {
    Write-Line "FAIL  משתמש '$UserName': הבדיקה לא הסתיימה תוך $TimeoutMinutes דקות, והתהליך נעצר"
    exit 1
}
if ($null -eq $data) { Stop-WithEnvironmentFailure "הסשן של '$UserName' הסתיים (קוד $code) בלי לכתוב report.json" }
# לא סומכים על הסשן בשאלה מי הריץ אותו: הוא כותב את ה-SID שלו, וכאן משווים.
if ($null -ne $data.environment -and $data.environment.sid -ne $sid) {
    Stop-WithEnvironmentFailure "הסשן רץ בשם $($data.environment.sid), ולא בשם המשתמש שנוצר ($sid)"
}
Write-Line "### משתמש '$UserName' (שם קצר: $ShortNames)"
foreach ($line in @($data.lines)) { Write-Line $line }
Write-Host "הסשן של '$UserName' הסתיים בקוד $code אחרי $elapsed שניות"
switch ($code) {
    0 { }
    1 { Write-Host "::error::גשר נכשל אצל המשתמש '$UserName'. הפירוט בסיכום ובתוצאות" }
    2 { Write-Host "::error::הסביבה של המשתמש '$UserName' או הבדיקה עצמה נכשלו, ולכן אין כאן תוצאה על גשר" }
    default { Write-Host "::error::הסשן של '$UserName' הסתיים בקוד לא צפוי $code" }
}
exit $code
