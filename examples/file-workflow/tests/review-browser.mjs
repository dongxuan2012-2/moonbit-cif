// Full file workflow plus actual browser layout, using independent byte fixtures.
// Requires an installed Chromium browser; never downloads one or uses a user profile.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const example = path.resolve(fileURLToPath(new URL('../', import.meta.url)));
const fixtures = path.join(example, 'tests/review-lines');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = filename => {
  const bytes = fs.readFileSync(filename);
  return { path: filename, bytes: bytes.length, sha256: digest(bytes) };
};
const work = path.join(example, 'work');
fs.mkdirSync(work, { recursive: true });
let evidence;
if (process.env.CIF_REVIEW_EVIDENCE) {
  evidence = path.resolve(process.env.CIF_REVIEW_EVIDENCE);
  fs.mkdirSync(path.dirname(evidence), { recursive: true });
  fs.mkdirSync(evidence); // Evidence must be new, like the product's output paths.
} else {
  evidence = fs.mkdtempSync(path.join(work, 'review-browser-'));
}
fs.mkdirSync(path.join(evidence, 'logs'));
fs.mkdirSync(path.join(evidence, 'cases'));
const commands = [], outcomes = [];
let compiled, browser, passed = false;

function run(label, executable, args, cwd, timeout = 60_000) {
  const child = spawnSync(executable, args, { cwd, timeout, maxBuffer: 16 * 1024 * 1024,
    windowsHide: true });
  const stdout = path.join(evidence, 'logs', `${label}.stdout`);
  const stderr = path.join(evidence, 'logs', `${label}.stderr`);
  fs.writeFileSync(stdout, child.stdout ?? Buffer.alloc(0));
  fs.writeFileSync(stderr, child.stderr ?? Buffer.alloc(0));
  commands.push({ label, executable, args, cwd, exitCode: child.status, signal: child.signal,
    stdout: identity(stdout), stderr: identity(stderr) });
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, 0, `${label}: ${child.stderr}`);
  return child.stdout;
}

function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? files(filename) : [filename];
  });
}

function findBrowser() {
  const candidates = process.env.CIF_REVIEW_BROWSER ? [process.env.CIF_REVIEW_BROWSER] : [
    ...['google-chrome', 'chromium', 'chromium-browser'].flatMap(name =>
      (process.env.PATH ?? '').split(path.delimiter).filter(Boolean).map(dir => path.join(dir, name))),
    ...[process.env.ProgramFiles, process.env['ProgramFiles(x86)']].filter(Boolean).flatMap(dir => [
      path.join(dir, 'Google/Chrome/Application/chrome.exe'),
      path.join(dir, 'Microsoft/Edge/Application/msedge.exe'),
    ]),
  ];
  const found = candidates.find(filename => fs.existsSync(filename) && fs.statSync(filename).isFile());
  assert.ok(found, 'Install Chromium or set CIF_REVIEW_BROWSER to its executable; this gate does not skip');
  return path.resolve(found);
}

