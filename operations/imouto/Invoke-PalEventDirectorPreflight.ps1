[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Preview')]
param(
    [Parameter(ParameterSetName = 'Preview')][switch]$Preview,
    [Parameter(Mandatory, ParameterSetName = 'Step')]
    [ValidatePattern('^\d+-\d+-[a-z0-9-]+$')][string]$ExpectedStep,
    [Parameter(Mandatory, ParameterSetName = 'Result')][switch]$ReadResult,
    [Parameter(DontShow)][string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',
    [Parameter(DontShow)][switch]$SyntheticTestFixture
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$canonical = 'D:\SteamLibrary\steamapps\common\PalServer'
$ServerRoot = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
if ($SyntheticTestFixture) {
    if (-not $ServerRoot.StartsWith('C:\PED-Imouto-Preflight-Test\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SyntheticTestFixture is restricted to the disposable preflight command root.'
    }
} elseif ([Environment]::MachineName -ine 'IMOUTO' -or $ServerRoot -ine $canonical) {
    throw 'This diagnostic command must run locally on IMOUTO against its fixed dedicated-server root.'
}
$deployRoot = Join-Path $ServerRoot 'PalEventDirectorDeployments'
$record = Get-Content -LiteralPath (Join-Path $deployRoot 'deployment.json') -Raw | ConvertFrom-Json
$installed = Join-Path $deployRoot 'Invoke-PalEventDirectorPreflight.ps1'
if ($record.deliveryProfile -notin @('preflight-diagnostic-only', 'laboratory-native-test') -or $record.serverBuildId -ne '24575149' -or
    [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path) -ine $installed -or
    (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ine $record.preflightCommandSha256) {
    throw 'Installed diagnostic command does not match the quarantined deployment provenance.'
}
$directory = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector\preflight-commands'
if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'Start the diagnostic build through its verified launcher before submitting a request.' }
$current = $directory
while ($current) {
    if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing diagnostic ingress through a reparse point.'
    }
    $parent = Split-Path $current -Parent
    if ($parent -eq $current) { break }
    $current = $parent
}
$requestPath = Join-Path $directory 'request.json'
$claimedPath = Join-Path $directory 'in-flight.json'
$responsePath = Join-Path $directory 'response.json'
if ($ReadResult) {
    if (Test-Path -LiteralPath $claimedPath) { Write-Output 'Diagnostic is in flight or was interrupted. Do not retry; inspect breadcrumbs/server health.'; return }
    if (Test-Path -LiteralPath $requestPath) { Write-Output 'Request is queued; no response yet.'; return }
    if (-not (Test-Path -LiteralPath $responsePath)) { Write-Output 'No diagnostic response is available.'; return }
    $response = Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json
    [pscustomobject]@{ RequestId = $response.id; Success = $response.success; Message = $response.message }
    return
}
if ((Test-Path -LiteralPath $requestPath) -or (Test-Path -LiteralPath $claimedPath)) {
    throw 'A diagnostic request is already queued or in flight; do not submit another.'
}
if (-not $SyntheticTestFixture) {
    $server = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($ServerRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
        $_.Name -eq 'PalServer-Win64-Shipping-Cmd.exe'
    })
    if ($server.Count -ne 1) { throw 'Exactly one IMOUTO Shipping server must be running before queuing diagnostics.' }
}
if ($ExpectedStep -and -not $PSCmdlet.ShouldProcess($ExpectedStep, 'execute ONE read-only diagnostic operation; native crash remains possible')) { return }
$payload = [ordered]@{ schemaVersion = 1; id = [Guid]::NewGuid().ToString(); preview = -not [bool]$ExpectedStep }
if ($ExpectedStep) { $payload.confirmation = 'confirm-disposable-readonly'; $payload.expectedStep = $ExpectedStep }
$temporary = Join-Path $directory ('request-' + $payload.id + '.tmp')
try {
    [IO.File]::WriteAllText($temporary, (($payload | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $requestPath -ErrorAction Stop
} finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
}
[pscustomobject]@{ Status = 'Queued'; RequestId = $payload.id; PreviewOnly = $payload.preview; NextAction = 'Use -ReadResult after the server processes this request; do not queue another step until its after-marker is checked.' }