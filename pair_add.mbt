///|
fn pair_scopes(container : Container, found : Array[Container]) -> Unit {
  found.push(container)
  for frame in container.frames {
    pair_scopes(frame, found)
  }
}

///|
fn pair_container_same(
  before : Container,
  after : Container,
  target : Container,
  new_tag : Token,
  new_value : Value,
  tag_start : Int,
  shift : (Int, Int),
) -> Bool {
  let selected = before == target
  let added = if selected { 1 } else { 0 }
  if !append_token_same(before.name, after.name, Some(shift)) ||
    after.entries.length() != before.entries.length() + added ||
    before.frames.length() != after.frames.length() {
    return false
  }
  if selected {
    match after.entries[0] {
      Pair(tag, value) =>
        if !append_token_same(new_tag, tag, None) ||
          !append_value_same(new_value, value, None) ||
          tag.span.start_offset != tag_start ||
          tag.span.end_offset != tag_start + @utf8.encode(new_tag.raw).length() {
          return false
        }
      _ => return false
    }
  }
  for i in 0..<before.entries.length() {
    match (before.entries[i], after.entries[i + added]) {
      (Pair(ta, va), Pair(tb, vb)) =>
        if !append_token_same(ta, tb, Some(shift)) ||
          !append_value_same(va, vb, Some(shift)) {
          return false
        }
      (Loop(ha, va, sa), Loop(hb, vb, sb)) => {
        if ha.length() != hb.length() ||
          !append_values_same(va, vb, Some(shift)) ||
          !append_span_same(sa, sb, Some(shift)) {
          return false
        }
        for j in 0..<ha.length() {
          if !append_token_same(ha[j], hb[j], Some(shift)) {
            return false
          }
        }
      }
      _ => return false
    }
  }
  for i in 0..<before.frames.length() {
    if !pair_container_same(
        before.frames[i],
        after.frames[i],
        target,
        new_tag,
        new_value,
        tag_start,
        shift,
      ) {
      return false
    }
  }
  true
}

///|
/// Add one missing Pair to an explicitly selected original block or frame.
/// Exact snapshot and a unique structural Container witness are required.
/// The name is one legal new data-name, unique among that scope's direct tags;
/// the fragment is one already-encoded value (use format_string for new text).
/// Insert after the header's original leading trivia/comments, before its first
/// significant token or EOF. Only inserted separators are LF; old bytes remain.
/// Returns complete same-version valid text or Err without mutation or disk IO.
pub fn CifFile::add_pair(
  self : CifFile,
  target : Container,
  name : String,
  fragment : String,
  expected_source~ : String,
) -> Result[String, String] {
  if expected_source != self.source {
    return Err("Expected source differs from the original snapshot")
  }
  if self.version == Auto {
    return Err("Pair creation requires a resolved CIF version")
  }
  let original = parse_report(self.source, version=self.version)
  if !original.is_valid() {
    return Err("Pair creation requires a valid original CIF file")
  }
  let scopes : Array[Container] = []
  for block in original.file.blocks {
    pair_scopes(block, scopes)
  }
  let matched = scopes.filter(scope => scope == target)
  if matched.length() != 1 {
    return Err(
      "Container witness must match exactly one original block or frame",
    )
  }
  if validate_replacement(self.version, "\n" + fragment) is Err(message) {
    return Err(message)
  }
  let header = if self.version == Cif2 { "#\\#CIF_2.0\n" } else { "" }
  let probe = parse_report(
    header + "data_pair\n" + name + "\n" + fragment + "\n",
    version=self.version,
  )
  if !probe.is_valid() ||
    probe.file.blocks.length() != 1 ||
    probe.file.blocks[0].entries.length() != 1 ||
    !probe.file.blocks[0].frames.is_empty() {
    return Err("New name and value must form exactly one legal Pair")
  }
  let (new_tag, new_value) = match probe.file.blocks[0].entries[0] {
    Pair(tag, value) => (tag, value)
    _ => return Err("New name and value must form exactly one legal Pair")
  }
  if new_tag.kind != Word || new_tag.raw != name || new_tag.text != name {
    return Err("New name must be exactly one original-spelling data-name token")
  }
  let key = name_key(name)
  for entry in matched[0].entries {
    let tags = match entry {
      Pair(tag, _) => [tag]
      Loop(tags, _, _) => tags
    }
    if tags.any(tag => name_key(tag.text) == key) {
      return Err("New data-name already exists in the selected scope")
    }
  }
  let bytes = @utf8.encode(self.source)
  let mut at = bytes.length()
  for token in original.file.tokens {
    if token.span.start_offset >= matched[0].name.span.end_offset &&
      token.kind != Trivia &&
      token.kind != Comment {
      at = token.span.start_offset
      break
    }
  }
  let leading = if at > 0 &&
    bytes[at - 1].to_int() != 10 &&
    bytes[at - 1].to_int() != 13 {
    "\n"
  } else {
    ""
  }
  let inserted = leading + name + "\n" + fragment + "\n"
  let edited = try
    @utf8.decode(bytes[:at], ignore_bom=false) +
    inserted +
    @utf8.decode(bytes[at:], ignore_bom=false)
  catch {
    _ => return Err("Insertion must align to original UTF-8 boundaries")
  }
  let after = parse_report(edited, version=self.version)
  if !after.is_valid() ||
    after.file.blocks.length() != original.file.blocks.length() {
    return Err("New Pair conflicts with its original CIF context or budgets")
  }
  let shift = (at, @utf8.encode(inserted).length())
  for i in 0..<original.file.blocks.length() {
    if !pair_container_same(
        original.file.blocks[i],
        after.file.blocks[i],
        matched[0],
        new_tag,
        new_value,
        at + leading.length(),
        shift,
      ) {
      return Err(
        "Pair creation must retain all original entries and add exactly one field",
      )
    }
  }
  Ok(edited)
}
