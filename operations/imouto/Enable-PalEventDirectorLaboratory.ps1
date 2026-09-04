[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('operatorOnly', 'palworldAdminOnly', 'operatorOrPalworldAdmin')]
    [string]$AuthorizationPolicy = 'operatorOrPalworldAdmin',

    [Parameter(DontShow)]
    [string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',

    [Parameter(DontShow)]
    [switch]$SyntheticTestFixture,

    [Parameter(DontShow)]
    [string]$SyntheticExpectedUe4ssDllSha256 = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CanonicalServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer'
$ExpectedAppId = '2394010'
$ExpectedBuildId = '24575149'
$ExpectedUe4ssApiVersion = '3.0.1'
$ExpectedUe4ssDllSha256 = '21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8'

function Assert-ServerStopped {
    param([string]$Root)
    $serverNames = @('PalServer.exe', 'PalServer-Win64-Shipping-Cmd.exe', 'PalServer-Win64-Test-Cmd.exe')
    foreach ($process in @(Get-CimInstance Win32_Process)) {
        if ($process.Name -in $serverNames -and -not $process.ExecutablePath) {
            throw "Cannot establish the path for Palworld server PID $($process.ProcessId); refusing activation."
        }
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Stop every process under the IMOUTO dedicated-server root before activation (PID $($process.ProcessId))."
        }
    }
}

function Get-AcfValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, '"' + [regex]::Escape($Name) + '"\s+"(?<Value>[^"]*)"')
    if ($match.Success) { $match.Groups['Value'].Value }
}

function ConvertTo-FlatArray {
    param($Value)
    @($Value | ForEach-Object { $_ })
}

function Assert-JsonArrayProperty {
    param($Owner, [string]$PropertyName, [string]$Path)
    if ($null -eq $Owner -or $null -eq $Owner.PSObject.Properties[$PropertyName] -or
        $Owner.PSObject.Properties[$PropertyName].Value -isnot [System.Array]) {
        throw "$Path must be a JSON array."
    }
}

function Assert-BooleanValue {
    param($Value, [string]$Name)
    if ($Value -isnot [bool]) { throw "$Name must be a Boolean." }
}

function Assert-IntegerRange {
    param($Value, [string]$Name, [long]$Minimum, [long]$Maximum)
    if ($Value -isnot [int] -and $Value -isnot [long]) { throw "$Name must be an integer." }
    if ([long]$Value -lt $Minimum -or [long]$Value -gt $Maximum) { throw "$Name must be from $Minimum through $Maximum." }
}

function Assert-RewardDefinition {
    param($Reward, [string]$Name)
    if ($null -eq $Reward) { throw "$Name is required." }
    if ($null -ne $Reward.PSObject.Properties['enabled']) { Assert-BooleanValue $Reward.enabled "$Name.enabled" }
    if ([string]$Reward.itemId -notmatch '^[A-Za-z0-9_]+$') { throw "$Name.itemId is invalid." }
    Assert-IntegerRange $Reward.count "$Name.count" 1 1000
}

