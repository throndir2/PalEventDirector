import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { ZipArchive } from 'archiver';
import { createWriteStream } from 'node:fs';
import { hostname } from 'node:os';
import { mkdir, lstat, readFile, readdir, realpath, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const backupRoot = 'D:\\Backups\\Palworld\\daily';
const dist = path.join(root, 'dist');
const importerPath = path.join(root, 'operations', 'imouto', 'Import-MikoProductionWorldImouto.ps1');
const snapshotPattern = /^daily_(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})$/;
const fixedDate = new Date('2000-01-01T00:00:00.000Z');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

async function assertNoLinks(pathname, stopAt) {
  const resolvedStop = path.resolve(stopAt);
  let current = path.resolve(pathname);
  const chain = [];
  while (true) {
    const relative = path.relative(resolvedStop, current);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      throw new Error(`path escapes trusted backup root: ${pathname}`);
    }
    chain.push(current);
    if (current.toLowerCase() === resolvedStop.toLowerCase()) break;
    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`path escapes trusted backup root: ${pathname}`);
    }
    current = parent;
  }
  for (const candidate of chain) {
    const info = await lstat(candidate);
    if (info.isSymbolicLink()) throw new Error(`managed backup path is a link: ${candidate}`);
  }
  const physical = await realpath(pathname);
  const physicalStop = await realpath(stopAt);
  const physicalRelative = path.relative(physicalStop, physical);
  if (physicalRelative.startsWith('..') || path.isAbsolute(physicalRelative)) {
    throw new Error(`managed backup resolves outside trusted root: ${pathname}`);
  }
}

if (hostname().toUpperCase() !== 'MIKO') throw new Error('world seeds may be built only on MIKO');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
if (git('status', '--porcelain') !== '') throw new Error('world seed requires a clean repository');
const sourceRevision = git('rev-parse', 'HEAD');
if (sourceRevision !== git('rev-parse', 'refs/remotes/origin/main')) throw new Error('HEAD does not equal origin/main');
const remoteRevision = git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0];
if (sourceRevision !== remoteRevision) throw new Error('HEAD does not equal canonical origin/main');

await assertNoLinks(backupRoot, path.parse(backupRoot).root);
const now = Date.now();
const candidates = (await readdir(backupRoot, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory() && snapshotPattern.test(entry.name))
  .filter((entry) => {
    const match = entry.name.match(snapshotPattern);
    const timestamp = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]));
    return now - timestamp.getTime() >= 10 * 60 * 1000;
  })
  .map((entry) => entry.name)
  .sort()
  .reverse();
if (!candidates.length) throw new Error(`no managed daily backup under ${backupRoot}`);
const sourceSnapshot = candidates[0];
const match = sourceSnapshot.match(snapshotPattern);
const snapshotLocalTime = new Date(
  Number(match[1]), Number(match[2]) - 1, Number(match[3]),
  Number(match[4]), Number(match[5]), Number(match[6]),
);
const productionStartText = execFileSync('powershell.exe', [
  '-NoProfile',
  '-NonInteractive',
  '-Command',
  "$p=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'PalServer.exe' -and $_.ExecutablePath -eq 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\PalServer\\PalServer.exe'});if($p.Count -ne 1){exit 2};(Get-Process -Id $p[0].ProcessId).StartTime.ToString('o')",
], { encoding: 'utf8' }).trim();
const productionRelaunchAt = new Date(productionStartText);
if (!Number.isFinite(productionRelaunchAt.getTime()) || productionRelaunchAt <= snapshotLocalTime) {
  throw new Error('current MIKO Production process does not prove a post-backup relaunch');
}

