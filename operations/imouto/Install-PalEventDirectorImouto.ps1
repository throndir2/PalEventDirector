[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',
    [string]$ArtifactPath = '',
    [string]$RuntimeArchivePath = '',
    [string]$ExpectedSourceRevision = '',
    [switch]$ReplaceExistingUe4ss,
    [switch]$DisableOtherUe4ssMods,

    [Parameter(DontShow)]
    [switch]$SyntheticTestFixture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ExpectedAppId = '2394010'
$ExpectedBuildId = '24575149'
$ExpectedRootExeHash = '4a42e42750ccb7537e378c5ca4f781b9534c53fd12f4bc1410f8cd16bec592da'
$ExpectedExeHash = '6be7c3f4d4762b70990e4b7f919016ba4ef8584552950e749c37d40502b1a115'
$ExpectedPakHash = 'bffab47cbd3b3c6d14d616376d4e0b060b2429a5eb4c2022820d4f38d36a0770'
$RuntimeTag = '2281fa31'
$RuntimeApiVersion = '3.0.1'
$RuntimeName = 'UE4SS-Palworld-g2281fa31-zDev.zip'
$RuntimeUrl = 'https://github.com/Okaetsu/RE-UE4SS/releases/download/2281fa31/UE4SS-Palworld-g2281fa31-zDev.zip'
$RuntimeHash = '3b5c8ad11ed7983edde08412eac214222749e83e4b47f12476741c6c536bf060'
$RuntimeFiles = [ordered]@{
    'dwmapi.dll' = '4c258e9bef0145c9099244d4a9b0b68602f746d561b195862fb7d27945987d77'
    'ue4ss\UE4SS.dll' = '21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8'
    'ue4ss\MemberVariableLayout.ini' = '1f93bb4fec5d00f7a958e62b3e3ce101d25e41879bf308ff19252957c0cbdcb1'
}
$InstallerSource = $MyInvocation.MyCommand.Path
$LauncherSource = Join-Path $PSScriptRoot 'Start-PalEventDirectorImouto.ps1'
$ActivationSource = Join-Path $PSScriptRoot 'Enable-PalEventDirectorLaboratory.ps1'
$PreflightSource = Join-Path $PSScriptRoot 'Invoke-PalEventDirectorPreflight.ps1'
$BundleManifestPath = Join-Path $PSScriptRoot 'bundle.json'

function Get-ProcessesUnderRoot {
    param([Parameter(Mandatory)][string]$Root)
    @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)
    })
}

function Assert-ServerStopped {
    param([string]$Root)
    $named = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @('PalServer.exe', 'PalServer-Win64-Shipping-Cmd.exe', 'PalServer-Win64-Test-Cmd.exe')
    })
    foreach ($process in $named) {
        if (-not $process.ExecutablePath) {
            throw "Cannot establish the path for running Palworld server PID $($process.ProcessId); refusing deployment."
        }
        if ($process.ExecutablePath.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Stop the IMOUTO dedicated server before deploying the mod (PID $($process.ProcessId))."
        }
    }
}

function Get-AcfValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, '"' + [regex]::Escape($Name) + '"\s+"(?<Value>[^"]*)"')
    if ($match.Success) { $match.Groups['Value'].Value }
}

function Test-PinnedRuntime {
    param([string]$Win64Root)
    foreach ($entry in $RuntimeFiles.GetEnumerator()) {
        $path = Join-Path $Win64Root $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.Value) { return $false }
    }
    $true
}

function Read-Ue4ssModEntries {
    param([Parameter(Mandatory)][string]$Path)
    $decoded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $entries = @()
    foreach ($entry in @($decoded)) {
        if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['mod_name']) {
            throw "UE4SS mod-control file contains an entry without mod_name: $Path"
        }
        if ($null -eq $entry.PSObject.Properties['mod_enabled']) {
            throw "UE4SS mod-control entry $($entry.mod_name) has no mod_enabled property: $Path"
        }
        if ($entry.mod_enabled -isnot [bool]) {
            throw "UE4SS mod-control entry $($entry.mod_name) has a non-Boolean mod_enabled property: $Path"
        }
        $entries += $entry
    }
    $entries
}

function Assert-NoReparsePoint {
    param([string]$Root, [string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing installation through reparse point: $current"
            }
        }
        if ($current -ieq $Root) { break }
        $current = Split-Path $current -Parent
    }
}

function Assert-NoReparseTree {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $root = Get-Item -LiteralPath $Path -Force
    if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing reparse-point tree: $Path" }
    $reparse = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    } | Select-Object -First 1)
    if ($reparse.Count -gt 0) { throw "Refusing reparse point inside mutable tree: $($reparse[0].FullName)" }
}

