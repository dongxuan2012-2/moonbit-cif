///|
fn append_span_same(before : Span, after : Span, shift : (Int, Int)?) -> Bool {
  match shift {
    None => true
    Some((at, size)) =>
      after.start_offset ==
      before.start_offset + (if before.start_offset >= at { size } else { 0 }) &&
      after.end_offset ==
      before.end_offset + (if before.end_offset > at { size } else { 0 })
  }
}

///|
fn append_token_same(
  before : Token,
  after : Token,
  shift : (Int, Int)?,
) -> Bool {
  before.kind == after.kind &&
  before.raw == after.raw &&
  before.text == after.text &&
  append_span_same(before.span, after.span, shift)
}

///|
fn append_values_same(
  before : Array[Value],
  after : Array[Value],
  shift : (Int, Int)?,
) -> Bool {
  if before.length() != after.length() {
    return false
  }
  for i in 0..<before.length() {
    if !append_value_same(before[i], after[i], shift) {
      return false
    }
  }
  true
}

///|
fn append_value_same(
  before : Value,
  after : Value,
  shift : (Int, Int)?,
) -> Bool {
  match (before, after) {
    (Scalar(a), Scalar(b)) => append_token_same(a, b, shift)
    (List(a, sa), List(b, sb)) =>
      append_span_same(sa, sb, shift) && append_values_same(a, b, shift)
    (Table(a, sa), Table(b, sb)) => {
      if !append_span_same(sa, sb, shift) || a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !append_token_same(a[i].0, b[i].0, shift) ||
          !append_value_same(a[i].1, b[i].1, shift) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn append_collect_loops(container : Container, loops : Array[Entry]) -> Unit {
  for entry in container.entries {
    if entry is Loop(_, _, _) {
      loops.push(entry)
    }
  }
  for frame in container.frames {
    append_collect_loops(frame, loops)
  }
}

///|
fn append_container_same(
  before : Container,
  after : Container,
  target : Entry,
  new_values : Array[Value],
  shift : (Int, Int),
) -> Bool {
  if !append_token_same(before.name, after.name, Some(shift)) ||
    before.entries.length() != after.entries.length() ||
    before.frames.length() != after.frames.length() {
    return false
  }
  for i in 0..<before.entries.length() {
    match (before.entries[i], after.entries[i]) {
      (Pair(ta, va), Pair(tb, vb)) =>
        if !append_token_same(ta, tb, Some(shift)) ||
          !append_value_same(va, vb, Some(shift)) {
          return false
        }
      (Loop(ha, va, sa), Loop(hb, vb, sb)) => {
        let selected = before.entries[i] == target
        if ha.length() != hb.length() ||
          vb.length() !=
          va.length() + (if selected { new_values.length() } else { 0 }) {
          return false
        }
        for column in 0..<ha.length() {
          if !append_token_same(ha[column], hb[column], Some(shift)) {
            return false
          }
        }
        for cell in 0..<va.length() {
          if !append_value_same(va[cell], vb[cell], Some(shift)) {
            return false
          }
        }
        if selected {
          if sa.start_offset != sb.start_offset ||
            sb.end_offset != vb[vb.length() - 1].span().end_offset {
            return false
          }
          for cell in 0..<new_values.length() {
            if !append_value_same(
                new_values[cell],
                vb[va.length() + cell],
                None,
              ) {
              return false
            }
          }
        } else if !append_span_same(sa, sb, Some(shift)) {
          return false
        }
      }
      _ => return false
    }
  }
  for i in 0..<before.frames.length() {
    if !append_container_same(
        before.frames[i],
        after.frames[i],
        target,
        new_values,
        shift,
      ) {
      return false
    }
  }
  true
}

///|
/// Append exactly one logical row to an original complete Loop witness.
/// The expected source is compared exactly; the public structural witness is
/// matched against a fresh same-version parse, not treated as an owner token.
/// Cells are already encoded single CIF values in original header order.
/// Only inserted separators use newline (LF or CRLF); old bytes and fragments
/// are retained. Returns complete text or Err, without mutation or disk I/O.
pub fn CifFile::append_loop_row(
  self : CifFile,
  target : Entry,
  cells : Array[String],
  expected_source~ : String,
  newline? : String = "\n",
) -> Result[String, String] {
  if expected_source != self.source {
    return Err("Expected source differs from the original snapshot")
  }
  if newline != "\n" && newline != "\r\n" {
    return Err("New separators must be LF or CRLF")
  }
  if self.version == Auto {
    return Err("Append requires a resolved CIF version")
  }
  let original = parse_report(self.source, version=self.version)
  if !original.is_valid() {
    return Err("Append requires a valid original CIF file")
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
  let (headers, old_values, span) = match matched[0] {
    Loop(headers, values, span) => (headers, values, span)
    _ => return Err("Selected witness must be a Loop")
  }
  let width = headers.length()
  if width == 0 || old_values.is_empty() || old_values.length() % width != 0 {
    return Err("Selected loop must have nonempty complete rows")
  }
  let names : Map[String, Bool] = Map([])
  for header in headers {
    let key = name_key(header.text)
    if names.contains(key) {
      return Err("Selected loop has duplicate headers")
    }
    names[key] = true
  }
  if cells.length() != width {
    return Err("New row width must equal the original loop header width")
  }
  let new_values : Array[Value] = []
  let probe_header = if self.version == Cif2 { "#\\#CIF_2.0\n" } else { "" }
  for cell in cells {
    // A cell occupies its own physical lines. Do not spend the probe's `_v `
    // prefix on a legal 2048-character value line.
    if validate_replacement(self.version, "\n" + cell) is Err(message) {
      return Err(message)
    }
    let probe = parse_report(
      probe_header + "data_append\n_v\n" + cell + "\n",
      version=self.version,
    )
    match probe.file.blocks[0].entries[0] {
      Pair(_, value) => new_values.push(value)
      _ => return Err("New cell must be a single legal CIF value")
    }
  }
  let bytes = @utf8.encode(self.source)
  let mut at = bytes.length()
  for token in original.file.tokens {
    if token.span.start_offset >= span.end_offset &&
      token.kind != Trivia &&
      token.kind != Comment {
      at = token.span.start_offset
      break
    }
  }
  let leading = if at > 0 &&
    bytes[at - 1].to_int() != 10 &&
    bytes[at - 1].to_int() != 13 {
    newline
  } else {
    ""
  }
  let inserted = leading + cells.join(newline) + newline
  try {
    let edited = @utf8.decode(bytes[:at], ignore_bom=false) +
      inserted +
      @utf8.decode(bytes[at:], ignore_bom=false)
    let after = parse_report(edited, version=self.version)
    if !after.is_valid() ||
      after.file.blocks.length() != original.file.blocks.length() {
      return Err("Appended row conflicts with its original CIF context")
    }
    let shift = (at, @utf8.encode(inserted).length())
    for i in 0..<original.file.blocks.length() {
      if !append_container_same(
          original.file.blocks[i],
          after.file.blocks[i],
          matched[0],
          new_values,
          shift,
        ) {
        return Err(
          "Append must preserve existing entries and add exactly one row",
        )
      }
    }
    Ok(edited)
  } catch {
    _ => Err("Insertion must align to original UTF-8 boundaries")
  }
}