const snapshotRoot = path.join(backupRoot, sourceSnapshot);
await assertNoLinks(snapshotRoot, backupRoot);
const snapshotInfo = await lstat(snapshotRoot);
if (!snapshotInfo.isDirectory() || snapshotInfo.isSymbolicLink()) throw new Error('managed backup root is not a safe directory');
const completionSentinel = path.join(snapshotRoot, 'PalWorldSettings.ini');
await assertNoLinks(completionSentinel, backupRoot);
const completionInfo = await lstat(completionSentinel);
if (!completionInfo.isFile() || completionInfo.isSymbolicLink() || completionInfo.size < 1) {
  throw new Error('managed backup lacks its final nonempty completion sentinel');
}
const accountRoot = path.join(snapshotRoot, 'SaveGames', '0');
await assertNoLinks(accountRoot, backupRoot);
const accountInfo = await lstat(accountRoot);
if (!accountInfo.isDirectory() || accountInfo.isSymbolicLink()) throw new Error('managed account save root is not a safe directory');
const worlds = (await readdir(accountRoot, { withFileTypes: true })).filter((entry) => entry.isDirectory());
if (worlds.length !== 1 || !/^[a-f0-9]{32}$/i.test(worlds[0].name)) {
  throw new Error('managed backup must contain exactly one canonical world directory');
}
const worldId = worlds[0].name.toUpperCase();
const worldRoot = path.join(accountRoot, worlds[0].name);
await assertNoLinks(worldRoot, backupRoot);
const worldInfo = await lstat(worldRoot);
if (!worldInfo.isDirectory() || worldInfo.isSymbolicLink()) throw new Error('managed world root is not a safe directory');
const rootEntries = await readdir(worldRoot, { withFileTypes: true });
for (const entry of rootEntries) {
  if (entry.name.toLowerCase() === 'backup') continue;
  if (!['Level.sav', 'LevelMeta.sav', 'Players'].includes(entry.name)) {
    throw new Error(`unexpected active world entry: ${entry.name}`);
  }
}

const levelPath = path.join(worldRoot, 'Level.sav');
const levelMetaPath = path.join(worldRoot, 'LevelMeta.sav');
if ((await stat(levelPath)).size < 1 || (await stat(levelMetaPath)).size < 1) {
  throw new Error('managed backup level files are empty');
}
const playersRoot = path.join(worldRoot, 'Players');
await assertNoLinks(playersRoot, backupRoot);
const playersInfo = await lstat(playersRoot);
if (!playersInfo.isDirectory() || playersInfo.isSymbolicLink()) throw new Error('managed Players root is not a safe directory');
const playerEntries = await readdir(playersRoot, { withFileTypes: true });
if (playerEntries.some((entry) => !entry.isFile() || !/^[a-f0-9]{32}(?:_dps)?\.sav$/i.test(entry.name))) {
  throw new Error('managed backup contains an unexpected player entry');
}
const primaryCharacterCount = playerEntries.filter((entry) => /^[a-f0-9]{32}\.sav$/i.test(entry.name)).length;
const playerSidecarCount = playerEntries.filter((entry) => /^[a-f0-9]{32}_dps\.sav$/i.test(entry.name)).length;
if (primaryCharacterCount < 1) throw new Error('managed backup has no primary character saves');

const sourceFiles = [levelPath, levelMetaPath, ...playerEntries.map((entry) => path.join(playersRoot, entry.name))]
  .sort((left, right) => left.localeCompare(right));
const files = [];
for (const sourcePath of sourceFiles) {
  await assertNoLinks(sourcePath, backupRoot);
  const info = await lstat(sourcePath);
  if (!info.isFile() || info.isSymbolicLink()) throw new Error(`unsafe source save file: ${sourcePath}`);
  const bytes = await readFile(sourcePath);
  if (bytes.length < 1) throw new Error(`managed save file is empty: ${sourcePath}`);
  const worldRelative = path.relative(worldRoot, sourcePath).replaceAll('\\', '/');
  files.push({
    sourcePath,
    archivePath: `SaveGames/0/${worldId}/${worldRelative}`,
    bytes,
    length: bytes.length,
    hash: sha256(bytes),
  });
}
for (const file of files) {
  const verification = await readFile(file.sourcePath);
  if (verification.length !== file.length || sha256(verification) !== file.hash) {
    throw new Error(`managed backup changed while being snapshotted: ${file.sourcePath}`);
  }
  if ((await stat(file.sourcePath)).mtime > productionRelaunchAt) {
    throw new Error(`managed save changed after the current Production relaunch: ${file.sourcePath}`);
  }
}