function Set-Ue4ssSafetySettings {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    foreach ($entry in ([ordered]@{
        EnableHotReloadSystem = '0'
        ConsoleEnabled = '0'
        GuiConsoleEnabled = '0'
        GuiConsoleVisible = '0'
    }).GetEnumerator()) {
        $pattern = '(?m)^(\s*' + [regex]::Escape($entry.Key) + '\s*=\s*)\S+\s*$'
        if ([regex]::Matches($text, $pattern).Count -ne 1) {
            throw "Expected exactly one UE4SS setting named $($entry.Key)."
        }
        $text = [regex]::Replace($text, $pattern, '${1}' + $entry.Value)
    }
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Remove-InstallationTarget {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $Path) { throw 'Existing installation target could not be removed completely.' }
}

function Get-InstallationInventory {
    param([Parameter(Mandatory)][string]$Root)
    Assert-NoReparseTree -Path $Root
    $inventory = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop)) {
        $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $inventory[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $inventory
}

function Assert-InstallationInventory {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][hashtable]$Expected)
    $actual = Get-InstallationInventory -Root $Root
    if ($actual.Count -ne $Expected.Count) { throw 'Installed runtime inventory differs from the immutable staged runtime.' }
    foreach ($name in $Expected.Keys) {
        if (-not $actual.ContainsKey($name) -or $actual[$name] -ine $Expected[$name]) {
            throw 'Installed runtime bytes differ from the immutable staged runtime.'
        }
    }
}