function Assert-PedConfigSchema3 {
    param($Config)
    if ($null -eq $Config) { throw 'PED configuration root is required.' }
    Assert-IntegerRange $Config.schemaVersion 'schemaVersion' 3 3
    if ([string]$Config.mode -notin @('laboratory', 'production')) { throw 'mode is invalid.' }
    if ([string]::IsNullOrWhiteSpace([string]$Config.compatibility.requiredAdapter)) { throw 'compatibility.requiredAdapter is required.' }
    Assert-JsonArrayProperty $Config.compatibility 'allowedServerBuildIds' 'compatibility.allowedServerBuildIds'
    Assert-JsonArrayProperty $Config.compatibility 'allowedUe4ssVersions' 'compatibility.allowedUe4ssVersions'
    foreach ($build in (ConvertTo-FlatArray $Config.compatibility.allowedServerBuildIds)) {
        if ([string]$build -notmatch '^\d+$') { throw 'compatibility.allowedServerBuildIds contains an invalid value.' }
    }
    foreach ($version in (ConvertTo-FlatArray $Config.compatibility.allowedUe4ssVersions)) {
        if ([string]$version -notmatch '^\d+\.\d+\.\d+$') { throw 'compatibility.allowedUe4ssVersions contains an invalid value.' }
    }
    Assert-IntegerRange $Config.runtime.pollIntervalMs 'runtime.pollIntervalMs' 250 5000
    Assert-IntegerRange $Config.runtime.checkpointIntervalSeconds 'runtime.checkpointIntervalSeconds' 1 300
    if ([string]$Config.runtime.logLevel -notin @('debug', 'info', 'warn', 'error')) { throw 'runtime.logLevel is invalid.' }
    $requiredCapabilities = @('observeCombat', 'observeInvasions', 'chatCommands', 'startAllInvasions', 'substituteBountyMembers', 'grantItems')
    foreach ($name in $requiredCapabilities) {
        Assert-BooleanValue $Config.capabilities.$name "capabilities.$name"
    }
    foreach ($property in $Config.capabilities.PSObject.Properties) { Assert-BooleanValue $property.Value "capabilities.$($property.Name)" }
    if ($Config.capabilities.grantItems) { throw 'grantItems is unavailable in alpha.3.' }
    if ($Config.capabilities.startAllInvasions -and (-not $Config.capabilities.observeCombat -or -not $Config.capabilities.observeInvasions)) {
        throw 'startAllInvasions requires both observation capabilities.'
    }
    if ($Config.capabilities.startAllInvasions -and @(ConvertTo-FlatArray $Config.compatibility.allowedServerBuildIds).Count -lt 1) {
        throw 'startAllInvasions requires a server build allowlist.'
    }
    if ($Config.capabilities.startAllInvasions -and @(ConvertTo-FlatArray $Config.compatibility.allowedUe4ssVersions).Count -lt 1) {
        throw 'startAllInvasions requires a UE4SS allowlist.'
    }
    Assert-BooleanValue $Config.diagnostics.traceHooks 'diagnostics.traceHooks'
    Assert-BooleanValue $Config.diagnostics.observationProbe 'diagnostics.observationProbe'
    Assert-IntegerRange $Config.limits.maxBases 'limits.maxBases' 1 256
    Assert-IntegerRange $Config.limits.maxTargets 'limits.maxTargets' 1 4096
    Assert-IntegerRange $Config.limits.maxPlayers 'limits.maxPlayers' 1 1024
    Assert-IntegerRange $Config.limits.maxDamageRecords 'limits.maxDamageRecords' 100 1000000
    Assert-IntegerRange $Config.limits.maxAnnouncementLength 'limits.maxAnnouncementLength' 40 1000

    $siege = $Config.siegeLeague
    if ([string]$siege.chatStartPolicy -notin @('operatorOnly', 'palworldAdminOnly', 'operatorOrPalworldAdmin', 'anyUser')) { throw 'siegeLeague.chatStartPolicy is invalid.' }
    Assert-IntegerRange $siege.userStartCooldownSeconds 'siegeLeague.userStartCooldownSeconds' 60 604800
    Assert-IntegerRange $siege.manualCountdownMinutes 'siegeLeague.manualCountdownMinutes' 0 60
    Assert-BooleanValue $siege.allowCrossBaseRoaming 'siegeLeague.allowCrossBaseRoaming'
    if (-not $siege.allowCrossBaseRoaming) { throw 'alpha.3 requires cross-base roaming.' }
    Assert-IntegerRange $siege.targetPoints 'siegeLeague.targetPoints' 1 1000000
    Assert-IntegerRange $siege.minimumParticipationPoints 'siegeLeague.minimumParticipationPoints' 0 ([long]$siege.targetPoints * [long]$Config.limits.maxTargets)
    Assert-IntegerRange $siege.leaderboardSize 'siegeLeague.leaderboardSize' 1 50
    Assert-IntegerRange $siege.startDiscoverySeconds 'siegeLeague.startDiscoverySeconds' 5 600
    Assert-IntegerRange $siege.settleDelaySeconds 'siegeLeague.settleDelaySeconds' 1 300
    Assert-IntegerRange $siege.maxRuntimeSeconds 'siegeLeague.maxRuntimeSeconds' 60 21600
    foreach ($name in @('creditDirectPlayer', 'creditActivePal', 'creditBaseWorkers')) { Assert-BooleanValue $siege.$name "siegeLeague.$name" }
    $knownProfiles = @('all-bounty', 'patrol', 'mixed', 'most-wanted', 'kingpin', 'jackpot', 'native')
    $allowedProfiles = @{}
    Assert-JsonArrayProperty $siege 'allowedProfiles' 'siegeLeague.allowedProfiles'
    foreach ($profile in (ConvertTo-FlatArray $siege.allowedProfiles)) {
        if ([string]$profile -notin $knownProfiles -or $allowedProfiles.ContainsKey([string]$profile)) { throw "Invalid or duplicate allowed profile: $profile" }
        $allowedProfiles[[string]$profile] = $true
    }
    if (-not $allowedProfiles.ContainsKey([string]$siege.defaultProfile)) { throw 'siegeLeague.defaultProfile is not allowed.' }
    if ($Config.capabilities.startAllInvasions -and -not $Config.capabilities.substituteBountyMembers -and
        @($allowedProfiles.Keys | Where-Object { $_ -ne 'native' }).Count -gt 0) {
        throw 'Enabled non-native profiles require substituteBountyMembers.'
    }

    $scheduleIds = @{}
    Assert-JsonArrayProperty $Config 'schedules' 'schedules'
    foreach ($schedule in (ConvertTo-FlatArray $Config.schedules)) {
        if ([string]$schedule.id -notmatch '^[a-z0-9][a-z0-9.-]*$' -or $scheduleIds.ContainsKey([string]$schedule.id)) { throw 'Schedule ID is invalid or duplicated.' }
        $scheduleIds[[string]$schedule.id] = $true
        if ([string]::IsNullOrWhiteSpace([string]$schedule.name) -or ([string]$schedule.name).Length -gt 120) { throw "Schedule $($schedule.id) name is invalid." }
        Assert-BooleanValue $schedule.enabled "schedule $($schedule.id).enabled"
        if ($schedule.enabled -and -not $Config.capabilities.startAllInvasions) { throw "Schedule $($schedule.id) requires startAllInvasions." }
        if ([string]$schedule.frequency -notin @('daily', 'weekly')) { throw "Schedule $($schedule.id) frequency is invalid." }
        if ($schedule.frequency -eq 'weekly' -and [string]$schedule.dayOfWeek -notin @('SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT')) { throw "Schedule $($schedule.id) weekday is invalid." }
        Assert-IntegerRange $schedule.hour "schedule $($schedule.id).hour" 0 23
        Assert-IntegerRange $schedule.minute "schedule $($schedule.id).minute" 0 59
        Assert-IntegerRange $schedule.lateStartToleranceSeconds "schedule $($schedule.id).lateStartToleranceSeconds" 0 600
        if (-not $allowedProfiles.ContainsKey([string]$schedule.profile)) { throw "Schedule $($schedule.id) profile is not enabled." }
        if ($schedule.enabled -and $schedule.profile -ne 'native' -and -not $Config.capabilities.substituteBountyMembers) {
            throw "Schedule $($schedule.id) requires substituteBountyMembers."
        }
        Assert-JsonArrayProperty $schedule 'warningSeconds' "schedule $($schedule.id).warningSeconds"
        $warnings = @(ConvertTo-FlatArray $schedule.warningSeconds | ForEach-Object { Assert-IntegerRange $_ "schedule $($schedule.id) warning" 1 86400; [int]$_ })
        foreach ($requiredWarning in @(600, 300, 60)) { if ($warnings -notcontains $requiredWarning) { throw "Schedule $($schedule.id) lacks mandatory warning $requiredWarning." } }
    }

    Assert-RewardDefinition $Config.rewards.participation 'rewards.participation'
    Assert-RewardDefinition $Config.rewards.baseCompletion 'rewards.baseCompletion'
    Assert-IntegerRange $Config.rewards.baseCompletion.maxPerPlayer 'rewards.baseCompletion.maxPerPlayer' 1 $Config.limits.maxBases
    $allowedItems = @{}
    Assert-JsonArrayProperty $Config.rewards 'allowedItemIds' 'rewards.allowedItemIds'
    Assert-JsonArrayProperty $Config.rewards 'podium' 'rewards.podium'
    foreach ($item in (ConvertTo-FlatArray $Config.rewards.allowedItemIds)) {
        if ([string]$item -notmatch '^[A-Za-z0-9_]+$') { throw 'rewards.allowedItemIds contains an invalid ID.' }
        $allowedItems[[string]$item] = $true
    }
    foreach ($reward in @($Config.rewards.participation, $Config.rewards.baseCompletion) + @(ConvertTo-FlatArray $Config.rewards.podium)) {
        if (-not $allowedItems.ContainsKey([string]$reward.itemId)) { throw "Reward item is not allowlisted: $($reward.itemId)" }
    }
    $ranks = @{}
    foreach ($reward in (ConvertTo-FlatArray $Config.rewards.podium)) {
        Assert-RewardDefinition $reward 'rewards.podium'
        Assert-IntegerRange $reward.rank 'rewards.podium.rank' 1 3
        if ($ranks.ContainsKey([int]$reward.rank)) { throw 'Duplicate podium rank.' }
        $ranks[[int]$reward.rank] = $true
    }
    Assert-JsonArrayProperty $Config 'operatorUids' 'operatorUids'
    foreach ($uid in (ConvertTo-FlatArray $Config.operatorUids)) {
        if ([string]$uid -notmatch '^[A-Fa-f0-9-]{8,64}$') { throw 'operatorUids contains an invalid GUID.' }
    }
}

