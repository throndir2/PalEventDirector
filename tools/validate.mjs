import { execFileSync } from 'node:child_process';
import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(import.meta.dirname, '..');
const failures = [];
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
  'Scripts/ped/scoreboard.lua',
  'Scripts/ped/store.lua',
  'Scripts/ped/util.lua',
  'Scripts/ped/version.lua',
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

try {
  JSON.parse(await readFile(path.join(root, 'Scripts/config/default.json'), 'utf8'));
} catch (error) {
  failures.push(`default config is invalid JSON: ${error.message}`);
}

const packageJson = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
if (info && packageJson.version !== info.Version) failures.push('package.json and Info.json versions differ');
const versionLua = await readFile(path.join(root, 'Scripts/ped/version.lua'), 'utf8');
if (info && !versionLua.includes(`version = "${info.Version}"`)) failures.push('Lua runtime and Info.json versions differ');

const sourceFiles = (await walk(root)).filter((file) => !file.includes(`${path.sep}.git${path.sep}`) && !file.includes(`${path.sep}node_modules${path.sep}`) && !file.includes(`${path.sep}dist${path.sep}`));
const forbiddenExtensions = new Set(['.uasset', '.uexp', '.ubulk', '.pak', '.dll', '.exe']);
const secretPattern = /(adminpassword\s*[=:]|api[_ -]?key\s*[=:]|client[_ -]?secret\s*[=:]|bearer\s+[a-z0-9._-]{16,})/i;
for (const file of sourceFiles) {
  const extension = path.extname(file).toLowerCase();
  const relative = path.relative(root, file).replaceAll('\\', '/');
  if (forbiddenExtensions.has(extension)) failures.push(`forbidden game/binary artifact: ${relative}`);
  const metadata = await stat(file);
  if (metadata.size > 1_000_000) failures.push(`unexpected source file over 1 MB: ${relative}`);
  if (['.lua', '.json', '.md', '.mjs'].includes(extension)) {
    const content = await readFile(file, 'utf8');
    if (secretPattern.test(content)) failures.push(`possible secret-bearing content: ${relative}`);
  }
}

const luaRunner = path.join(root, 'node_modules', '.bin', process.platform === 'win32' ? 'fengari.cmd' : 'fengari');
if (!await exists(path.relative(root, luaRunner))) {
  failures.push('Lua test VM is unavailable; run npm install');
} else {
  const luaFiles = sourceFiles.filter((candidate) => candidate.endsWith('.lua'));
  try {
    execFileSync(luaRunner, ['tests/compile.lua', ...luaFiles], { cwd: root, stdio: 'pipe' });
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
