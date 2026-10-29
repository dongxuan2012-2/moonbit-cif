// Actual arbitrary-path CLI -> new physical file -> external public API/Lunar.
// The complete source/output fixtures were handwritten before implementation.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = path.resolve(fileURLToPath(new URL('../', import.meta.url)));
const repository = path.resolve(example, '../..');
const fixture = path.join(example, 'tests/append');
const oracle = JSON.parse(fs.readFileSync(path.join(fixture, 'expected.json'), 'utf8'));
const digest = raw => createHash('sha256').update(raw).digest('hex');
const identity = filename => {
  const raw = fs.readFileSync(filename);
  return { path: filename, bytes: raw.length, sha256: digest(raw) };
};
const data = Object.fromEntries(['cif2', 'cif1'].map(kind => {
  const source = fs.readFileSync(path.join(fixture, `${kind}-source.cif`));
  const inserted = fs.readFileSync(path.join(fixture, `${kind}-inserted.cif`));
  const expected = fs.readFileSync(path.join(fixture, `${kind}-expected.cif`));
  const row = JSON.parse(fs.readFileSync(path.join(fixture, `${kind}-row.json`), 'utf8'));
  const o = oracle[kind];
  for (const [raw, bytes, hash] of [[source, o.sourceBytes, o.sourceSha256], [inserted, o.insertedBytes, o.insertedSha256], [expected, o.outputBytes, o.outputSha256]]) {
    assert.equal(raw.length, bytes);
    assert.equal(digest(raw), hash);
  }
  assert.deepEqual(expected, Buffer.concat([source.subarray(0, o.insertOffset), inserted, source.subarray(o.insertOffset)]));
  return [kind, { source, inserted, expected, row }];
}));
fs.mkdirSync(path.join(example, 'work'), { recursive: true });
const evidence = fs.mkdtempSync(path.join(example, 'work', 'append-file-'));
const logs = path.join(evidence, 'logs');
const foreignCwd = path.join(evidence, 'foreign-cwd');
fs.mkdirSync(logs);
fs.mkdirSync(foreignCwd);
const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';
const outcomes = [];

function processRun(label, executable, args, cwd, env = process.env) {
  const child = spawnSync(executable, args, { cwd, env, timeout: 180_000 });
  fs.writeFileSync(path.join(logs, `${label}.stdout`), child.stdout ?? Buffer.alloc(0));
  fs.writeFileSync(path.join(logs, `${label}.stderr`), child.stderr ?? Buffer.alloc(0));
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  return child;
}

function jsArtifacts(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? jsArtifacts(filename) : entry.name.endsWith('.js') ? [identity(filename)] : [];
  });
}
const built = processRun('build-cli', moon, ['build', '--deny-warn', '--target', 'js', '--target-dir', path.join(evidence, 'cli-build')], example);
assert.equal(built.status, 0, built.stderr.toString());
const compiled = jsArtifacts(path.join(evidence, 'cli-build'));
const entrypoints = compiled.filter(item => path.basename(item.path) === 'cif-file-workflow-example.js');
assert.equal(entrypoints.length, 1);
const cli = entrypoints[0].path;
const recipient = fs.mkdtempSync(path.join(path.dirname(repository), 'cif-file-append-recipient-'));
assert.equal(recipient.startsWith(repository + path.sep), false);
for (const name of ['moon.mod', 'moon.pkg', 'main.mbt']) {
  fs.copyFileSync(path.join(repository, 'examples/file-append-receiver', name), path.join(recipient, name));
}
fs.writeFileSync(path.join(recipient, 'moon.work'), `members = [".", ${JSON.stringify(repository.replaceAll('\\', '/'))}]\n`);

