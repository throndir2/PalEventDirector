[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$ServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer',
    [switch]$ReplaceExistingSeed,

    [Parameter(DontShow)]
    [switch]$SyntheticTestFixture,

    [Parameter(DontShow)]
    [ValidateSet('', 'savegames_archived', 'event_state_archived', 'seed_installed', 'world_selected')]
    [string]$SyntheticFailAfter = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$CanonicalServerRoot = 'D:\SteamLibrary\steamapps\common\PalServer'
$ExpectedAppId = '2394010'
$ExpectedBuildId = '24575149'
$ExpectedExeHash = '6be7c3f4d4762b70990e4b7f919016ba4ef8584552950e749c37d40502b1a115'
$ExpectedPakHash = 'bffab47cbd3b3c6d14d616376d4e0b060b2429a5eb4c2022820d4f38d36a0770'
$SeedManifestPath = Join-Path $PSScriptRoot 'world-seed-manifest.json'
$BundleManifestPath = Join-Path $PSScriptRoot 'bundle.json'
$ImporterSourcePath = $MyInvocation.MyCommand.Path

function Get-AcfValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, '"' + [regex]::Escape($Name) + '"\s+"(?<Value>[^"]*)"')
    if ($match.Success) { $match.Groups['Value'].Value }
}

function Assert-ServerStopped {
    param([string]$Root)
    $serverNames = @('PalServer.exe', 'PalServer-Win64-Shipping-Cmd.exe', 'PalServer-Win64-Test-Cmd.exe')
    foreach ($process in @(Get-CimInstance Win32_Process)) {
        if ($process.Name -in $serverNames -and -not $process.ExecutablePath) {
            throw "Cannot establish the path for Palworld server PID $($process.ProcessId); refusing import."
        }
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Stop every process under the IMOUTO dedicated-server root before importing (PID $($process.ProcessId))."
        }
    }
}

function Assert-NoReparsePath {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    $current = $root
    foreach ($component in $fullPath.Substring($root.Length).Split(@('\'), [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $component
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point in mutable path: $current"
            }
        }
    }
}

function Assert-NoReparseTree {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Assert-NoReparsePath -Path $Path
    $reparse = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    } | Select-Object -First 1)
    if ($reparse.Count -gt 0) { throw "Refusing reparse point inside mutable tree: $($reparse[0].FullName)" }
}

