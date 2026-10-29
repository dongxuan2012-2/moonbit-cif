// File-reading producer -> exact new physical artifact -> public API/real Lunar.
// Independent full source/output files and deletion ranges preceded API code.
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
const evidence = fs.mkdtempSync(path.join(example, 'work', 'curation-'));
const logs = path.join(evidence, 'logs');
fs.mkdirSync(logs);
const recipient = fs.mkdtempSync(path.join(path.dirname(repository), 'cif-curation-recipient-'));
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
  const expected = fs.readFileSync(path.join(fixtures, kind + '-expected.cif'));
  const o = oracle[kind];
  assert.equal(source.length, o.sourceBytes);
  assert.equal(digest(source), o.sourceSha256);
  assert.equal(expected.length, o.outputBytes);
  assert.equal(digest(expected), o.outputSha256);
  const input = path.join(evidence, kind + '-input.cif');
  const output = path.join(evidence, kind + '-curated.cif');
  writeExact(input, source);
  const actual = run(kind + '-producer', example, ['run', 'producer', '--target', 'js', '--target-dir', path.join(evidence, 'producer-build'), '--', kind, input]);
  assert.deepEqual(actual, expected);
  let oldAt = 0, newAt = 0;
  for (const [start, end] of o.ranges) {
    const size = start - oldAt;
    assert.deepEqual(actual.subarray(newAt, newAt + size), source.subarray(oldAt, start));
    newAt += size; oldAt = end;
  }
  assert.deepEqual(actual.subarray(newAt), source.subarray(oldAt));
  writeExact(output, actual);
  const received = JSON.parse(run(kind + '-receiver', recipient, ['run', 'receiver', '--target', 'js', '--target-dir', path.join(recipient, 'build'), '--', kind, 'curated', output, input, path.join(fixtures, kind + '-expected.cif')]).toString('utf8'));
  assert.equal(received.ok, true);
  assert.equal(received.mode, 'curated');
  assert.equal(received.rows, o.rowsAfter);
  assert.equal(received.receivedBytes, o.outputBytes);
  assert.equal(received.realLunar, true);
  assert.equal(received.unitChosenByCaller, 'm');
  assert.deepEqual(received.retainedMeasurementValues, o.retainedMeasurements.map(m => m.value));
  assert.deepEqual(received.retainedUncertainties, o.retainedMeasurements.map(m => m.uncertainty));
  assert.equal(received.allOutsideRangesVerified, true);
  assert.deepEqual(fs.readFileSync(input), source);
  assert.deepEqual(fs.readFileSync(output), expected);
  deliveries.push({ kind, input: identity(input), output: identity(output), removedRanges: o.ranges, receiver: received });
}
// Vary an unrelated original field to prove the producer reads its input path;
// the full independent golden relation changes only by that caller-owned text.
const variantSource = Buffer.from(fs.readFileSync(path.join(fixtures, 'cif2-source.cif'), 'utf8').replace('_root keep', '_root keep_variant'));
const variantExpected = Buffer.from(fs.readFileSync(path.join(fixtures, 'cif2-expected.cif'), 'utf8').replace('_root keep', '_root keep_variant'));
const variantInput = path.join(evidence, 'variant-input.cif');
const variantOutput = path.join(evidence, 'variant-curated.cif');
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
  proofBoundary: 'Self-authored public API/real Lunar recipient actually consumes written curated files; no third-party adoption, inferred outlier rule, new file-workflow command or scientific novelty is claimed.',
};
fs.writeFileSync(path.join(evidence, 'RESULT.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