$ServerRoot = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
$SyntheticRoot = [IO.Path]::GetFullPath('C:\PED-Imouto-Installer-Test').TrimEnd('\')
if ($SyntheticTestFixture -and -not $ServerRoot.StartsWith($SyntheticRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SyntheticTestFixture is restricted to a canonical descendant of the disposable installer-test root.'
}
if ([Environment]::MachineName -ine 'IMOUTO' -and -not $SyntheticTestFixture) {
    throw 'This installer must run locally on IMOUTO. MIKO and remote target execution are prohibited.'
}
if ($ServerRoot.StartsWith('\\') -or $ServerRoot.StartsWith('\\?\') -or $ServerRoot.StartsWith('\\.\')) {
    throw 'ServerRoot must be a local fixed-drive path on IMOUTO; UNC and device targets are prohibited.'
}
$serverDrive = [IO.Path]::GetPathRoot($ServerRoot)
$driveInfo = [IO.DriveInfo]::new($serverDrive)
if ($driveInfo.DriveType -ne [IO.DriveType]::Fixed) {
    throw 'ServerRoot must be on a local fixed drive on IMOUTO.'
}
if ([IO.Path]::GetFileName($ServerRoot) -ine 'PalServer') {
    throw 'ServerRoot must end in PalServer. The Palworld client directory is never a valid target.'
}
$SteamAppsRoot = Split-Path (Split-Path $ServerRoot -Parent) -Parent
$ClientRoot = Join-Path (Split-Path $ServerRoot -Parent) 'Palworld'
$SteamManifest = Join-Path $SteamAppsRoot 'appmanifest_2394010.acf'
$RootServerExe = Join-Path $ServerRoot 'PalServer.exe'
$Win64Root = Join-Path $ServerRoot 'Pal\Binaries\Win64'
$ServerExe = Join-Path $Win64Root 'PalServer-Win64-Shipping-Cmd.exe'
$ServerPak = Join-Path $ServerRoot 'Pal\Content\Paks\Pal-WindowsServer.pak'
$Ue4ssRoot = Join-Path $Win64Root 'ue4ss'
$ModsRoot = Join-Path $Ue4ssRoot 'Mods'
$ModTarget = Join-Path $ModsRoot 'PalEventDirector'
$DeployRoot = Join-Path $ServerRoot 'PalEventDirectorDeployments'
$DeployRecord = Join-Path $DeployRoot 'deployment.json'
$LauncherTarget = Join-Path $DeployRoot 'Start-PalEventDirectorImouto.ps1'
$ActivationTarget = Join-Path $DeployRoot 'Enable-PalEventDirectorLaboratory.ps1'
$PreflightTarget = Join-Path $DeployRoot 'Invoke-PalEventDirectorPreflight.ps1'

if ($ServerRoot -ieq $ClientRoot -or $ServerRoot.StartsWith($ClientRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to install into the Palworld client.'
}
foreach ($required in @($SteamManifest, $RootServerExe, $ServerExe, $ServerPak)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Palworld Dedicated Server file is missing: $required"
    }
}
Assert-NoReparsePoint -Root $ServerRoot -Path $Win64Root
$volumeRoot = [IO.Path]::GetPathRoot($ServerRoot)
$relativeComponents = $ServerRoot.Substring($volumeRoot.Length).Split(@('\'), [StringSplitOptions]::RemoveEmptyEntries)
$ancestor = $volumeRoot
foreach ($component in $relativeComponents) {
    $ancestor = Join-Path $ancestor $component
    Assert-NoReparsePoint -Root $volumeRoot -Path $ancestor
}
Assert-NoReparseTree -Path $Ue4ssRoot
Assert-NoReparseTree -Path $DeployRoot
Assert-ServerStopped -Root $ServerRoot

$acf = [IO.File]::ReadAllText($SteamManifest)
if ((Get-AcfValue $acf 'appid') -ne $ExpectedAppId) { throw 'Target is not Dedicated Server App ID 2394010.' }
$VerifiedBuildId = Get-AcfValue $acf 'buildid'
if ($VerifiedBuildId -ne $ExpectedBuildId) { throw "Target is not validated build $ExpectedBuildId." }
if ((Get-FileHash -LiteralPath $RootServerExe -Algorithm SHA256).Hash -ine $ExpectedRootExeHash) { throw 'Root dedicated-server launcher hash is unvalidated.' }
if ((Get-FileHash -LiteralPath $ServerExe -Algorithm SHA256).Hash -ine $ExpectedExeHash) { throw 'Dedicated-server executable hash is unvalidated.' }
if ((Get-FileHash -LiteralPath $ServerPak -Algorithm SHA256).Hash -ine $ExpectedPakHash) { throw 'Dedicated-server pak hash is unvalidated.' }

if (-not $ArtifactPath) {
    $BuildManifestPath = Join-Path $PSScriptRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $BuildManifestPath -PathType Leaf)) {
        throw 'No deployment manifest exists beside the installer. Build the IMOUTO bundle from the local workspace first or pass ArtifactPath.'
    }
    $BuildManifest = Get-Content -LiteralPath $BuildManifestPath -Raw | ConvertFrom-Json
    $ArtifactPath = Join-Path (Split-Path $BuildManifestPath -Parent) ([string]$BuildManifest.archive)
} else {
    $ArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path
    $BuildManifestPath = Join-Path (Split-Path $ArtifactPath -Parent) 'manifest.json'
    if (-not (Test-Path -LiteralPath $BuildManifestPath -PathType Leaf)) {
        throw "manifest.json must be beside the artifact: $BuildManifestPath"
    }
    $BuildManifest = Get-Content -LiteralPath $BuildManifestPath -Raw | ConvertFrom-Json
}
if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Artifact is missing: $ArtifactPath" }
$ArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path
$ArtifactHash = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash
if ($BuildManifest.sourceDirty -ne $false -or [string]$BuildManifest.sha256 -ine $ArtifactHash -or
    [string]$BuildManifest.archive -ine (Split-Path $ArtifactPath -Leaf)) {
    throw 'Artifact does not match a clean source build manifest.'
}
if ([string]$BuildManifest.packageName -ne 'PalEventDirector' -or
    -not ([string]$BuildManifest.sourceRevision -match '^[a-fA-F0-9]{40}$')) {
    throw 'Build manifest package identity or source revision is invalid.'
}
if ([string]$BuildManifest.version -ne '0.1.0-alpha.3') {
    throw 'This installer requires the alpha.3 package; stale alpha artifacts are rejected.'
}
if ([string]$BuildManifest.deliveryProfile -notin @('preflight-diagnostic-only', 'laboratory-native-test')) {
    throw 'This installer requires an audited laboratory delivery profile.'
}
if ([string]$BuildManifest.sourceRevision -eq '575a9f521977069dcfcb244994f6c017044e9604') {
    throw 'This source revision is revoked after a confirmed IMOUTO native preflight crash.'
}
if ($ExpectedSourceRevision) {
    if ($ExpectedSourceRevision -notmatch '^[a-fA-F0-9]{40}$' -or [string]$BuildManifest.sourceRevision -ine $ExpectedSourceRevision) {
        throw 'The clean-build source revision does not match ExpectedSourceRevision.'
    }
}
foreach ($required in @($InstallerSource, $LauncherSource, $ActivationSource, $PreflightSource, $BundleManifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "The deployment bundle is incomplete: $required"
    }
}
$BundleManifest = Get-Content -LiteralPath $BundleManifestPath -Raw | ConvertFrom-Json
if ($BundleManifest.schemaVersion -ne 1 -or [string]$BundleManifest.packageName -ne 'PalEventDirector' -or
    [string]$BundleManifest.deliveryProfile -ne [string]$BuildManifest.deliveryProfile -or
    [string]$BundleManifest.preflightCommand -ne (Split-Path $PreflightSource -Leaf) -or
    [string]$BundleManifest.preflightCommandSha256 -ine (Get-FileHash $PreflightSource -Algorithm SHA256).Hash -or
    [string]$BundleManifest.version -ne [string]$BuildManifest.version -or
    [string]$BundleManifest.sourceRevision -ne [string]$BuildManifest.sourceRevision -or
    [string]$BundleManifest.artifact -ne (Split-Path $ArtifactPath -Leaf) -or
    [string]$BundleManifest.artifactSha256 -ine $ArtifactHash -or
    [string]$BundleManifest.installer -ne (Split-Path $InstallerSource -Leaf) -or
    [string]$BundleManifest.installerSha256 -ine (Get-FileHash $InstallerSource -Algorithm SHA256).Hash -or
    [string]$BundleManifest.launcher -ne (Split-Path $LauncherSource -Leaf) -or
    [string]$BundleManifest.launcherSha256 -ine (Get-FileHash $LauncherSource -Algorithm SHA256).Hash -or
    [string]$BundleManifest.activation -ne (Split-Path $ActivationSource -Leaf) -or
    [string]$BundleManifest.activationSha256 -ine (Get-FileHash $ActivationSource -Algorithm SHA256).Hash) {
    throw 'The IMOUTO deployment bundle provenance is invalid.'
}

$RuntimeMatches = Test-PinnedRuntime $Win64Root
$RuntimeExists = (Test-Path -LiteralPath $Ue4ssRoot) -or (Test-Path -LiteralPath (Join-Path $Win64Root 'dwmapi.dll'))
$ExistingOtherModDirectories = if (Test-Path -LiteralPath $ModsRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $ModsRoot -Directory -Force | Where-Object {
        $_.Name -ne 'PalEventDirector' -and $_.Name -ne 'shared'
    })
} else { @() }
if ($RuntimeExists -and -not $RuntimeMatches -and -not $ReplaceExistingUe4ss) {
    throw 'A different/incomplete UE4SS exists. Review it, then explicitly use -ReplaceExistingUe4ss to back it up and replace it.'
}
if ($RuntimeExists -and -not $RuntimeMatches -and $ExistingOtherModDirectories.Count -gt 0 -and -not $DisableOtherUe4ssMods) {
    throw "Replacing UE4SS would remove other mod directories: $($ExistingOtherModDirectories.Name -join ', '). Also pass -DisableOtherUe4ssMods only for this disposable test server."
}
if ($RuntimeMatches) {
    $ModsJson = Join-Path $ModsRoot 'mods.json'
    if (-not (Test-Path -LiteralPath $ModsJson -PathType Leaf)) { throw 'Pinned UE4SS exists but mods.json is missing.' }
    $ExistingEntries = @(Read-Ue4ssModEntries -Path $ModsJson)
    $EnabledOthers = @($ExistingEntries | Where-Object { $_.mod_enabled -and $_.mod_name -ne 'PalEventDirector' })
    if ($EnabledOthers.Count -gt 0 -and -not $DisableOtherUe4ssMods) {
        throw "Other UE4SS mods are enabled: $($EnabledOthers.mod_name -join ', '). Use a clean test server or explicitly pass -DisableOtherUe4ssMods."
    }
}

if ($RuntimeExists -and -not $ReplaceExistingUe4ss) {
    throw 'Diagnostic reproducibility requires a fresh pinned runtime. Review the backup/replacement and pass -ReplaceExistingUe4ss.'
}
# Never bless unknown existing settings, signature scripts, shared Lua, or DLLs.
$RuntimeMatches = $false
if (-not $PSCmdlet.ShouldProcess($ServerRoot, "back up and deploy PalEventDirector $($BuildManifest.version) with a FRESH pinned UE4SS $RuntimeTag runtime")) { return }

$Mutex = [Threading.Mutex]::new($false, 'Global\PalEventDirectorImoutoLifecycle')
$HasMutex = $false
$Stage = Join-Path $ServerRoot ('.ped-stage-' + [Guid]::NewGuid().ToString('N'))
$LocalArtifact = Join-Path $Stage (Split-Path $ArtifactPath -Leaf)
$LocalBuildManifest = Join-Path $Stage 'manifest.json'
$LocalBundleManifest = Join-Path $Stage 'bundle.json'
$LocalLauncher = Join-Path $Stage 'Start-PalEventDirectorImouto.ps1'
$LocalActivation = Join-Path $Stage 'Enable-PalEventDirectorLaboratory.ps1'
$LocalPreflight = Join-Path $Stage 'Invoke-PalEventDirectorPreflight.ps1'
$ArtifactStage = Join-Path $Stage 'artifact'
$RuntimeStage = Join-Path $Stage 'runtime'
$Backup = Join-Path $ServerRoot ('PalEventDirectorInstallerBackups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
$HadUe4ss = $false
$HadProxy = $false
$HadDeployRecord = $false
$HadLauncher = $false
$HadActivation = $false
$HadPreflight = $false
$LauncherIncoming = "$LauncherTarget.incoming"
$ActivationIncoming = "$ActivationTarget.incoming"
$PreflightIncoming = "$PreflightTarget.incoming"
$MutationStarted = $false

try {
    $HasMutex = $Mutex.WaitOne(0)
    if (-not $HasMutex) { throw 'Another Pal Event Director installation is already running on IMOUTO.' }
    Assert-ServerStopped -Root $ServerRoot
    $HadUe4ss = Test-Path -LiteralPath $Ue4ssRoot
    $HadProxy = Test-Path -LiteralPath (Join-Path $Win64Root 'dwmapi.dll')
    $HadDeployRecord = Test-Path -LiteralPath $DeployRecord
    $HadLauncher = Test-Path -LiteralPath $LauncherTarget
    $HadActivation = Test-Path -LiteralPath $ActivationTarget
    $HadPreflight = Test-Path -LiteralPath $PreflightTarget
    New-Item -ItemType Directory -Path $Stage -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $ArtifactPath -Destination $LocalArtifact -ErrorAction Stop
    Copy-Item -LiteralPath $BuildManifestPath -Destination $LocalBuildManifest -ErrorAction Stop
    Copy-Item -LiteralPath $BundleManifestPath -Destination $LocalBundleManifest -ErrorAction Stop
    Copy-Item -LiteralPath $LauncherSource -Destination $LocalLauncher -ErrorAction Stop
    Copy-Item -LiteralPath $ActivationSource -Destination $LocalActivation -ErrorAction Stop
    Copy-Item -LiteralPath $PreflightSource -Destination $LocalPreflight -ErrorAction Stop
    $LocalManifest = Get-Content -LiteralPath $LocalBuildManifest -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $LocalArtifact -Algorithm SHA256).Hash -ine $ArtifactHash -or
        [string]$LocalManifest.sha256 -ine $ArtifactHash -or [string]$LocalManifest.sourceRevision -ine [string]$BuildManifest.sourceRevision -or
        (Get-FileHash $LocalBundleManifest -Algorithm SHA256).Hash -ine (Get-FileHash $BundleManifestPath -Algorithm SHA256).Hash -or
        (Get-FileHash $LocalLauncher -Algorithm SHA256).Hash -ine [string]$BundleManifest.launcherSha256 -or
        (Get-FileHash $LocalActivation -Algorithm SHA256).Hash -ine [string]$BundleManifest.activationSha256 -or
        (Get-FileHash $LocalPreflight -Algorithm SHA256).Hash -ine [string]$BundleManifest.preflightCommandSha256) {
        throw 'The local immutable artifact snapshot differs from the validated source.'
    }
    New-Item -ItemType Directory -Path $ArtifactStage -Force | Out-Null
    Expand-Archive -LiteralPath $LocalArtifact -DestinationPath $ArtifactStage
    foreach ($required in @('Info.json', 'Scripts\main.lua', 'Scripts\ped\version.lua')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ArtifactStage $required) -PathType Leaf)) { throw "Artifact is missing $required" }
    }
    $Info = Get-Content -LiteralPath (Join-Path $ArtifactStage 'Info.json') -Raw | ConvertFrom-Json
    $VersionSource = [IO.File]::ReadAllText((Join-Path $ArtifactStage 'Scripts\ped\version.lua'))
    $ProfileMatch = [regex]::Matches($VersionSource, 'delivery_profile\s*=\s*"([^"]+)"')
    if ($ProfileMatch.Count -ne 1 -or $ProfileMatch[0].Groups[1].Value -ne [string]$BuildManifest.deliveryProfile) {
        throw 'Packaged Lua profile differs from the attested delivery profile.'
    }
    if ($Info.PackageName -ne 'PalEventDirector' -or $Info.Version -ne $BuildManifest.version -or
        @($Info.InstallRule).Count -ne 1 -or $Info.InstallRule[0].IsServer -ne $true) {
        throw 'Artifact is not the expected server-only package.'
    }

    if (-not $RuntimeMatches) {
        New-Item -ItemType Directory -Path $RuntimeStage -Force | Out-Null
        if ($RuntimeArchivePath) {
            $RuntimeSource = (Resolve-Path -LiteralPath $RuntimeArchivePath).Path
            $RuntimeArchive = Join-Path $Stage $RuntimeName
            Copy-Item -LiteralPath $RuntimeSource -Destination $RuntimeArchive -ErrorAction Stop
        } else {
            $RuntimeArchive = Join-Path $Stage $RuntimeName
            $PreviousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $RuntimeUrl -OutFile $RuntimeArchive
            } finally {
                [Net.ServicePointManager]::SecurityProtocol = $PreviousSecurityProtocol
            }
        }
        if ((Get-FileHash -LiteralPath $RuntimeArchive -Algorithm SHA256).Hash -ine $RuntimeHash) { throw 'Pinned UE4SS archive hash mismatch.' }
        Expand-Archive -LiteralPath $RuntimeArchive -DestinationPath $RuntimeStage
        foreach ($entry in $RuntimeFiles.GetEnumerator()) {
            $path = Join-Path $RuntimeStage $entry.Key
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.Value) {
                throw "Staged UE4SS file failed verification: $($entry.Key)"
            }
        }
        # Only PED and the pinned shared libraries belong in the crash-isolation stack.
        Get-ChildItem -LiteralPath (Join-Path $RuntimeStage 'ue4ss\Mods') -Directory | Where-Object { $_.Name -ne 'shared' } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        }
    }

    # Finish all reviewed transformations BEFORE computing the intended installation.
    $StagedUe4ssRoot = Join-Path $RuntimeStage 'ue4ss'
    $StagedModsRoot = Join-Path $StagedUe4ssRoot 'Mods'
    $StagedModTarget = Join-Path $StagedModsRoot 'PalEventDirector'
    if (Test-Path -LiteralPath $StagedModTarget) { throw 'Pinned runtime unexpectedly contains a PED package.' }
    Move-Item -LiteralPath $ArtifactStage -Destination $StagedModTarget -ErrorAction Stop
    Set-Ue4ssSafetySettings (Join-Path $StagedUe4ssRoot 'UE4SS-settings.ini')
    $Entries = @(Read-Ue4ssModEntries -Path (Join-Path $StagedModsRoot 'mods.json'))
    foreach ($entry in $Entries) { $entry.mod_enabled = $false }
    $PedEntries = @($Entries | Where-Object { $_.mod_name -eq 'PalEventDirector' })
    if ($PedEntries.Count -gt 1) { throw 'Duplicate PalEventDirector entries exist in pinned mods.json.' }
    if ($PedEntries.Count -eq 0) { $Entries += [pscustomobject]@{ mod_name = 'PalEventDirector'; mod_enabled = $true } }
    else { $PedEntries[0].mod_enabled = $true }
    $Enabled = @($Entries | Where-Object { $_.mod_enabled })
    if ($Enabled.Count -ne 1 -or $Enabled[0].mod_name -ne 'PalEventDirector') { throw 'Final UE4SS state must enable exactly PalEventDirector.' }
    $Utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $StagedModsRoot 'mods.json'), ((ConvertTo-Json -InputObject $Entries -Depth 5) + [Environment]::NewLine), $Utf8)
    $ModsText = (($Entries | ForEach-Object { '{0} : {1}' -f $_.mod_name, $(if ($_.mod_enabled) { 1 } else { 0 }) }) -join [Environment]::NewLine) + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $StagedModsRoot 'mods.txt'), $ModsText, $Utf8)
    $ExpectedInstalledRuntime = Get-InstallationInventory -Root $StagedUe4ssRoot

    New-Item -ItemType Directory -Path $Backup -ErrorAction Stop | Out-Null
    $BackupMetadata = [ordered]@{ schemaVersion = 1; hadUe4ss = $HadUe4ss; hadProxy = $HadProxy; hadDeploymentRecord = $HadDeployRecord; hadLauncher = $HadLauncher; hadActivation = $HadActivation }
    $BackupMetadata.hadPreflight = $HadPreflight
    [IO.File]::WriteAllText((Join-Path $Backup 'backup.json'), (($BackupMetadata | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    if ($HadUe4ss) { Copy-Item -LiteralPath $Ue4ssRoot -Destination (Join-Path $Backup 'ue4ss') -Recurse -Force }
    if ($HadProxy) { Copy-Item -LiteralPath (Join-Path $Win64Root 'dwmapi.dll') -Destination (Join-Path $Backup 'dwmapi.dll') -Force }
    if ($HadDeployRecord) { Copy-Item -LiteralPath $DeployRecord -Destination (Join-Path $Backup 'deployment.json') -Force }
    if ($HadLauncher) { Copy-Item -LiteralPath $LauncherTarget -Destination (Join-Path $Backup 'Start-PalEventDirectorImouto.ps1') -Force }
    if ($HadActivation) { Copy-Item -LiteralPath $ActivationTarget -Destination (Join-Path $Backup 'Enable-PalEventDirectorLaboratory.ps1') -Force }
    if ($HadPreflight) { Copy-Item -LiteralPath $PreflightTarget -Destination (Join-Path $Backup 'Invoke-PalEventDirectorPreflight.ps1') -Force }

    $MutationStarted = $true
    Assert-ServerStopped -Root $ServerRoot
    Remove-InstallationTarget -Path $Ue4ssRoot
    Remove-InstallationTarget -Path (Join-Path $Win64Root 'dwmapi.dll')
    if (Test-Path -LiteralPath $ModTarget) { throw 'Existing PED target survived runtime removal.' }
    Move-Item -LiteralPath $StagedUe4ssRoot -Destination $Ue4ssRoot -ErrorAction Stop
    Move-Item -LiteralPath (Join-Path $RuntimeStage 'dwmapi.dll') -Destination (Join-Path $Win64Root 'dwmapi.dll') -ErrorAction Stop
    Assert-InstallationInventory -Root $Ue4ssRoot -Expected $ExpectedInstalledRuntime
    if (-not (Test-PinnedRuntime $Win64Root)) { throw 'Installed UE4SS failed final verification.' }
    New-Item -ItemType Directory -Path $DeployRoot -Force | Out-Null
    Remove-Item -LiteralPath $LauncherIncoming -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $LocalLauncher -Destination $LauncherIncoming -Force -ErrorAction Stop
    if ((Get-FileHash $LauncherIncoming -Algorithm SHA256).Hash -ine [string]$BundleManifest.launcherSha256) {
        throw 'Staged IMOUTO launcher failed final verification.'
    }
    Move-Item -LiteralPath $LauncherIncoming -Destination $LauncherTarget -Force -ErrorAction Stop
    Remove-Item -LiteralPath $ActivationIncoming -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $LocalActivation -Destination $ActivationIncoming -Force -ErrorAction Stop
    if ((Get-FileHash $ActivationIncoming -Algorithm SHA256).Hash -ine [string]$BundleManifest.activationSha256) {
        throw 'Staged IMOUTO laboratory activation command failed final verification.'
    }
    Move-Item -LiteralPath $ActivationIncoming -Destination $ActivationTarget -Force -ErrorAction Stop
    Copy-Item -LiteralPath $LocalPreflight -Destination $PreflightIncoming -Force -ErrorAction Stop
    if ((Get-FileHash $PreflightIncoming -Algorithm SHA256).Hash -ine [string]$BundleManifest.preflightCommandSha256) {
        throw 'Staged local preflight command failed final verification.'
    }
    Move-Item -LiteralPath $PreflightIncoming -Destination $PreflightTarget -Force -ErrorAction Stop
    $StartupPaths = @((Join-Path $Win64Root 'dwmapi.dll'), $LauncherTarget, $ActivationTarget, $PreflightTarget) + @(
        Get-ChildItem -LiteralPath $Ue4ssRoot -File -Recurse | Where-Object { $_.Extension -notin @('.log', '.pdb') } | Select-Object -ExpandProperty FullName
    )
    $StartupFiles = @($StartupPaths | Sort-Object -Unique | ForEach-Object {
        [ordered]@{ path = $_.Substring($ServerRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $Record = [ordered]@{
        schemaVersion = 1
        packageName = 'PalEventDirector'
        version = [string]$BuildManifest.version
        deliveryProfile = [string]$BuildManifest.deliveryProfile
        startupFiles = $StartupFiles
        sourceRevision = ([string]$BuildManifest.sourceRevision).ToLowerInvariant()
        artifactSha256 = $ArtifactHash.ToLowerInvariant()
        ue4ssTag = $RuntimeTag
        ue4ssApiVersion = $RuntimeApiVersion
        ue4ssDllSha256 = $RuntimeFiles['ue4ss\UE4SS.dll']
        serverAppId = $ExpectedAppId
        serverBuildId = $VerifiedBuildId
        rootServerExecutableSha256 = (Get-FileHash $RootServerExe -Algorithm SHA256).Hash.ToLowerInvariant()
        serverExecutableSha256 = (Get-FileHash $ServerExe -Algorithm SHA256).Hash.ToLowerInvariant()
        serverPakSha256 = (Get-FileHash $ServerPak -Algorithm SHA256).Hash.ToLowerInvariant()
        dataDirectory = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector'
        launcherPath = $LauncherTarget
        launcherSha256 = ([string]$BundleManifest.launcherSha256).ToLowerInvariant()
        activationPath = $ActivationTarget
        activationSha256 = ([string]$BundleManifest.activationSha256).ToLowerInvariant()
        preflightCommandPath = $PreflightTarget
        preflightCommandSha256 = ([string]$BundleManifest.preflightCommandSha256).ToLowerInvariant()
        laboratoryActivationConfigured = $true
        launchIntegrationConfigured = $true
        launchEnvironmentSource = 'verified-steam-manifest'
        installedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        backupRoot = $Backup
    }
    [IO.File]::WriteAllText($DeployRecord, (($Record | ConvertTo-Json -Depth 5) + [Environment]::NewLine), $Utf8)

    $PersistentConfigPath = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector\config.json'
    $PersistentCapabilitiesConfigured = $false
    $CapabilityStatus = 'NotConfigured'
    $GrantItemsEnabled = $false
    $EnabledScheduleCount = 0
    if (Test-Path $PersistentConfigPath -PathType Leaf) {
        try {
            $PersistentConfig = Get-Content $PersistentConfigPath -Raw | ConvertFrom-Json
            $CapabilityNames = @('chatCommands', 'observeCombat', 'observeInvasions', 'startAllInvasions', 'substituteBountyMembers')
            $PersistentCapabilitiesConfigured = @($CapabilityNames | Where-Object { $PersistentConfig.capabilities.$_ -ne $true }).Count -eq 0
            $GrantItemsEnabled = $PersistentConfig.capabilities.grantItems -eq $true
            $EnabledScheduleCount = @($PersistentConfig.schedules | ForEach-Object { $_ } | Where-Object { $_.enabled }).Count
            $CapabilityStatus = if ($PersistentCapabilitiesConfigured) { 'ConfiguredEnabled-ReactivationRequired' } else { 'ConfiguredButNotFullyEnabled-ReactivationRequired' }
        } catch {
            $CapabilityStatus = 'ConfigurationUnreadable'
        }
    }

    [pscustomobject]@{
        Status = 'Installed'
        DeliveryProfile = $Record.deliveryProfile
        NativeStartsQuarantined = ($Record.deliveryProfile -ne 'laboratory-native-test')
        NativePreflightRequired = $false
        ServerRoot = $ServerRoot
        ClientRootUntouched = $ClientRoot
        Version = $Record.version
        SourceRevision = $Record.sourceRevision
        ArtifactSha256 = $Record.artifactSha256
        BackupRoot = $Backup
        LaunchIntegrationConfigured = $true
        LauncherPath = $LauncherTarget
        LaboratoryActivationConfigured = $true
        ActivationPath = $ActivationTarget
        PreflightCommandPath = $PreflightTarget
        PersistentCapabilitiesConfigured = $PersistentCapabilitiesConfigured
        CapabilitiesValidatedForThisDeployment = $false
        CapabilityStatus = $CapabilityStatus
        GrantItemsEnabled = $GrantItemsEnabled
        EnabledScheduleCount = $EnabledScheduleCount
        ServerBuildId = $VerifiedBuildId
        ServerStarted = $false
    }
} catch {
    $OriginalError = $_
    if ($MutationStarted) {
        try {
            if (Test-Path -LiteralPath $Ue4ssRoot) { Remove-Item -LiteralPath $Ue4ssRoot -Recurse -Force -ErrorAction Stop }
            $ProxyPath = Join-Path $Win64Root 'dwmapi.dll'
            if (Test-Path -LiteralPath $ProxyPath) { Remove-Item -LiteralPath $ProxyPath -Force -ErrorAction Stop }
            if ($HadUe4ss -and (Test-Path -LiteralPath (Join-Path $Backup 'ue4ss'))) { Copy-Item -LiteralPath (Join-Path $Backup 'ue4ss') -Destination $Ue4ssRoot -Recurse -ErrorAction Stop }
            if ($HadProxy -and (Test-Path -LiteralPath (Join-Path $Backup 'dwmapi.dll'))) { Copy-Item -LiteralPath (Join-Path $Backup 'dwmapi.dll') -Destination $ProxyPath -ErrorAction Stop }
            if (Test-Path -LiteralPath $DeployRecord) { Remove-Item -LiteralPath $DeployRecord -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $LauncherTarget) { Remove-Item -LiteralPath $LauncherTarget -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $ActivationTarget) { Remove-Item -LiteralPath $ActivationTarget -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $PreflightTarget) { Remove-Item -LiteralPath $PreflightTarget -Force -ErrorAction Stop }
            if ($HadDeployRecord -and (Test-Path -LiteralPath (Join-Path $Backup 'deployment.json'))) {
                New-Item -ItemType Directory -Path $DeployRoot -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $Backup 'deployment.json') -Destination $DeployRecord -ErrorAction Stop
            }
            if ($HadLauncher -and (Test-Path -LiteralPath (Join-Path $Backup 'Start-PalEventDirectorImouto.ps1'))) {
                New-Item -ItemType Directory -Path $DeployRoot -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $Backup 'Start-PalEventDirectorImouto.ps1') -Destination $LauncherTarget -ErrorAction Stop
            }
            if ($HadActivation -and (Test-Path -LiteralPath (Join-Path $Backup 'Enable-PalEventDirectorLaboratory.ps1'))) {
                New-Item -ItemType Directory -Path $DeployRoot -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $Backup 'Enable-PalEventDirectorLaboratory.ps1') -Destination $ActivationTarget -ErrorAction Stop
            }
            if ($HadPreflight -and (Test-Path -LiteralPath (Join-Path $Backup 'Invoke-PalEventDirectorPreflight.ps1'))) {
                Copy-Item -LiteralPath (Join-Path $Backup 'Invoke-PalEventDirectorPreflight.ps1') -Destination $PreflightTarget -ErrorAction Stop
            }
        } catch {
            throw "Installation failed ($($OriginalError.Exception.Message)) and rollback also failed ($($_.Exception.Message)). Keep the server stopped and recover from $Backup."
        }
    }
    throw $OriginalError
} finally {
    Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
    if ($HasMutex) { Remove-Item -LiteralPath $LauncherIncoming -Force -ErrorAction SilentlyContinue }
    if ($HasMutex) { Remove-Item -LiteralPath $ActivationIncoming -Force -ErrorAction SilentlyContinue }
    if ($HasMutex) { Remove-Item -LiteralPath $PreflightIncoming -Force -ErrorAction SilentlyContinue }
    if ($HasMutex) { $Mutex.ReleaseMutex() }
    $Mutex.Dispose()
}
