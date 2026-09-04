import { execFileSync } from 'node:child_process';
import { readFile, readdir, stat } from 'node:fs/promises';
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
const palworldAdapter = await readFile(path.join(root, 'Scripts/ped/palworld.lua'), 'utf8');
for (const requiredGuard of [
  'GetInvaderManager',
  'GetAddress',
  'probe lifecycle is not confirmed',
  'StartInvaderMarchAll',
  'confirm-disposable-start-all',
  'COMPUTERNAME',
  'SendSystemAnnounce',
  'SendSystemToPlayerChat',
  'function(context, return_value, grade, biome, out_members)',
]) {
  if (!palworldAdapter.includes(requiredGuard)) failures.push(`Palworld adapter is missing required guard: ${requiredGuard}`);
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

const sourceFiles = (await walk(root)).filter((file) => !file.includes(`${path.sep}.git${path.sep}`) && !file.includes(`${path.sep}node_modules${path.sep}`) && !file.includes(`${path.sep}dist${path.sep}`));
if (sourceFiles.some((file) => path.relative(root, file).replaceAll('\\', '/').startsWith('operations/dev/'))) {
  failures.push('obsolete same-box operations/dev files are forbidden; IMOUTO is the only laboratory deployment target');
}
const forbiddenExtensions = new Set(['.uasset', '.uexp', '.ubulk', '.pak', '.dll', '.exe']);
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
    '$Entries = @(Read-Ue4ssModEntries -Path $ModsJson)',
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
    '$config.capabilities.chatCommands = $true',
    '$config.capabilities.startAllInvasions = $true',
    '$config.capabilities.substituteBountyMembers = $true',
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
}

const luaRunner = path.join(root, 'node_modules', 'fengari-node-cli', 'src', 'lua-cli.js');
if (!await exists(path.relative(root, luaRunner))) {
  failures.push('Lua test VM is unavailable; run npm install');
} else {
  const luaFiles = sourceFiles.filter((candidate) => candidate.endsWith('.lua'));
  try {
    execFileSync(process.execPath, [luaRunner, 'tests/compile.lua', ...luaFiles], { cwd: root, stdio: 'pipe' });
  } catch (error) {
    failures.push(`Lua syntax validation failed: ${error.stderr?.toString().trim() || error.message}`);
  }
}

if (failures.length) {
  for (const failure of failures) console.error(`ERROR ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`PASS package metadata, ${sourceFiles.length} source files, JSON, Lua syntax, and secret/artifact policy`);
}
