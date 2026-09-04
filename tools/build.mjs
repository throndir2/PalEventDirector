import { ZipArchive } from 'archiver';
import { createHash } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { execFileSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const info = JSON.parse(await readFile(path.join(root, 'Info.json'), 'utf8'));
const outputDirectory = path.join(root, 'dist');
const archiveName = `${info.PackageName}-${info.Version}.zip`;
const archivePath = path.join(outputDirectory, archiveName);
const fixedDate = new Date('2000-01-01T00:00:00.000Z');

await mkdir(outputDirectory, { recursive: true });
await rm(archivePath, { force: true });
const packageFiles = [
  'Info.json',
  'Scripts/config/default.json',
  'Scripts/main.lua',
  'Scripts/ped/bounties.lua',
  'Scripts/ped/config.lua',
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
const files = packageFiles.map((relative) => path.join(root, relative));

await new Promise((resolve, reject) => {
  const output = createWriteStream(archivePath);
  const archive = new ZipArchive({ zlib: { level: 9 } });
  output.on('close', resolve);
  output.on('error', reject);
  archive.on('warning', reject);
  archive.on('error', reject);
  archive.pipe(output);
  (async () => {
  for (const file of files) {
    const name = path.relative(root, file).replaceAll('\\', '/');
    archive.append(await readFile(file), { name, date: fixedDate, mode: 0o644 });
  }
  await archive.finalize();
  })().catch(reject);
});

const bytes = await readFile(archivePath);
const sha256 = createHash('sha256').update(bytes).digest('hex');
let revision = 'unknown';
let dirty = true;
try {
  revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  dirty = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim() !== '';
} catch {
  // Build remains usable outside a Git checkout, but the manifest shows unknown provenance.
}
const manifest = {
  schemaVersion: 1,
  packageName: info.PackageName,
  version: info.Version,
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