function Get-FileInventory {
    param([string]$Root)
    $result = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Force -Recurse | Sort-Object FullName)) {
        $result += [pscustomobject]@{
            relativePath = $file.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
            length = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $result
}

function Assert-InventoriesEqual {
    param([object[]]$Expected, [object[]]$Actual)
    $left = @($Expected | Sort-Object relativePath)
    $right = @($Actual | Sort-Object relativePath)
    if ($left.Count -ne $right.Count) { throw "Save inventory count mismatch: expected $($left.Count), found $($right.Count)." }
    for ($index = 0; $index -lt $left.Count; $index++) {
        if ($left[$index].relativePath -cne $right[$index].relativePath -or
            [long]$left[$index].length -ne [long]$right[$index].length -or
            [string]$left[$index].sha256 -ine [string]$right[$index].sha256) {
            throw "Save inventory mismatch at $($left[$index].relativePath)."
        }
    }
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value)
    $directory = Split-Path $Path -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ('.' + (Split-Path $Path -Leaf) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) {
            $replaceBackup = $temporary + '.bak'
            try { [IO.File]::Replace($temporary, $Path, $replaceBackup, $true) }
            finally { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
        } else {
            Move-Item -LiteralPath $temporary -Destination $Path -ErrorAction Stop
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-TextEncoding {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [pscustomobject]@{ Encoding = [Text.UTF8Encoding]::new($true, $true); Offset = 3 }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [pscustomobject]@{ Encoding = [Text.UnicodeEncoding]::new($false, $true, $true); Offset = 2 }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [pscustomobject]@{ Encoding = [Text.UnicodeEncoding]::new($true, $true, $true); Offset = 2 }
    }
    [pscustomobject]@{ Encoding = [Text.UTF8Encoding]::new($false, $true); Offset = 0 }
}

function Set-DedicatedServerNameAtomic {
    param([string]$Path, [string]$WorldId)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $format = Get-TextEncoding -Bytes $bytes
    try { $text = $format.Encoding.GetString($bytes, $format.Offset, $bytes.Length - $format.Offset) }
    catch { throw 'GameUserSettings.ini is not valid UTF-8/UTF-16 and was not changed.' }
    $pattern = '(?m)^(DedicatedServerName=)[^\r\n]*'
    if ([regex]::Matches($text, $pattern).Count -ne 1) { throw 'GameUserSettings.ini must contain exactly one DedicatedServerName entry.' }
    $updated = [regex]::Replace($text, $pattern, '${1}' + $WorldId)
    $payload = $format.Encoding.GetBytes($updated)
    if ($format.Offset -gt 0) { $payload = $format.Encoding.GetPreamble() + $payload }

    $directory = Split-Path $Path -Parent
    $temporary = Join-Path $directory ('.GameUserSettings.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $replaceBackup = $temporary + '.bak'
    try {
        [IO.File]::WriteAllBytes($temporary, $payload)
        $verification = [IO.File]::ReadAllText($temporary, $format.Encoding)
        if (-not [regex]::IsMatch($verification, '(?m)^DedicatedServerName=' + [regex]::Escape($WorldId) + '\r?$')) {
            throw 'Staged GameUserSettings.ini did not retain the imported world ID.'
        }
        [IO.File]::Replace($temporary, $Path, $replaceBackup, $true)
    } catch {
        if (-not (Test-Path -LiteralPath $Path) -and (Test-Path -LiteralPath $replaceBackup)) {
            Move-Item -LiteralPath $replaceBackup -Destination $Path -Force
        }
        throw
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
    }
}

$ServerRoot = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
$SyntheticRoot = [IO.Path]::GetFullPath('C:\PED-Imouto-World-Test').TrimEnd('\')
if ($SyntheticTestFixture -and -not $ServerRoot.StartsWith($SyntheticRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SyntheticTestFixture is restricted to a canonical descendant of the disposable world-import test root.'
}
if ($SyntheticFailAfter -and -not $SyntheticTestFixture) { throw 'SyntheticFailAfter is available only in a disposable synthetic fixture.' }
if ([Environment]::MachineName -ine 'IMOUTO' -and -not $SyntheticTestFixture) { throw 'This world importer must run locally on IMOUTO.' }
if (-not $SyntheticTestFixture -and $ServerRoot -ine $CanonicalServerRoot) {
    throw "The production-mode target is fixed to $CanonicalServerRoot."
}
if ($ServerRoot.StartsWith('\\') -or $ServerRoot.StartsWith('\\?\') -or $ServerRoot.StartsWith('\\.\')) {
    throw 'ServerRoot must be a local fixed-drive path on IMOUTO.'
}

if ([IO.Path]::GetFileName($ServerRoot) -ine 'PalServer') { throw 'ServerRoot must end in PalServer; the Palworld client is never a valid target.' }
if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($ServerRoot)).DriveType -ne [IO.DriveType]::Fixed) { throw 'ServerRoot must be on a local fixed drive.' }

$SteamAppsRoot = Split-Path (Split-Path $ServerRoot -Parent) -Parent
$ClientRoot = Join-Path (Split-Path $ServerRoot -Parent) 'Palworld'
$SteamManifest = Join-Path $SteamAppsRoot 'appmanifest_2394010.acf'
$ServerExe = Join-Path $ServerRoot 'Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe'
$ServerPak = Join-Path $ServerRoot 'Pal\Content\Paks\Pal-WindowsServer.pak'
$SavedRoot = Join-Path $ServerRoot 'Pal\Saved'
$TargetSaveGames = Join-Path $SavedRoot 'SaveGames'
$ConfigRoot = Join-Path $SavedRoot 'Config\WindowsServer'
$GameUserSettings = Join-Path $ConfigRoot 'GameUserSettings.ini'
$PalWorldSettings = Join-Path $ConfigRoot 'PalWorldSettings.ini'
$EventData = Join-Path $SavedRoot 'PalEventDirector'
$ImportRecordRoot = Join-Path $ServerRoot 'PalworldWorldSeedImports'
$CurrentRecord = Join-Path $ImportRecordRoot 'current.json'
$PendingRecord = Join-Path $ImportRecordRoot 'pending.json'

if ($ServerRoot -ieq $ClientRoot -or $ServerRoot.StartsWith($ClientRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to import into the Palworld client.' }
foreach ($required in @($SteamManifest, $ServerExe, $ServerPak, $GameUserSettings, $PalWorldSettings, $SeedManifestPath, $BundleManifestPath, $ImporterSourcePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required import file is missing: $required" }
}
$acf = [IO.File]::ReadAllText($SteamManifest)
if ((Get-AcfValue $acf 'appid') -ne $ExpectedAppId) { throw 'Target is not Palworld Dedicated Server App ID 2394010.' }
if ((Get-AcfValue $acf 'buildid') -ne $ExpectedBuildId) { throw "Target is not validated build $ExpectedBuildId." }
if ((Get-FileHash $ServerExe -Algorithm SHA256).Hash -ine $ExpectedExeHash) { throw 'Dedicated-server executable hash is unvalidated.' }
if ((Get-FileHash $ServerPak -Algorithm SHA256).Hash -ine $ExpectedPakHash) { throw 'Dedicated-server pak hash is unvalidated.' }

$manifest = Get-Content -LiteralPath $SeedManifestPath -Raw | ConvertFrom-Json
$bundle = Get-Content -LiteralPath $BundleManifestPath -Raw | ConvertFrom-Json
$BundleManifestHash = (Get-FileHash $BundleManifestPath -Algorithm SHA256).Hash
if ($manifest.schemaVersion -ne 1 -or [string]$manifest.sourceSnapshot -notmatch '^daily_\d{4}-\d{2}-\d{2}_\d{6}$' -or
    [string]$manifest.worldId -notmatch '^[A-Fa-f0-9]{32}$' -or [string]$manifest.archive -ne 'world-seed.zip' -or
    [string]$manifest.archiveSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$manifest.sourceRevision -notmatch '^[A-Fa-f0-9]{40}$') {
    throw 'World-seed manifest identity is invalid.'
}
if ($bundle.schemaVersion -ne 1 -or [string]$bundle.type -ne 'PalEventDirectorImoutoWorldSeed' -or
    [string]$bundle.sourceSnapshot -ne [string]$manifest.sourceSnapshot -or
    [string]$bundle.sourceRevision -ne [string]$manifest.sourceRevision -or
    [string]$bundle.worldSeedManifestSha256 -ine (Get-FileHash $SeedManifestPath -Algorithm SHA256).Hash -or
    [string]$bundle.worldSeedArchiveSha256 -ine [string]$manifest.archiveSha256 -or
    [string]$bundle.importer -ne (Split-Path $ImporterSourcePath -Leaf) -or
    [string]$bundle.importerSha256 -ine (Get-FileHash $ImporterSourcePath -Algorithm SHA256).Hash) {
    throw 'World-seed bundle provenance is invalid.'
}
$WorldId = ([string]$manifest.worldId).ToUpperInvariant()
$SeedArchivePath = Join-Path $PSScriptRoot ([string]$manifest.archive)
if (-not (Test-Path $SeedArchivePath -PathType Leaf)) { throw "World-seed archive is missing: $SeedArchivePath" }
if ((Get-FileHash $SeedArchivePath -Algorithm SHA256).Hash -ine [string]$manifest.archiveSha256) { throw 'World-seed archive hash does not match its manifest.' }
$ExpectedInventory = @($manifest.files | ForEach-Object { $_ })
if ($ExpectedInventory.Count -ne [int]$manifest.fileCount -or $ExpectedInventory.Count -lt 3) { throw 'World-seed manifest file count is invalid.' }
$pathSet = @{}
$prefix = "SaveGames/0/$WorldId/"
foreach ($file in $ExpectedInventory) {
    $relative = [string]$file.relativePath
    $suffix = if ($relative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $relative.Substring($prefix.Length) } else { '' }
    if (-not $relative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $relative.Contains('..') -or
        $relative.Contains(':') -or $relative.Contains('\') -or $relative -match '(?i)(?:^|/)backup/' -or
        $relative -match '(?i)\.(?:ini|json|cfg|xml|pem|key|txt)$' -or [string]$file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [long]$file.length -lt 1 -or $pathSet.ContainsKey($relative.ToLowerInvariant()) -or
        ($suffix -notin @('Level.sav', 'LevelMeta.sav') -and $suffix -notmatch '^Players/[A-Fa-f0-9]{32}(?:_dps)?\.sav$')) {
        throw "Unsafe or duplicate world-seed inventory path: $relative"
    }
    $pathSet[$relative.ToLowerInvariant()] = $true
}
$InventoryBytes = ($ExpectedInventory | Measure-Object length -Sum).Sum
if ([long]$InventoryBytes -ne [long]$manifest.activeBytes) { throw 'World-seed manifest byte total is invalid.' }
if (-not $pathSet.ContainsKey(($prefix + 'Level.sav').ToLowerInvariant()) -or
    -not $pathSet.ContainsKey(($prefix + 'LevelMeta.sav').ToLowerInvariant())) { throw 'World-seed manifest lacks level files.' }
$PrimaryCharacterCount = @($ExpectedInventory | Where-Object { $_.relativePath -match ('^' + [regex]::Escape($prefix) + 'Players/[A-Fa-f0-9]{32}\.sav$') }).Count
$PlayerSidecarCount = @($ExpectedInventory | Where-Object { $_.relativePath -match ('^' + [regex]::Escape($prefix) + 'Players/[A-Fa-f0-9]{32}_dps\.sav$') }).Count
if ($PrimaryCharacterCount -ne [int]$manifest.primaryCharacterCount -or $PrimaryCharacterCount -lt 1 -or
    $PlayerSidecarCount -ne [int]$manifest.playerSidecarCount) { throw 'World-seed player inventory is invalid.' }

$override = [Environment]::GetEnvironmentVariable('PAL_EVENT_DIRECTOR_DATA_DIR')
if ($override -and [IO.Path]::GetFullPath($override).TrimEnd('\') -ine $EventData) {
    throw 'PAL_EVENT_DIRECTOR_DATA_DIR points outside the default IMOUTO event-state directory; refusing stale-state import.'
}
foreach ($path in @($ServerRoot, $SavedRoot, $ConfigRoot, $GameUserSettings, $TargetSaveGames, $EventData, $ImportRecordRoot)) { Assert-NoReparsePath -Path $path }
foreach ($path in @($TargetSaveGames, $EventData, $ImportRecordRoot)) { Assert-NoReparseTree -Path $path }
Assert-ServerStopped -Root $ServerRoot
if (Test-Path $PendingRecord) { throw "An interrupted world import requires manual recovery before retrying: $PendingRecord" }
if ((Test-Path $CurrentRecord) -and -not $ReplaceExistingSeed) { throw 'A Production world seed was already imported. Use ReplaceExistingSeed only for a deliberate newer refresh.' }
if (Test-Path $CurrentRecord) {
    $current = Get-Content $CurrentRecord -Raw | ConvertFrom-Json
    if ([string]$current.sourceSnapshot -ge [string]$manifest.sourceSnapshot) { throw 'The bundled world seed is not newer than the currently imported snapshot.' }
}

$summary = "$PrimaryCharacterCount primary characters, $PlayerSidecarCount player sidecars, $($ExpectedInventory.Count) active files, snapshot $($manifest.sourceSnapshot)"
if (-not $PSCmdlet.ShouldProcess($ServerRoot, "replace the disposable IMOUTO world from immutable MIKO seed ($summary); preserve IMOUTO settings")) { return }

$Mutex = [Threading.Mutex]::new($false, 'Global\PalEventDirectorImoutoLifecycle')
$HasMutex = $false
$TransactionId = [Guid]::NewGuid().ToString('N')
$Stage = Join-Path $SavedRoot ('.ped-world-stage-' + $TransactionId)
$LocalSeedArchive = Join-Path $Stage 'world-seed.zip'
$LocalSeedManifest = Join-Path $Stage 'world-seed-manifest.json'
$LocalBundleManifest = Join-Path $Stage 'bundle.json'
$LocalImporter = Join-Path $Stage 'Import-MikoProductionWorldImouto.ps1'
$ExtractRoot = Join-Path $Stage 'extract'
$StagedSaveGames = Join-Path $ExtractRoot 'SaveGames'
$StagedWorld = Join-Path $StagedSaveGames ('0\' + $WorldId)
$Backup = Join-Path $ServerRoot ('PalworldWorldSeedBackups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $TransactionId)
$HadSaveGames = $false
$HadEventData = $false
$HadCurrentRecord = $false
$SaveGamesMoved = $false
$EventDataMoved = $false
$NewSaveGamesInstalled = $false
$NewEventDataCreated = $false
$CurrentRecordWritten = $false
$MutationStarted = $false
$OriginalError = $null
$PalWorldSettingsHash = (Get-FileHash $PalWorldSettings -Algorithm SHA256).Hash
$EventConfigHash = $null

try {
    $HasMutex = $Mutex.WaitOne(0)
    if (-not $HasMutex) { throw 'Another IMOUTO world import is already running.' }
    Assert-ServerStopped -Root $ServerRoot
    if (Test-Path $PendingRecord) { throw "An interrupted world import requires manual recovery: $PendingRecord" }
    if ((Test-Path $CurrentRecord) -and -not $ReplaceExistingSeed) { throw 'A Production world seed was already imported.' }
    if (Test-Path $CurrentRecord) {
        $latestCurrent = Get-Content $CurrentRecord -Raw | ConvertFrom-Json
        if ([string]$latestCurrent.sourceSnapshot -ge [string]$manifest.sourceSnapshot) { throw 'The bundled world seed is not newer than the imported snapshot.' }
    }

    $HadSaveGames = Test-Path $TargetSaveGames
    $HadEventData = Test-Path $EventData
    $HadCurrentRecord = Test-Path $CurrentRecord
    if ($HadEventData -and (Test-Path (Join-Path $EventData 'config.json') -PathType Leaf)) {
        $EventConfigHash = (Get-FileHash (Join-Path $EventData 'config.json') -Algorithm SHA256).Hash
    }

    New-Item -ItemType Directory -Path $Stage -ErrorAction Stop | Out-Null
    Assert-NoReparsePath -Path $Stage
    Copy-Item -LiteralPath $SeedArchivePath -Destination $LocalSeedArchive -ErrorAction Stop
    Copy-Item -LiteralPath $SeedManifestPath -Destination $LocalSeedManifest -ErrorAction Stop
    Copy-Item -LiteralPath $BundleManifestPath -Destination $LocalBundleManifest -ErrorAction Stop
    Copy-Item -LiteralPath $ImporterSourcePath -Destination $LocalImporter -ErrorAction Stop
    if ((Get-FileHash $LocalSeedArchive -Algorithm SHA256).Hash -ine [string]$manifest.archiveSha256 -or
        (Get-FileHash $LocalSeedManifest -Algorithm SHA256).Hash -ine [string]$bundle.worldSeedManifestSha256 -or
        (Get-FileHash $LocalImporter -Algorithm SHA256).Hash -ine [string]$bundle.importerSha256 -or
        (Get-FileHash $LocalBundleManifest -Algorithm SHA256).Hash -ine $BundleManifestHash) {
        throw 'Local world-seed snapshot differs from the verified bundle.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($LocalSeedArchive)
    try {
        $archiveFiles = @($archive.Entries | Where-Object { $_.Name -ne '' })
        if ($archiveFiles.Count -ne $ExpectedInventory.Count) { throw 'World-seed archive entry count differs from the manifest.' }
        $archiveEntrySet = @{}
        foreach ($entry in $archiveFiles) {
            $name = $entry.FullName.Replace('\', '/')
            $key = $name.ToLowerInvariant()
            if (-not $pathSet.ContainsKey($key) -or $archiveEntrySet.ContainsKey($key)) { throw "Unexpected or duplicate world-seed archive entry: $name" }
            $archiveEntrySet[$key] = $true
        }
    } finally { $archive.Dispose() }

    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null
    Expand-Archive -LiteralPath $LocalSeedArchive -DestinationPath $ExtractRoot
    if (-not (Test-Path $StagedWorld -PathType Container)) { throw 'Extracted world-seed directory is missing.' }
    $ActualInventory = @(Get-FileInventory -Root $ExtractRoot)
    Assert-InventoriesEqual -Expected $ExpectedInventory -Actual $ActualInventory
    if ((Get-Item (Join-Path $StagedWorld 'Level.sav')).Length -lt 1 -or
        (Get-Item (Join-Path $StagedWorld 'LevelMeta.sav')).Length -lt 1) { throw 'Extracted level files are empty.' }

    Assert-ServerStopped -Root $ServerRoot
    New-Item -ItemType Directory -Path $Backup -ErrorAction Stop | Out-Null
    Assert-NoReparsePath -Path $Backup
    Copy-Item -LiteralPath $GameUserSettings -Destination (Join-Path $Backup 'GameUserSettings.ini') -ErrorAction Stop
    if ($HadCurrentRecord) { Copy-Item -LiteralPath $CurrentRecord -Destination (Join-Path $Backup 'world-import.json') -ErrorAction Stop }
    $backupMetadata = [ordered]@{
        schemaVersion = 1
        transactionId = $TransactionId
        hadSaveGames = $HadSaveGames
        hadEventData = $HadEventData
        hadCurrentRecord = $HadCurrentRecord
        gameUserSettingsSha256 = (Get-FileHash $GameUserSettings -Algorithm SHA256).Hash.ToLowerInvariant()
        eventConfigSha256 = $EventConfigHash
    }
    Write-JsonAtomic -Path (Join-Path $Backup 'backup.json') -Value $backupMetadata

    $pending = [ordered]@{
        schemaVersion = 1
        transactionId = $TransactionId
        status = 'prepared'
        sourceSnapshot = [string]$manifest.sourceSnapshot
        worldId = $WorldId
        backupRoot = $Backup
        hadSaveGames = $HadSaveGames
        hadEventData = $HadEventData
        hadCurrentRecord = $HadCurrentRecord
        startedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    Write-JsonAtomic -Path $PendingRecord -Value $pending
    $MutationStarted = $true

    if ($HadSaveGames) {
        Assert-ServerStopped -Root $ServerRoot
        $pending.status = 'archiving_savegames'; Write-JsonAtomic -Path $PendingRecord -Value $pending
        Move-Item -LiteralPath $TargetSaveGames -Destination (Join-Path $Backup 'SaveGames') -ErrorAction Stop
        $SaveGamesMoved = $true
        $pending.status = 'savegames_archived'; Write-JsonAtomic -Path $PendingRecord -Value $pending
        if ($SyntheticFailAfter -eq 'savegames_archived') { throw 'synthetic failure after savegames_archived' }
    }
    if ($HadEventData) {
        Assert-ServerStopped -Root $ServerRoot
        $pending.status = 'archiving_event_state'; Write-JsonAtomic -Path $PendingRecord -Value $pending
        Move-Item -LiteralPath $EventData -Destination (Join-Path $Backup 'PalEventDirector') -ErrorAction Stop
        $EventDataMoved = $true
        $pending.status = 'event_state_archived'; Write-JsonAtomic -Path $PendingRecord -Value $pending
        if ($SyntheticFailAfter -eq 'event_state_archived') { throw 'synthetic failure after event_state_archived' }
    }

    Assert-ServerStopped -Root $ServerRoot
    $pending.status = 'installing_seed'; Write-JsonAtomic -Path $PendingRecord -Value $pending
    Move-Item -LiteralPath $StagedSaveGames -Destination $TargetSaveGames -ErrorAction Stop
    $NewSaveGamesInstalled = $true
    $pending.status = 'seed_installed'; Write-JsonAtomic -Path $PendingRecord -Value $pending
    if ($SyntheticFailAfter -eq 'seed_installed') { throw 'synthetic failure after seed_installed' }

    $pending.status = 'selecting_world'; Write-JsonAtomic -Path $PendingRecord -Value $pending
    Set-DedicatedServerNameAtomic -Path $GameUserSettings -WorldId $WorldId
    $pending.status = 'world_selected'; Write-JsonAtomic -Path $PendingRecord -Value $pending
    if ($SyntheticFailAfter -eq 'world_selected') { throw 'synthetic failure after world_selected' }

    if ($EventConfigHash) {
        New-Item -ItemType Directory -Path $EventData -ErrorAction Stop | Out-Null
        $NewEventDataCreated = $true
        Copy-Item -LiteralPath (Join-Path $Backup 'PalEventDirector\config.json') -Destination (Join-Path $EventData 'config.json') -ErrorAction Stop
        if ((Get-FileHash (Join-Path $EventData 'config.json') -Algorithm SHA256).Hash -ine $EventConfigHash) { throw 'Preserved Pal Event Director config failed verification.' }
    }
    if ((Get-FileHash $PalWorldSettings -Algorithm SHA256).Hash -ine $PalWorldSettingsHash) { throw 'IMOUTO PalWorldSettings.ini changed unexpectedly.' }
    Assert-InventoriesEqual -Expected $ExpectedInventory -Actual @(Get-FileInventory -Root $SavedRoot | Where-Object { $_.relativePath.StartsWith('SaveGames/', [StringComparison]::OrdinalIgnoreCase) })

    $record = [ordered]@{
        schemaVersion = 1
        transactionId = $TransactionId
        sourceSnapshot = [string]$manifest.sourceSnapshot
        sourceSnapshotLocalTime = [string]$manifest.sourceSnapshotLocalTime
        sourceBundleRevision = [string]$manifest.sourceRevision
        worldId = $WorldId
        primaryCharacterCount = $PrimaryCharacterCount
        playerSidecarCount = $PlayerSidecarCount
        activeFileCount = $ExpectedInventory.Count
        activeBytes = [long]$manifest.activeBytes
        importedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        previousImoutoDataBackup = $Backup
        copiedProductionConfig = $false
        resetEventRuntimeState = $HadEventData
    }
    Write-JsonAtomic -Path $CurrentRecord -Value $record
    $CurrentRecordWritten = $true
    Remove-Item -LiteralPath $PendingRecord -Force -ErrorAction Stop

    [pscustomobject]@{
        Status = 'Imported'
        SourceSnapshot = $record.sourceSnapshot
        SourceSnapshotLocalTime = $record.sourceSnapshotLocalTime
        WorldId = $WorldId
        PrimaryCharacterCount = $PrimaryCharacterCount
        PlayerSidecarCount = $PlayerSidecarCount
        ActiveBytes = $record.activeBytes
        ImoutoBackup = $Backup
        PalWorldSettingsPreserved = $true
        ProductionConfigCopied = $false
        ServerStarted = $false
    }
} catch {
    $OriginalError = $_
    if ($MutationStarted) {
        try {
            Assert-ServerStopped -Root $ServerRoot
            if ($CurrentRecordWritten -and (Test-Path $CurrentRecord)) { Remove-Item -LiteralPath $CurrentRecord -Force -ErrorAction Stop }
            if ($NewEventDataCreated -and (Test-Path $EventData)) { Remove-Item -LiteralPath $EventData -Recurse -Force -ErrorAction Stop }
            if ($NewSaveGamesInstalled -and (Test-Path $TargetSaveGames)) { Remove-Item -LiteralPath $TargetSaveGames -Recurse -Force -ErrorAction Stop }
            if ($SaveGamesMoved) {
                if (Test-Path $TargetSaveGames) { throw 'Cannot restore prior SaveGames because the destination is occupied.' }
                Move-Item -LiteralPath (Join-Path $Backup 'SaveGames') -Destination $TargetSaveGames -ErrorAction Stop
            }
            if ($EventDataMoved) {
                if (Test-Path $EventData) { throw 'Cannot restore prior Pal Event Director state because the destination is occupied.' }
                Move-Item -LiteralPath (Join-Path $Backup 'PalEventDirector') -Destination $EventData -ErrorAction Stop
            }
            Copy-Item -LiteralPath (Join-Path $Backup 'GameUserSettings.ini') -Destination $GameUserSettings -Force -ErrorAction Stop
            if (Test-Path $CurrentRecord) { Remove-Item -LiteralPath $CurrentRecord -Force -ErrorAction Stop }
            if ($HadCurrentRecord) {
                New-Item -ItemType Directory -Path $ImportRecordRoot -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $Backup 'world-import.json') -Destination $CurrentRecord -ErrorAction Stop
            }
            if (Test-Path $PendingRecord) { Remove-Item -LiteralPath $PendingRecord -Force -ErrorAction Stop }
        } catch {
            throw "World import failed ($($OriginalError.Exception.Message)) and rollback also failed ($($_.Exception.Message)). Keep IMOUTO stopped and recover from $Backup using pending transaction $PendingRecord."
        }
    }
    throw $OriginalError
} finally {
    if (Test-Path $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ($HasMutex) { $Mutex.ReleaseMutex() }
    $Mutex.Dispose()
}
