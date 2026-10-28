// Render a saved forecast for human review. This example never executes apply.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const usage = 'node review-preview.mjs PREVIEW.json NEW_REVIEW.html [--source INPUT.cif]';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const escape = text => text.replace(/[&<>"'\r]/g, character => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '\r': '&#13;',
})[character]);

function requireText(value, label) {
  if (typeof value !== 'string') throw new Error(`Expected string: ${label}`);
  return value;
}

function requireHash(value, label) {
  requireText(value, label);
  if (!/^[0-9a-f]{64}$/i.test(value)) throw new Error(`Expected SHA256: ${label}`);
}

function validate(preview) {
  if (!preview || preview.ok !== true || preview.mode !== 'preview' || preview.writesFiles !== false) {
    throw new Error('Expected a successful no-write preview JSON');
  }
  for (const key of ['input', 'block', 'frame', 'idTag']) requireText(preview[key], key);
  requireHash(preview.sourceSha256, 'sourceSha256');
  if (!preview.planned || preview.planned.ok !== true) throw new Error('Missing planned result');
  requireHash(preview.planned.sha256, 'planned.sha256');
  if (!Number.isSafeInteger(preview.planned.bytes) || preview.planned.bytes < 0) {
    throw new Error('Expected nonnegative planned.bytes');
  }
  if (!Array.isArray(preview.edits) || preview.editCount !== preview.edits.length) {
    throw new Error('editCount does not match edits');
  }
  for (const edit of preview.edits) {
    requireText(edit?.id, 'edit.id');
    requireText(edit.tag, 'edit.tag');
    requireText(edit.replacement, 'edit.replacement');
    requireText(edit.original?.literal, 'edit.original.literal');
    requireText(edit.original.kind, 'edit.original.kind');
    const span = edit.original.span;
    for (const key of ['start_line', 'start_col', 'end_line', 'end_col', 'start_offset', 'end_offset']) {
      const minimum = key.endsWith('_offset') ? 0 : 1;
      if (!Number.isSafeInteger(span?.[key]) || span[key] < minimum) throw new Error(`Invalid span.${key}`);
    }
    if (span.end_offset < span.start_offset) throw new Error('Reversed original span');
  }
}

function contextItems(bytes, intervals) {
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
  decoder.decode(bytes);
  const starts = [0];
  for (let index = 0; index < bytes.length; index++) {
    if (bytes[index] === 13) {
      if (bytes[index + 1] === 10) index++;
      starts.push(index + 1);
    } else if (bytes[index] === 10) {
      starts.push(index + 1);
    }
  }
  const lineAt = offset => {
    let low = 0, high = starts.length;
    while (low + 1 < high) {
      const middle = Math.floor((low + high) / 2);
      if (starts[middle] <= offset) low = middle;
      else high = middle;
    }
    return low;
  };
  return intervals.map(span => {
    const first = Math.max(0, lineAt(span.start_offset) - 1);
    const last = Math.min(starts.length - 1, lineAt(Math.max(span.start_offset, span.end_offset - 1)) + 1);
    const start = starts[first], end = starts[last + 1] ?? bytes.length;
    return { firstLine: first + 1, lastLine: last + 1, start, end,
      before: decoder.decode(bytes.subarray(start, span.start_offset)),
      highlight: decoder.decode(bytes.subarray(span.start_offset, span.end_offset)),
      after: decoder.decode(bytes.subarray(span.end_offset, end)) };
  });
}

function replaySavedEdits(preview, source) {
  const ordered = preview.edits.map((edit, index) => ({
    index, start: edit.original.span.start_offset, end: edit.original.span.end_offset,
    replacement: Buffer.from(edit.replacement, 'utf8'),
  })).sort((a, b) => a.start - b.start);
  const parts = [], intervals = [];
  let cursor = 0, offset = 0;
  for (const edit of ordered) {
    if (edit.start < cursor) throw new Error('Overlapping original byte spans in saved preview');
    const prefix = source.subarray(cursor, edit.start);
    parts.push(prefix, edit.replacement);
    offset += prefix.length;
    intervals[edit.index] = { start_offset: offset, end_offset: offset + edit.replacement.length };
    offset += edit.replacement.length;
    cursor = edit.end;
  }
  parts.push(source.subarray(cursor));
  const bytes = Buffer.concat(parts);
  const hash = sha256(bytes);
  if (bytes.length !== preview.planned.bytes || hash !== preview.planned.sha256.toLowerCase()) {
    throw new Error('Planned result bytes differ from the saved preview');
  }
  return { bytes, intervals, sha256: hash };
}

