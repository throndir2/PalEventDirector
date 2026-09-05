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
    $runtimeRoot = Join-Path $shippingRoot 'ue4ss'
    $modsRoot = Join-Path $runtimeRoot 'Mods'
    $pakRoot = Join-Path $serverRoot 'Pal\Content\Paks'
    New-Item -ItemType Directory -Path $serverRoot, $deploymentRoot, $shippingRoot, $runtimeRoot, $modsRoot, $pakRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $serverRoot 'PalServer.exe'), 'fixture-root-launcher')
    [IO.File]::WriteAllText((Join-Path $shippingRoot 'PalServer-Win64-Shipping-Cmd.exe'), 'fixture-shipping')
    [IO.File]::WriteAllText((Join-Path $pakRoot 'Pal-WindowsServer.pak'), 'fixture-pak')
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'UE4SS.dll'), 'fixture-pinned-runtime')
    [IO.File]::WriteAllText((Join-Path $shippingRoot 'dwmapi.dll'), 'fixture-proxy')
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'MemberVariableLayout.ini'), 'fixture-layout')
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'UE4SS-settings.ini'), 'fixture-settings')
    [IO.File]::WriteAllText((Join-Path $modsRoot 'mods.json'), '[{"mod_name":"PalEventDirector","mod_enabled":true}]')
    [IO.File]::WriteAllText((Join-Path $modsRoot 'mods.txt'), 'PalEventDirector : 1')
    [IO.File]::WriteAllText((Join-Path $deploymentRoot 'Enable-PalEventDirectorLaboratory.ps1'), '# fixture activation')
    [IO.File]::WriteAllText((Join-Path $deploymentRoot 'Invoke-PalEventDirectorPreflight.ps1'), '# fixture ingress')
    $installedLauncher = Join-Path $deploymentRoot 'Start-PalEventDirectorImouto.ps1'
    Copy-Item -LiteralPath $Launcher -Destination $installedLauncher
    $startupPaths = @((Join-Path $shippingRoot 'dwmapi.dll')) + @(Get-ChildItem $runtimeRoot -File -Recurse | Select-Object -ExpandProperty FullName) + @(Get-ChildItem $deploymentRoot -Filter '*.ps1' -File | Select-Object -ExpandProperty FullName)
    $startupFiles = @($startupPaths | ForEach-Object { @{ path = $_.Substring($serverRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash $_ -Algorithm SHA256).Hash } })
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
            deliveryProfile = 'preflight-diagnostic-only'
            startupFiles = $startupFiles
            sourceRevision = '1111111111111111111111111111111111111111'
            artifactSha256 = '2222222222222222222222222222222222222222222222222222222222222222'
            ue4ssTag = '2281fa31'
            ue4ssApiVersion = '3.0.1'
            ue4ssDllSha256 = (Get-FileHash (Join-Path $runtimeRoot 'UE4SS.dll') -Algorithm SHA256).Hash
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
    $profileRecordPath = Join-Path $matching.ServerRoot 'PalEventDirectorDeployments\deployment.json'
    $profileRecord = Get-Content $profileRecordPath -Raw | ConvertFrom-Json
    $profileRecord.deliveryProfile = 'laboratory-native-test'
    [IO.File]::WriteAllText($profileRecordPath, ($profileRecord | ConvertTo-Json -Depth 8))
    $profileResult = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -ValidateOnly
    if ($profileResult.DeliveryProfile -ne 'laboratory-native-test' -or $profileResult.NativePreflightRequired -ne $false -or
        $profileResult.NativeStartsQuarantined -ne $false) {
        throw 'Laboratory launch unexpectedly required manual preflight.'
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

    $runtimeTampered = New-LauncherFixture -Name 'runtime-tampered' -ManifestBuildId '24575149' -DeploymentBuildId '24575149'
    [IO.File]::AppendAllText((Join-Path $runtimeTampered.ServerRoot 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'), 'tampered')
    try {
        & $runtimeTampered.Launcher -ServerRoot $runtimeTampered.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Tampered diagnostic runtime unexpectedly passed validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'UE4SS runtime bytes/API') { throw }
    }

    $layoutTampered = New-LauncherFixture -Name 'layout-tampered' -ManifestBuildId '24575149' -DeploymentBuildId '24575149'
    [IO.File]::AppendAllText((Join-Path $layoutTampered.ServerRoot 'Pal\Binaries\Win64\ue4ss\MemberVariableLayout.ini'), 'tampered')
    try {
        & $layoutTampered.Launcher -ServerRoot $layoutTampered.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Tampered reflection layout unexpectedly passed validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'startup bytes no longer match') { throw }
    }

    $capturePath = Join-Path $FixtureRoot 'captured-environment.json'
    $childScript = Join-Path $FixtureRoot 'capture-environment.ps1'
    [IO.File]::WriteAllText($childScript, @"
`$record = @{
    buildId = `$env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
    dataDirectory = `$env:PAL_EVENT_DIRECTOR_DATA_DIR
    runtimeTag = `$env:PAL_EVENT_DIRECTOR_UE4SS_TAG
    runtimeApi = `$env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION
}
[IO.File]::WriteAllText('$($capturePath.Replace("'", "''"))', (`$record | ConvertTo-Json))
"@)
    $previousBuildId = $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
    $previousDataDirectory = $env:PAL_EVENT_DIRECTOR_DATA_DIR
    $previousRuntimeTag = $env:PAL_EVENT_DIRECTOR_UE4SS_TAG
    $previousRuntimeApi = $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION
    try {
        $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = 'parent-build'
        $env:PAL_EVENT_DIRECTOR_DATA_DIR = 'parent-data'
        $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = 'parent-tag'
        $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = 'parent-api'
        $started = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript
        if ($started.Started -ne $true -or -not (Test-Path $capturePath)) { throw 'Synthetic child did not run.' }
        $captured = Get-Content $capturePath -Raw | ConvertFrom-Json
        if ($captured.buildId -ne '24575149' -or
            $captured.runtimeTag -ne '2281fa31' -or $captured.runtimeApi -ne '3.0.1' -or
            $captured.dataDirectory -ne (Join-Path $matching.ServerRoot 'Pal\Saved\PalEventDirector')) {
            throw 'Required launch variables did not reach the child process.'
        }
        if ($env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID -ne 'parent-build' -or $env:PAL_EVENT_DIRECTOR_DATA_DIR -ne 'parent-data') {
            throw 'Launcher did not restore the parent process environment.'
        }
        if ($env:PAL_EVENT_DIRECTOR_UE4SS_TAG -ne 'parent-tag' -or $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION -ne 'parent-api') {
            throw 'Launcher leaked diagnostic runtime attestation into its parent.'
        }
    } finally {
        $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $previousBuildId
        $env:PAL_EVENT_DIRECTOR_DATA_DIR = $previousDataDirectory
        $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = $previousRuntimeTag
        $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = $previousRuntimeApi
    }

    Write-Output 'PASS IMOUTO launcher rejects absent/mismatched IDs and passes verified variables only to the child process'
} finally {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallerFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