function snapshot(directory) {
  return Object.fromEntries(fs.readdirSync(directory).sort().filter(name => fs.statSync(path.join(directory, name)).isFile()).map(name => [name, fs.readFileSync(path.join(directory, name))]));
}
const snapshotIds = files => Object.fromEntries(Object.entries(files).map(([name, raw]) => [name, { bytes: raw.length, sha256: digest(raw) }]));
function readonly(label, args) {
  const result = processRun(label, process.execPath, [cli, ...args], foreignCwd);
  assert.equal(result.status, 0, result.stderr.toString());
  const receipt = JSON.parse(result.stdout);
  assert.equal(receipt.ok, true);
  return receipt;
}
const faultPreload = path.join(evidence, 'fault.cjs');
fs.writeFileSync(faultPreload, `
const fs = require('node:fs');
const path = require('node:path');
const target = process.env.CIF_APPEND_TEST_OUTPUT;
const originalRead = fs.readFileSync;
const originalUnlink = fs.unlinkSync;
fs.readFileSync = function(filename, ...args) {
  const raw = originalRead.call(this, filename, ...args);
  if (typeof filename === 'string' && path.resolve(filename) === target) return Buffer.from('forced readback mismatch');
  return raw;
};
fs.unlinkSync = function(filename, ...args) {
  if (process.env.CIF_APPEND_TEST_CLEANUP_FAIL === '1' && path.resolve(filename) === target) throw new Error('forced cleanup failure');
  return originalUnlink.call(this, filename, ...args);
};
`);

function appendCase(label, { kind = 'cif2', source = data[kind].source, row = structuredClone(data[kind].row), expected, error, resultHash, existing = false, samePath = false, missingInput = false, missingParent = false, rawRow, fault, catalogSelection = false } = {}) {
  const directory = path.join(evidence, label);
  fs.mkdirSync(directory);
  const input = path.join(directory, 'input.cif');
  const plan = path.join(directory, 'row.json');
  const output = samePath ? input : path.join(directory, missingParent ? 'absent/output.cif' : 'output.cif');
  if (!missingInput) fs.writeFileSync(input, source);
  if (catalogSelection) {
    const catalog = readonly(label + '-catalog-before', ['catalog', input]);
    const scope = kind === 'cif2' ? catalog.blocks[0].frames[0] : catalog.blocks[0];
    const selected = scope.loops[0]; // Explicit fixture policy, never an inferred ID.
    assert.deepEqual(selected.tags, oracle[kind].headers);
    assert.deepEqual([selected.span.start_offset, selected.span.end_offset], oracle[kind].loopSpanBefore);
    row.sourceSha256 = catalog.sourceSha256;
    row.block = catalog.blocks[0].name;
    if (kind === 'cif2') row.frame = scope.name;
    row.headers = selected.tags;
  }
  fs.writeFileSync(plan, rawRow ?? JSON.stringify(row));
  if (existing) fs.writeFileSync(output, Buffer.from([0, 255, 13, 10, 65]));
  const before = snapshot(directory);
  const argv = ['append', input, plan, output];
  if (resultHash !== undefined) argv.push('--expect-result-sha256', resultHash);
  const nodeArgs = fault ? ['--require', faultPreload, cli, ...argv] : [cli, ...argv];
  const env = fault ? { ...process.env, CIF_APPEND_TEST_OUTPUT: output, CIF_APPEND_TEST_CLEANUP_FAIL: fault === 'cleanup-fail' ? '1' : '0' } : process.env;
  const result = processRun(label, process.execPath, nodeArgs, foreignCwd, env);
  const receipt = JSON.parse(result.stdout);
  const after = snapshot(directory);
  for (const [name, raw] of Object.entries(before)) assert.deepEqual(after[name], raw, `${label}: protected ${name} changed`);
  if (expected) {
    assert.equal(result.status, 0, result.stderr.toString());
    assert.equal(receipt.ok, true);
    assert.equal(receipt.mode, 'append');
    assert.deepEqual(after['output.cif'], expected);
    assert.equal(receipt.disk.readbackVerified, true);
    assert.equal(receipt.disk.bytes, expected.length);
    assert.equal(receipt.disk.sha256, digest(expected));
    if (resultHash !== undefined) assert.equal(receipt.disk.expectedResultSha256, resultHash.toLowerCase());
  } else {
    assert.equal(result.status, 1, `${label}: must exit1`);
    assert.equal(receipt.ok, false);
    assert.match(receipt.error, error ?? /.+/);
    if (fault === 'cleanup-fail') {
      assert.match(receipt.error, /new output cleanup failed: forced cleanup failure/);
      assert.deepEqual(after['output.cif'], data[kind].expected);
    } else assert.deepEqual(after, before, `${label}: rejection must preserve the directory`);
  }
  outcomes.push({ case: label, exitCode: result.status, receipt, before: snapshotIds(before), after: snapshotIds(after) });
  return { input, output, receipt };
}

