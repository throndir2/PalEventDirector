import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { verifyArtifact } from './verify-artifact.mjs';

const root = path.resolve(import.meta.dirname, '..');
const dist = path.join(root, 'dist');
const manifestPath = path.join(dist, 'manifest.json');
const installerPath = path.join(root, 'operations', 'imouto', 'Install-PalEventDirectorImouto.ps1');
const launcherPath = path.join(root, 'operations', 'imouto', 'Start-PalEventDirectorImouto.ps1');
const activationPath = path.join(root, 'operations', 'imouto', 'Enable-PalEventDirectorLaboratory.ps1');
const preflightRelative = 'operations/imouto/Invoke-PalEventDirectorPreflight.ps1';
const preflightPath = path.join(root, preflightRelative);
const guideRelative = 'docs/15-preflight-crash-diagnostics.md';
const guidePath = path.join(root, guideRelative);
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();

if (manifest.sourceDirty !== false) throw new Error('IMOUTO bundle requires a clean-source artifact manifest');
if (manifest.packageName !== 'PalEventDirector') throw new Error('unexpected artifact package name');
if (manifest.version !== '0.1.0-alpha.3') throw new Error('IMOUTO bundle requires alpha.3');
if (!['preflight-diagnostic-only', 'laboratory-native-test'].includes(manifest.deliveryProfile)) throw new Error('IMOUTO bundle requires an audited laboratory profile');
if (!/^[a-f0-9]{40}$/i.test(manifest.sourceRevision ?? '')) throw new Error('artifact source revision is invalid');
if (git('status', '--porcelain') !== '') throw new Error('IMOUTO bundle requires a clean current worktree');
const head = git('rev-parse', 'HEAD');
if (head === '575a9f521977069dcfcb244994f6c017044e9604') throw new Error('Known crashing revision is revoked');
if (manifest.sourceRevision !== head || head !== git('rev-parse', 'refs/remotes/origin/main')) {
  throw new Error('artifact, HEAD, and origin/main revisions differ');
}
if (head !== git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0]) {
  throw new Error('HEAD does not equal canonical origin/main');
}

const archivePath = path.join(dist, manifest.archive);
const trackedBytes = (relative) => execFileSync('git', ['show', `${head}:${relative}`], { cwd: root, maxBuffer: 4 * 1024 * 1024 });
if (trackedBytes('Scripts/ped/version.lua').toString('utf8').match(/delivery_profile\s*=\s*"([^"]+)"/)?.[1] !== manifest.deliveryProfile) {
  throw new Error('artifact profile differs from the selected source revision');
}
const [archive, installer, launcher, activation, manifestBytes, guide, preflightCommand] = await Promise.all([
  readFile(archivePath),
  trackedBytes('operations/imouto/Install-PalEventDirectorImouto.ps1'),
  trackedBytes('operations/imouto/Start-PalEventDirectorImouto.ps1'),
  trackedBytes('operations/imouto/Enable-PalEventDirectorLaboratory.ps1'),
  readFile(manifestPath),
  trackedBytes(guideRelative),
  trackedBytes(preflightRelative),
]);
const hashBufferAsPath = (buffer, relative) => execFileSync('git', [
  'hash-object',
  '--stdin',
  '--no-filters',
], { cwd: root, input: buffer, encoding: 'utf8' }).trim();
const installerRelative = 'operations/imouto/Install-PalEventDirectorImouto.ps1';
const workingInstallerBlob = hashBufferAsPath(installer, installerRelative);
const trackedInstallerBlob = git('rev-parse', `${head}:${installerRelative}`);
if (workingInstallerBlob !== trackedInstallerBlob) throw new Error('installer bytes differ from the selected Git revision');
const launcherRelative = 'operations/imouto/Start-PalEventDirectorImouto.ps1';
const workingLauncherBlob = hashBufferAsPath(launcher, launcherRelative);
const trackedLauncherBlob = git('rev-parse', `${head}:${launcherRelative}`);
if (workingLauncherBlob !== trackedLauncherBlob) throw new Error('launcher bytes differ from the selected Git revision');
const activationRelative = 'operations/imouto/Enable-PalEventDirectorLaboratory.ps1';
const workingActivationBlob = hashBufferAsPath(activation, activationRelative);
const trackedActivationBlob = git('rev-parse', `${head}:${activationRelative}`);
if (workingActivationBlob !== trackedActivationBlob) throw new Error('activation command bytes differ from the selected Git revision');
if (hashBufferAsPath(guide, guideRelative) !== git('rev-parse', `${head}:${guideRelative}`)) {
  throw new Error('diagnostic guide differs from the selected Git revision');
}
if (hashBufferAsPath(preflightCommand, preflightRelative) !== git('rev-parse', `${head}:${preflightRelative}`)) {
  throw new Error('preflight command differs from the selected Git revision');
}
const archiveHash = createHash('sha256').update(archive).digest('hex');
if (archiveHash !== manifest.sha256) throw new Error('artifact hash differs from manifest');
await verifyArtifact(archive, head, root);