function readSourceContext(preview, sourcePath) {
  const bytes = fs.readFileSync(sourcePath);
  const hash = sha256(bytes);
  if (hash !== preview.sourceSha256.toLowerCase()) throw new Error('Source SHA256 differs from the saved preview');
  for (const edit of preview.edits) {
    const span = edit.original.span;
    if (span.end_offset > bytes.length ||
        !bytes.subarray(span.start_offset, span.end_offset).equals(Buffer.from(edit.original.literal, 'utf8'))) {
      throw new Error(`Original byte span differs from source: ${edit.id} / ${edit.tag}`);
    }
  }
  const items = contextItems(bytes, preview.edits.map(edit => edit.original.span));
  const result = replaySavedEdits(preview, bytes);
  return { path: path.resolve(sourcePath), sha256: hash, items,
    resultItems: contextItems(result.bytes, result.intervals),
    plannedReplay: { sha256: result.sha256, bytes: result.bytes.length, verified: true } };
}

function render(preview, sourceContext) {
  const contextStyle = sourceContext ? '.source-context,.planned-context{margin-top:18px;padding:16px;background:#f4f7fb;border:1px solid #d9e2ec;border-radius:6px}.planned-context{background:#f0faf4;border-color:#cce4d5}mark{background:#ffe5a3;color:inherit}\n' : '';
  const sourceMetadata = sourceContext ? `<dt>源文上下文已核对</dt><dd id="verified-source-path">${escape(sourceContext.path)}</dd><dt>预计组合结果</dt><dd>完整重放字节数及 SHA256 已核对</dd>` : '';
  const edits = preview.edits.map((edit, index) => {
    const span = edit.original.span;
    const position = `L${span.start_line}:${span.start_col} – L${span.end_line}:${span.end_col}`;
    const item = sourceContext?.items[index];
    const context = item ? `<div class="source-context"><h3>源文上下文 · L${item.firstLine}–L${item.lastLine} · UTF-8 [${item.start}, ${item.end})</h3><pre><code class="source-context-text">${escape(item.before)}<mark>${escape(edit.original.literal)}</mark>${escape(item.after)}</code></pre></div>` : '';
    const result = sourceContext?.resultItems[index];
    const plannedContext = result ? `<div class="planned-context"><h3>预计结果上下文 · L${result.firstLine}–L${result.lastLine} · UTF-8 [${result.start}, ${result.end})</h3><p class="position">高亮本项替换片段，包含其空白；预计结果不表示实际写出完成。</p><pre><code class="planned-context-text">${escape(result.before)}<mark>${escape(result.highlight)}</mark>${escape(result.after)}</code></pre></div>` : '';
    return `<section class="edit"><h2>${index + 1}. ${escape(edit.tag)} <small>ID ${escape(edit.id)}</small></h2>
<p class="position">${position} · UTF-8 [${span.start_offset}, ${span.end_offset}) · ${escape(edit.original.kind)}</p>
<div class="comparison"><div class="before"><h3>原字面量</h3><pre><code class="original">${escape(edit.original.literal)}</code></pre></div>
<div class="after"><h3>替换片段</h3><pre><code class="replacement">${escape(edit.replacement)}</code></pre></div></div>${context}${plannedContext}</section>`;
  }).join('\n');
  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>CIF 变更审阅</title><style>
*{box-sizing:border-box}body{margin:0;background:#f1f4f8;color:#172b3b;font:16px/1.6 system-ui,sans-serif}
main{max-width:1160px;margin:auto;padding:36px 24px 56px}header{border-top:5px solid #27648e;padding:24px;background:#fff;border-radius:8px}
h1{margin:8px 0 12px;font-size:30px;line-height:1.3}.badge{display:inline-block;background:#fff2d2;color:#785410;padding:3px 10px;border-radius:16px;font-size:13px}
.notice{color:#526474;margin:0}dl{display:grid;grid-template-columns:160px 1fr;gap:10px 16px;margin:24px 0 0}dt{font-weight:600}dd{margin:0;min-width:0;overflow-wrap:anywhere}
code{font:14px/1.65 ui-monospace,Consolas,monospace}.edit{background:#fff;margin-top:24px;padding:24px;border-radius:8px;border:1px solid #dfe5eb}
h2{font-size:19px;margin:0}h2 small{font-size:14px;font-weight:400;color:#526474;margin-left:12px}.position{font-size:13px;color:#526474;margin:6px 0 18px}
.comparison{display:grid;grid-template-columns:1fr 1fr;gap:16px}.before,.after{min-width:0;padding:16px;border:1px solid #eadbd6;border-radius:6px;background:#fff6f2}
.after{border-color:#cce4d5;background:#f0faf4}h3{font-size:13px;margin:0 0 10px;color:#526474}pre{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}.empty{padding:20px 0}
${contextStyle}@media(max-width:720px){main{padding:20px 12px}header,.edit{padding:18px}dl{grid-template-columns:1fr;gap:2px}dd{margin-bottom:10px}.comparison{grid-template-columns:1fr}h1{font-size:25px}}
</style></head><body><main><header><span class="badge">待人工审阅</span><h1>CIF 变更审阅</h1>
<p class="notice">本页展示保存的预览。页面生成和散列匹配均不表示批准或 CIF 写入完成；实际写出后请核对 apply 的磁盘回执。</p>
<dl><dt>输入路径</dt><dd>${escape(preview.input)}</dd><dt>作用域</dt><dd>${escape(preview.block)} / ${escape(preview.frame || '块根作用域')}</dd>
<dt>ID 列</dt><dd>${escape(preview.idTag)}</dd><dt>源 SHA256</dt><dd><code id="source-sha256">${escape(preview.sourceSha256)}</code></dd>
<dt>预计结果 SHA256</dt><dd><code id="result-sha256">${escape(preview.planned.sha256)}</code></dd>
<dt>预计 UTF-8 字节</dt><dd id="result-bytes">${preview.planned.bytes}</dd><dt>修改数</dt><dd>${preview.editCount}</dd>${sourceMetadata}</dl></header>
${edits || '<p class="empty">本次计划没有修改。</p>'}
</main></body></html>\n`;
}

function writeNew(output, bytes) {
  let descriptor = null;
  let created = false;
  try {
    descriptor = fs.openSync(output, 'wx');
    created = true;
    fs.writeFileSync(descriptor, bytes);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = null;
    const actual = fs.readFileSync(output);
    if (!actual.equals(bytes)) throw new Error('Review page byte readback mismatch');
    return sha256(actual);
  } catch (error) {
    if (descriptor !== null) { try { fs.closeSync(descriptor); } catch {} }
    let cleanup = '';
    if (created) { try { fs.unlinkSync(output); } catch (failure) { cleanup = `; new page cleanup failed: ${failure.message}`; } }
    throw new Error(String(error.message || error) + cleanup);
  }
}

function main(args) {
  if (args.length === 1 && args[0] === '--help') return { ok: true, usage };
  if (!(args.length === 2 || (args.length === 4 && args[2] === '--source'))) throw new Error(usage);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(fs.readFileSync(args[0]));
  const preview = JSON.parse(text);
  validate(preview);
  const sourceContext = args.length === 4 ? readSourceContext(preview, args[3]) : null;
  const output = path.resolve(args[1]);
  const bytes = Buffer.from(render(preview, sourceContext), 'utf8');
  const htmlSha256 = writeNew(output, bytes);
  const receipt = { ok: true, output, htmlSha256, sourceSha256: preview.sourceSha256,
    planned: preview.planned, writesCifFiles: false, approvesEdits: false };
  if (sourceContext) {
    receipt.sourceContext = { path: sourceContext.path, sha256: sourceContext.sha256, verifiedSpans: sourceContext.items.length };
    receipt.plannedReplay = sourceContext.plannedReplay;
  }
  return receipt;
}

try {
  process.stdout.write(JSON.stringify(main(process.argv.slice(2))) + '\n');
} catch (error) {
  process.stdout.write(JSON.stringify({ ok: false, error: String(error.message || error) }) + '\n');
  process.exitCode = 1;
}