const deliveries = [];
for (const kind of ['cif2', 'cif1']) {
  const row = structuredClone(data[kind].row);
  if (kind === 'cif2') delete row.newline; // Default LF; old source keeps CRLF/BOM.
  const delivered = appendCase(kind + '-real-delivery', { kind, row, expected: data[kind].expected, resultHash: oracle[kind].outputSha256.toUpperCase(), catalogSelection: true });
  assert.equal(delivered.receipt.sourceSha256, oracle[kind].sourceSha256);
  assert.deepEqual(delivered.receipt.target.headers, oracle[kind].headers);
  assert.equal(delivered.receipt.target.rowCountBefore, oracle[kind].rowCountBefore);
  assert.equal(delivered.receipt.target.rowCountAfter, oracle[kind].rowCountAfter);
  const actual = fs.readFileSync(delivered.output);
  const at = oracle[kind].insertOffset;
  assert.deepEqual(actual.subarray(0, at), data[kind].source.subarray(0, at));
  assert.deepEqual(actual.subarray(at, at + data[kind].inserted.length), data[kind].inserted);
  assert.deepEqual(actual.subarray(at + data[kind].inserted.length), data[kind].source.subarray(at));
  const catalog = readonly(kind + '-catalog-after', ['catalog', delivered.output]);
  const selected = kind === 'cif2' ? catalog.blocks[0].frames[0].loops[0] : catalog.blocks[0].loops[0];
  assert.deepEqual([selected.span.start_offset, selected.span.end_offset], oracle[kind].loopSpanAfter);
  assert.equal(selected.rowCount, oracle[kind].rowCountAfter);
  const received = processRun(kind + '-lunar-receiver', moon, ['run', '.', '--target', 'js', '--target-dir', path.join(recipient, 'build'), '--', kind, 'appended', delivered.output, delivered.input, path.join(fixture, `${kind}-inserted.cif`), path.join(fixture, `${kind}-expected.cif`)], recipient);
  assert.equal(received.status, 0, received.stderr.toString());
  const receipt = JSON.parse(received.stdout);
  assert.equal(receipt.ok, true);
  assert.equal(receipt.newMeasurementReceived, true);
  assert.equal(receipt.newValue, oracle[kind].measurement.value);
  assert.equal(receipt.newUncertainty, oracle[kind].measurement.uncertainty);
  assert.equal(receipt.unitChosenByCaller, 'm');
  assert.deepEqual(fs.readFileSync(delivered.input), data[kind].source);
  assert.deepEqual(fs.readFileSync(delivered.output), data[kind].expected);
  deliveries.push({ kind, input: identity(delivered.input), output: identity(delivered.output), cliReceipt: delivered.receipt, receiver: receipt });
}