const bundlePath = path.join(dist, `IMOUTO-${manifest.version}-${manifest.sourceRevision.slice(0, 12)}`);
const temporaryPath = `${bundlePath}.${randomUUID()}.tmp`;
const bundle = {
  schemaVersion: 1,
  packageName: manifest.packageName,
  version: manifest.version,
  deliveryProfile: manifest.deliveryProfile,
  sourceRevision: manifest.sourceRevision,
  artifact: manifest.archive,
  artifactSha256: manifest.sha256,
  installer: path.basename(installerPath),
  installerSha256: createHash('sha256').update(installer).digest('hex'),
  launcher: path.basename(launcherPath),
  launcherSha256: createHash('sha256').update(launcher).digest('hex'),
  activation: path.basename(activationPath),
  activationSha256: createHash('sha256').update(activation).digest('hex'),
  diagnosticGuide: 'PREFLIGHT-DIAGNOSTICS.md',
  diagnosticGuideSha256: createHash('sha256').update(guide).digest('hex'),
  preflightCommand: path.basename(preflightPath),
  preflightCommandSha256: createHash('sha256').update(preflightCommand).digest('hex'),
};
if (git('status', '--porcelain') !== '' || git('rev-parse', 'HEAD') !== head ||
    git('rev-parse', 'refs/remotes/origin/main') !== head ||
    git('ls-remote', '--exit-code', 'origin', 'refs/heads/main').split(/\s+/)[0] !== head) {
  throw new Error('repository provenance changed while building the IMOUTO bundle');
}
try {
  await mkdir(temporaryPath, { recursive: false });
  await writeFile(path.join(temporaryPath, path.basename(installerPath)), installer);
  await writeFile(path.join(temporaryPath, path.basename(launcherPath)), launcher);
  await writeFile(path.join(temporaryPath, path.basename(activationPath)), activation);
  await writeFile(path.join(temporaryPath, 'manifest.json'), manifestBytes);
  await writeFile(path.join(temporaryPath, manifest.archive), archive);
  await writeFile(path.join(temporaryPath, 'bundle.json'), `${JSON.stringify(bundle, null, 2)}\n`);
  await writeFile(path.join(temporaryPath, bundle.diagnosticGuide), guide);
  await writeFile(path.join(temporaryPath, bundle.preflightCommand), preflightCommand);
  await rm(bundlePath, { recursive: true, force: true });
  await rename(temporaryPath, bundlePath);
} catch (error) {
  await rm(temporaryPath, { recursive: true, force: true });
  throw error;
}
console.log(`BUILT ${path.relative(root, bundlePath)}`);
console.log(`SOURCE ${manifest.sourceRevision}`);
console.log(`ARTIFACT_SHA256 ${manifest.sha256}`);
