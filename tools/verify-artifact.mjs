import yauzl from 'yauzl';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

export async function verifyArtifact(archiveBytes, revision, root) {
  const files = execFileSync('git', ['ls-tree', '-r', '--name-only', revision, '--', 'Info.json', 'Scripts'], { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/);
  const expected = new Map(files.map((name) => [name, createHash('sha256').update(
    execFileSync('git', ['show', `${revision}:${name}`], { cwd: root, maxBuffer: 4 * 1024 * 1024 }),
  ).digest('hex')]));
  await new Promise((resolve, reject) => {
    yauzl.fromBuffer(archiveBytes, { lazyEntries: true, validateEntrySizes: true }, (openError, zip) => {
      if (openError) return reject(openError);
      let settled = false;
      const fail = (error) => { if (!settled) { settled = true; zip.close(); reject(error); } };
      zip.on('error', fail);
      zip.on('entry', (entry) => {
        const expectedHash = expected.get(entry.fileName);
        if (!expectedHash || entry.uncompressedSize > 4 * 1024 * 1024) return fail(new Error('Artifact contains an unexpected, duplicate, or oversized entry'));
        zip.openReadStream(entry, (streamError, stream) => {
          if (streamError) return fail(streamError);
          const hash = createHash('sha256');
          stream.on('error', fail);
          stream.on('data', (bytes) => hash.update(bytes));
          stream.on('end', () => {
            if (settled) return;
            if (hash.digest('hex') !== expectedHash) return fail(new Error(`Artifact entry differs from pushed Git content: ${entry.fileName}`));
            expected.delete(entry.fileName);
            zip.readEntry();
          });
        });
      });
      zip.on('end', () => {
        if (settled) return;
        if (expected.size) return fail(new Error('Artifact omits tracked package inputs'));
        settled = true;
        resolve();
      });
      zip.readEntry();
    });
  });
}