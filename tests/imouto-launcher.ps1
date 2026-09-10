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

function Write-StartupTestFixtureOutcome {
    param([string]$Path, [object]$State)
    $raw = @{ schemaVersion=1; sequence=1; previousChecksum='00000000'; kind='startup_test_finished'; state=$State } | ConvertTo-Json -Depth 8 -Compress
    [long]$hash = 5381
    foreach ($value in [Text.Encoding]::UTF8.GetBytes('00000000' + $raw)) { $hash = ($hash * 33 + $value) % 2147483647 }
    $line = '{"checksum":"' + $hash.ToString('x8') + '",' + $raw.Substring(1)
    [IO.File]::WriteAllText((Join-Path (Split-Path $Path -Parent) 'journal.ndjson'), $line + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($Path, (@{payload=$State} | ConvertTo-Json -Depth 8))
}

try {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallerFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue

    $absent = New-LauncherFixture -Name 'absent' -ManifestBuildId '' -DeploymentBuildId '25080279'
    try {
        & $absent.Launcher -ServerRoot $absent.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Absent build ID unexpectedly passed launcher validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not contain a server build ID') { throw }
    }

    $mismatch = New-LauncherFixture -Name 'mismatch' -ManifestBuildId '25080279' -DeploymentBuildId '99999999'
    try {
        & $mismatch.Launcher -ServerRoot $mismatch.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Mismatched build ID unexpectedly passed launcher validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not match the verified Steam manifest') { throw }
    }

    $matching = New-LauncherFixture -Name 'matching' -ManifestBuildId '25080279' -DeploymentBuildId '25080279'
    $result = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -ValidateOnly
    if ($result.LaunchIntegrationReady -ne $true -or $result.ServerBuildId -ne '25080279' -or
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

    $installerMatching = New-LauncherFixture -Name 'matching' -ManifestBuildId '25080279' `
        -DeploymentBuildId '25080279' -Root $InstallerFixtureRoot
    $installerResult = & $installerMatching.Launcher -ServerRoot $installerMatching.ServerRoot `
        -SyntheticTestFixture -ValidateOnly
    if ($installerResult.LaunchIntegrationReady -ne $true) {
        throw 'Launcher rejected the confined installer integration fixture.'
    }

    $incomplete = New-LauncherFixture -Name 'incomplete' -ManifestBuildId '25080279' -DeploymentBuildId '25080279'
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

    $tampered = New-LauncherFixture -Name 'tampered' -ManifestBuildId '25080279' -DeploymentBuildId '25080279'
    [IO.File]::AppendAllText((Join-Path $tampered.ServerRoot 'PalServer.exe'), 'tampered')
    try {
        & $tampered.Launcher -ServerRoot $tampered.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Tampered root server launcher unexpectedly passed validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'server bytes no longer match') { throw }
    }

    $runtimeTampered = New-LauncherFixture -Name 'runtime-tampered' -ManifestBuildId '25080279' -DeploymentBuildId '25080279'
    [IO.File]::AppendAllText((Join-Path $runtimeTampered.ServerRoot 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'), 'tampered')
    try {
        & $runtimeTampered.Launcher -ServerRoot $runtimeTampered.ServerRoot -SyntheticTestFixture -ValidateOnly | Out-Null
        throw 'Tampered diagnostic runtime unexpectedly passed validation.'
    } catch {
        if ($_.Exception.Message -notmatch 'UE4SS runtime bytes/API') { throw }
    }

    $layoutTampered = New-LauncherFixture -Name 'layout-tampered' -ManifestBuildId '25080279' -DeploymentBuildId '25080279'
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
    startupTestRun = `$env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN
    sourceRevision = `$env:PAL_EVENT_DIRECTOR_SOURCE_REVISION
}
[IO.File]::WriteAllText('$($capturePath.Replace("'", "''"))', (`$record | ConvertTo-Json))
"@)
    $previousBuildId = $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID
    $previousDataDirectory = $env:PAL_EVENT_DIRECTOR_DATA_DIR
    $previousRuntimeTag = $env:PAL_EVENT_DIRECTOR_UE4SS_TAG
    $previousRuntimeApi = $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION
    $previousStartupTest = $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN
    $previousSourceRevision = $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION
    try {
        $env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = 'parent-build'
        $env:PAL_EVENT_DIRECTOR_DATA_DIR = 'parent-data'
        $env:PAL_EVENT_DIRECTOR_UE4SS_TAG = 'parent-tag'
        $env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = 'parent-api'
        $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN = 'parent-test'
        $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION = 'parent-source'
        $started = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript
        if ($started.Started -ne $true -or -not (Test-Path $capturePath)) { throw 'Synthetic child did not run.' }
        $captured = Get-Content $capturePath -Raw | ConvertFrom-Json
        if ($captured.buildId -ne '25080279' -or
            $captured.runtimeTag -ne '2281fa31' -or $captured.runtimeApi -ne '3.0.1' -or
            $captured.dataDirectory -ne (Join-Path $matching.ServerRoot 'Pal\Saved\PalEventDirector')) {
            throw 'Required launch variables did not reach the child process.'
        }
        if ($captured.startupTestRun -or $captured.sourceRevision -ne '1111111111111111111111111111111111111111') {
            throw 'Normal launch inherited a startup test or omitted source provenance.'
        }
        if ($env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN -ne 'parent-test' -or $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION -ne 'parent-source') {
            throw 'Launcher did not restore startup-test environment variables.'
        }
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest SpawnCleanup -ValidateOnly | Out-Null
        $testRoot = Join-Path $matching.ServerRoot 'Pal\Saved\PalEventDirector\startup-tests'
        if (Test-Path $testRoot) { throw 'ValidateOnly armed a mutation test.' }
        $testLaunch = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript -StartupTest SpawnCleanup
        $testCapture = Get-Content $capturePath -Raw | ConvertFrom-Json
        $testPlan = Get-Content (Join-Path $testLaunch.StartupTestDirectory 'plan.json') -Raw | ConvertFrom-Json
        if ($testCapture.startupTestRun -ne $testLaunch.StartupTestRunId -or $testPlan.case -ne 'spawn-cleanup' -or
            $testPlan.sourceRevision -ne $testCapture.sourceRevision) { throw 'Explicit startup test provenance did not reach the child.' }
        $testStatePath = Join-Path $testLaunch.StartupTestDirectory 'snapshot.json'
        $testState = @{ payload = @{ schemaVersion=1; runId=$testLaunch.StartupTestRunId; case='spawn-cleanup'; status='failed'; mutationStarted=$true;
            cleanupComplete=$false; sourceRevision=$testPlan.sourceRevision; artifactSha256=$testPlan.artifactSha256;
            spawned=1; cleaned=0; initialized=0; moved=0 } }
        Write-StartupTestFixtureOutcome $testStatePath $testState.payload
        [IO.File]::WriteAllText($testStatePath, '{"payload":{"cleanupComplete":true,"mutationStarted":false,"status":"passed"}}')
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest SpawnCleanup -ValidateOnly | Out-Null
            throw 'Uncertain startup entities unexpectedly allowed another test.'
        } catch {
            if ($_.Exception.Message -notmatch 'retains uncertain spawned entities') { throw }
        }
        $testState.payload.mutationStarted = $false
        $testState.payload.spawned = 0
        $testState.payload.cleanupComplete = $true
        $testState.payload.sourceRevision = '3333333333333333333333333333333333333333'
        Write-StartupTestFixtureOutcome $testStatePath $testState.payload
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest SpawnCleanup -ValidateOnly | Out-Null
            throw 'Failed startup test was retried on the same artifact.'
        } catch {
            if ($_.Exception.Message -notmatch 'Do not retry') { throw }
        }
        $testState.payload.status = 'passed'
        Write-StartupTestFixtureOutcome $testStatePath $testState.payload
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest Movement -ValidateOnly | Out-Null
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest SurfaceSurvey -ValidateOnly | Out-Null
        $surveyLaunch = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript -StartupTest SurfaceSurvey
        $surveyPlan = Get-Content (Join-Path $surveyLaunch.StartupTestDirectory 'plan.json') -Raw | ConvertFrom-Json
        if ($surveyPlan.case -ne 'surface-survey' -or $surveyPlan.previousRunId -ne $testLaunch.StartupTestRunId) {
            throw 'Surface survey plan did not preserve explicit case selection and prior outcome identity.'
        }
        $surveyState = @{ schemaVersion=1; runId=$surveyLaunch.StartupTestRunId; case='surface-survey'; status='passed'; mutationStarted=$false;
            cleanupComplete=$true; sourceRevision=$surveyPlan.sourceRevision; artifactSha256=$surveyPlan.artifactSha256;
            spawned=0; cleaned=0; initialized=0; moved=0 }
        Write-StartupTestFixtureOutcome (Join-Path $surveyLaunch.StartupTestDirectory 'snapshot.json') $surveyState
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest ShapeQualification -ValidateOnly | Out-Null
        $activeAfterValidate = Get-Content (Join-Path $testRoot 'active.json') -Raw | ConvertFrom-Json
        if ($activeAfterValidate.runId -ne $surveyLaunch.StartupTestRunId) { throw 'Shape validation armed a new experiment.' }
        $shapeLaunch = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript -StartupTest ShapeQualification
        $shapePlan = Get-Content (Join-Path $shapeLaunch.StartupTestDirectory 'plan.json') -Raw | ConvertFrom-Json
        if ($shapePlan.case -ne 'shape-qualification' -or $shapePlan.experiment -cne 'hunter-level30-one-instance-v1' -or
            $shapePlan.previousRunId -ne $surveyLaunch.StartupTestRunId -or $shapePlan.artifactSha256 -ne $surveyPlan.artifactSha256) {
            throw 'Shape qualification did not preserve the explicit experiment and artifact/run binding.'
        }
        $shapeState = @{ schemaVersion=1; runId=$shapeLaunch.StartupTestRunId; case='shape-qualification'; status='passed'; mutationStarted=$true;
            cleanupComplete=$true; sourceRevision=$shapePlan.sourceRevision; artifactSha256=$shapePlan.artifactSha256;
            experiment=$shapePlan.experiment; spawned=1; cleaned=1; initialized=1; moved=0; helpersCreated=1; helpersCleaned=1;
            shapeObservations=@(@{comparison='MATCH';instanceOnly=$true;spawnQualified=$false},@{comparison='MATCH';instanceOnly=$true;spawnQualified=$false}) }
        $shapeStatePath = Join-Path $shapeLaunch.StartupTestDirectory 'snapshot.json'
        Write-StartupTestFixtureOutcome $shapeStatePath $shapeState
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest ShapeQualification -ValidateOnly | Out-Null
        $shapeState.shapeObservations[1].comparison = 'MISMATCH'
        Write-StartupTestFixtureOutcome $shapeStatePath $shapeState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest ShapeQualification -ValidateOnly | Out-Null
            throw 'A fabricated shape pass was accepted.'
        } catch {
            if ($_.Exception.Message -notmatch 'shape evidence is not a qualification') { throw }
        }
        $shapeState.shapeObservations[1].comparison = 'MATCH'
        Write-StartupTestFixtureOutcome $shapeStatePath $shapeState
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest QualifiedEngagement -ValidateOnly | Out-Null
        $activeAfterValidate = Get-Content (Join-Path $testRoot 'active.json') -Raw | ConvertFrom-Json
        if ($activeAfterValidate.runId -ne $shapeLaunch.StartupTestRunId) { throw 'Qualified engagement validation armed a test.' }
        $qualifiedLaunch = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript -StartupTest QualifiedEngagement -StartupTestBaseIndex 2
        $qualifiedPlan = Get-Content (Join-Path $qualifiedLaunch.StartupTestDirectory 'plan.json') -Raw | ConvertFrom-Json
        if ($qualifiedPlan.case -cne 'qualified-engagement' -or $qualifiedPlan.experiment -cne 'hunter-level30-qualified-engagement-v1' -or
            $qualifiedPlan.baseOrdinal -ne 2 -or $qualifiedLaunch.StartupTestBaseIndex -ne 2 -or
            $qualifiedPlan.previousRunId -cne $shapeLaunch.StartupTestRunId -or $qualifiedPlan.runId -ceq $shapeLaunch.StartupTestRunId) {
            throw 'Qualified engagement reused a shape run or omitted its distinct contract.'
        }
        $qualifiedState = @{schemaVersion=1;runId=$qualifiedPlan.runId;case=$qualifiedPlan.case;experiment=$qualifiedPlan.experiment;
            status='passed';mutationStarted=$true;cleanupComplete=$true;sourceRevision=$qualifiedPlan.sourceRevision;
            artifactSha256=$qualifiedPlan.artifactSha256;spawned=1;initialized=1;cleaned=1;moved=0;helpersCreated=1;helpersCleaned=1;
            qualifiedEngagementArmed=$true;dealtDamageEvents=1;dealtDamage=1;members=@(@{baseId='fixture-base';actorAddress='fixture-actor'});
            shapeObservations=@()}
        $qualifiedState.engagementAuthorization = @{armed=$true;runId=$qualifiedPlan.runId;case=$qualifiedPlan.case;
            experiment=$qualifiedPlan.experiment;artifactSha256=$qualifiedPlan.artifactSha256;memberIndex=1;samples=2;
            baseId='fixture-base';actorAddress='fixture-actor'}
        foreach ($sample in @(1,2)) {
            $qualifiedState.shapeObservations += @{comparison='MATCH';instanceOnly=$true;spawnQualified=$false;
                receipt=@{sample=$sample;runId=$qualifiedPlan.runId;case=$qualifiedPlan.case;experiment=$qualifiedPlan.experiment;
                    artifactSha256=$qualifiedPlan.artifactSha256;memberIndex=1;actorAddress='fixture-actor'}}
        }
        $qualifiedStatePath = Join-Path $qualifiedLaunch.StartupTestDirectory 'snapshot.json'
        Write-StartupTestFixtureOutcome $qualifiedStatePath $qualifiedState
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest QualifiedEngagement -ValidateOnly | Out-Null
        $qualifiedState.dealtDamageEvents = 0
        Write-StartupTestFixtureOutcome $qualifiedStatePath $qualifiedState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest QualifiedEngagement -ValidateOnly | Out-Null
            throw 'A damage-free qualified engagement pass was accepted.'
        } catch {
            if ($_.Exception.Message -notmatch 'requires observed outgoing damage') { throw }
        }
        $qualifiedState.dealtDamageEvents = 1
        Write-StartupTestFixtureOutcome $qualifiedStatePath $qualifiedState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -StartupTestRequirePlayer -ValidateOnly | Out-Null
            throw 'Player-present launch accepted an unspecified base.'
        } catch {
            if ($_.Exception.Message -notmatch 'explicit base index') { throw }
        }
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -StartupTestBaseIndex 3 -StartupTestRequirePlayer -ValidateOnly | Out-Null
        $activeAfterValidate = Get-Content (Join-Path $testRoot 'active.json') -Raw | ConvertFrom-Json
        if ($activeAfterValidate.runId -cne $qualifiedLaunch.StartupTestRunId) { throw 'Cadence validation armed a test.' }
        $cadenceLaunch = & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -SyntheticChildScript $childScript -StartupTest CadencedEngagement -StartupTestBaseIndex 3 -StartupTestRequirePlayer
        $cadencePlan = Get-Content (Join-Path $cadenceLaunch.StartupTestDirectory 'plan.json') -Raw | ConvertFrom-Json
        if ($cadencePlan.case -cne 'cadenced-engagement' -or $cadencePlan.experiment -cne 'hunter-level30-network-sphere-cadence-v1' -or
            $cadencePlan.capturePolicy -cne 'stock-networked-spheres-only-v1' -or $cadencePlan.cadenceSeconds -ne 0.1 -or
            $cadencePlan.requirePlayerAtBase -ne $true -or $cadencePlan.baseOrdinal -ne 3 -or $cadenceLaunch.StartupTestRequirePlayer -ne $true) {
            throw 'Cadence launch omitted its restricted capture policy or fixed interval.'
        }
        $cadenceState = @{schemaVersion=1;runId=$cadencePlan.runId;case=$cadencePlan.case;experiment=$cadencePlan.experiment;
            requirePlayerAtBase=$true;baseOrdinal=3;
            capturePolicy=$cadencePlan.capturePolicy;cadenceSeconds=$cadencePlan.cadenceSeconds;status='blocked';mutationStarted=$true;
            cleanupComplete=$true;sourceRevision=$cadencePlan.sourceRevision;artifactSha256=$cadencePlan.artifactSha256;
            spawned=1;initialized=1;cleaned=1;moved=0;helpersCreated=1;helpersCleaned=1;
            cadence=@{status='UNRESOLVED';active=$false;retired=$true}}
        $cadenceStatePath = Join-Path $cadenceLaunch.StartupTestDirectory 'snapshot.json'
        Write-StartupTestFixtureOutcome $cadenceStatePath $cadenceState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -ValidateOnly | Out-Null
            throw 'An unresolved cadence lease was accepted as cleaned.'
        } catch {
            if ($_.Exception.Message -notmatch 'Cadence lease cleanup is unresolved') { throw }
        }
        $cadenceState.cadence.runtimeDisposition = 'WORLD_FINALIZED'
        $cadenceState.cadence.worldFinalizationVerified = $true
        Write-StartupTestFixtureOutcome $cadenceStatePath $cadenceState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -ValidateOnly | Out-Null
            throw 'Unpinned world finalization was accepted.'
        } catch {
            if ($_.Exception.Message -notmatch 'world finalization evidence is invalid') { throw }
        }
        $worldRunId = '20260909-221539-b5664f1858dd4afcab2f296570f197e1'
        $worldDirectory = Join-Path $testRoot $worldRunId
        New-Item -ItemType Directory -Path $worldDirectory -ErrorAction Stop | Out-Null
        $worldStatePath = Join-Path $worldDirectory 'snapshot.json'
        $cadenceState.runId = $worldRunId
        $cadenceState.sourceRevision = '29bea671d8cafc3588fa1c12bcf7c0ecbee0db48'
        $cadenceState.artifactSha256 = 'd3b4a9b6628189cbfa0545e6ca4ce593fedfa19265e708e645695aa2e79cf274'
        $cadenceState.failedArtifactSha256 = $cadenceState.artifactSha256
        $cadenceState.code = 'cadence-world-finalized'
        $cadenceState.cleaned = 0
        $cadenceState.helpersCleaned = 0
        $cadenceState.npcsFinalized = 1
        $cadenceState.helpersFinalized = 1
        $cadenceState.finalization = @{
            runId=$worldRunId;oldRootPid=14328;nativeCalls=0
            processExitVerified=$true;installationProcessTreeEmpty=$true;instanceOnlyLeaseVerified=$true
            noReplay=$true;preserveSavedTransfers=$true;noExternalReapply=$true
            certificateSha256='45a3328ee826697958f997f26356953ad469eabfb2eb34e1fbe25222427455ae'
            journalSha256='0d92fee98b9bfd3adbebccf143a2cd44bc05cb87ec97e6eb7dcbad5a2736aa1b'
            snapshotSha256='a5610801008d136212a48aa75e4781f8e56122eb0bc0b65988339326fac7768c'
            evidenceManifestSha256='82a0f705074dde66b8c73e32d54c03afef1a774f0f720831add56f39ad1defb3'
            breadcrumbsSha256='5192e3d3378d6fc205edb15b510e2c1774d644e7866608deb6f2b4e021c7aad1'
            missingAfterStep='1788992144-2197-start-projectile-creation-observation'
            serverExecutableSha256='61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02'
            serverPakSha256='2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe'
        }
        Write-StartupTestFixtureOutcome $worldStatePath $cadenceState
        [IO.File]::WriteAllText((Join-Path $testRoot 'active.json'), (@{runId=$worldRunId} | ConvertTo-Json))
        & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -ValidateOnly | Out-Null
        $cadenceState.cadence.restorationVerified = $true
        Write-StartupTestFixtureOutcome $worldStatePath $cadenceState
        try {
            & $matching.Launcher -ServerRoot $matching.ServerRoot -SyntheticTestFixture -StartupTest CadencedEngagement -ValidateOnly | Out-Null
            throw 'World finalization claimed live restoration.'
        } catch {
            if ($_.Exception.Message -notmatch 'cannot claim live restoration or disposal') { throw }
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
        $env:PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN = $previousStartupTest
        $env:PAL_EVENT_DIRECTOR_SOURCE_REVISION = $previousSourceRevision
    }

    Write-Output 'PASS IMOUTO launcher rejects absent/mismatched IDs and passes verified variables only to the child process'
} finally {
    Remove-Item $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallerFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
