import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const dist = path.join(root, 'dist');
const manifestPath = path.join(dist, 'manifest.json');
const installerPath = path.join(root, 'operations', 'imouto', 'Install-PalEventDirectorImouto.ps1');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();

if (manifest.sourceDirty !== false) throw new Error('IMOUTO bundle requires a clean-source artifact manifest');
if (manifest.packageName !== 'PalEventDirector') throw new Error('unexpected artifact package name');
if (manifest.version !== '0.1.0-alpha.3') throw new Error('IMOUTO bundle requires alpha.3');
if (!/^[a-f0-9]{40}$/i.test(manifest.sourceRevision ?? '')) throw new Error('artifact source revision is invalid');
if (git('status', '--porcelain') !== '') throw new Error('IMOUTO bundle requires a clean current worktree');
const head = git('rev-parse', 'HEAD');
if (manifest.sourceRevision !== head || head !== git('rev-parse', 'refs/remotes/origin/main')) {
  throw new Error('artifact, HEAD, and origin/main revisions differ');
}
if (head !== git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0]) {
  throw new Error('HEAD does not equal canonical origin/main');
}

const archivePath = path.join(dist, manifest.archive);
const [archive, installer, manifestBytes] = await Promise.all([
  readFile(archivePath),
  readFile(installerPath),
  readFile(manifestPath),
]);
const installerRelative = 'operations/imouto/Install-PalEventDirectorImouto.ps1';
const workingInstallerBlob = git('hash-object', `--path=${installerRelative}`, installerRelative);
const trackedInstallerBlob = git('rev-parse', `${head}:${installerRelative}`);
if (workingInstallerBlob !== trackedInstallerBlob) throw new Error('installer bytes differ from the selected Git revision');
const archiveHash = createHash('sha256').update(archive).digest('hex');
if (archiveHash !== manifest.sha256) throw new Error('artifact hash differs from manifest');

const bundlePath = path.join(dist, `IMOUTO-${manifest.version}-${manifest.sourceRevision.slice(0, 12)}`);
const temporaryPath = `${bundlePath}.${randomUUID()}.tmp`;
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
if (git('status', '--porcelain') !== '' || git('rev-parse', 'HEAD') !== head ||
    git('rev-parse', 'refs/remotes/origin/main') !== head ||
    git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0] !== head) {
  throw new Error('repository provenance changed while building the IMOUTO bundle');
}
try {
  await mkdir(temporaryPath, { recursive: false });
  await writeFile(path.join(temporaryPath, path.basename(installerPath)), installer);
  await writeFile(path.join(temporaryPath, 'manifest.json'), manifestBytes);
  await writeFile(path.join(temporaryPath, manifest.archive), archive);
  await writeFile(path.join(temporaryPath, 'bundle.json'), `${JSON.stringify(bundle, null, 2)}\n`);
  await rm(bundlePath, { recursive: true, force: true });
  await rename(temporaryPath, bundlePath);
} catch (error) {
  await rm(temporaryPath, { recursive: true, force: true });
  throw error;
}
console.log(`BUILT ${path.relative(root, bundlePath)}`);
console.log(`SOURCE ${manifest.sourceRevision}`);
console.log(`ARTIFACT_SHA256 ${manifest.sha256}`);
