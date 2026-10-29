///|
fn removed_container_same(
  before : Container,
  after : Container,
  target : Entry,
  first : Int,
  limit : Int,
) -> Bool {
  if !append_token_same(before.name, after.name, None) ||
    before.entries.length() != after.entries.length() ||
    before.frames.length() != after.frames.length() {
    return false
  }
  for i in 0..<before.entries.length() {
    match (before.entries[i], after.entries[i]) {
      (Pair(ta, va), Pair(tb, vb)) =>
        if !append_token_same(ta, tb, None) || !append_value_same(va, vb, None) {
          return false
        }
      (Loop(ha, va, sa), Loop(hb, vb, sb)) => {
        let selected = before.entries[i] == target
        let kept = if selected {
          va[:first].to_owned() + va[limit:].to_owned()
        } else {
          va
        }
        if ha.length() != hb.length() || !append_values_same(kept, vb, None) {
          return false
        }
        for column in 0..<ha.length() {
          if !append_token_same(ha[column], hb[column], None) {
            return false
          }
        }
        if selected &&
          (
            sa.start_offset != sb.start_offset ||
            sb.end_offset != vb[vb.length() - 1].span().end_offset
          ) {
          return false
        }
      }
      _ => return false
    }
  }
  for i in 0..<before.frames.length() {
    if !removed_container_same(
        before.frames[i],
        after.frames[i],
        target,
        first,
        limit,
      ) {
      return false
    }
  }
  true
}

///|
fn removed_tokens_same(
  before : Array[Token],
  after : Array[Token],
  ranges : Array[Span],
) -> Bool {
  let kept_after = after.filter(t => t.kind != Trivia && t.kind != Comment)
  let mut range_index = 0
  let mut removed = 0
  let mut next = 0
  for old in before {
    if old.kind == Trivia || old.kind == Comment {
      continue
    }
    while range_index < ranges.length() &&
          ranges[range_index].end_offset <= old.span.start_offset {
      removed += ranges[range_index].end_offset -
        ranges[range_index].start_offset
      range_index += 1
    }
    if range_index < ranges.length() &&
      old.span.end_offset > ranges[range_index].start_offset {
      if old.span.start_offset >= ranges[range_index].start_offset &&
        old.span.end_offset <= ranges[range_index].end_offset {
        continue
      }
      return false
    }
    if next >= kept_after.length() {
      return false
    }
    let now = kept_after[next]
    if !append_token_same(old, now, None) ||
      now.span.start_offset != old.span.start_offset - removed ||
      now.span.end_offset != old.span.end_offset - removed {
      return false
    }
    next += 1
  }
  next == kept_after.length()
}

///|
/// Remove one explicitly indexed original logical row, leaving a nonempty loop.
/// Exact snapshot and unique structural Loop witness are required. Delete only
/// each selected top-level Value span; preserve every byte outside those spans.
/// Retained whitespace/comments can leave blank or comment-only physical lines.
/// Comments inside a deleted compound cell belong to that removed Value span.
/// Returns a complete same-version valid String or Err without mutation or IO.
pub fn CifFile::remove_loop_row(
  self : CifFile,
  target : Entry,
  row : Int,
  expected_source~ : String,
) -> Result[String, String] {
  if expected_source != self.source {
    return Err("Expected source differs from the original snapshot")
  }
  if self.version == Auto {
    return Err("Removal requires a resolved CIF version")
  }
  let original = parse_report(self.source, version=self.version)
  if !original.is_valid() {
    return Err("Removal requires a valid original CIF file")
  }
  if !(target is Loop(_, _, _)) {
    return Err("Selected witness must be a Loop")
  }
  let loops : Array[Entry] = []
  for block in original.file.blocks {
    append_collect_loops(block, loops)
  }
  let matched = loops.filter(entry => entry == target)
  if matched.length() != 1 {
    return Err("Loop witness must match exactly one actual source loop")
  }
  let (headers, values) = match matched[0] {
    Loop(headers, values, _) => (headers, values)
    _ => return Err("Selected witness must be a Loop")
  }
  let width = headers.length()
  if width == 0 || values.is_empty() || values.length() % width != 0 {
    return Err("Selected loop must have nonempty complete rows")
  }
  let count = values.length() / width
  if row < 0 || row >= count {
    return Err("Original row index is out of bounds")
  }
  if count == 1 {
    return Err("Removal must leave at least one complete loop row")
  }
  let first = row * width
  let limit = first + width
  let ranges = values[first:limit].to_owned().map(Value::span)
  let bytes = @utf8.encode(self.source)
  let chunks : Array[String] = []
  let mut cursor = 0
  try {
    for span in ranges {
      chunks.push(
        @utf8.decode(bytes[cursor:span.start_offset], ignore_bom=false),
      )
      cursor = span.end_offset
    }
    chunks.push(@utf8.decode(bytes[cursor:], ignore_bom=false))
  } catch {
    _ => return Err("Deletion spans must align to original UTF-8 boundaries")
  }
  let edited = chunks.join("")
  let after = parse_report(edited, version=self.version)
  if !after.is_valid() ||
    after.file.blocks.length() != original.file.blocks.length() {
    return Err("Removed row conflicts with its retained CIF context or budgets")
  }
  if !removed_tokens_same(original.file.tokens, after.file.tokens, ranges) {
    return Err("Removal must preserve retained token bytes and mapped offsets")
  }
  for i in 0..<original.file.blocks.length() {
    if !removed_container_same(
        original.file.blocks[i],
        after.file.blocks[i],
        matched[0],
        first,
        limit,
      ) {
      return Err("Removal must retain other entries and delete exactly one row")
    }
  }
  Ok(edited)
}
