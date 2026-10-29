// Real raw files -> stdout values JSON -> isolated public CIF / pinned Lunar module.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const example = path.resolve(fileURLToPath(new URL('./', import.meta.url)));
const repo = path.resolve(example, '../..');
const fixture = path.join(example, 'fixtures');
const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = filename => {
  const bytes = fs.readFileSync(filename);
  return { path: filename, bytes: bytes.length, sha256: sha(bytes) };
};
fs.mkdirSync(path.join(example, 'work'), { recursive: true });
let evidence;
if (process.env.CIF_VALUES_EVIDENCE) {
  evidence = path.resolve(process.env.CIF_VALUES_EVIDENCE);
  fs.mkdirSync(path.dirname(evidence), { recursive: true });
  fs.mkdirSync(evidence);
} else evidence = fs.mkdtempSync(path.join(example, 'work/values-'));
for (const name of ['logs', 'cases', 'deliveries']) fs.mkdirSync(path.join(evidence, name));
const commands = [], cases = [], deliveries = [], legacy = [], receiverRejections = [];
let cli, recipientJS, passed = false;
const recipient = path.join(evidence, 'recipient');

function run(label, executable, args, cwd, status = 0) {
  const child = spawnSync(executable, args, { cwd, timeout: 180_000,
    maxBuffer: 16 * 1024 * 1024, windowsHide: true });
  const stdout = path.join(evidence, 'logs', label + '.stdout');
  const stderr = path.join(evidence, 'logs', label + '.stderr');
  fs.writeFileSync(stdout, child.stdout ?? Buffer.alloc(0));
  fs.writeFileSync(stderr, child.stderr ?? Buffer.alloc(0));
  commands.push({ label, executable, args, cwd, exitCode: child.status, expectedExitCode: status,
    signal: child.signal, error: child.error ? { code: child.error.code, message: child.error.message } : null,
    stdout: identity(stdout), stderr: identity(stderr) });
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, status, `${label}: ${child.stderr}`);
  return child.stdout;
}
function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? files(filename) : [filename];
  });
}
function entrypoint(directory, basename) {
  const found = files(directory).filter(filename => path.basename(filename) === basename);
  assert.equal(found.length, 1);
  return found[0];
}
function snapshot(directory) {
  return Object.fromEntries(fs.readdirSync(directory).sort().map(name => [name,
    identity(path.join(directory, name))]));
}
function inspectCase(name, source, scope, expected, success) {
  const directory = path.join(evidence, 'cases', name);
  fs.mkdirSync(directory);
  fs.writeFileSync(path.join(directory, 'source.cif'), source);
  fs.writeFileSync(path.join(directory, 'scope.json'), JSON.stringify(scope) + '\n');
  fs.writeFileSync(path.join(directory, 'old.output.cif'), Buffer.from('KEEP OLD OUTPUT\r\n\x00\xff', 'latin1'));
  const before = snapshot(directory);
  const stdout = run(name, process.execPath, [cli, 'values', 'source.cif', 'scope.json'], directory, success ? 0 : 1);
  const receipt = JSON.parse(stdout);
  assert.deepEqual(snapshot(directory), before, `${name}: read-only command changed files`);
  assert.equal(receipt.ok, success);
  if (success) {
    assert.deepEqual(receipt, expected, `${name}: full independently specified JSON`);
    assert.equal(receipt.writesFiles, false);
  }
  cases.push({ name, exitCode: success ? 0 : 1, immutableFiles: before, receipt });
  return { directory, stdout, receipt };
}
try {
  run('build-cli', moon, ['build', '--deny-warn', '--target', 'js', '--target-dir', path.join(evidence, 'cli-build')], path.join(repo, 'examples/file-workflow'));
  cli = entrypoint(path.join(evidence, 'cli-build'), 'cif-file-workflow-example.js');
  fs.mkdirSync(recipient);
  for (const name of ['moon.mod', 'moon.pkg', 'main.mbt', 'pkg.generated.mbti']) fs.copyFileSync(path.join(example, name), path.join(recipient, name));
  fs.writeFileSync(path.join(recipient, 'moon.work'), `members = [".", ${JSON.stringify(repo.replaceAll('\\', '/'))}]\n`);
  run('build-recipient', moon, ['build', '--deny-warn', '--target', 'js', '--target-dir', path.join(evidence, 'recipient-build')], recipient);
  recipientJS = entrypoint(path.join(evidence, 'recipient-build'), 'cif-value-reader-example.js');
  const receiverExpected = JSON.parse(fs.readFileSync(path.join(fixture, 'receiver-expected.json'), 'utf8'));
  for (const name of ['cif1', 'cif2']) {
    const source = fs.readFileSync(path.join(fixture, name, 'source.cif'));
    const scope = JSON.parse(fs.readFileSync(path.join(fixture, name, 'scope.json'), 'utf8'));
    const expected = JSON.parse(fs.readFileSync(path.join(fixture, name, 'expected.json'), 'utf8'));
    assert.equal(sha(source), expected.sourceSha256);
    const result = inspectCase(name, source, scope, expected, true);
    const delivery = path.join(evidence, 'deliveries', name + '.values.json');
    fs.writeFileSync(delivery, result.stdout, { flag: 'wx' });
    const before = identity(delivery);
    const actual = JSON.parse(run(name + '-lunar', process.execPath,
      [recipientJS, path.join(result.directory, 'source.cif'), delivery, 'metre'], recipient));
    assert.deepEqual(actual, receiverExpected[name], `${name}: complete real Lunar recipient result`);
    assert.deepEqual(identity(delivery), before);
    deliveries.push({ name, source: identity(path.join(result.directory, 'source.cif')),
      actualDelivery: before, receiverResult: actual });
  }
  for (const control of JSON.parse(fs.readFileSync(path.join(fixture, 'controls.json'), 'utf8'))) {
    const source = control.source ? fs.readFileSync(path.join(fixture, control.source, 'source.cif')) :
      control.sourceHex ? Buffer.from(control.sourceHex, 'hex') : Buffer.from(control.sourceText);
    inspectCase(control.name, source, control.scope, control.expected, control.success);
  }

  // Distinct old loop query/apply behavior and existing-target protection.
  const directory = path.join(evidence, 'cases', 'legacy'); fs.mkdirSync(directory);
  fs.copyFileSync(path.join(fixture, 'cif2/source.cif'), path.join(directory, 'source.cif'));
  for (const [from, to] of [['legacy-scope.json', 'scope.json'], ['legacy-plan.json', 'plan.json']]) fs.copyFileSync(path.join(fixture, from), path.join(directory, to));
  fs.writeFileSync(path.join(directory, 'old.output.cif'), 'KEEP EXISTING OUTPUT\n');
  const before = snapshot(directory);
  const query = JSON.parse(run('legacy-query', process.execPath, [cli, 'query', 'source.cif', 'scope.json'], directory));
  assert.deepEqual(query, JSON.parse(fs.readFileSync(path.join(fixture, 'legacy-query-expected.json'), 'utf8')));
  assert.deepEqual(snapshot(directory), before);
  const applied = JSON.parse(run('legacy-apply', process.execPath, [cli, 'apply', 'source.cif', 'plan.json', 'new.output.cif'], directory));
  const expected = fs.readFileSync(path.join(fixture, 'legacy-expected.cif'));
  assert.equal(applied.ok, true);
  assert.equal(applied.disk.readbackVerified, true);
  assert.equal(applied.disk.sha256, sha(expected));
  assert.deepEqual(fs.readFileSync(path.join(directory, 'new.output.cif')), expected);
  for (const [name, item] of Object.entries(before)) assert.deepEqual(identity(path.join(directory, name)), item);
  const afterApply = snapshot(directory);
  const rejected = JSON.parse(run('legacy-existing-output', process.execPath, [cli, 'apply', 'source.cif', 'plan.json', 'old.output.cif'], directory, 1));
  assert.equal(rejected.ok, false); assert.match(rejected.error, /EEXIST/);
  assert.deepEqual(snapshot(directory), afterApply);
  legacy.push({ query, applied, existingOutputRejected: rejected, before, after: afterApply });

  for (const kind of ['changed-source', 'changed-span']) {
    const directory = path.join(evidence, 'cases', kind); fs.mkdirSync(directory);
    const source = fs.readFileSync(path.join(fixture, 'cif1/source.cif'));
    const json = JSON.parse(fs.readFileSync(deliveries[0].actualDelivery.path, 'utf8'));
    if (kind === 'changed-span') json.selections[0].values[0].span.start_offset++;
    fs.writeFileSync(path.join(directory, 'source.cif'), kind === 'changed-source' ? Buffer.concat([source, Buffer.from('# changed\n')]) : source);
    fs.writeFileSync(path.join(directory, 'values.json'), JSON.stringify(json) + '\n');
    const before = snapshot(directory);
    run(kind, process.execPath, [recipientJS, path.join(directory, 'source.cif'), path.join(directory, 'values.json'), 'metre'], recipient, 1);
    assert.deepEqual(snapshot(directory), before);
    const error = fs.readFileSync(path.join(evidence, 'logs', kind + '.stderr'), 'utf8');
    assert.match(error, kind === 'changed-source' ? /Source SHA256 differs/ : /literal span differs/);
    receiverRejections.push({ kind, immutableFiles: before, exitCode: 1 });
  }
  passed = true;
} finally {
  const relative = path.relative(repo, recipient);
  const dependencies = [];
  for (const name of ['FrozenLemonTee/LunarUncertainty', 'FrozenLemonTee/LunarUnits', 'moonbit-community/normalization', 'moonbit-community/ucd']) {
    const directory = path.join(recipient, '.mooncakes', name);
    if (fs.existsSync(directory)) dependencies.push({ module: name,
      members: files(directory).sort().map(filename => ({ relativePath: path.relative(directory, filename).replaceAll('\\', '/'), ...identity(filename) })) });
  }
  const result = { ok: passed, cases, deliveries, legacy, receiverRejections, commands,
    compiledArtifacts: [cli, recipientJS].filter(Boolean).map(identity),
    recipientSources: fs.existsSync(recipient) ? files(recipient).filter(filename => !filename.includes(path.sep + '.mooncakes' + path.sep) && !filename.includes(path.sep + '_build' + path.sep)).map(identity) : [],
    dependencies, isolatedPublicModule: true,
    externalToGitCheckout: relative.startsWith('..' + path.sep) || path.isAbsolute(relative),
    evidenceDirectory: evidence, recipientDirectory: recipient,
    proofBoundary: 'Self-authored actual file/public-API/pinned-Lunar receiving. Caller chooses metres; no unit inference, third-party adoption or new scientific model.' };
  fs.writeFileSync(path.join(evidence, 'RESULT.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
}
