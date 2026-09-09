[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$GamePort = 8213,

    [ValidateRange(1, 65535)]
    [int]$QueryPort = 27016,

    [switch]$ValidateOnly,

    [ValidateSet('None', 'SpawnCleanup', 'Movement', 'TwoBaseMovement', 'Prewarm', 'Engagement', 'ClassCatalog', 'SurfaceSurvey', 'ShapeQualification', 'QualifiedEngagement', 'CadencedEngagement')]
    [string]$StartupTest = 'None',

    [ValidateRange(0,64)]
    [int]$StartupTestBaseIndex = 0,

    [Parameter(DontShow)]
    [string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',

    [Parameter(DontShow)]
    [switch]$SyntheticTestFixture,

    [Parameter(DontShow)]
    [string]$SyntheticChildScript = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($StartupTestBaseIndex -gt 0 -and $StartupTest -in @('None','ClassCatalog')) {
    throw 'An explicit base index requires a world-based startup scenario.'
}

$CanonicalServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer'
$ExpectedAppId = '2394010'
$ExpectedRuntimeTag = '2281fa31'
$ExpectedRuntimeApi = '3.0.1'
$ExpectedRuntimeHash = '21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8'

$ServerRoot = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
$SyntheticRoots = @(
    [IO.Path]::GetFullPath('C:\PED-Imouto-Launcher-Test').TrimEnd('\'),
    [IO.Path]::GetFullPath('C:\PED-Imouto-Installer-Test').TrimEnd('\')
)
$SyntheticRoot = $SyntheticRoots | Where-Object {
    $ServerRoot.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1
if ($SyntheticTestFixture -and [string]::IsNullOrWhiteSpace([string]$SyntheticRoot)) {
    throw 'SyntheticTestFixture is restricted to a canonical descendant of a disposable PED test root.'
}
if ($SyntheticChildScript) {
    if (-not $SyntheticTestFixture) { throw 'SyntheticChildScript is available only in a disposable synthetic fixture.' }
    $SyntheticChildScript = [IO.Path]::GetFullPath($SyntheticChildScript)
    if (-not $SyntheticChildScript.StartsWith($SyntheticRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $SyntheticChildScript -PathType Leaf)) {
        throw 'SyntheticChildScript must be an existing canonical descendant of the selected disposable PED test root.'
    }
}
if ([Environment]::MachineName -ine 'IMOUTO' -and -not $SyntheticTestFixture) {
    throw 'This launcher must run locally on IMOUTO.'
}
if (-not $SyntheticTestFixture -and $ServerRoot -ine $CanonicalServerRoot) {
    throw "The launch target is fixed to $CanonicalServerRoot."
}
if ($ServerRoot.StartsWith('\\') -or $ServerRoot.StartsWith('\\?\') -or $ServerRoot.StartsWith('\\.\')) {
    throw 'ServerRoot must be a local fixed-drive path.'
}
if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($ServerRoot)).DriveType -ne [IO.DriveType]::Fixed) {
    throw 'ServerRoot must be on a local fixed drive.'
}
if ($GamePort -eq $QueryPort) {
    throw 'GamePort and QueryPort must be different.'
}

$SteamAppsRoot = Split-Path (Split-Path $ServerRoot -Parent) -Parent
$SteamManifestPath = Join-Path $SteamAppsRoot 'appmanifest_2394010.acf'
$DeploymentPath = Join-Path $ServerRoot 'PalEventDirectorDeployments\deployment.json'
$ServerExecutable = Join-Path $ServerRoot 'PalServer.exe'
$ShippingExecutable = Join-Path $ServerRoot 'Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe'
$ServerPak = Join-Path $ServerRoot 'Pal\Content\Paks\Pal-WindowsServer.pak'
$RuntimeDll = Join-Path $ServerRoot 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
$DataDirectory = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector'

$LifecycleMutex = [Threading.Mutex]::new($false, 'Global\PalEventDirectorImoutoLifecycle')
$HasLifecycleMutex = $false
try {
    $HasLifecycleMutex = $LifecycleMutex.WaitOne(0)
    if (-not $HasLifecycleMutex) { throw 'Another IMOUTO install, activation, launch, or world import is running.' }

foreach ($required in @($SteamManifestPath, $DeploymentPath, $ServerExecutable, $ShippingExecutable, $ServerPak, $RuntimeDll)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required launch file is missing: $required"
    }
}

$manifestText = [IO.File]::ReadAllText($SteamManifestPath)
$appMatch = [regex]::Match($manifestText, '"appid"\s+"(?<Value>\d+)"')
$buildMatch = [regex]::Match($manifestText, '"buildid"\s+"(?<Value>\d+)"')
if (-not $appMatch.Success -or $appMatch.Groups['Value'].Value -ne $ExpectedAppId) {
    throw 'Target is not Palworld Dedicated Server App ID 2394010.'
}
if (-not $buildMatch.Success -or [string]::IsNullOrWhiteSpace($buildMatch.Groups['Value'].Value)) {
    throw 'The verified Steam manifest does not contain a server build ID.'
}
$VerifiedBuildId = $buildMatch.Groups['Value'].Value
$deployment = Get-Content -LiteralPath $DeploymentPath -Raw | ConvertFrom-Json
if ($deployment.schemaVersion -ne 1 -or [string]$deployment.packageName -ne 'PalEventDirector' -or
    [string]$deployment.deliveryProfile -notin @('preflight-diagnostic-only', 'laboratory-native-test') -or
    [string]$deployment.serverAppId -ne $ExpectedAppId -or $deployment.launchIntegrationConfigured -ne $true -or
    [string]$deployment.launchEnvironmentSource -ne 'verified-steam-manifest' -or
    [string]$deployment.version -ne '0.1.0-alpha.3' -or [string]$deployment.ue4ssTag -ne '2281fa31' -or
    [string]$deployment.sourceRevision -notmatch '^[A-Fa-f0-9]{40}$' -or
    [string]$deployment.artifactSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'The deployment record is not for Pal Event Director on the dedicated server.'
}
if ($SyntheticTestFixture) { $ExpectedRuntimeHash = [string]$deployment.ue4ssDllSha256 }
if ([string]$deployment.ue4ssApiVersion -ne $ExpectedRuntimeApi -or
    [string]$deployment.ue4ssTag -ne $ExpectedRuntimeTag -or
    $ExpectedRuntimeHash -notmatch '^[A-Fa-f0-9]{64}$' -or
    [string]$deployment.ue4ssDllSha256 -ine $ExpectedRuntimeHash -or
    (Get-FileHash $RuntimeDll -Algorithm SHA256).Hash -ine $ExpectedRuntimeHash) {
    throw 'UE4SS runtime bytes/API do not match the pinned diagnostic deployment.'
}
if ([string]::IsNullOrWhiteSpace([string]$deployment.serverBuildId)) {
    throw 'The deployment record has no verified server build ID.'
}
if ([string]$deployment.serverBuildId -ne $VerifiedBuildId) {
    throw "The deployment build ID $($deployment.serverBuildId) does not match the verified Steam manifest build ID $VerifiedBuildId. Redeploy before starting."
}
foreach ($requiredValue in @(
    $deployment.dataDirectory,
    $deployment.launcherPath,
    $deployment.launcherSha256,
    $deployment.rootServerExecutableSha256,
    $deployment.serverExecutableSha256,
    $deployment.serverPakSha256
)) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValue)) {
        throw 'The deployment record does not contain complete launch integration. Redeploy before starting.'
    }
}
$ExpectedDataDirectory = [IO.Path]::GetFullPath((Join-Path $ServerRoot 'Pal\Saved\PalEventDirector')).TrimEnd('\')
$ExpectedLauncherPath = [IO.Path]::GetFullPath((Join-Path $ServerRoot 'PalEventDirectorDeployments\Start-PalEventDirectorImouto.ps1')).TrimEnd('\')
$CurrentLauncherPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path).TrimEnd('\')
if ([IO.Path]::GetFullPath([string]$deployment.dataDirectory).TrimEnd('\') -ine $ExpectedDataDirectory -or
    [IO.Path]::GetFullPath([string]$deployment.launcherPath).TrimEnd('\') -ine $ExpectedLauncherPath -or
    $CurrentLauncherPath -ine $ExpectedLauncherPath -or [string]$deployment.launcherSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
    (Get-FileHash $CurrentLauncherPath -Algorithm SHA256).Hash -ine [string]$deployment.launcherSha256) {
    throw 'The installed launcher or data-directory provenance does not match the deployment record.'
}
if ((Get-FileHash $ServerExecutable -Algorithm SHA256).Hash -ine [string]$deployment.rootServerExecutableSha256 -or
    (Get-FileHash $ShippingExecutable -Algorithm SHA256).Hash -ine [string]$deployment.serverExecutableSha256 -or
    (Get-FileHash $ServerPak -Algorithm SHA256).Hash -ine [string]$deployment.serverPakSha256) {
    throw 'Dedicated-server bytes no longer match the verified deployment record. Redeploy before starting.'
}
$DataDirectory = $ExpectedDataDirectory

$expectedFiles = @{}
if ($null -eq $deployment.PSObject.Properties['startupFiles'] -or @($deployment.startupFiles).Count -lt 8) {
    throw 'Diagnostic deployment is missing its complete startup-file attestation.'
}
foreach ($entry in $deployment.startupFiles) {
    $relative = [string]$entry.path
    if ($relative -notmatch '^(Pal/Binaries/Win64/|PalEventDirectorDeployments/)[A-Za-z0-9_./ -]+$' -or
        $relative.Split('/') -contains '..' -or $expectedFiles.ContainsKey($relative)) {
        throw 'Diagnostic startup-file inventory contains an unsafe or duplicate path.'
    }
    $file = Join-Path $ServerRoot $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        (Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine [string]$entry.sha256) {
        throw 'Installed diagnostic startup bytes no longer match deployment provenance.'
    }
    $expectedFiles[$relative] = $true
}
$ue4ssRoot = Join-Path $ServerRoot 'Pal\Binaries\Win64\ue4ss'
$currentPaths = @(
    'Pal/Binaries/Win64/dwmapi.dll',
    'PalEventDirectorDeployments/Start-PalEventDirectorImouto.ps1',
    'PalEventDirectorDeployments/Enable-PalEventDirectorLaboratory.ps1',
    'PalEventDirectorDeployments/Invoke-PalEventDirectorPreflight.ps1'
) + @(Get-ChildItem -LiteralPath $ue4ssRoot -File -Recurse | Where-Object { $_.Extension -notin @('.log', '.pdb') } | ForEach-Object { $_.FullName.Substring($ServerRoot.Length + 1).Replace('\', '/') })
if ($currentPaths.Count -ne $expectedFiles.Count -or @($currentPaths | Where-Object { -not $expectedFiles.ContainsKey($_) }).Count) {
    throw 'Diagnostic startup-file inventory changed; redeploy before launch.'
}
$modsRoot = Join-Path $ue4ssRoot 'Mods'
$enabledMods = @(Get-Content (Join-Path $modsRoot 'mods.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.mod_enabled -eq $true })
if ($enabledMods.Count -ne 1 -or $enabledMods[0].mod_name -ne 'PalEventDirector') {
    throw 'Diagnostic launch requires exactly PalEventDirector enabled.'
}
$extraMarkers = @(Get-ChildItem -LiteralPath $modsRoot -Filter 'enabled.txt' -File -Recurse | Where-Object {
    -not $_.FullName.StartsWith((Join-Path $modsRoot 'PalEventDirector') + '\', [StringComparison]::OrdinalIgnoreCase)
})
if ($extraMarkers.Count) { throw 'Another UE4SS mod has an enabled.txt marker; diagnostic launch refused.' }

$existing = @(Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($ServerRoot + '\', [StringComparison]::OrdinalIgnoreCase)
})
if ($existing.Count -gt 0) {
    throw "The IMOUTO dedicated server is already running (PID(s): $($existing.ProcessId -join ', '))."
}

$launch = [ordered]@{
    LaunchIntegrationReady = $true
    ServerRoot = $ServerRoot
    ServerBuildId = $VerifiedBuildId
    DataDirectory = $DataDirectory
    GamePort = $GamePort
    QueryPort = $QueryPort
    EnvironmentScope = 'child-process-only'
    DeliveryProfile = [string]$deployment.deliveryProfile
    NativeStartsQuarantined = ($deployment.deliveryProfile -ne 'laboratory-native-test')
    NativePreflightRequired = $false
    Ue4ssTag = $ExpectedRuntimeTag
    Ue4ssApiVersion = $ExpectedRuntimeApi
    StartupTest = $StartupTest
    StartupTestBaseIndex = $StartupTestBaseIndex
}
$testRoot = Join-Path $DataDirectory 'startup-tests'
$activeTestPath = Join-Path $testRoot 'active.json'
function Assert-StartupTestPath {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    if (-not $current.StartsWith($ServerRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Startup test state must remain inside the dedicated server.'
    }
    while ($current.Length -ge $ServerRoot.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Startup test state may not use a reparse point.'
            }
        }
        if ($current -ieq $ServerRoot) { break }
        $current = Split-Path $current -Parent
    }
}
Assert-StartupTestPath $activeTestPath
function Get-StartupTestChecksum {
    param([string]$Text)
    [long]$hash = 5381
    foreach ($value in [Text.Encoding]::UTF8.GetBytes($Text)) { $hash = ($hash * 33 + $value) % 2147483647 }
    $hash.ToString('x8')
}
function Read-StartupTestOutcome {
    param([string]$RunId)
    $journal = Join-Path (Join-Path $testRoot $RunId) 'journal.ndjson'
    Assert-StartupTestPath $journal
    if (-not (Test-Path -LiteralPath $journal -PathType Leaf)) { throw 'A previous startup test has no durable outcome; investigate before rearming.' }
    $chain = '00000000'; $sequence = 0; $state = $null
    foreach ($line in Get-Content -LiteralPath $journal) {
        if ($line -eq '') { continue }
        $match = [regex]::Match($line, '^\{"checksum":"(?<hash>[0-9a-f]{8})",(?<rest>.*)\}$')
        if (-not $match.Success) { throw 'Startup test journal encoding is invalid.' }
        $raw = '{' + $match.Groups['rest'].Value + '}'
        if ((Get-StartupTestChecksum ($chain + $raw)) -cne $match.Groups['hash'].Value) { throw 'Startup test journal checksum mismatch.' }
        $record = $line | ConvertFrom-Json
        if ($record.schemaVersion -ne 1 -or $record.sequence -ne ($sequence + 1) -or $record.previousChecksum -cne $chain) {
            throw 'Startup test journal chain mismatch.'
        }
        $chain = $record.checksum; $sequence = $record.sequence; $state = $record.state
    }
    if ($null -eq $state -or $state.schemaVersion -ne 1 -or $state.runId -cne $RunId -or
        $state.status -notin @('running','passed','blocked','failed') -or
        $state.mutationStarted -isnot [bool] -or $state.cleanupComplete -isnot [bool] -or
        [string]$state.artifactSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Startup test outcome schema is invalid.' }
    if ($state.case -in @('shape-qualification','qualified-engagement','cadenced-engagement')) {
        $expectedContract = if ($state.case -eq 'cadenced-engagement') { 'hunter-level30-network-sphere-cadence-v1' } elseif ($state.case -eq 'qualified-engagement') { 'hunter-level30-qualified-engagement-v1' } else { 'hunter-level30-one-instance-v1' }
        if ($null -eq $state.PSObject.Properties['experiment'] -or $state.experiment -cne $expectedContract -or
            $state.moved -ne 0 -or $state.spawned -gt 1) { throw 'Startup shape experiment outcome is invalid.' }
        if ($state.status -eq 'passed') {
            if ($state.spawned -ne 1 -or $state.initialized -ne 1 -or $state.cleaned -ne 1 -or
                $state.helpersCreated -ne 1 -or $state.helpersCleaned -ne 1 -or
                $null -eq $state.PSObject.Properties['shapeObservations']) { throw 'Startup shape evidence is incomplete.' }
            $shapeObservations = @($state.shapeObservations | ForEach-Object { $_ })
            if ($shapeObservations.Count -ne 2) { throw 'Startup shape evidence is incomplete.' }
            foreach ($observation in $shapeObservations) {
                if ($observation.comparison -cne 'MATCH' -or $observation.instanceOnly -ne $true -or
                    $observation.spawnQualified -ne $false) { throw 'Startup shape evidence is not a qualification.' }
            }
            if ($state.case -in @('qualified-engagement','cadenced-engagement')) {
                if ($null -eq $state.PSObject.Properties['qualifiedEngagementArmed'] -or $state.qualifiedEngagementArmed -ne $true -or
                    $null -eq $state.PSObject.Properties['dealtDamageEvents'] -or $state.dealtDamageEvents -lt 1 -or
                    $null -eq $state.PSObject.Properties['dealtDamage'] -or $state.dealtDamage -lt 1) {
                    throw 'Qualified engagement requires observed outgoing damage.'
                }
                $members = @($state.members | ForEach-Object { $_ })
                if ($members.Count -ne 1) { throw 'Qualified engagement member count is invalid.' }
                $authorization = $state.engagementAuthorization
                if ($null -eq $authorization -or $authorization.armed -ne $true -or $authorization.runId -cne $state.runId -or
                    $authorization.case -cne $state.case -or $authorization.experiment -cne $expectedContract -or
                    $authorization.artifactSha256 -cne $state.artifactSha256 -or $authorization.memberIndex -ne 1 -or
                    $authorization.samples -ne 2 -or $authorization.baseId -cne $members[0].baseId -or
                    $authorization.actorAddress -cne $members[0].actorAddress) { throw 'Qualified engagement authorization is invalid.' }
                for ($index = 0; $index -lt 2; $index++) {
                    $receipt = $shapeObservations[$index].receipt
                    if ($null -eq $receipt -or $receipt.sample -ne ($index + 1) -or $receipt.runId -cne $state.runId -or
                        $receipt.case -cne $state.case -or $receipt.experiment -cne $expectedContract -or
                        $receipt.artifactSha256 -cne $state.artifactSha256 -or $receipt.memberIndex -ne 1 -or
                        -not $receipt.actorAddress -or $receipt.actorAddress -cne $members[0].actorAddress) {
                        throw 'Qualified engagement receipt is invalid.'
                    }
                }
            }
        }
    }
    if ($state.case -eq 'cadenced-engagement') {
        if ($state.capturePolicy -cne 'stock-networked-spheres-only-v1' -or $state.cadenceSeconds -ne 0.1) {
            throw 'Cadence trial capture policy or interval is invalid.'
        }
        $worldFinalized = $false
        if ($null -ne $state.cadence.PSObject.Properties['runtimeDisposition'] -and
            $state.cadence.runtimeDisposition -ceq 'WORLD_FINALIZED') {
            $pins = @{
                runId='20260909-221539-b5664f1858dd4afcab2f296570f197e1'
                certificateSha256='45a3328ee826697958f997f26356953ad469eabfb2eb34e1fbe25222427455ae'
                journalSha256='0d92fee98b9bfd3adbebccf143a2cd44bc05cb87ec97e6eb7dcbad5a2736aa1b'
                snapshotSha256='a5610801008d136212a48aa75e4781f8e56122eb0bc0b65988339326fac7768c'
                evidenceManifestSha256='82a0f705074dde66b8c73e32d54c03afef1a774f0f720831add56f39ad1defb3'
                breadcrumbsSha256='5192e3d3378d6fc205edb15b510e2c1774d644e7866608deb6f2b4e021c7aad1'
                missingAfterStep='1788992144-2197-start-projectile-creation-observation'
                serverExecutableSha256='61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02'
                serverPakSha256='2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe'
            }
            if ($state.runId -cne $pins.runId -or
                $state.sourceRevision -cne '29bea671d8cafc3588fa1c12bcf7c0ecbee0db48' -or
                $state.artifactSha256 -cne 'd3b4a9b6628189cbfa0545e6ca4ce593fedfa19265e708e645695aa2e79cf274' -or
                $state.failedArtifactSha256 -cne $state.artifactSha256 -or
                $state.status -cne 'blocked' -or $state.code -cne 'cadence-world-finalized' -or
                $state.cleanupComplete -ne $true -or $state.spawned -ne 1 -or $state.initialized -ne 1 -or
                $state.cleaned -ne 0 -or $state.npcsFinalized -ne 1 -or $state.helpersFinalized -ne 1 -or
                $state.helpersCreated -ne 1 -or $state.helpersCleaned -ne 0 -or
                $state.cadence.status -cne 'UNRESOLVED' -or $state.cadence.active -ne $false -or
                $state.cadence.retired -ne $true -or $state.cadence.worldFinalizationVerified -ne $true -or
                $state.finalization.oldRootPid -ne 14328 -or $state.finalization.nativeCalls -ne 0) {
                throw 'Cadence world finalization evidence is invalid.'
            }
            foreach ($key in $pins.Keys) {
                if ($state.finalization.$key -cne $pins[$key]) { throw 'Cadence world finalization evidence is invalid.' }
            }
            foreach ($key in @('processExitVerified','installationProcessTreeEmpty','instanceOnlyLeaseVerified','noReplay','preserveSavedTransfers','noExternalReapply')) {
                if ($state.finalization.$key -ne $true) { throw 'Cadence world finalization evidence is invalid.' }
            }
            foreach ($key in @('restorationVerified','disposalVerified')) {
                if ($null -ne $state.cadence.PSObject.Properties[$key] -and $state.cadence.$key -eq $true) {
                    throw 'Cadence world finalization cannot claim live restoration or disposal.'
                }
            }
            $worldFinalized = $true
        }
        if ($state.cleanupComplete -and -not $worldFinalized -and ($state.cadence.active -ne $false -or
            $state.cadence.status -notin @('NOT_ACQUIRED','RESTORED','DISPOSED','OVERRIDDEN') -or
            ($state.cadence.status -eq 'RESTORED' -and $state.cadence.restorationVerified -ne $true) -or
            ($state.cadence.status -eq 'DISPOSED' -and $state.cadence.disposalVerified -ne $true))) {
            throw 'Cadence lease cleanup is unresolved.'
        }
        if ($state.status -eq 'passed' -and ($state.cadence.appliedObserved -ne $true -or
            $state.cadence.retired -ne $true -or
            ($state.cadence.status -ne 'RESTORED' -and
                ($state.cadence.status -ne 'DISPOSED' -or $state.cadence.disposalVerified -ne $true)))) {
            throw 'Cadence lease was not restored or disposed.'
        }
    } elseif ($null -ne $state.PSObject.Properties['capturePolicy'] -or $null -ne $state.PSObject.Properties['cadenceSeconds']) {
        throw 'Cadence policy cannot be attached to another startup case.'
    }
    $finalizedNpcs = 0
    if ($null -ne $state.PSObject.Properties['npcsFinalized']) { $finalizedNpcs = $state.npcsFinalized }
    if ($state.cleanupComplete -and $state.mutationStarted -and
        ($state.status -notin @('passed','blocked') -or ($state.cleaned + $finalizedNpcs) -ne $state.spawned)) {
        throw 'Startup test cleanup outcome is inconsistent.'
    }
    $finalizedHelpers = 0
    if ($null -ne $state.PSObject.Properties['helpersFinalized']) { $finalizedHelpers = $state.helpersFinalized }
    if ($state.cleanupComplete -and $null -ne $state.PSObject.Properties['helpersCreated'] -and
        $state.helpersCreated -ne ($state.helpersCleaned + $finalizedHelpers)) { throw 'Startup support cleanup is incomplete.' }
    $state
}
$previousTestRunId = $null
if ($StartupTest -ne 'None') {
    if ($deployment.deliveryProfile -ne 'laboratory-native-test') { throw 'Startup mutation tests require the laboratory test profile.' }
    if (Test-Path -LiteralPath $activeTestPath -PathType Leaf) {
        $activeTest = Get-Content -LiteralPath $activeTestPath -Raw | ConvertFrom-Json
        if ([string]$activeTest.runId -notmatch '^[a-z0-9-]{1,80}$') { throw 'Previous startup test identity is invalid.' }
        $previousTestRunId = [string]$activeTest.runId
        $previousTest = Read-StartupTestOutcome $previousTestRunId
        if ($previousTest.mutationStarted -and -not $previousTest.cleanupComplete) {
            throw 'A previous startup test retains uncertain spawned entities; no new mutation test may start.'
        }
        $failedArtifact = $previousTest.PSObject.Properties['failedArtifactSha256']
        if (($null -ne $failedArtifact -and $failedArtifact.Value -eq $deployment.artifactSha256) -or
            ($previousTest.status -in @('failed', 'running') -and $previousTest.artifactSha256 -eq $deployment.artifactSha256)) {
            throw 'Do not retry the failed/interrupted startup test on the same artifact.'
        }
    }
}
if ($ValidateOnly) {
    [pscustomobject]$launch
    return
}

New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$previousBuildId = $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
$previousDataDirectory = $env:PAL_EVENT_DIRECTOR_DATA_DIR
$previousRuntimeTag = $env:PAL_EVENT_DIRECTOR_UE4SS_TAG
$previousRuntimeApi = $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION
$previousStartupTest = $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN
$previousSourceRevision = $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION
$previousArtifactHash = $env:PAL_EVENT_DIRECTOR_ARTIFACT_SHA256
try {
    $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $VerifiedBuildId
    $env:PAL_EVENT_DIRECTOR_DATA_DIR = $DataDirectory
    $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = $ExpectedRuntimeTag
    $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = $ExpectedRuntimeApi
    $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION = [string]$deployment.sourceRevision
    $env:PAL_EVENT_DIRECTOR_ARTIFACT_SHA256 = [string]$deployment.artifactSha256
    $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN = $null
    if ($StartupTest -ne 'None') {
        $testRunId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
        $testDirectory = Join-Path $testRoot $testRunId
        Assert-StartupTestPath $testDirectory
        New-Item -ItemType Directory -Path $testDirectory -ErrorAction Stop | Out-Null
        $caseNames = @{ SpawnCleanup='spawn-cleanup'; Movement='movement'; TwoBaseMovement='two-base-movement'; Prewarm='prewarm'; Engagement='engagement'; ClassCatalog='class-catalog'; SurfaceSurvey='surface-survey'; ShapeQualification='shape-qualification'; QualifiedEngagement='qualified-engagement'; CadencedEngagement='cadenced-engagement' }
        $plan = [ordered]@{ schemaVersion=1; runId=$testRunId; case=$caseNames[$StartupTest]; sourceRevision=[string]$deployment.sourceRevision;
            artifactSha256=[string]$deployment.artifactSha256 }
        if ($StartupTestBaseIndex -gt 0) { $plan['baseOrdinal'] = $StartupTestBaseIndex }
        if ($StartupTest -eq 'ShapeQualification') { $plan['experiment'] = 'hunter-level30-one-instance-v1' }
        if ($StartupTest -eq 'QualifiedEngagement') { $plan['experiment'] = 'hunter-level30-qualified-engagement-v1' }
        if ($StartupTest -eq 'CadencedEngagement') {
            $plan['experiment'] = 'hunter-level30-network-sphere-cadence-v1'
            $plan['capturePolicy'] = 'stock-networked-spheres-only-v1'
            $plan['cadenceSeconds'] = 0.1
        }
        if ($previousTestRunId) { $plan['previousRunId'] = $previousTestRunId }
        [IO.File]::WriteAllText((Join-Path $testDirectory 'plan.json'), ($plan | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($activeTestPath, (@{ runId=$testRunId } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN = $testRunId
        $launch['StartupTestRunId'] = $testRunId
        $launch['StartupTestDirectory'] = $testDirectory
    }
    if ($SyntheticChildScript) {
        $process = Start-Process -FilePath 'powershell.exe' `
            -WorkingDirectory $ServerRoot `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $SyntheticChildScript) `
            -Wait `
            -PassThru
    } else {
        $process = Start-Process -FilePath $ServerExecutable `
            -WorkingDirectory $ServerRoot `
            -ArgumentList @("-port=$GamePort", "-queryport=$QueryPort", '-logformat=text') `
            -PassThru
    }
} finally {
    $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $previousBuildId
    $env:PAL_EVENT_DIRECTOR_DATA_DIR = $previousDataDirectory
    $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = $previousRuntimeTag
    $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = $previousRuntimeApi
    $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN = $previousStartupTest
    $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION = $previousSourceRevision
    $env:PAL_EVENT_DIRECTOR_ARTIFACT_SHA256 = $previousArtifactHash
}

$launch['ProcessId'] = $process.Id
$launch['Started'] = $true
[pscustomobject]$launch
} finally {
    if ($HasLifecycleMutex) { $LifecycleMutex.ReleaseMutex() }
    $LifecycleMutex.Dispose()
}
