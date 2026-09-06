import { execFileSync, spawnSync } from 'node:child_process';
import { readFile, readdir, stat, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(import.meta.dirname, '..');
const failures = [];
const windowsPowerShellEnvironment = process.platform === 'win32' ? {
  ...process.env,
  PSModulePath: [
    path.join(process.env.USERPROFILE, 'Documents', 'WindowsPowerShell', 'Modules'),
    path.join(process.env.ProgramFiles, 'WindowsPowerShell', 'Modules'),
    path.join(process.env.SystemRoot, 'system32', 'WindowsPowerShell', 'v1.0', 'Modules'),
  ].join(path.delimiter),
} : process.env;
const required = [
  'Info.json',
  'Scripts/main.lua',
  'Scripts/config/default.json',
  'Scripts/ped/config.lua',
  'Scripts/ped/bounties.lua',
  'Scripts/ped/director.lua',
  'Scripts/ped/filesystem.lua',
  'Scripts/ped/json.lua',
  'Scripts/ped/logger.lua',
  'Scripts/ped/palworld.lua',
  'Scripts/ped/path.lua',
  'Scripts/ped/preflight_diagnostic.lua',
  'Scripts/ped/native_experiments.lua',
  'Scripts/ped/native_observer.lua',
  'Scripts/ped/diagnostic_ingress.lua',
  'Scripts/ped/rewards.lua',
  'Scripts/ped/scheduler.lua',
  'Scripts/ped/scoreboard.lua',
  'Scripts/ped/store.lua',
  'Scripts/ped/util.lua',
  'Scripts/ped/version.lua',
  'docs/13-admin-and-scheduling.md',
  'docs/14-imouto-dev-deployment.md',
  'operations/imouto/Install-PalEventDirectorImouto.ps1',
  'operations/imouto/Start-PalEventDirectorImouto.ps1',
  'operations/imouto/Enable-PalEventDirectorLaboratory.ps1',
  'operations/imouto/Import-MikoProductionWorldImouto.ps1',
  'tests/path_contract.lua',
  'tests/imouto-launcher.ps1',
  'tests/imouto-activation.ps1',
  'tests/imouto-preflight-command.ps1',
  'tests/imouto-runtime-replacement.ps1',
  'operations/imouto/Invoke-PalEventDirectorPreflight.ps1',
  'tools/verify-artifact.mjs',
  'tests/artifact-provenance.mjs',
  'tests/preflight-diagnostic.lua',
  'tests/admin-control.lua',
  'tests/native-probe-diagnostics.lua',
  'tests/native-experiments.lua',
  'tests/native-observer.lua',
  'tests/admin-native-policy.lua',
  'tests/march-lifecycle.lua',
  'tests/preflight-failfast.lua',
  'tests/preflight-failfast.mjs',
  'tests/preflight-property-binding.mjs',
  'tests/fname-binding.mjs',
  'docs/15-preflight-crash-diagnostics.md',
  'tools/build-imouto-bundle.mjs',
  'tools/build-imouto-world-seed.mjs',
];

async function exists(relative) {
  try {
    await stat(path.join(root, relative));
    return true;
  } catch {
    return false;
  }
}

async function walk(directory) {
  const output = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...await walk(absolute));
    else output.push(absolute);
  }
  return output;
}

for (const relative of required) {
  if (!await exists(relative)) failures.push(`missing required file: ${relative}`);
}

let info;
try {
  info = JSON.parse(await readFile(path.join(root, 'Info.json'), 'utf8'));
} catch (error) {
  failures.push(`Info.json is invalid: ${error.message}`);
}

