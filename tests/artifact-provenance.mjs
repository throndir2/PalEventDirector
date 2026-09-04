import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { ZipArchive } from 'archiver';
import { verifyArtifact } from '../tools/verify-artifact.mjs';

const root = path.resolve(import.meta.dirname, '..');
const git = (...args) => execFileSync('git', args, { cwd: root, maxBuffer: 4 * 1024 * 1024 });
const revision = git('rev-parse', 'HEAD').toString().trim();
const files = git('ls-tree', '-r', '--name-only', revision, '--', 'Info.json', 'Scripts').toString().trim().split(/\r?\n/);
const entries = files.map((name) => [name, git('show', `${revision}:${name}`)]);
async function zipBytes(values) {
  const archive = new ZipArchive({ zlib: { level: 1 } });
  const chunks = [];
  const result = new Promise((resolve, reject) => {
    archive.on('data', (bytes) => chunks.push(bytes));
    archive.on('end', () => resolve(Buffer.concat(chunks)));
    archive.on('error', reject);
  });
  for (const [name, bytes] of values) archive.append(bytes, { name });
  await archive.finalize();
  return result;
}
await verifyArtifact(await zipBytes(entries), revision, root);
const changed = entries.map(([name, bytes]) => [name, name === 'Scripts/main.lua' ? Buffer.concat([bytes, Buffer.from('\n-- unrelated bytes\n')]) : bytes]);
await assert.rejects(verifyArtifact(await zipBytes(changed), revision, root), /differs from pushed Git content/);
await assert.rejects(verifyArtifact(await zipBytes(entries.slice(1)), revision, root), /omits tracked/);
await assert.rejects(verifyArtifact(await zipBytes([...entries, ['Scripts/extra.lua', Buffer.from('-- extra')]]), revision, root), /unexpected/);
console.log('PASS exact ZIP entries match Git; tampered, missing, and extra package inputs are rejected');