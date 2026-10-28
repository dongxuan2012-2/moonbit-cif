// Integration handoff only: the public library returns String and has no disk API.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = path.resolve(fileURLToPath(new URL('./', import.meta.url)));
const repository = path.resolve(example, '../..');
const originalPath = path.join(example, 'fixtures/original.cif');
const expectedPath = path.join(example, 'fixtures/expected.cif');
const original = fs.readFileSync(originalPath);
const expected = fs.readFileSync(expectedPath);
// This literal and both full files were frozen before append API implementation.
const inserted = Buffer.from('B\r\n2.500(3)\r\n.\r\n');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(original.length, 96);
assert.equal(expected.length, 112);
assert.equal(inserted.length, 16);
assert.deepEqual(expected, Buffer.concat([original.subarray(0, 82), inserted, original.subarray(82)]));
fs.mkdirSync(path.join(example, 'work'), { recursive: true });
const evidence = fs.mkdtempSync(path.join(example, 'work', 'handoff-'));
// A separate module physically outside this Git checkout consumes public APIs.
const recipient = fs.mkdtempSync(path.join(path.dirname(repository), 'cif-append-recipient-'));
assert.equal(path.dirname(recipient), path.dirname(repository));
assert.equal(recipient.startsWith(repository + path.sep), false);
for (const name of ['moon.mod', 'moon.pkg', 'main.mbt']) {
  fs.copyFileSync(path.join(repository, 'examples/append-receiver', name), path.join(recipient, name));
}
fs.writeFileSync(path.join(recipient, 'moon.work'), `members = [".", ${JSON.stringify(repository.replaceAll('\\', '/'))}]\n`);
const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';

function run(label, directory, args) {
  const child = spawnSync(moon, args, { cwd: directory, timeout: 180_000 });
  fs.writeFileSync(path.join(evidence, `${label}.stdout`), child.stdout ?? Buffer.alloc(0));
  fs.writeFileSync(path.join(evidence, `${label}.stderr`), child.stderr ?? Buffer.alloc(0));
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, 0, child.stderr.toString('utf8'));
  return child.stdout;
}

const outputBytes = run('producer', example, ['run', '.', '--target', 'js', '--target-dir', path.join(evidence, 'producer-build')]);
assert.deepEqual(outputBytes, expected);
assert.deepEqual(outputBytes.subarray(0, 82), original.subarray(0, 82));
assert.deepEqual(outputBytes.subarray(82, 98), inserted);
assert.deepEqual(outputBytes.subarray(98), original.subarray(82));
const outputPath = path.join(evidence, 'appended.cif');
const descriptor = fs.openSync(outputPath, 'wx');
try {
  fs.writeFileSync(descriptor, outputBytes);
  fs.fsyncSync(descriptor);
} finally {
  fs.closeSync(descriptor);
}
assert.deepEqual(fs.readFileSync(outputPath), expected);
const insertedPath = path.join(evidence, 'inserted.bin');
fs.writeFileSync(insertedPath, inserted);
const received = JSON.parse(run('receiver', recipient, [
  'run', '.', '--target', 'js', '--target-dir', path.join(recipient, 'build'), '--',
  outputPath, originalPath, insertedPath, 'appended',
]).toString('utf8'));
assert.equal(received.ok, true);
assert.equal(received.mode, 'appended');
assert.equal(received.rows, 2);
assert.equal(received.value, 2.5);
assert.equal(received.uncertainty, 0.003);
assert.equal(received.unitChosenByCaller, 'm');
assert.equal(received.sourceReadOnly, true);
assert.equal(received.rawByteRelationVerified, true);
assert.deepEqual(fs.readFileSync(originalPath), original);
assert.deepEqual(fs.readFileSync(outputPath), expected);
function jsArtifacts(directory) {
  const out = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) out.push(...jsArtifacts(filename));
    else if (entry.name.endsWith('.js')) {
      const raw = fs.readFileSync(filename);
      out.push({ path: filename, bytes: raw.length, sha256: digest(raw) });
    }
  }
  return out;
}
const receipt = {
  ok: true, originalBytes: 96, insertedBytes: 16, insertionOffset: 82, outputBytes: 112,
  originalSha256: digest(original), insertedSha256: digest(inserted), outputSha256: digest(expected),
  output: outputPath, evidenceDirectory: evidence, externalRecipientDirectory: recipient,
  externalToGitCheckout: true, receiver: received,
  compiledArtifacts: [...jsArtifacts(path.join(evidence, 'producer-build')), ...jsArtifacts(path.join(recipient, 'build'))],
  proofBoundary: 'Actual file/API/Lunar receiving only; no laboratory request, external adoption or market validation',
};
fs.writeFileSync(path.join(evidence, 'RECEIPT.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