if (info) {
  if (!/^[A-Za-z0-9]+$/.test(info.PackageName ?? '')) failures.push('PackageName must be strictly alphanumeric');
  if (info.PackageName !== 'PalEventDirector') failures.push('PackageName must remain PalEventDirector');
  if (!Array.isArray(info.Dependencies) || !info.Dependencies.includes('UE4SS')) failures.push('UE4SS dependency is required');
  if (!Array.isArray(info.InstallRule) || info.InstallRule.length !== 1) failures.push('exactly one server-only install rule is required');
  for (const rule of info.InstallRule ?? []) {
    if (rule.Type !== 'Lua' || rule.IsServer !== true) failures.push('the install rule must be server-only Lua');
    for (const target of rule.Targets ?? []) {
      if (path.isAbsolute(target) || target.includes('..')) failures.push(`unsafe install target: ${target}`);
      if (!await exists(target.replace(/^\.\//, ''))) failures.push(`missing install target: ${target}`);
    }
  }
}

const packageJson = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
if (info && packageJson.version !== info.Version) failures.push('package.json and Info.json versions differ');
const versionLua = await readFile(path.join(root, 'Scripts/ped/version.lua'), 'utf8');
if (info && !versionLua.includes(`version = "${info.Version}"`)) failures.push('Lua runtime and Info.json versions differ');
const deliveryProfile = versionLua.match(/delivery_profile\s*=\s*"([^"]+)"/)?.[1];
if (!['preflight-diagnostic-only', 'laboratory-native-test'].includes(deliveryProfile)) failures.push('unsupported Lua delivery profile');
const palworldAdapter = await readFile(path.join(root, 'Scripts/ped/palworld.lua'), 'utf8');
for (const requiredGuard of [
  'function Bridge:native_start_guard()',
  'Native starts are quarantined',
  'self.native_fault',
  'function Bridge:_native_step',
  'function Bridge:_world_invaders_enabled',
  'function Bridge:diagnose_preflight',
  'if not hooks_enabled then',
  'function(context, return_value, grade, biome, out_members)',
]) {
  if (!palworldAdapter.includes(requiredGuard)) failures.push(`Palworld adapter is missing required guard: ${requiredGuard}`);
}
if (/call\([^,\n]+,\s*["']GetOptionWorldSettings["']|:\s*GetOptionWorldSettings\s*\(/.test(palworldAdapter)) {
  failures.push('runtime adapter may not invoke the oversized by-value settings getter');
}
const directorSource = await readFile(path.join(root, 'Scripts/ped/director.lua'), 'utf8');
for (const requiredGuard of [
  'event_start_confirmed',
  'event_start_failed',
  'START FAILED',
  'confirmedBaseCount = 0',
]) {
  if (!directorSource.includes(requiredGuard)) failures.push(`Director is missing required lifecycle guard: ${requiredGuard}`);
}
const diagnosticSource = await readFile(path.join(root, 'Scripts/ped/preflight_diagnostic.lua'), 'utf8');
for (const requiredGuard of [
  'confirm-disposable-readonly',
  'self.getenv("COMPUTERNAME") ~= "IMOUTO"',
  'CALL_BUFFER_BYTES = 0x200',
  'self:_record("before"',
  'self:_record("after"',
  'GetOptionWorldSettings is blocked',
]) {
  if (!diagnosticSource.includes(requiredGuard)) failures.push(`Preflight diagnostic is missing required guard: ${requiredGuard}`);
}
if (/:\s*(?:StartInvader\w*|GetOptionWorldSettings|_dispatch_snapshot|list_online_players)\s*\(/.test(diagnosticSource)) {
  failures.push('Preflight diagnostic may not dispatch, materialize large world settings, or batch legacy preflight helpers');
}

const sourceFiles = (await walk(root)).filter((file) => !file.includes(`${path.sep}.git${path.sep}`) && !file.includes(`${path.sep}node_modules${path.sep}`) && !file.includes(`${path.sep}dist${path.sep}`));
if (sourceFiles.some((file) => path.relative(root, file).replaceAll('\\', '/').startsWith('operations/dev/'))) {
  failures.push('obsolete same-box operations/dev files are forbidden; IMOUTO is the only laboratory deployment target');
}
const forbiddenExtensions = new Set(['.uasset', '.uexp', '.ubulk', '.pak', '.dll', '.exe', '.dmp', '.mdmp']);
const secretPattern = /(adminpassword\s*[=:]|api[_ -]?key\s*[=:]|client[_ -]?secret\s*[=:]|bearer\s+[a-z0-9._-]{16,})/i;
const protectedMikoPathPattern = /(?:c:\\palserverdev|d:\\scripts\\|startpalworldserver\.(?:cmd|ps1))/i;
for (const file of sourceFiles) {
  const extension = path.extname(file).toLowerCase();
  const relative = path.relative(root, file).replaceAll('\\', '/');
  if (forbiddenExtensions.has(extension)) failures.push(`forbidden game/binary artifact: ${relative}`);
  const metadata = await stat(file);
  if (metadata.size > 1_000_000) failures.push(`unexpected source file over 1 MB: ${relative}`);
  if (['.lua', '.json', '.md', '.mjs', '.ps1'].includes(extension)) {
    const content = await readFile(file, 'utf8');
    if (secretPattern.test(content)) failures.push(`possible secret-bearing content: ${relative}`);
  }
  if (extension === '.json') {
    try {
      JSON.parse(await readFile(file, 'utf8'));
    } catch (error) {
      failures.push(`invalid JSON in ${relative}: ${error.message}`);
    }
  }
  if (extension === '.ps1' && relative.startsWith('operations/')) {
    const content = await readFile(file, 'utf8');
    if (protectedMikoPathPattern.test(content)) {
      failures.push(`deployment operation must not reference a protected MIKO path: ${relative}`);
    }
  }
}

const imoutoInstallerPath = path.join(root, 'operations', 'imouto', 'Install-PalEventDirectorImouto.ps1');
if (await exists('operations/imouto/Install-PalEventDirectorImouto.ps1')) {
  const installer = await readFile(imoutoInstallerPath, 'utf8');
  for (const requiredGuard of [
    "[Environment]::MachineName -ine 'IMOUTO'",
    "[IO.DriveType]::Fixed",
    "ServerRoot.StartsWith('\\\\')",
    "Global\\PalEventDirectorImoutoLifecycle",
    'sourceDirty',
    "version -ne '0.1.0-alpha.3'",
    'function Read-Ue4ssModEntries',
    '$ExistingEntries = @(Read-Ue4ssModEntries -Path $ModsJson)',
    '$ExpectedInstalledRuntime = Get-InstallationInventory',
    'Assert-InstallationInventory -Root $Ue4ssRoot -Expected $ExpectedInstalledRuntime',
    'Remove-InstallationTarget -Path $Ue4ssRoot',
    "LauncherSource = Join-Path $PSScriptRoot 'Start-PalEventDirectorImouto.ps1'",
    'launchIntegrationConfigured = $true',
    "launchEnvironmentSource = 'verified-steam-manifest'",
    "ActivationSource = Join-Path $PSScriptRoot 'Enable-PalEventDirectorLaboratory.ps1'",
    'laboratoryActivationConfigured = $true',
  ]) {
    if (!installer.includes(requiredGuard)) failures.push(`IMOUTO installer is missing required guard: ${requiredGuard}`);
  }
}

const imoutoLauncherPath = path.join(root, 'operations', 'imouto', 'Start-PalEventDirectorImouto.ps1');
if (await exists('operations/imouto/Start-PalEventDirectorImouto.ps1')) {
  const launcher = await readFile(imoutoLauncherPath, 'utf8');
  for (const requiredGuard of [
    "[Environment]::MachineName -ine 'IMOUTO'",
    "CanonicalServerRoot = 'D:\\SteamLibrary\\steamapps\\common\\PalServer'",
    "$VerifiedBuildId = $buildMatch.Groups['Value'].Value",
    '$env:PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = $VerifiedBuildId',
    '$env:PAL_EVENT_DIRECTOR_DATA_DIR = $DataDirectory',
    "EnvironmentScope = 'child-process-only'",
    '$ValidateOnly',
    '$deployment.rootServerExecutableSha256',
    '$env:PAL_EVENT_DIRECTOR_UE4SS_TAG = $ExpectedRuntimeTag',
    '$env:PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = $ExpectedRuntimeApi',
    'Get-FileHash $RuntimeDll -Algorithm SHA256',
    "deliveryProfile -notin @('preflight-diagnostic-only', 'laboratory-native-test')",
    "$deployment.version -ne '0.1.0-alpha.3'",
    "$deployment.ue4ssTag -ne '2281fa31'",
  ]) {
    if (!launcher.includes(requiredGuard)) failures.push(`IMOUTO launcher is missing required guard: ${requiredGuard}`);
  }
}

const imoutoActivationPath = path.join(root, 'operations', 'imouto', 'Enable-PalEventDirectorLaboratory.ps1');
if (await exists('operations/imouto/Enable-PalEventDirectorLaboratory.ps1')) {
  const activation = await readFile(imoutoActivationPath, 'utf8');
  for (const requiredGuard of [
    "ExpectedUe4ssApiVersion = '3.0.1'",
    "ExpectedBuildId = '24575149'",
    "AuthorizationPolicy = 'operatorOrPalworldAdmin'",
    "$NativeTest = $deployment.deliveryProfile -eq 'laboratory-native-test'",
    '$config.capabilities.chatCommands = $NativeTest',
    '$config.capabilities.observeCombat = $NativeTest',
    '$config.capabilities.observeInvasions = $NativeTest',
    '$config.capabilities.startAllInvasions = $NativeTest',
    '$config.capabilities.substituteBountyMembers = $NativeTest',
    "'LaboratoryTestEnabled'",
    '$config.capabilities.grantItems = $false',
    '$schedule.enabled = $false',
    "MandatoryWarnings = '600,300,60'",
    'RestartRequired = $true',
    '$deployment.laboratoryActivationConfigured',
    '$deployment.activationSha256',
  ]) {
    if (!activation.includes(requiredGuard)) failures.push(`IMOUTO activation is missing required guard: ${requiredGuard}`);
  }
}

const imoutoWorldImporterPath = path.join(root, 'operations', 'imouto', 'Import-MikoProductionWorldImouto.ps1');
if (await exists('operations/imouto/Import-MikoProductionWorldImouto.ps1')) {
  const importer = await readFile(imoutoWorldImporterPath, 'utf8');
  for (const requiredGuard of [
    "[Environment]::MachineName -ine 'IMOUTO'",
    "CanonicalServerRoot = 'D:\\SteamLibrary\\steamapps\\common\\PalServer'",
    "SeedManifestPath = Join-Path $PSScriptRoot 'world-seed-manifest.json'",
    "BundleManifestPath = Join-Path $PSScriptRoot 'bundle.json'",
    "'^daily_\\d{4}-\\d{2}-\\d{2}_\\d{6}$'",
    'function Assert-ServerStopped',
    'function Assert-InventoriesEqual',
    'function Set-DedicatedServerNameAtomic',
    '$PalWorldSettingsHash',
    '$ReplaceExistingSeed',
    '$PendingRecord',
    '$SaveGamesMoved',
    '$NewSaveGamesInstalled',
    '$SyntheticFailAfter',
    "throw 'synthetic failure after seed_installed'",
    "$ServerRoot.StartsWith($SyntheticRoot + '\\'",
    "'archiving_savegames'",
    "'installing_seed'",
  ]) {
    if (!importer.includes(requiredGuard)) failures.push(`IMOUTO world importer is missing required guard: ${requiredGuard}`);
  }
}

const worldSeedBuilderPath = path.join(root, 'tools', 'build-imouto-world-seed.mjs');
if (await exists('tools/build-imouto-world-seed.mjs')) {
  const builder = await readFile(worldSeedBuilderPath, 'utf8');
  for (const requiredGuard of [
    "hostname().toUpperCase() !== 'MIKO'",
    "const backupRoot = 'D:\\\\Backups\\\\Palworld\\\\daily'",
    "git('status', '--porcelain') !== ''",
    "git('ls-remote', '--exit-code', 'origin', 'refs/heads/main')",
    "entry.name.toLowerCase() === 'backup'",
    'primaryCharacterCount',
    'playerSidecarCount',
    'world-seed-manifest.json',
  ]) {
    if (!builder.includes(requiredGuard)) failures.push(`MIKO world-seed builder is missing required guard: ${requiredGuard}`);
  }
}

if (process.platform === 'win32') {
  const powershellFiles = sourceFiles.filter((candidate) => candidate.endsWith('.ps1'));
  for (const file of powershellFiles) {
    const quoted = file.replaceAll("'", "''");
    const command = `$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile('${quoted}',[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{[Console]::Error.WriteLine($_.Message)};exit 1}`;
    try {
      execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { cwd: root, env: windowsPowerShellEnvironment, stdio: 'pipe' });
    } catch (error) {
      failures.push(`PowerShell syntax validation failed for ${path.relative(root, file).replaceAll('\\', '/')}: ${error.stderr?.toString().trim() || error.message}`);
    }
  }
  try {
    const output = execFileSync('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path.join(root, 'tests', 'imouto-launcher.ps1'),
    ], { cwd: root, env: windowsPowerShellEnvironment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    process.stdout.write(output);
  } catch (error) {
    failures.push(`IMOUTO launcher contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  try {
    const output = execFileSync('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path.join(root, 'tests', 'imouto-activation.ps1'),
    ], { cwd: root, env: windowsPowerShellEnvironment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    process.stdout.write(output);
  } catch (error) {
    failures.push(`IMOUTO activation contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  try {
    process.stdout.write(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
      path.join(root, 'tests', 'imouto-preflight-command.ps1')], { cwd: root, env: windowsPowerShellEnvironment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch (error) {
    failures.push(`Local preflight command contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  try {
    process.stdout.write(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
      path.join(root, 'tests', 'imouto-runtime-replacement.ps1')], { cwd: root, env: windowsPowerShellEnvironment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch (error) {
    failures.push(`Runtime replacement safety contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
}

try {
  process.stdout.write(execFileSync(process.execPath, ['tests/artifact-provenance.mjs'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
} catch (error) {
  failures.push(`Artifact Git-content verification failed: ${error.stderr?.toString().trim() || error.message}`);
}

const luaRunner = path.join(root, 'node_modules', 'fengari-node-cli', 'src', 'lua-cli.js');
if (!await exists(path.relative(root, luaRunner))) {
  failures.push('Lua test VM is unavailable; run npm install');
} else {
  try {
    process.stdout.write(execFileSync(process.execPath, ['tests/preflight-property-binding.mjs'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch (error) {
    failures.push(`Preflight property binding contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  try {
    process.stdout.write(execFileSync(process.execPath, ['tests/fname-binding.mjs'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch (error) {
    failures.push(`FName userdata binding contract failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  const luaFiles = sourceFiles.filter((candidate) => candidate.endsWith('.lua'));
  try {
    execFileSync(process.execPath, [luaRunner, 'tests/compile.lua', ...luaFiles], { cwd: root, stdio: 'pipe' });
  } catch (error) {
    failures.push(`Lua syntax validation failed: ${error.stderr?.toString().trim() || error.message}`);
  }
  const fixture = await mkdtemp(path.join(tmpdir(), 'ped-preflight-failfast-'));
  try {
    const breadcrumbPath = path.join(fixture, 'breadcrumbs.ndjson');
    const child = spawnSync(process.execPath, ['tests/preflight-failfast.mjs', breadcrumbPath], { cwd: root, encoding: 'utf8' });
    if (child.status !== 86 || child.error) {
      throw new Error(`simulated fail-fast did not exit at its requested boundary (exit ${child.status}): ${child.stderr || child.stdout || child.error?.message || 'no child output'}`);
    }
    const lines = (await readFile(breadcrumbPath, 'utf8')).trim().split(/\r?\n/);
    const record = JSON.parse(lines[0]);
    if (lines.length !== 1 || !record.step.endsWith('.before') || record.buildId !== '24575149' ||
        typeof record.objectValid !== 'boolean' || Object.keys(record).sort().join(',') !== 'buildId,objectValid,step') {
      throw new Error('fail-fast breadcrumb was absent, unredacted, or incorrectly contained an after-marker');
    }
    console.log('PASS flushed preflight before-marker survives abrupt simulated process exit; no native game calls executed');
  } catch (error) {
    failures.push(`Preflight fail-fast log contract failed: ${error.message}`);
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
}

if (failures.length) {
  for (const failure of failures) console.error(`ERROR ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`PASS package metadata, ${sourceFiles.length} source files, JSON, Lua syntax, and secret/artifact policy`);
}
