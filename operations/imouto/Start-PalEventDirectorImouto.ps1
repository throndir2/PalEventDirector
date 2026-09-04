[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$GamePort = 8213,

    [ValidateRange(1, 65535)]
    [int]$QueryPort = 27016,

    [switch]$ValidateOnly,

    [Parameter(DontShow)]
    [string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',

    [Parameter(DontShow)]
    [switch]$SyntheticTestFixture,

    [Parameter(DontShow)]
    [string]$SyntheticChildScript = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    [string]$deployment.deliveryProfile -ne 'preflight-diagnostic-only' -or
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
    DeliveryProfile = 'preflight-diagnostic-only'
    NativeStartsQuarantined = $true
    Ue4ssTag = $ExpectedRuntimeTag
    Ue4ssApiVersion = $ExpectedRuntimeApi
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
try {
    $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $VerifiedBuildId
    $env:PAL_EVENT_DIRECTOR_DATA_DIR = $DataDirectory
    $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = $ExpectedRuntimeTag
    $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = $ExpectedRuntimeApi
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
}

$launch['ProcessId'] = $process.Id
$launch['Started'] = $true
[pscustomobject]$launch
} finally {
    if ($HasLifecycleMutex) { $LifecycleMutex.ReleaseMutex() }
    $LifecycleMutex.Dispose()
}
