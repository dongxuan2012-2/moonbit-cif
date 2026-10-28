// Real file/JSON boundary checks; expected CIF files are handwritten in full.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = fileURLToPath(new URL('../', import.meta.url));
const fixtures = new URL('targets/', import.meta.url);
const source = fs.readFileSync(new URL('source.cif', fixtures));
const plans = JSON.parse(fs.readFileSync(new URL('plans.json', fixtures), 'utf8'));
const golden = {
  'valid-prefix': fs.readFileSync(new URL('expected-prefix.cif', fixtures)),
  'valid-selection': fs.readFileSync(new URL('expected-selection.cif', fixtures)),
};
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceHash = '576c9c6ab132d5e26e02150107b630e1d5e1f723f26d06720fd8e464f66503f5';
const expectedHashes = {
  'valid-prefix': '9c956ef08f2f3979da72047e0599151af668292c94b014bf766f285886dccc48',
  'valid-selection': '086c759fcf2c17492bf281c04a1e39bcfea04f51ac30cec6fdfd69185285e566',
};
assert.equal(source.length, 112);
assert.equal(digest(source), sourceHash);
for (const [name, bytes] of Object.entries(golden)) {
  assert.equal(bytes.length, 112);
  assert.equal(digest(bytes), expectedHashes[name]);
}
for (const plan of Object.values(plans)) assert.equal(plan.sourceSha256, sourceHash);

const work = path.join(example, 'work');
fs.mkdirSync(work, { recursive: true });
const temporary = fs.mkdtempSync(path.join(work, 'plan-targets-'));
const cases = [];
for (const name of ['missing-id', 'ambiguous-id', 'invalid-later-value']) {
  for (const existing of [false, true]) cases.push({ name, existing });
}
cases.push({ name: 'valid-prefix', existing: false },
  { name: 'valid-selection', existing: false },
  { name: 'valid-selection', existing: true });
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
  for (const { name, existing } of cases) {
    const label = name + (existing ? '-existing' : '');
    const directory = path.join(temporary, label);
    fs.mkdirSync(directory);
    const input = path.join(directory, 'input.cif');
    const plan = path.join(directory, 'plan.json');
    const output = path.join(directory, 'output.cif');
    fs.writeFileSync(input, source);
    fs.writeFileSync(plan, JSON.stringify(plans[name], null, 2) + '\n');
    if (existing) fs.writeFileSync(output, Buffer.from('EXISTING TARGET\r\n\x00\xff', 'latin1'));
    const before = snapshot(directory);
    // No expected-result option: exercise plan validation and the default CLI.
    const child = spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', [
      'run', '.', '--target', 'js', '--target-dir', path.join(temporary, 'build'),
      '--', 'apply', input, plan, output,
    ], { cwd: example, encoding: 'utf8', timeout: 120_000 });
    assert.ifError(child.error);
    assert.equal(child.signal, null);
    const receipt = JSON.parse(child.stdout);
    const after = snapshot(directory);
    assert.deepEqual(after['input.cif'], before['input.cif'], `${label}: input changed`);
    assert.deepEqual(after['plan.json'], before['plan.json'], `${label}: saved plan changed`);
    if (name.startsWith('valid-') && !existing) {
      assert.equal(child.status, 0, child.stderr);
      assert.equal(receipt.ok, true);
      assert.deepEqual(after['output.cif'], golden[name], `${label}: independent whole-file bytes differ`);
      assert.deepEqual(Object.keys(after).sort(), ['input.cif', 'output.cif', 'plan.json']);
      assert.equal(receipt.sourceSha256, sourceHash);
      assert.equal(receipt.disk.readbackVerified, true);
      assert.equal(receipt.disk.bytes, golden[name].length);
      assert.equal(receipt.disk.sha256, expectedHashes[name]);
      assert.equal(receipt.disk.expectedResultSha256, undefined);
    } else {
      assert.equal(child.status, 1, `${label}: invalid plan/output must fail the process`);
      assert.equal(receipt.ok, false);
      const reason = {
        'missing-id': /ID must identify exactly one row: missing/,
        'ambiguous-id': /ID must identify exactly one row: dup/,
        'invalid-later-value': /single legal CIF value/,
        'valid-selection': /EEXIST/,
      }[name];
      assert.match(receipt.error, reason);
      // Every invalid plan starts with the independently verified legal prefix.
      // Exact directory/file equality rejects partial output and sentinel damage.
      assert.deepEqual(after, before, `${label}: rejection changed filesystem state`);
    }
    outcomes.push({ case: label, exitCode: child.status, receipt,
      before: identities(before), after: identities(after) });
  }
  console.log(JSON.stringify({ ok: true, cases: outcomes, independentExpected: {
    sourceBytes: source.length, sourceSha256: sourceHash,
    prefixSha256: expectedHashes['valid-prefix'], selectionSha256: expectedHashes['valid-selection'],
    goldenBytes: 112, expectedResultOptionUsed: false,
    semantics: 'A/a distinct; quoted ?/. selectable, bare ?/. unchanged; [A] not a scalar ID; duplicate dup remains ambiguous',
  } }, null, 2));
  passed = true;
} finally {
  if (passed) {
    assert.equal(path.dirname(temporary), work);
    assert.ok(path.basename(temporary).startsWith('plan-targets-'));
    fs.rmSync(temporary, { recursive: true });
  } else {
    console.error('Filesystem evidence retained at:', temporary);
  }
}
