// Consumer contracts for saved JSON, not a second renderer or replay algorithm.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = fileURLToPath(new URL('../', import.meta.url));
const fixture = new URL('review/', import.meta.url);
const source = fs.readFileSync(new URL('source.cif', fixture));
const expected = fs.readFileSync(new URL('expected.cif', fixture));
const saved = JSON.parse(fs.readFileSync(new URL('preview.json', fixture), 'utf8'));
const contexts = JSON.parse(fs.readFileSync(new URL('expected-context.json', fixture), 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceHash = '33ac5334051846490236266a9bad25188267ef5adea62e6c6ebdd0a1bea74aae';
const expectedHash = '6ba2af85576d237d4f06fccd4b3ede397f0961f5bb72d7cc1b51ce20b725ce8f';
assert.equal(source.length, 98);
assert.equal(expected.length, 104);
assert.equal(digest(source), sourceHash);
assert.equal(digest(expected), expectedHash);
assert.equal(saved.sourceSha256, sourceHash);
assert.equal(saved.planned.sha256, expectedHash);
assert.equal(saved.planned.bytes, expected.length);

const work = path.join(example, 'work');
fs.mkdirSync(work, { recursive: true });
const temporary = fs.mkdtempSync(path.join(work, 'saved-preview-'));
const cases = [];
for (const name of ['source-hash-mismatch', 'planned-hash-mismatch', 'planned-byte-count-mismatch', 'overlap']) {
  for (const existing of [false, true]) cases.push({ name, existing });
}
cases.push({ name: 'valid-context', existing: false },
  { name: 'offline-two-argument', existing: false },
  { name: 'valid-existing-review', existing: true });
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
    const label = name + (existing && name !== 'valid-existing-review' ? '-existing' : '');
    const directory = path.join(temporary, label);
    fs.mkdirSync(directory);
    const preview = structuredClone(saved);
    if (name === 'planned-hash-mismatch') preview.planned.sha256 = '0'.repeat(64);
    if (name === 'planned-byte-count-mismatch') preview.planned.bytes++;
    if (name === 'overlap') {
      preview.edits.push(structuredClone(preview.edits[0]));
      preview.editCount++;
    }
    if (name === 'offline-two-argument') preview.input = 'does-not-exist.cif';
    fs.writeFileSync(path.join(directory, 'source.cif'), name === 'source-hash-mismatch'
      ? Buffer.concat([source, Buffer.from('# changed source\r\n')]) : source);
    fs.writeFileSync(path.join(directory, 'preview.json'), JSON.stringify(preview, null, 2) + '\n');
    if (existing) fs.writeFileSync(path.join(directory, 'review.html'), Buffer.from('EXISTING REVIEW\r\n\x00\xff', 'latin1'));
    const before = snapshot(directory);
    const args = [path.join(example, 'review-preview.mjs'), 'preview.json', 'review.html'];
    if (name !== 'offline-two-argument') args.push('--source', 'source.cif');
    const child = spawnSync(process.execPath, args, { cwd: directory, encoding: 'utf8', timeout: 30_000 });
    assert.ifError(child.error);
    assert.equal(child.signal, null);
    const receipt = JSON.parse(child.stdout);
    const after = snapshot(directory);
    assert.deepEqual(after['source.cif'], before['source.cif'], `${label}: source changed`);
    assert.deepEqual(after['preview.json'], before['preview.json'], `${label}: saved preview changed`);
    if (name !== 'valid-context' && name !== 'offline-two-argument') {
      assert.equal(child.status, 1, `${label}: rejection must reach the process`);
      assert.equal(receipt.ok, false);
      const rejection = {
        'source-hash-mismatch': /Source SHA256 differs/,
        'planned-hash-mismatch': /Planned result bytes differ/,
        'planned-byte-count-mismatch': /Planned result bytes differ/,
        'overlap': /Overlapping original byte spans/,
        'valid-existing-review': /EEXIST/,
      }[name];
      assert.match(receipt.error, rejection);
      assert.deepEqual(after, before, `${label}: rejection changed files`);
    } else {
      assert.equal(child.status, 0, child.stderr);
      assert.equal(receipt.ok, true);
      assert.equal(receipt.writesCifFiles, false);
      assert.equal(receipt.approvesEdits, false);
      assert.equal(receipt.htmlSha256, digest(after['review.html']));
      assert.deepEqual(Object.keys(after).sort(), ['preview.json', 'review.html', 'source.cif']);
      const html = after['review.html'].toString('utf8');
      const blocks = kind => [...html.matchAll(new RegExp(`<code class="${kind}">([\\s\\S]*?)</code>`, 'g'))].map(match => match[1]);
      // Explicit hand-escaped fragments; the product is not our oracle.
      assert.deepEqual(blocks('original'), contexts.originals);
      assert.deepEqual(blocks('replacement'), contexts.replacements);
      if (name === 'valid-context') {
        assert.deepEqual(blocks('source-context-text'), contexts.source);
        assert.deepEqual(blocks('planned-context-text'), contexts.planned);
        assert.equal(receipt.sourceContext.verifiedSpans, 2);
        assert.equal(receipt.sourceContext.sha256, sourceHash);
        assert.equal(receipt.plannedReplay.verified, true);
        assert.equal(receipt.plannedReplay.bytes, expected.length);
        assert.equal(receipt.plannedReplay.sha256, expectedHash);
      } else {
        // Offline mode must succeed even though preview.input does not exist.
        assert.equal(receipt.sourceContext, undefined);
        assert.equal(receipt.plannedReplay, undefined);
        assert.deepEqual(blocks('source-context-text'), []);
        assert.deepEqual(blocks('planned-context-text'), []);
      }
    }
    outcomes.push({ case: label, exitCode: child.status, receipt,
      before: identities(before), after: identities(after) });
  }
  console.log(JSON.stringify({ ok: true, cases: outcomes, independentExpected: {
    sourceBytes: source.length, sourceSha256: sourceHash, plannedBytes: expected.length,
    plannedSha256: expectedHash, contexts: 'tests/review/expected-context.json',
    browserVisualCertification: false,
  } }, null, 2));
  passed = true;
} finally {
  if (passed) {
    assert.equal(path.dirname(temporary), work);
    assert.ok(path.basename(temporary).startsWith('saved-preview-'));
    fs.rmSync(temporary, { recursive: true });
  } else {
    console.error('Filesystem evidence retained at:', temporary);
  }
}
