Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Launcher = Join-Path $RepositoryRoot 'operations\imouto\Start-PalEventDirectorImouto.ps1'
$FixtureRoot = 'C:\PED-Imouto-Launcher-Test'
$InstallerFixtureRoot = 'C:\PED-Imouto-Installer-Test'

function New-LauncherFixture {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$ManifestBuildId,
        [AllowEmptyString()][string]$DeploymentBuildId,
        [string]$Root = $FixtureRoot
    )
    $serverRoot = Join-Path $Root "$Name\steamapps\common\PalServer"
    $steamAppsRoot = Split-Path (Split-Path $serverRoot -Parent) -Parent
    $deploymentRoot = Join-Path $serverRoot 'PalEventDirectorDeployments'
    $shippingRoot = Join-Path $serverRoot 'Pal\Binaries\Win64'
    $pakRoot = Join-Path $serverRoot 'Pal\Content\Paks'
    New-Item -ItemType Directory -Path $serverRoot, $deploymentRoot, $shippingRoot, $pakRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $serverRoot 'PalServer.exe'), 'fixture-root-launcher')
    [IO.File]::WriteAllText((Join-Path $shippingRoot 'PalServer-Win64-Shipping-Cmd.exe'), 'fixture-shipping')
    [IO.File]::WriteAllText((Join-Path $pakRoot 'Pal-WindowsServer.pak'), 'fixture-pak')
    $installedLauncher = Join-Path $deploymentRoot 'Start-PalEventDirectorImouto.ps1'
    Copy-Item -LiteralPath $Launcher -Destination $installedLauncher
    $buildLine = if ($ManifestBuildId) { "`t`"buildid`"`t`t`"$ManifestBuildId`"`r`n" } else { '' }
    [IO.File]::WriteAllText(
        (Join-Path $steamAppsRoot 'appmanifest_2394010.acf'),
        "`"AppState`"`r`n{`r`n`t`"appid`"`t`t`"2394010`"`r`n$buildLine}`r`n")
    [IO.File]::WriteAllText(
        (Join-Path $deploymentRoot 'deployment.json'),
        (@{
            packageName = 'PalEventDirector'
            schemaVersion = 1
            serverAppId = '2394010'
            serverBuildId = $DeploymentBuildId
            version = '0.1.0-alpha.3'
            sourceRevision = '1111111111111111111111111111111111111111'
            artifactSha256 = '2222222222222222222222222222222222222222222222222222222222222222'
            ue4ssTag = '2281fa31'
            dataDirectory = Join-Path $serverRoot 'Pal\Saved\PalEventDirector'
            launcherPath = $installedLauncher
            launcherSha256 = (Get-FileHash $installedLauncher -Algorithm SHA256).Hash
            rootServerExecutableSha256 = (Get-FileHash (Join-Path $serverRoot 'PalServer.exe') -Algorithm SHA256).Hash
            serverExecutableSha256 = (Get-FileHash (Join-Path $shippingRoot 'PalServer-Win64-Shipping-Cmd.exe') -Algorithm SHA256).Hash
            serverPakSha256 = (Get-FileHash (Join-Path $pakRoot 'Pal-WindowsServer.pak') -Algorithm SHA256).Hash
            launchIntegrationConfigured = $true
            launchEnvironmentSource = 'verified-steam-manifest'
        } | ConvertTo-Json))
    [pscustomobject]@{ ServerRoot = $serverRoot; Launcher = $installedLauncher }
}

try {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallerFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue

    $absent = New-LauncherFixture -Name 'absent' -ManifestBuildId '' -DeploymentBuildId '24575149'
    try {
        & $absent.Launcher -ServerRoot $absent.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Absent build ID unexpectedly passed launcher validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not contain a server build ID') { throw }
    }

    $mismatch = New-LauncherFixture -Name 'mismatch' -ManifestBuildId '24575149' -DeploymentBuildId '99999999'
    try {
        & $mismatch.Launcher -ServerRoot $mismatch.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Mismatched build ID unexpectedly passed launcher validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not match the verified Steam manifest') { throw }
    }

    $matching = New-LauncherFixture -Name 'matching' -ManifestBuildId '24575149' -DeploymentBuildId '24575149'
    $result = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -ValidateOnly
    if ($result.LaunchIntegrationReady -ne $true -or $result.ServerBuildId -ne '24575149' -or
        $result.DataDirectory -ne (Join-Path $matching.ServerRoot 'Pal\Saved\PalEventDirector') -or
        $result.EnvironmentScope -ne 'child-process-only') {
        throw 'Matching launcher validation returned the wrong launch contract.'
    }

    $installerMatching = New-LauncherFixture -Name 'matching' -ManifestBuildId '24575149' `
        -DeploymentBuildId '24575149' -Root $InstallerFixtureRoot
    $installerResult = & $installerMatching.Launcher -ServerRoot $installerMatching.ServerRoot `
        -SyntheticTestFixture -ValidateOnly
    if ($installerResult.LaunchIntegrationReady -ne $true) {
        throw 'Launcher rejected the confined installer integration fixture.'
    }

    $incomplete = New-LauncherFixture -Name 'incomplete' -ManifestBuildId '24575149' -DeploymentBuildId '24575149'
    $incompleteRecordPath = Join-Path $incomplete.ServerRoot 'PalEventDirectorDeployments\deployment.json'
    $incompleteRecord = Get-Content $incompleteRecordPath -Raw | ConvertFrom-Json
    $incompleteRecord.sourceRevision = 'invalid'
    [IO.File]::WriteAllText($incompleteRecordPath, ($incompleteRecord | ConvertTo-Json))
    try {
        & $incomplete.Launcher -ServerRoot $incomplete.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Incomplete package provenance unexpectedly passed launcher validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'deployment record is not for Pal Event Director') { throw }
    }

    $tampered = New-LauncherFixture -Name 'tampered' -ManifestBuildId '24575149' -DeploymentBuildId '24575149'
    [IO.File]::AppendAllText((Join-Path $tampered.ServerRoot 'PalServer.exe'), 'tampered')
    try {
        & $tampered.Launcher -ServerRoot $tampered.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Tampered root server launcher unexpectedly passed validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'server bytes no longer match') { throw }
    }

    $capturePath = Join-Path $FixtureRoot 'captured-environment.json'
    $childScript = Join-Path $FixtureRoot 'capture-environment.ps1'
    [IO.File]::WriteAllText($childScript, @"
`$record = @{
    buildId = `$env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
    dataDirectory = `$env:PAL_EVENT_DIRECTOR_DATA_DIR
}
[IO.File]::WriteAllText('$($capturePath.Replace("'", "''"))', (`$record | ConvertTo-Json))
"@)
    $previousBuildId = $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
    $previousDataDirectory = $env:PAL_EVENT_DIRECTOR_DATA_DIR
    try {
        $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = 'parent-build'
        $env:PAL_EVENT_DIRECTOR_DATA_DIR = 'parent-data'
        $started = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript
        if ($started.Started -ne $true -or -not (Test-Path $capturePath)) { throw 'Synthetic child did not run.' }
        $captured = Get-Content $capturePath -Raw | ConvertFrom-Json
        if ($captured.buildId -ne '24575149' -or
            $captured.dataDirectory -ne (Join-Path $matching.ServerRoot 'Pal\Saved\PalEventDirector')) {
            throw 'Required launch variables did not reach the child process.'
        }
        if ($env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID -ne 'parent-build' -or $env:PAL_EVENT_DIRECTOR_DATA_DIR -ne 'parent-data') {
            throw 'Launcher did not restore the parent process environment.'
        }
    } finally {
        $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $previousBuildId
        $env:PAL_EVENT_DIRECTOR_DATA_DIR = $previousDataDirectory
    }

    Write-Output 'PASS IMOUTO launcher rejects absent/mismatched IDs and passes verified variables only to the child process'
} finally {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallerFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