const change = fn => { const row = structuredClone(data.cif2.row); fn(row); return row; };
const twoFrames = Buffer.from('#\\#CIF_2.0\ndata_f\nsave_a\nloop_\n_id\n_m\nA 1\nsave_\nsave_b\nloop_\n_id\n_m\nB 2\nsave_\n');
const twoFramesExpected = Buffer.from('#\\#CIF_2.0\ndata_f\nsave_a\nloop_\n_id\n_m\nA 1\nC\n3\nsave_\nsave_b\nloop_\n_id\n_m\nB 2\nsave_\n');
appendCase('other-frame-preserved', { source: twoFrames, row: { block: 'F', frame: 'A', sourceSha256: digest(twoFrames), headers: ['_id', '_m'], cells: [{ cif: 'C' }, { cif: '3' }] }, expected: twoFramesExpected });
appendCase('stale-source', { source: Buffer.concat([data.cif2.source, Buffer.from('# changed\n')]), error: /sourceSha256 differs/ });
appendCase('wrong-source-hash', { row: change(r => { r.sourceSha256 = '0'.repeat(64); }), error: /sourceSha256 differs/ });
appendCase('missing-block', { row: change(r => { r.block = 'absent'; }) });
appendCase('missing-frame', { row: change(r => { r.frame = 'absent'; }) });
appendCase('subset-headers', { row: change(r => { r.headers = r.headers.slice(0, 2); r.cells = r.cells.slice(0, 2); }), error: /catalog order/ });
appendCase('reordered-headers', { row: change(r => { r.headers.reverse(); r.cells.reverse(); }), error: /catalog order/ });
appendCase('header-spelling', { row: change(r => { r.headers = r.headers.map(t => t.toUpperCase()); }), error: /catalog order/ });
appendCase('duplicate-headers', { row: change(r => { r.headers[1] = r.headers[0]; }) });
appendCase('empty-headers', { row: change(r => { r.headers = []; r.cells = []; }) });
appendCase('cross-loop-headers', { row: change(r => { r.headers[1] = '_background_m'; }) });
appendCase('wrong-width', { row: change(r => { r.cells.pop(); }), error: /width/ });
appendCase('extra-values', { row: change(r => { r.cells[0] = { cif: 'R S' }; }) });
appendCase('extra-block', { row: change(r => { r.cells[0] = { cif: 'R\ndata_injected\n_x 1' }; }) });
appendCase('trailing-comment', { row: change(r => { r.cells[0] = { cif: 'R # injected' }; }) });
appendCase('text-crlf', { row: change(r => { r.cells[2] = { text: 'line\r\nnext' }; }) });
appendCase('ambiguous-cell-keys', { row: change(r => { r.cells[0].text = 'R'; }), error: /exactly one of cif\/text/ });
appendCase('malformed-cells', { row: change(r => { r.cells = 'wrong'; }), error: /cells must be an array/ });
appendCase('bad-newline', { row: change(r => { r.newline = '\r'; }), error: /LF or CRLF/ });
for (const [name, cell] of [['cif1-unrepresentable', { text: '测量' }], ['cif1-compound', { cif: '[1 2]' }]]) {
  const row = structuredClone(data.cif1.row); row.cells[2] = cell;
  appendCase(name, { kind: 'cif1', row });
}
appendCase('invalid-source', { source: Buffer.from('data_bad\nloop_\n_a\n_b\n1\n'), error: /Invalid CIF/ });
appendCase('invalid-utf8', { source: Buffer.from([0xc3]) });
appendCase('missing-input', { missingInput: true, error: /ENOENT/ });
appendCase('missing-output-parent', { missingParent: true, error: /ENOENT/ });
appendCase('existing-output', { existing: true, error: /EEXIST/ });
appendCase('input-as-output', { samePath: true, error: /EEXIST/ });
appendCase('wrong-result-hash', { resultHash: '0'.repeat(64), error: /Expected result SHA256 differs/ });
appendCase('malformed-result-hash', { resultHash: 'invalid', error: /64 hexadecimal/ });
appendCase('invalid-json-plan', { rawRow: '{broken', error: /Invalid JSON/ });
const context = Buffer.from("#\\#CIF_2.0\ndata_x\nloop_\n_v\n'x'#EOF");
appendCase('final-context', { source: context, row: { block: 'x', sourceSha256: digest(context), headers: ['_v'], cells: [{ cif: '2' }] }, error: /context/ });
appendCase('readback-mismatch-cleaned', { fault: 'mismatch', error: /Output byte readback mismatch/ });
appendCase('readback-cleanup-failure-reported', { fault: 'cleanup-fail', error: /Output byte readback mismatch/ });
const duplicate = change(r => { r.cells[0] = { cif: 'P' }; });
const duplicateExpected = Buffer.concat([data.cif2.source.subarray(0, 225), Buffer.from("P\n6.250(12)\n'late R'\n[3 {'x':4}]\n"), data.cif2.source.subarray(225)]);
appendCase('duplicate-id-is-caller-policy', { row: duplicate, expected: duplicateExpected });

const receipt = {
  ok: true, caseCount: outcomes.length, cases: outcomes, deliveries,
  evidenceDirectory: evidence, arbitraryWorkingDirectory: foreignCwd,
  executedCli: identity(cli),
  externalRecipientDirectory: recipient, externalToGitCheckout: true,
  compiledArtifacts: [...compiled, ...jsArtifacts(path.join(recipient, 'build'))],
  receiverSources: ['main.mbt', 'moon.mod', 'moon.pkg', 'moon.work'].map(name => identity(path.join(recipient, name))),
  rawLogs: fs.readdirSync(logs).sort().map(name => identity(path.join(logs, name))),
  proofBoundary: 'Actual arbitrary-file command and public API/real Lunar receiving; self-authored receiver does not establish third-party adoption or laboratory demand.',
};
fs.writeFileSync(path.join(evidence, 'RESULT.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({ ...receipt, cases: outcomes.map(({ case: name, exitCode }) => ({ case: name, exitCode })), rawLogs: undefined }, null, 2));
