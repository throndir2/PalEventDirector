Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ActivationSource = Join-Path $RepositoryRoot 'operations\imouto\Enable-PalEventDirectorLaboratory.ps1'
$DefaultConfig = Join-Path $RepositoryRoot 'Scripts\config\default.json'
$FixtureRoot = 'C:\PED-Imouto-Activation-Test'
$ServerRoot = Join-Path $FixtureRoot 'case\steamapps\common\PalServer'
$SteamAppsRoot = Split-Path (Split-Path $ServerRoot -Parent) -Parent
$DeployRoot = Join-Path $ServerRoot 'PalEventDirectorDeployments'
$Activation = Join-Path $DeployRoot 'Enable-PalEventDirectorLaboratory.ps1'
$Ue4ssRoot = Join-Path $ServerRoot 'Pal\Binaries\Win64\ue4ss'
$InstalledConfigRoot = Join-Path $Ue4ssRoot 'Mods\PalEventDirector\Scripts\config'
$DataRoot = Join-Path $ServerRoot 'Pal\Saved\PalEventDirector'
$ConfigPath = Join-Path $DataRoot 'config.json'

try {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $DeployRoot, $Ue4ssRoot, $InstalledConfigRoot, $DataRoot -Force | Out-Null
    Copy-Item $ActivationSource $Activation
    Copy-Item $DefaultConfig (Join-Path $InstalledConfigRoot 'default.json')
    Copy-Item $DefaultConfig $ConfigPath
    [IO.File]::WriteAllText((Join-Path $Ue4ssRoot 'UE4SS.dll'), 'synthetic UE4SS 3.0.1')
    $ue4ssHash = (Get-FileHash (Join-Path $Ue4ssRoot 'UE4SS.dll') -Algorithm SHA256).Hash
    [IO.File]::WriteAllText(
        (Join-Path $SteamAppsRoot 'appmanifest_2394010.acf'),
        "`"AppState`"`r`n{`r`n`t`"appid`"`t`t`"2394010`"`r`n`t`"buildid`"`t`t`"24575149`"`r`n}`r`n")
    [IO.File]::WriteAllText(
        (Join-Path $DeployRoot 'deployment.json'),
        (@{
            schemaVersion = 1
            packageName = 'PalEventDirector'
            serverBuildId = '24575149'
            ue4ssApiVersion = '3.0.1'
            ue4ssDllSha256 = $ue4ssHash
            activationPath = $Activation
            activationSha256 = (Get-FileHash $Activation -Algorithm SHA256).Hash
            laboratoryActivationConfigured = $true
        } | ConvertTo-Json))

    $invalid = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $invalid.runtime.pollIntervalMs = 1
    [IO.File]::WriteAllText($ConfigPath, ($invalid | ConvertTo-Json -Depth 30))
    $invalidHash = (Get-FileHash $ConfigPath -Algorithm SHA256).Hash
    try {
        & $Activation `
            -ServerRoot $ServerRoot `
            -SyntheticTestFixture `
            -SyntheticExpectedUe4ssDllSha256 $ue4ssHash `
            -Confirm:$false | Out-Null
        throw 'Runtime-invalid config unexpectedly passed activation.'
    } catch {
        if ($_.Exception.Message -notmatch 'runtime.pollIntervalMs') { throw }
    }
    if ((Get-FileHash $ConfigPath -Algorithm SHA256).Hash -ne $invalidHash) {
        throw 'Rejected activation modified the invalid config.'
    }
    Copy-Item $DefaultConfig $ConfigPath -Force
    $invalidArray = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $invalidArray.siegeLeague.allowedProfiles = 'all-bounty'
    [IO.File]::WriteAllText($ConfigPath, ($invalidArray | ConvertTo-Json -Depth 30))
    $invalidArrayHash = (Get-FileHash $ConfigPath -Algorithm SHA256).Hash
    try {
        & $Activation `
            -ServerRoot $ServerRoot `
            -SyntheticTestFixture `
            -SyntheticExpectedUe4ssDllSha256 $ue4ssHash `
            -Confirm:$false | Out-Null
        throw 'Scalar allowedProfiles unexpectedly passed activation.'
    } catch {
        if ($_.Exception.Message -notmatch 'siegeLeague.allowedProfiles must be a JSON array') { throw }
    }
    if ((Get-FileHash $ConfigPath -Algorithm SHA256).Hash -ne $invalidArrayHash) {
        throw 'Rejected scalar-array activation modified config.'
    }
    Copy-Item $DefaultConfig $ConfigPath -Force

    $result = & $Activation `
        -ServerRoot $ServerRoot `
        -SyntheticTestFixture `
        -SyntheticExpectedUe4ssDllSha256 $ue4ssHash `
        -AuthorizationPolicy operatorOrPalworldAdmin `
        -Confirm:$false

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    foreach ($capability in @('chatCommands', 'observeCombat', 'observeInvasions', 'startAllInvasions', 'substituteBountyMembers')) {
        if ($config.capabilities.$capability -ne $true) { throw "Activation did not enable $capability." }
    }
    if ($config.capabilities.grantItems -ne $false) { throw 'Activation enabled grantItems.' }
    if (@($config.schedules | ForEach-Object { $_ } | Where-Object { $_.enabled }).Count -ne 0) { throw 'Activation enabled a schedule.' }
    if ($config.siegeLeague.chatStartPolicy -ne 'operatorOrPalworldAdmin') { throw 'Activation selected the wrong policy.' }
    $versions = @($config.compatibility.allowedUe4ssVersions | ForEach-Object { $_ })
    $builds = @($config.compatibility.allowedServerBuildIds | ForEach-Object { $_ })
    if ($versions.Count -ne 1 -or $versions[0] -ne '3.0.1' -or $builds.Count -ne 1 -or $builds[0] -ne '24575149') {
        throw 'Activation wrote the wrong compatibility allowlists.'
    }
    foreach ($schedule in @($config.schedules | ForEach-Object { $_ })) {
        $warnings = @($schedule.warningSeconds | ForEach-Object { [int]$_ })
        foreach ($required in @(600, 300, 60)) {
            if ($warnings -notcontains $required) { throw "Activation removed mandatory warning $required." }
        }
    }
    if ($result.RestartRequired -ne $true -or -not (Test-Path $result.ConfigBackup)) {
        throw 'Activation did not report restart/backup requirements.'
    }

    Write-Output 'PASS IMOUTO activation enables validated gameplay capabilities while preserving warnings and disabling grants/schedules'
} finally {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
