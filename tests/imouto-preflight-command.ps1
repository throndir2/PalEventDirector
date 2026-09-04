Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root = 'C:\PED-Imouto-Preflight-Test'
$serverRoot = Join-Path $root 'PalServer'
$deployRoot = Join-Path $serverRoot 'PalEventDirectorDeployments'
$directory = Join-Path $serverRoot 'Pal\Saved\PalEventDirector\preflight-commands'
$command = Join-Path $deployRoot 'Invoke-PalEventDirectorPreflight.ps1'
try {
    New-Item -ItemType Directory -Path $deployRoot, $directory -Force | Out-Null
    Copy-Item (Join-Path $repository 'operations\imouto\Invoke-PalEventDirectorPreflight.ps1') $command
    [IO.File]::WriteAllText((Join-Path $deployRoot 'deployment.json'), (@{
        deliveryProfile = 'preflight-diagnostic-only'; serverBuildId = '24575149'; preflightCommandSha256 = (Get-FileHash $command -Algorithm SHA256).Hash
    } | ConvertTo-Json))
    $queued = & $command -ServerRoot $serverRoot -SyntheticTestFixture -Preview
    if ($queued.Status -ne 'Queued' -or $queued.PreviewOnly -ne $true) { throw 'Preview did not queue the expected request.' }
    $requestPath = Join-Path $directory 'request.json'
    $request = Get-Content $requestPath -Raw | ConvertFrom-Json
    if ($request.preview -ne $true -or $request.id -ne $queued.RequestId) { throw 'Preview request identity mismatch.' }
    try {
        & $command -ServerRoot $serverRoot -SyntheticTestFixture -Preview | Out-Null
        throw 'Duplicate pending request accepted.'
    } catch { if ($_.Exception.Message -notmatch 'already queued') { throw } }
    Remove-Item $requestPath
    $step = '100-0001-ue4ss-version'
    $queued = & $command -ServerRoot $serverRoot -SyntheticTestFixture -ExpectedStep $step -Confirm:$false
    $request = Get-Content $requestPath -Raw | ConvertFrom-Json
    if ($request.preview -ne $false -or $request.confirmation -ne 'confirm-disposable-readonly' -or $request.expectedStep -ne $step) { throw 'Step request is invalid.' }
    Remove-Item $requestPath
    [IO.File]::WriteAllText((Join-Path $directory 'response.json'), (@{ id = $queued.RequestId; success = $true; message = 'Next: fixture' } | ConvertTo-Json))
    $result = & $command -ServerRoot $serverRoot -SyntheticTestFixture -ReadResult
    if ($result.RequestId -ne $queued.RequestId -or $result.Success -ne $true) { throw 'Local response did not match the request.' }
    Write-Output 'PASS IMOUTO local-only preflight command queues preview/explicit steps, rejects duplicates, and reads matched responses'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}