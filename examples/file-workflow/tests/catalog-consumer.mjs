// Independent byte/structure oracle plus a real catalog -> query -> apply chain.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = fileURLToPath(new URL('../', import.meta.url));
const fixtures = new URL('catalog/', import.meta.url);
const source = fs.readFileSync(new URL('source.cif', fixtures));
const expectedOutput = fs.readFileSync(new URL('expected-output.cif', fixtures));
const pairOnly = fs.readFileSync(new URL('pair-only.cif', fixtures));
const oracle = JSON.parse(fs.readFileSync(new URL('expected.json', fixtures), 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(source.length, 198);
assert.equal(expectedOutput.length, 200);
assert.equal(pairOnly.length, 41);
assert.equal(digest(source), 'f320c106ae3815f6b1737a77de9fbf07d2c3712b7f89c63fb88598fc2632039d');
assert.equal(digest(expectedOutput), 'e64bb0efe596de6a8baafadd19a43ac2068ade198bc653665b9a4b4b42cc7ce8');
assert.equal(digest(pairOnly), '2ae5c34f04b21e339b7ae3655c42cfe49e86276636d3c435fb1815ab19fc657e');

const work = path.join(example, 'work');
fs.mkdirSync(work, { recursive: true });
const temporary = fs.mkdtempSync(path.join(work, 'catalog-consumer-'));
const flow = path.join(temporary, 'flow');
const pairDirectory = path.join(temporary, 'pair-only');
fs.mkdirSync(flow);
fs.mkdirSync(pairDirectory);
fs.writeFileSync(path.join(flow, 'input.cif'), source);
fs.writeFileSync(path.join(pairDirectory, 'input.cif'), pairOnly);
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

function invoke(label, directory, args, { success = true, createsOutput = false } = {}) {
  const before = snapshot(directory);
  const child = spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', [
    'run', '.', '--target', 'js', '--target-dir', path.join(temporary, 'build'), '--', ...args,
  ], { cwd: example, encoding: 'utf8', timeout: 120_000 });
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  const receipt = JSON.parse(child.stdout);
  const after = snapshot(directory);
  assert.equal(child.status, success ? 0 : 1, child.stderr);
  assert.equal(receipt.ok, success);
  for (const [name, bytes] of Object.entries(before)) assert.deepEqual(after[name], bytes, `${label}: ${name} changed`);
  if (createsOutput) {
    assert.deepEqual(Object.keys(after).sort(), [...Object.keys(before), 'output.cif'].sort());
    assert.deepEqual(after['output.cif'], expectedOutput, 'Independent complete output bytes differ');
  } else {
    assert.deepEqual(after, before, `${label}: read-only/rejected command changed files`);
  }
  outcomes.push({ case: label, args, exitCode: child.status, receipt,
    before: identities(before), after: identities(after) });
  return receipt;
}

function checkSlices(actual, checks, bytes) {
  for (const check of checks) {
    const span = check.path.reduce((value, key) => value[key], actual);
    assert.equal(bytes.subarray(span.start_offset, span.end_offset).toString('utf8'), check.literal);
  }
}

function scopeFromCatalog(catalog) {
  // Explicit fixture policy: this caller selects the known first frame/loop,
  // its first column as ID, and the other columns as data. No ID is inferred.
  const block = catalog.blocks[0];
  const frame = block.frames[0];
  const loop = frame.loops[0];
  return { block: block.name, frame: frame.name, idTag: loop.tags[0], columns: loop.tags.slice(1) };
}

try {
  const input = path.join(flow, 'input.cif');
  const output = path.join(flow, 'output.cif');
  const scopePath = path.join(flow, 'scope.json');
  const planPath = path.join(flow, 'plan.json');
  const catalog = invoke('catalog-source', flow, ['catalog', input]);
  assert.deepEqual(catalog, oracle.catalogBefore);
  checkSlices(catalog, oracle.beforeSlices, source);
  const scope = scopeFromCatalog(catalog);
  fs.writeFileSync(scopePath, JSON.stringify(scope, null, 2) + '\n');
  const query = invoke('query-from-catalog', flow, ['query', input, scopePath]);
  assert.deepEqual(query, oracle.queryBefore);
  for (const row of query.rows) {
    for (const cell of row) assert.equal(source.subarray(cell.span.start_offset, cell.span.end_offset).toString('utf8'), cell.literal);
  }
  // The caller explicitly chooses row B and a replacement; names/tags, the
  // decoded ID and source identity come from the actual discovery/query flow.
  const plan = { block: scope.block, frame: scope.frame, idTag: scope.idTag,
    sourceSha256: query.sourceSha256,
    edits: [{ id: query.rows[1][0].value, tag: scope.columns[1], cif: '2000' }] };
  fs.writeFileSync(planPath, JSON.stringify(plan, null, 2) + '\n');
  const applied = invoke('apply-from-query', flow, ['apply', input, planPath, output], { createsOutput: true });
  assert.equal(applied.disk.readbackVerified, true);
  assert.equal(applied.disk.bytes, expectedOutput.length);
  assert.equal(applied.disk.sha256, digest(expectedOutput));
  const catalogAfter = invoke('catalog-output', flow, ['catalog', output]);
  assert.deepEqual(catalogAfter, oracle.catalogAfter);
  checkSlices(catalogAfter, oracle.afterSlices, expectedOutput);
  const queryAfter = invoke('query-output', flow, ['query', output, scopePath]);
  assert.deepEqual(queryAfter, oracle.queryAfter);

  const pairInput = path.join(pairDirectory, 'input.cif');
  const pairCatalog = invoke('catalog-pair-only', pairDirectory, ['catalog', pairInput]);
  assert.deepEqual(pairCatalog, oracle.pairCatalog);
  checkSlices(pairCatalog, oracle.pairSlices, pairOnly);
  const block = pairCatalog.blocks[0];
  const badScope = path.join(pairDirectory, 'scope.json');
  fs.writeFileSync(badScope, JSON.stringify({ block: block.name, idTag: block.pairs[0].tag, columns: [] }) + '\n');
  const rejected = invoke('pair-is-not-loop', pairDirectory, ['query', pairInput, badScope], { success: false });
  assert.equal(typeof rejected.error, 'string');
  assert.ok(rejected.error.length > 0);
  console.log(JSON.stringify({ ok: true, cases: outcomes, independentExpected: {
    sourceBytes: source.length, sourceSha256: digest(source), outputBytes: expectedOutput.length,
    outputSha256: digest(expectedOutput), pairOnlyBytes: pairOnly.length, pairOnlySha256: digest(pairOnly),
    oracle: 'tests/catalog/expected.json',
    spanUnits: 'Half-open original UTF-8 byte offsets; Unicode scalar columns; CRLF one newline; BOM bytes retained',
    downstreamUsesCatalogAndQueryIdentifiers: true,
  } }, null, 2));
  passed = true;
} finally {
  if (passed) {
    assert.equal(path.dirname(temporary), work);
    assert.ok(path.basename(temporary).startsWith('catalog-consumer-'));
    fs.rmSync(temporary, { recursive: true });
  } else {
    console.error('Filesystem evidence retained at:', temporary);
  }
}