await mkdir(dist, { recursive: true });
const outputName = `IMOUTO-WORLD-SEED-${sourceSnapshot.slice('daily_'.length)}-${sourceRevision.slice(0, 12)}`;
const outputPath = path.join(dist, outputName);
const temporaryPath = path.join(dist, `.${outputName}.${randomUUID()}.tmp`);
const archiveName = 'world-seed.zip';
const archivePath = path.join(temporaryPath, archiveName);
try {
  await mkdir(temporaryPath, { recursive: false });
  await new Promise((resolve, reject) => {
    const output = createWriteStream(archivePath);
    const archive = new ZipArchive({ zlib: { level: 9 } });
    output.on('close', resolve);
    output.on('error', reject);
    archive.on('warning', reject);
    archive.on('error', reject);
    archive.pipe(output);
    for (const file of files) {
      archive.append(file.bytes, { name: file.archivePath, date: fixedDate, mode: 0o600 });
    }
    archive.finalize().catch(reject);
  });

  const archiveBytes = await readFile(archivePath);
  const manifest = {
    schemaVersion: 1,
    sourceSnapshot,
    sourceSnapshotLocalTime: `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}`,
    productionRelaunchAt: productionRelaunchAt.toISOString(),
    sourceRevision,
    worldId,
    primaryCharacterCount,
    playerSidecarCount,
    fileCount: files.length,
    activeBytes: files.reduce((total, file) => total + file.length, 0),
    archive: archiveName,
    archiveSha256: sha256(archiveBytes),
    files: files.map((file) => ({
      relativePath: file.archivePath,
      length: file.length,
      sha256: file.hash,
    })),
  };
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);
  const importerBytes = await readFile(importerPath);
  const importerRelative = 'operations/imouto/Import-MikoProductionWorldImouto.ps1';
  const workingImporterBlob = git('hash-object', `--path=${importerRelative}`, importerRelative);
  const trackedImporterBlob = git('rev-parse', `${sourceRevision}:${importerRelative}`);
  if (workingImporterBlob !== trackedImporterBlob) throw new Error('world importer bytes differ from the selected Git revision');
  if (git('status', '--porcelain') !== '' || git('rev-parse', 'HEAD') !== sourceRevision ||
      git('rev-parse', 'refs/remotes/origin/main') !== sourceRevision ||
      git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0] !== sourceRevision) {
    throw new Error('repository provenance changed while building the world seed');
  }
  await writeFile(path.join(temporaryPath, 'world-seed-manifest.json'), manifestBytes);
  await writeFile(path.join(temporaryPath, path.basename(importerPath)), importerBytes);
  await writeFile(path.join(temporaryPath, 'bundle.json'), `${JSON.stringify({
    schemaVersion: 1,
    type: 'PalEventDirectorImoutoWorldSeed',
    sourceSnapshot,
    sourceRevision,
    worldSeedManifestSha256: sha256(manifestBytes),
    worldSeedArchiveSha256: manifest.archiveSha256,
    importer: path.basename(importerPath),
    importerSha256: sha256(importerBytes),
  }, null, 2)}\n`);

  await rm(outputPath, { recursive: true, force: true });
  await rename(temporaryPath, outputPath);
  console.log(`BUILT ${path.relative(root, outputPath)}`);
  console.log(`SNAPSHOT ${sourceSnapshot}`);
  console.log(`PRIMARY_CHARACTERS ${primaryCharacterCount}`);
  console.log(`PLAYER_SIDECARS ${playerSidecarCount}`);
  console.log(`ACTIVE_BYTES ${manifest.activeBytes}`);
  console.log('WARNING world seed contains private Production player/save data; do not publish or commit it');
} catch (error) {
  await rm(temporaryPath, { recursive: true, force: true });
  throw error;
}
