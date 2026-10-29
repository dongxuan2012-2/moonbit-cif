// A caller-owned metadata creation policy over real input files, with independent
// complete golden bytes and an outside-checkout public API/real Lunar recipient.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = path.resolve(fileURLToPath(new URL('./', import.meta.url)));
const repository = path.resolve(example, '../..');
const fixtures = path.join(example, 'fixtures');
const oracle = JSON.parse(fs.readFileSync(path.join(fixtures, 'expected.json'), 'utf8'));
const digest = raw => createHash('sha256').update(raw).digest('hex');
const identity = filename => { const raw = fs.readFileSync(filename); return { path: filename, bytes: raw.length, sha256: digest(raw) }; };
fs.mkdirSync(path.join(example, 'work'), { recursive: true });
const evidence = fs.mkdtempSync(path.join(example, 'work', 'provenance-'));
const logs = path.join(evidence, 'logs');
fs.mkdirSync(logs);
// Optional location lets callers choose a writable external workspace.
const recipientBase = path.resolve(process.env.CIF_EXAMPLE_RECIPIENT_ROOT ?? path.dirname(repository));
fs.mkdirSync(recipientBase, { recursive: true });
const recipient = fs.mkdtempSync(path.join(recipientBase, 'cif-provenance-recipient-'));
assert.equal(recipient.startsWith(repository + path.sep), false);
fs.mkdirSync(path.join(recipient, 'receiver'));
for (const name of ['moon.mod', 'receiver/main.mbt', 'receiver/moon.pkg']) fs.copyFileSync(path.join(example, name), path.join(recipient, name));
fs.writeFileSync(path.join(recipient, 'moon.work'), `members = [".", ${JSON.stringify(repository.replaceAll('\\', '/'))}]\n`);
const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';
const commands = [];
function run(label, directory, args) {
  const child = spawnSync(moon, args, { cwd: directory, timeout: 180_000 });
  fs.writeFileSync(path.join(logs, label + '.stdout'), child.stdout ?? Buffer.alloc(0));
  fs.writeFileSync(path.join(logs, label + '.stderr'), child.stderr ?? Buffer.alloc(0));
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, 0, child.stderr.toString());
  commands.push({ label, directory, args, exitCode: child.status });
  return child.stdout;
}
function writeExact(filename, raw) {
  const fd = fs.openSync(filename, 'wx');
  try { fs.writeFileSync(fd, raw); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  assert.deepEqual(fs.readFileSync(filename), raw);
}
const deliveries = [];
for (const kind of ['cif2', 'cif1']) {
  const source = fs.readFileSync(path.join(fixtures, kind + '-source.cif'));
  const inserted = fs.readFileSync(path.join(fixtures, kind + '-inserted.cif'));
  const expected = fs.readFileSync(path.join(fixtures, kind + '-expected.cif'));
  const o = oracle[kind];
  for (const [raw, size, hash] of [[source, o.sourceBytes, o.sourceSha256], [inserted, o.insertedBytes, o.insertedSha256], [expected, o.outputBytes, o.outputSha256]]) {
    assert.equal(raw.length, size); assert.equal(digest(raw), hash);
  }
  assert.deepEqual(expected, Buffer.concat([source.subarray(0, o.insertOffset), inserted, source.subarray(o.insertOffset)]));
  const input = path.join(evidence, kind + '-input.cif');
  const output = path.join(evidence, kind + '-added.cif');
  writeExact(input, source);
  const actual = run(kind + '-producer', example, ['run', 'producer', '--target', 'js', '--target-dir', path.join(evidence, 'producer-build'), '--', kind, input]);
  assert.deepEqual(actual, expected);
  assert.deepEqual(actual.subarray(0, o.insertOffset), source.subarray(0, o.insertOffset));
  assert.deepEqual(actual.subarray(o.insertOffset, o.insertOffset + inserted.length), inserted);
  assert.deepEqual(actual.subarray(o.insertOffset + inserted.length), source.subarray(o.insertOffset));
  writeExact(output, actual);
  const received = JSON.parse(run(kind + '-receiver', recipient, ['run', 'receiver', '--target', 'js', '--target-dir', path.join(recipient, 'build'), '--', kind, 'added', output, input, path.join(fixtures, kind + '-inserted.cif'), path.join(fixtures, kind + '-expected.cif')]).toString('utf8'));
  assert.equal(received.ok, true);
  assert.equal(received.newNoteReceived, true);
  assert.equal(received.realLunar, true);
  assert.equal(received.unitChosenByCaller, 'm');
  assert.deepEqual(received.values, o.oldMeasurements.map(m => m.value));
  assert.deepEqual(received.uncertainties, o.oldMeasurements.map(m => m.uncertainty));
  assert.equal(received.oldBytesAndScopesPreserved, true);
  assert.deepEqual(fs.readFileSync(input), source);
  assert.deepEqual(fs.readFileSync(output), expected);
  deliveries.push({ kind, input: identity(input), output: identity(output), receiver: received });
}
const variantSource = Buffer.from(fs.readFileSync(path.join(fixtures, 'cif2-source.cif'), 'utf8').replace('_x keep', '_x keep_variant'));
const variantExpected = Buffer.from(fs.readFileSync(path.join(fixtures, 'cif2-expected.cif'), 'utf8').replace('_x keep', '_x keep_variant'));
const variantInput = path.join(evidence, 'variant-input.cif');
const variantOutput = path.join(evidence, 'variant-added.cif');
writeExact(variantInput, variantSource);
const variant = run('variant-producer', example, ['run', 'producer', '--target', 'js', '--target-dir', path.join(evidence, 'producer-build'), '--', 'cif2', variantInput]);
assert.deepEqual(variant, variantExpected);
writeExact(variantOutput, variant);
assert.deepEqual(fs.readFileSync(variantInput), variantSource);
function jsArtifacts(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? jsArtifacts(filename) : entry.name.endsWith('.js') ? [identity(filename)] : [];
  });
}
const receipt = {
  ok: true, deliveries, variant: { input: identity(variantInput), output: identity(variantOutput), completeIndependentExpectedSha256: digest(variantExpected) },
  evidenceDirectory: evidence, externalRecipientDirectory: recipient, externalToGitCheckout: true,
  commands, compiledArtifacts: [...jsArtifacts(path.join(evidence, 'producer-build')), ...jsArtifacts(path.join(recipient, 'build'))],
  receiverSources: ['moon.mod', 'moon.work', 'receiver/main.mbt', 'receiver/moon.pkg'].map(name => identity(path.join(recipient, name))),
  rawLogs: fs.readdirSync(logs).sort().map(name => identity(path.join(logs, name))),
  proofBoundary: 'Actual new Pair and retained measurements received through public APIs and pinned real Lunar; self-authored receiving is not third-party adoption or new scientific/metadata standards.',
};
fs.writeFileSync(path.join(evidence, 'RESULT.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