try {
  browser = findBrowser();
  const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';
  const build = path.join(evidence, 'cli-build');
  run('build-cli', moon, ['build', '--deny-warn', '--target', 'js', '--target-dir', build], example, 180_000);
  const entrypoints = files(build).filter(filename => path.basename(filename) === 'cif-file-workflow-example.js');
  assert.equal(entrypoints.length, 1);
  compiled = entrypoints[0];
  const observerPath = path.join(example, 'tests/review-browser-observer.js');
  const observer = fs.readFileSync(observerPath, 'utf8');
  fs.copyFileSync(observerPath, path.join(evidence, 'browser-observer.js'));

  for (const name of fs.readdirSync(fixtures).sort()) {
    const fixture = path.join(fixtures, name);
    const directory = path.join(evidence, 'cases', name);
    fs.mkdirSync(directory);
    for (const filename of ['source.cif', 'expected.cif', 'expected.json', 'plan.json']) {
      fs.copyFileSync(path.join(fixture, filename), path.join(directory, filename));
    }
    const expected = JSON.parse(fs.readFileSync(path.join(directory, 'expected.json'), 'utf8'));
    const before = Object.fromEntries(['source.cif', 'expected.cif', 'expected.json', 'plan.json'].map(
      filename => [filename, identity(path.join(directory, filename))]));
    for (const [filename, oracle] of [['source.cif', expected.source], ['expected.cif', expected.planned]]) {
      assert.equal(before[filename].bytes, oracle.bytes);
      assert.equal(before[filename].sha256, oracle.sha256);
    }
    const previewRaw = run(`${name}-preview`, process.execPath,
      [compiled, 'preview', 'source.cif', 'plan.json'], directory);
    fs.writeFileSync(path.join(directory, 'preview.json'), previewRaw);
    const preview = JSON.parse(previewRaw);
    assert.equal(preview.ok, true);
    assert.equal(preview.writesFiles, false);
    assert.equal(preview.planned.sha256, expected.planned.sha256);
    assert.equal(preview.planned.bytes, expected.planned.bytes);
    assert.equal(preview.edits[0].replacement, expected.replacement);
    for (const [key, value] of Object.entries(expected.originalSpan)) {
      assert.equal(preview.edits[0].original.span[key], value);
    }
    const rendered = JSON.parse(run(`${name}-render`, process.execPath,
      [path.join(example, 'review-preview.mjs'), 'preview.json', 'review.html', '--source', 'source.cif'], directory));
    assert.equal(rendered.ok, true);
    assert.equal(rendered.writesCifFiles, false);
    assert.equal(rendered.approvesEdits, false);
    assert.equal(rendered.plannedReplay.verified, true);
    const applied = JSON.parse(run(`${name}-apply`, process.execPath,
      [compiled, 'apply', 'source.cif', 'plan.json', 'output.cif', '--expect-result-sha256', expected.planned.sha256], directory));
    assert.equal(applied.ok, true);
    assert.deepEqual(fs.readFileSync(path.join(directory, 'output.cif')), fs.readFileSync(path.join(directory, 'expected.cif')));
    for (const [filename, original] of Object.entries(before)) {
      assert.deepEqual(identity(path.join(directory, filename)), original);
    }

    const html = fs.readFileSync(path.join(directory, 'review.html'), 'utf8');
    const injection = '<script type="application/json" id="review-line-expected">' +
      JSON.stringify(expected).replaceAll('<', '\\u003c') + '</script><script>' + observer + '</script>';
    const testCopy = path.join(directory, 'review.browser.html');
    fs.writeFileSync(testCopy, html.replace('</body>', injection + '</body>'));
    const dom = run(`${name}-browser`, browser, ['--headless', '--disable-gpu',
      '--disable-background-networking', '--no-first-run', '--no-default-browser-check',
      `--user-data-dir=${path.join(directory, 'browser-profile')}`, '--window-size=1200,1800',
      `--screenshot=${path.join(directory, 'review.png')}`, '--dump-dom',
      pathToFileURL(testCopy).href], directory);
    const receiptMatch = dom.toString('utf8').match(/<meta id="review-line-receipt" content="([^"]*)"/);
    assert.ok(receiptMatch, `${name}: actual browser observer must execute`);
    const receipt = JSON.parse(decodeURIComponent(receiptMatch[1]));
    fs.writeFileSync(path.join(directory, 'browser-receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
    for (const [kind, observation] of Object.entries(receipt.items)) {
      assert.equal(observation.actual.text, observation.reference.text, `${name}: ${kind} DOM text`);
      assert.equal(observation.matches, true, `${name}: ${kind} physical rows and line heights`);
    }
    assert.equal(receipt.mark, expected.highlightVisual, `${name}: highlighted whitespace`);
    assert.equal(receipt.replacement, expected.highlightVisual);
    assert.equal(rendered.htmlSha256, identity(path.join(directory, 'review.html')).sha256);
    outcomes.push({ name, immutableInputs: before, diskReceipt: applied.disk,
      actualOutput: identity(path.join(directory, 'output.cif')),
      renderedHTML: identity(path.join(directory, 'review.html')), actualTestCopy: identity(testCopy),
      browserReceipt: identity(path.join(directory, 'browser-receipt.json')),
      userAgent: receipt.userAgent, physicalRowsAndHeights: 'match independent normalized text in the same browser' });
  }
  assert.equal(outcomes.length, 6);
  passed = true;
} finally {
  const result = { ok: passed, cases: outcomes, commands,
    compilerOutput: compiled ? identity(compiled) : null,
    renderer: identity(path.join(example, 'review-preview.mjs')),
    observer: identity(path.join(example, 'tests/review-browser-observer.js')),
    browserExecutable: browser ? identity(browser) : null,
    visualScope: 'Six physical-newline fixtures in one installed Chromium, not full cross-browser certification',
    artifactLocation: evidence };
  fs.writeFileSync(path.join(evidence, 'RESULT.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
}
