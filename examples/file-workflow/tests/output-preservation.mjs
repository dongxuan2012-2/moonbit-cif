// Exercise real CLI processes and filesystem state, without deriving expected
// bytes from preview/apply. sample.expected.cif is the hand-authored full result.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = fileURLToPath(new URL('../', import.meta.url));
const source = fs.readFileSync(path.join(example, 'sample.cif'));
const plan = fs.readFileSync(path.join(example, 'sample-plan.json'));
const expected = fs.readFileSync(new URL('sample.expected.cif', import.meta.url));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const expectedHash = 'ab8513302dd7ee81be2aa181c6ff052645f768ac8bdca5437c1ba6443fc15665';
assert.equal(expected.length, 185);
assert.equal(digest(expected), expectedHash);
assert.equal(digest(source), JSON.parse(plan.toString('utf8')).sourceSha256);

const work = path.join(example, 'work');
fs.mkdirSync(work, { recursive: true });
const temporary = fs.mkdtempSync(path.join(work, 'output-preservation-'));
const outcomes = [];
let passed = false;

function snapshot(directory) {
  return Object.fromEntries(fs.readdirSync(directory).sort().map(name => [
    name, fs.readFileSync(path.join(directory, name)),
  ]));
}

function identities(files) {
  return Object.fromEntries(Object.entries(files).map(([name, bytes]) => [
    name, { bytes: bytes.length, sha256: digest(bytes) },
  ]));
}

try {
  for (const name of ['stale-source', 'wrong-result-hash', 'existing-output', 'valid-control']) {
    const directory = path.join(temporary, name);
    fs.mkdirSync(directory);
    const input = path.join(directory, 'input.cif');
    const savedPlan = path.join(directory, 'plan.json');
    const output = path.join(directory, 'output.cif');
    fs.writeFileSync(input, name === 'stale-source'
      ? Buffer.concat([source, Buffer.from('# changed since saved plan\n')]) : source);
    fs.writeFileSync(savedPlan, plan);
    if (name === 'existing-output') fs.writeFileSync(output, Buffer.from('EXISTING OUTPUT\r\n\x00\xff\n', 'latin1'));
    const before = snapshot(directory);
    const result = spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', [
      'run', '.', '--target', 'js', '--target-dir', path.join(temporary, 'build'),
      '--', 'apply', input, savedPlan, output, '--expect-result-sha256',
      name === 'wrong-result-hash' ? '0'.repeat(64) : expectedHash,
    ], { cwd: example, encoding: 'utf8', timeout: 120_000 });
    assert.ifError(result.error);
    assert.equal(result.signal, null, `${name}: unexpected signal`);
    const receipt = JSON.parse(result.stdout);
    const after = snapshot(directory);
    assert.deepEqual(after['input.cif'], before['input.cif'], `${name}: input changed`);
    assert.deepEqual(after['plan.json'], before['plan.json'], `${name}: saved plan changed`);
    if (name === 'valid-control') {
      assert.equal(result.status, 0, result.stderr);
      assert.equal(receipt.ok, true);
      assert.deepEqual(after['output.cif'], expected, 'Full output differs from independent golden bytes');
      assert.equal(receipt.disk.readbackVerified, true);
      assert.equal(receipt.disk.bytes, expected.length);
      assert.equal(receipt.disk.sha256, expectedHash);
      assert.equal(receipt.disk.expectedResultSha256, expectedHash);
    } else {
      assert.equal(result.status, 1, `${name}: failure must propagate to the process`);
      assert.equal(receipt.ok, false);
      assert.equal(typeof receipt.error, 'string');
      const error = {
        'stale-source': /sourceSha256 differs/,
        'wrong-result-hash': /Expected result SHA256 differs/,
        'existing-output': /EEXIST/,
      }[name];
      assert.match(receipt.error, error);
      // Checks absence of any new file for invalid identities, and exact bytes
      // (including binary sentinel) for a pre-existing output.
      assert.deepEqual(after, before, `${name}: filesystem changed on rejection`);
    }
    outcomes.push({ case: name, exitCode: result.status, receipt,
      before: identities(before), after: identities(after) });
  }
  console.log(JSON.stringify({ ok: true, cases: outcomes, independentExpected: {
    fixture: 'tests/sample.expected.cif', bytes: expected.length, sha256: expectedHash,
  } }, null, 2));
  passed = true;
} finally {
  if (passed) {
    // Delete only the fresh child directory allocated above, never the work root.
    assert.equal(path.dirname(temporary), work);
    assert.ok(path.basename(temporary).startsWith('output-preservation-'));
    fs.rmSync(temporary, { recursive: true });
  } else {
    console.error('Filesystem evidence retained at:', temporary);
  }
}
