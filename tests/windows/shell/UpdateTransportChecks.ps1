param([string] $UpdaterPath = (Join-Path $PSScriptRoot '../../../tools/package/gesher-update.ps1'))
$ErrorActionPreference = 'Stop'
. $UpdaterPath
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    'INFO: Initial Windows PowerShell TLS selection: {0}' -f [Net.ServicePointManager]::SecurityProtocol
}
Initialize-GesherUpdateTransport
# Exercise the compiled HTTP request/redirect code with in-memory responses.
# Windows also verifies real HTTPS negotiation from legacy Framework TLS defaults.
if (-not ('GesherUpdateTests.HttpFixture' -as [type])) {
    $compiler = @{ ErrorAction = 'Stop' }
    if ($PSVersionTable.PSEdition -eq 'Desktop') { $compiler.ReferencedAssemblies = @('System.Net.Http') }
    Add-Type @compiler -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
namespace GesherUpdateTests {
    public sealed class HttpFixture : HttpMessageHandler {
        public readonly Queue<HttpResponseMessage> Responses = new Queue<HttpResponseMessage>();
        public readonly List<string> Requests = new List<string>();
        public string Accept;
        public string ApiVersion;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            token.ThrowIfCancellationRequested();
            Requests.Add(request.RequestUri.AbsoluteUri);
            Accept = request.Headers.Accept.ToString();
            IEnumerable<string> values;
            if (request.Headers.TryGetValues("X-GitHub-Api-Version", out values))
                foreach (string value in values) ApiVersion = value;
            if (Responses.Count == 0) throw new InvalidOperationException("Unexpected extra HTTP request");
            return Task.FromResult(Responses.Dequeue());
        }
        protected override void Dispose(bool disposing) {
            if (disposing) while (Responses.Count > 0) Responses.Dequeue().Dispose();
            base.Dispose(disposing);
        }
    }
}
'@
}
$script:Checks = 0
function Assert-Transport([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:Checks++
}
function Assert-TransportThrows([scriptblock] $Action, [string] $Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Transport $threw $Message
}
$send = [Gesher.Updates.Transport].GetMethod('Send', [Reflection.BindingFlags]'NonPublic,Static')
if (-not $send) { throw 'Cannot inspect production transport request boundary' }
$latest = [uri]'https://api.github.com/repos/yosef220/APK/releases/latest'
$asset = [uri]'https://github.com/yosef220/APK/releases/download/v0.2.0/gesher-setup-0.2.0.exe'
function New-HttpFixture {
    $handler = New-Object GesherUpdateTests.HttpFixture
    [PSCustomObject]@{ Handler = $handler; Client = [Net.Http.HttpClient]::new($handler) }
}
function Add-HttpResponse($Fixture, [int] $Status = 200, [string] $Location = '') {
    # .NET Framework lacks named enum members for valid HTTP codes such as 429
    # and 308. Preserve those numeric responses without PowerShell's named-value cast.
    $code = [Enum]::ToObject([Net.HttpStatusCode], [int] $Status)
    $response = [Net.Http.HttpResponseMessage]::new($code)
    if ($Location) { $response.Headers.Location = [uri] $Location }
    $Fixture.Handler.Responses.Enqueue($response)
}
function Invoke-FixtureSend($Fixture, [uri] $Uri, [bool] $Metadata,
    [Threading.CancellationToken] $Token = [Threading.CancellationToken]::None) {
    $send.Invoke($null, [object[]] @($Fixture.Client, $Uri, $Metadata, $Token))
}
foreach ($status in 200, 404, 403, 429, 500) {
    $fixture = New-HttpFixture
    try {
        Add-HttpResponse $fixture $status
        $response = Invoke-FixtureSend $fixture $latest $true
        try {
            Assert-Transport ([int] $response.StatusCode -eq $status) 'Transport discarded the HTTP result'
            Assert-Transport ($fixture.Handler.Requests.Count -eq 1 -and $fixture.Handler.Requests[0] -ceq $latest.AbsoluteUri) 'Metadata used the wrong endpoint or retried unexpectedly'
            Assert-Transport ($fixture.Handler.Accept -ceq 'application/vnd.github+json' -and $fixture.Handler.ApiVersion -ceq '2022-11-28') 'Metadata omitted the GitHub API headers'
        } finally { $response.Dispose() }
    } finally { $fixture.Client.Dispose() }
}
foreach ($hostName in 'release-assets.githubusercontent.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com') {
    $fixture = New-HttpFixture
    try {
        $redirect = "https://$hostName/asset?download=fixture"
        Add-HttpResponse $fixture 302 $redirect
        Add-HttpResponse $fixture 200
        $response = Invoke-FixtureSend $fixture $asset $false
        try { Assert-Transport ($fixture.Handler.Requests.Count -eq 2 -and $fixture.Handler.Requests[1] -ceq $redirect) 'GitHub release asset redirect was not followed' }
        finally { $response.Dispose() }
    } finally { $fixture.Client.Dispose() }
}
foreach ($redirect in 'http://release-assets.githubusercontent.com/asset',
    'https://example.invalid/asset', 'https://github.com/another/repo/releases/download/v0.2.0/file.exe',
    'https://release-assets.githubusercontent.com:444/asset',
    'https://user@release-assets.githubusercontent.com/asset',
    'https://release-assets.githubusercontent.com/asset#fragment') {
    $fixture = New-HttpFixture
    try {
        Add-HttpResponse $fixture 302 $redirect
        Assert-TransportThrows { Invoke-FixtureSend $fixture $asset $false } 'Unapproved redirected download destination accepted'
        Assert-Transport ($fixture.Handler.Requests.Count -eq 1) 'Transport contacted the rejected redirect destination'
    } finally { $fixture.Client.Dispose() }
}
$fixture = New-HttpFixture
try {
    Add-HttpResponse $fixture 302 'https://api.github.com/repos/another/repo/releases/latest'
    Assert-TransportThrows { Invoke-FixtureSend $fixture $latest $true } 'Metadata redirect switched repositories'
    Assert-Transport ($fixture.Handler.Requests.Count -eq 1) 'Metadata contacted another repository after redirect'
} finally { $fixture.Client.Dispose() }
$fixture = New-HttpFixture
try {
    Add-HttpResponse $fixture 302
    Assert-TransportThrows { Invoke-FixtureSend $fixture $asset $false } 'Empty redirect Location was accepted'
    Assert-Transport ($fixture.Handler.Requests.Count -eq 1) 'Missing redirect target caused another request'
} finally { $fixture.Client.Dispose() }
$fixture = New-HttpFixture
try {
    for ($i = 0; $i -lt 8; $i++) { Add-HttpResponse $fixture 307 $asset.AbsoluteUri }
    Assert-TransportThrows { Invoke-FixtureSend $fixture $asset $false } 'Redirect loop was not bounded'
    Assert-Transport ($fixture.Handler.Requests.Count -eq 6) 'Redirect loop exceeded the six-request budget'
} finally { $fixture.Client.Dispose() }
$fixture = New-HttpFixture
$cts = [Threading.CancellationTokenSource]::new()
try {
    Add-HttpResponse $fixture 200
    $cts.Cancel()
    Assert-TransportThrows { Invoke-FixtureSend $fixture $latest $true $cts.Token } 'Pre-cancelled request was sent'
    Assert-Transport ($fixture.Handler.Requests.Count -eq 0) 'Cancellation did not reach HttpClient'
} finally { $cts.Dispose(); $fixture.Client.Dispose() }
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
        Initialize-GesherUpdateTransport
        Assert-Transport ([Net.ServicePointManager]::SecurityProtocol -eq [Net.SecurityProtocolType]::Tls12) 'Legacy Framework TLS selection cannot reach modern release endpoints'
        # Use the production client and request path, with normal Windows trust.
        # Any HTTP response proves HTTPS negotiation; 404 (no published release)
        # and rate-limit responses do not make this connectivity check flaky.
        $factory = [Gesher.Updates.Transport].GetMethod('CreateClient', [Reflection.BindingFlags]'NonPublic,Static')
        $client = $factory.Invoke($null, $null)
        $deadline = [Threading.CancellationTokenSource]::new()
        $response = $null
        try {
            $deadline.CancelAfter([TimeSpan]::FromSeconds(30))
            $response = $send.Invoke($null, [object[]] @($client, $latest, $true, $deadline.Token))
            Assert-Transport ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -le 599) 'Production updater did not receive a real GitHub HTTPS response'
            'INFO: Production updater received GitHub HTTPS status {0}' -f [int]$response.StatusCode
        } finally {
            if ($response) { $response.Dispose() }
            $deadline.Dispose()
            $client.Dispose()
        }
        $modern = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
        [Net.ServicePointManager]::SecurityProtocol = $modern
        Initialize-GesherUpdateTransport
        Assert-Transport ([Net.ServicePointManager]::SecurityProtocol -eq $modern) 'An explicit modern TLS selection was changed'
        [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 0)
        Initialize-GesherUpdateTransport
        Assert-Transport ([int][Net.ServicePointManager]::SecurityProtocol -eq 0) 'An existing OS-default TLS selection was changed'
    } finally { [Net.ServicePointManager]::SecurityProtocol = $originalProtocol }
}
"PASS: updater HTTP request and redirect contracts ($script:Checks checks)"