$ServerRoot = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
$SyntheticRoots = @(
    [IO.Path]::GetFullPath('C:\PED-Imouto-Activation-Test').TrimEnd('\'),
    [IO.Path]::GetFullPath('C:\PED-Imouto-Installer-Test').TrimEnd('\')
)
$SyntheticRootAccepted = @($SyntheticRoots | Where-Object {
    $ServerRoot.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase)
}).Count -eq 1
if ($SyntheticTestFixture -and -not $SyntheticRootAccepted) {
    throw 'SyntheticTestFixture is restricted to a canonical descendant of a disposable PED test root.'
}
if ($SyntheticExpectedUe4ssDllSha256) {
    if (-not $SyntheticTestFixture -or $SyntheticExpectedUe4ssDllSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'SyntheticExpectedUe4ssDllSha256 is restricted to a disposable synthetic fixture.'
    }
    $ExpectedUe4ssDllSha256 = $SyntheticExpectedUe4ssDllSha256
}
if ([Environment]::MachineName -ine 'IMOUTO' -and -not $SyntheticTestFixture) {
    throw 'This activation command must run locally on IMOUTO.'
}
if (-not $SyntheticTestFixture -and $ServerRoot -ine $CanonicalServerRoot) {
    throw "The activation target is fixed to $CanonicalServerRoot."
}

$SteamAppsRoot = Split-Path (Split-Path $ServerRoot -Parent) -Parent
$SteamManifestPath = Join-Path $SteamAppsRoot 'appmanifest_2394010.acf'
$DeploymentPath = Join-Path $ServerRoot 'PalEventDirectorDeployments\deployment.json'
$Ue4ssDllPath = Join-Path $ServerRoot 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
$DefaultConfigPath = Join-Path $ServerRoot 'Pal\Binaries\Win64\ue4ss\Mods\PalEventDirector\Scripts\config\default.json'
$DataDirectory = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector'
$ConfigPath = Join-Path $DataDirectory 'config.json'
$BackupRoot = Join-Path $ServerRoot 'PalEventDirectorLaboratoryActivationBackups'

foreach ($required in @($SteamManifestPath, $DeploymentPath, $Ue4ssDllPath, $DefaultConfigPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required activation file is missing: $required" }
}
$mutex = [Threading.Mutex]::new($false, 'Global\PalEventDirectorImoutoLifecycle')
$hasMutex = $false
try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { throw 'Another IMOUTO install, activation, launch, or world import is running.' }
Assert-ServerStopped -Root $ServerRoot
$manifestText = [IO.File]::ReadAllText($SteamManifestPath)
if ((Get-AcfValue $manifestText 'appid') -ne $ExpectedAppId) { throw 'Target is not Palworld Dedicated Server App ID 2394010.' }
$VerifiedBuildId = Get-AcfValue $manifestText 'buildid'
if ($VerifiedBuildId -ne $ExpectedBuildId) { throw "Laboratory activation requires verified server build $ExpectedBuildId." }

$deployment = Get-Content $DeploymentPath -Raw | ConvertFrom-Json
if ($deployment.schemaVersion -ne 1 -or [string]$deployment.packageName -ne 'PalEventDirector' -or
    [string]$deployment.deliveryProfile -ne 'preflight-diagnostic-only' -or
    [string]$deployment.serverBuildId -ne $VerifiedBuildId -or [string]$deployment.ue4ssApiVersion -ne $ExpectedUe4ssApiVersion -or
    [string]$deployment.ue4ssDllSha256 -ine $ExpectedUe4ssDllSha256 -or
    (Get-FileHash $Ue4ssDllPath -Algorithm SHA256).Hash -ine $ExpectedUe4ssDllSha256) {
    throw 'Deployment does not match the validated Palworld/UE4SS laboratory contract.'
}
$ExpectedActivationPath = [IO.Path]::GetFullPath((Join-Path $ServerRoot 'PalEventDirectorDeployments\Enable-PalEventDirectorLaboratory.ps1')).TrimEnd('\')
$CurrentActivationPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path).TrimEnd('\')
if ($deployment.laboratoryActivationConfigured -ne $true -or
    [string]$deployment.activationSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
    [IO.Path]::GetFullPath([string]$deployment.activationPath).TrimEnd('\') -ine $ExpectedActivationPath -or
    $CurrentActivationPath -ine $ExpectedActivationPath -or
    (Get-FileHash $CurrentActivationPath -Algorithm SHA256).Hash -ine [string]$deployment.activationSha256) {
    throw 'The installed laboratory activation command does not match deployment provenance.'
}

$configText = if (Test-Path $ConfigPath -PathType Leaf) {
    [IO.File]::ReadAllText($ConfigPath)
} else {
    [IO.File]::ReadAllText($DefaultConfigPath)
}
try { $config = $configText | ConvertFrom-Json }
catch { throw "PED configuration is invalid JSON: $($_.Exception.Message)" }
Assert-PedConfigSchema3 -Config $config
if ([string]$config.mode -ne 'laboratory') { throw 'Laboratory activation requires laboratory mode.' }

if (-not $PSCmdlet.ShouldProcess(
        $ConfigPath,
    "prepare read-only preflight diagnostics; disable every gameplay capability and recurring schedule")) {
    return
}

    Assert-ServerStopped -Root $ServerRoot
    New-Item -ItemType Directory -Path $DataDirectory, $BackupRoot -Force | Out-Null
    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        [IO.File]::WriteAllText($ConfigPath, $configText, [Text.UTF8Encoding]::new($false))
    }
    $backupPath = Join-Path $BackupRoot ('config-before-activation-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N') + '.json')
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -ErrorAction Stop

    $config.compatibility.allowedServerBuildIds = @($VerifiedBuildId)
    $config.compatibility.allowedUe4ssVersions = @($ExpectedUe4ssApiVersion)
    $config.siegeLeague.chatStartPolicy = $AuthorizationPolicy
    $config.capabilities.chatCommands = $false
    $config.capabilities.observeCombat = $false
    $config.capabilities.observeInvasions = $false
    $config.capabilities.startAllInvasions = $false
    $config.capabilities.substituteBountyMembers = $false
    $config.capabilities.grantItems = $false
    $config.diagnostics.traceHooks = $false
    $config.diagnostics.observationProbe = $false
    foreach ($schedule in (ConvertTo-FlatArray $config.schedules)) { $schedule.enabled = $false }

    $temporary = "$ConfigPath.activation.tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($config | ConvertTo-Json -Depth 30) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        $verified = Get-Content $temporary -Raw | ConvertFrom-Json
        Assert-PedConfigSchema3 -Config $verified
        $disabledCapabilities = @('chatCommands', 'observeCombat', 'observeInvasions', 'startAllInvasions', 'substituteBountyMembers', 'grantItems')
        foreach ($capability in $disabledCapabilities) {
            if ($verified.capabilities.$capability -ne $false) { throw "Diagnostic preparation failed to disable $capability." }
        }
        if ($verified.capabilities.grantItems -ne $false) { throw 'Activation must leave grantItems disabled.' }
        if (@(ConvertTo-FlatArray $verified.schedules | Where-Object { $_.enabled }).Count -ne 0) { throw 'Activation must leave all schedules disabled.' }
        if ([string]$verified.siegeLeague.chatStartPolicy -ne $AuthorizationPolicy) { throw 'Activation policy verification failed.' }
        Assert-ServerStopped -Root $ServerRoot
        Move-Item -LiteralPath $temporary -Destination $ConfigPath -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Status = 'PreflightDiagnosticsOnly'
        ServerBuildId = $VerifiedBuildId
        Ue4ssApiVersion = $ExpectedUe4ssApiVersion
        ConfigSchema = 3
        AuthorizationPolicy = $AuthorizationPolicy
        EnabledCapabilities = ''
        NativeStartsQuarantined = $true
        DiagnosticCommand = 'ped diagnose-preflight; then confirm-disposable-readonly with the exact previewed step'
        GrantItems = $false
        EnabledSchedules = 0
        MandatoryWarnings = '600,300,60'
        ConfigBackup = $backupPath
        RestartRequired = $true
    }
} finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
