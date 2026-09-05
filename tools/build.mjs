import { ZipArchive } from 'archiver';
import { createHash } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { execFileSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const sourceRevision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const sourceDirty = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim() !== '';
if (process.env.REQUIRE_CLEAN_BUILD === '1' && sourceDirty) throw new Error('clean source is required before build');
const info = JSON.parse(await readFile(path.join(root, 'Info.json'), 'utf8'));
const versionSource = await readFile(path.join(root, 'Scripts', 'ped', 'version.lua'), 'utf8');
const deliveryProfile = versionSource.match(/delivery_profile\s*=\s*"([^"]+)"/)?.[1];
if (!['preflight-diagnostic-only', 'laboratory-native-test'].includes(deliveryProfile)) throw new Error('unsupported delivery profile');
const outputDirectory = path.join(root, 'dist');
const archiveName = `${info.PackageName}-${info.Version}.zip`;
const archivePath = path.join(outputDirectory, archiveName);
const fixedDate = new Date('2000-01-01T00:00:00.000Z');

const installer = await readFile(path.join(root, 'operations', 'imouto', 'Install-PalEventDirectorImouto.ps1'), 'utf8');
const serverRootMatch = installer.match(/\[string\]\$ServerRoot\s*=\s*'([^']+)'/);
if (!serverRootMatch) throw new Error('unable to derive installer ServerRoot');
const values = { ServerRoot: serverRootMatch[1] };
for (const [name, parent] of [
  ['Win64Root', 'ServerRoot'],
  ['Ue4ssRoot', 'Win64Root'],
  ['ModsRoot', 'Ue4ssRoot'],
  ['ModTarget', 'ModsRoot'],
]) {
  const expression = new RegExp(`\\$${name}\\s*=\\s*Join-Path\\s+\\$${parent}\\s+'([^']+)'`);
  const match = installer.match(expression);
  if (!match) throw new Error(`unable to derive installer ${name}`);
  values[name] = path.win32.join(values[parent], match[1]);
}
await mkdir(outputDirectory, { recursive: true });
await rm(archivePath, { force: true });
const packageFiles = [
  'Info.json',
  'Scripts/config/default.json',
  'Scripts/main.lua',
  'Scripts/ped/bounties.lua',
  'Scripts/ped/config.lua',
  'Scripts/ped/director.lua',
  'Scripts/ped/diagnostic_ingress.lua',
  'Scripts/ped/filesystem.lua',
  'Scripts/ped/json.lua',
  'Scripts/ped/logger.lua',
  'Scripts/ped/palworld.lua',
  'Scripts/ped/path.lua',
  'Scripts/ped/preflight_diagnostic.lua',
  'Scripts/ped/rewards.lua',
  'Scripts/ped/scheduler.lua',
  'Scripts/ped/scoreboard.lua',
  'Scripts/ped/store.lua',
  'Scripts/ped/util.lua',
  'Scripts/ped/version.lua',
];
const files = packageFiles.map((relative) => path.join(root, relative));
const stageDirectory = path.join(outputDirectory, '.package-stage');
await rm(stageDirectory, { recursive: true, force: true });
for (let index = 0; index < files.length; index += 1) {
  const staged = path.join(stageDirectory, packageFiles[index]);
  await mkdir(path.dirname(staged), { recursive: true });
  const input = sourceDirty ? await readFile(files[index]) : execFileSync('git', ['show', `${sourceRevision}:${packageFiles[index]}`], { cwd: root, maxBuffer: 4 * 1024 * 1024 });
  await writeFile(staged, input);
}

const installedScriptsRoot = path.win32.join(values.ModTarget, 'Scripts');
const expectedDataDirectory = path.win32.join(values.ServerRoot, 'Pal', 'Saved', 'PalEventDirector');
const luaRunner = path.join(root, 'node_modules', 'fengari-node-cli', 'src', 'lua-cli.js');
execFileSync(process.execPath, [luaRunner,
  'tests/path_contract.lua',
  installedScriptsRoot,
  expectedDataDirectory,
  'win64-ue4ss-layout',
  path.join(stageDirectory, 'Scripts'),
], { cwd: root, stdio: 'inherit' });

await new Promise((resolve, reject) => {
  const output = createWriteStream(archivePath);
  const archive = new ZipArchive({ zlib: { level: 9 } });
  output.on('close', resolve);
  output.on('error', reject);
  archive.on('warning', reject);
  archive.on('error', reject);
  archive.pipe(output);
  (async () => {
  for (const relative of packageFiles) {
    const name = relative.replaceAll('\\', '/');
    archive.append(await readFile(path.join(stageDirectory, relative)), { name, date: fixedDate, mode: 0o644 });
  }
  await archive.finalize();
  })().catch(reject);
});

const bytes = await readFile(archivePath);
await rm(stageDirectory, { recursive: true, force: true });
const sha256 = createHash('sha256').update(bytes).digest('hex');
let revision = 'unknown';
let dirty = true;
try {
  revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  dirty = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim() !== '';
} catch {
  // Build remains usable outside a Git checkout, but the manifest shows unknown provenance.
}
if (revision !== sourceRevision || dirty !== sourceDirty) throw new Error('source provenance changed during packaging');
const manifest = {
  schemaVersion: 1,
  packageName: info.PackageName,
  version: info.Version,
  deliveryProfile,
  sourceRevision: revision,
  sourceDirty: dirty,
  fileCount: files.length,
  archive: archiveName,
  bytes: (await stat(archivePath)).size,
  sha256,
};
await writeFile(path.join(outputDirectory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
await writeFile(path.join(outputDirectory, 'SHA256SUMS'), `${sha256}  ${archiveName}\n`);
console.log(`BUILT ${path.relative(root, archivePath)} (${manifest.bytes} bytes)`);
console.log(`SHA256 ${sha256}`);
console.log(`SOURCE ${revision}${dirty ? '+dirty' : ''}`);
if (process.env.REQUIRE_CLEAN_BUILD === '1' && dirty) {
  console.error('ERROR clean source is required for this build');
  process.exitCode = 1;
}
