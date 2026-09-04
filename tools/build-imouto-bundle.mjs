import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(import.meta.dirname, '..');
const dist = path.join(root, 'dist');
const manifestPath = path.join(dist, 'manifest.json');
const installerPath = path.join(root, 'operations', 'imouto', 'Install-PalEventDirectorImouto.ps1');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));

if (manifest.sourceDirty !== false) throw new Error('IMOUTO bundle requires a clean-source artifact manifest');
if (manifest.packageName !== 'PalEventDirector') throw new Error('unexpected artifact package name');
if (manifest.version !== '0.1.0-alpha.3') throw new Error('IMOUTO bundle requires alpha.3');
if (!/^[a-f0-9]{40}$/i.test(manifest.sourceRevision ?? '')) throw new Error('artifact source revision is invalid');

const archivePath = path.join(dist, manifest.archive);
const archive = await readFile(archivePath);
const archiveHash = createHash('sha256').update(archive).digest('hex');
if (archiveHash !== manifest.sha256) throw new Error('artifact hash differs from manifest');

const bundlePath = path.join(dist, `IMOUTO-${manifest.version}-${manifest.sourceRevision.slice(0, 12)}`);
await rm(bundlePath, { recursive: true, force: true });
await mkdir(bundlePath, { recursive: true });
await copyFile(installerPath, path.join(bundlePath, path.basename(installerPath)));
await copyFile(manifestPath, path.join(bundlePath, 'manifest.json'));
await copyFile(archivePath, path.join(bundlePath, manifest.archive));

const installer = await readFile(installerPath);
const bundle = {
  schemaVersion: 1,
  packageName: manifest.packageName,
  version: manifest.version,
  sourceRevision: manifest.sourceRevision,
  artifact: manifest.archive,
  artifactSha256: manifest.sha256,
  installer: path.basename(installerPath),
  installerSha256: createHash('sha256').update(installer).digest('hex'),
};
await writeFile(path.join(bundlePath, 'bundle.json'), `${JSON.stringify(bundle, null, 2)}\n`);
console.log(`BUILT ${path.relative(root, bundlePath)}`);
console.log(`SOURCE ${manifest.sourceRevision}`);
console.log(`ARTIFACT_SHA256 ${manifest.sha256}`);
