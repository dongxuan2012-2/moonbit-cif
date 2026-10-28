///|
priv struct Reader {
  tokens : Array[Token]
  mut pos : Int
  diagnostics : Array[CifDiagnostic]
  raw_data : Array[Token]
  mut depth : Int
}

///|
fn Reader::error(
  self : Reader,
  code : String,
  message : String,
  span : Span,
) -> Unit {
  if self.diagnostics.length() < 100 {
    self.diagnostics.push({ code, message, span, })
  }
}

///|
fn reserved(t : Token) -> Bool {
  if t.kind != Word {
    return false
  }
  let s = t.text.to_lower()
  s.has_prefix("_") ||
  s.has_prefix("data_") ||
  s.has_prefix("save_") ||
  s == "loop_" ||
  s == "stop_" ||
  s == "global_"
}

///|
fn Reader::value(self : Reader) -> Value? {
  if self.pos >= self.tokens.length() {
    return None
  }
  let t = self.tokens[self.pos]
  if reserved(t) || t.kind == CloseList || t.kind == CloseTable {
    return None
  }
  if self.depth >= 128 {
    self.error("E005", "Nested value depth exceeds 128", t.span)
    self.raw_data.push(t)
    self.pos += 1
    return None
  }
  self.pos += 1
  if t.kind == OpenList || t.kind == OpenTable {
    self.depth += 1
    let list : Array[Value] = []
    let table : Array[(Token, Value)] = []
    let keys : Map[String, Bool] = Map([])
    let mut last = t.span
    let mut closed = false
    while self.pos < self.tokens.length() {
      let key = self.tokens[self.pos]
      if (t.kind == OpenList && key.kind == CloseList) ||
        (t.kind == OpenTable && key.kind == CloseTable) {
        last = key.span
        self.pos += 1
        closed = true
        break
      }
      if t.kind == OpenTable {
        if !(key.kind == Quoted || key.kind == Triple) {
          break
        }
        self.pos += 1
        if self.pos >= self.tokens.length() ||
          self.tokens[self.pos].kind != Colon {
          self.error(
            "E004",
            "Table key requires an immediately adjacent colon",
            key.span,
          )
          break
        }
        self.pos += 1
        match self.value() {
          Some(v) => {
            if keys.contains(key.text) {
              self.error("E004", "Duplicate table key", key.span)
            }
            keys[key.text] = true
            last = v.span()
            table.push((key, v))
          }
          None => {
            self.error("E004", "Missing table value", key.span)
            break
          }
        }
      } else {
        match self.value() {
          Some(v) => {
            last = v.span()
            list.push(v)
          }
          None => break
        }
      }
    }
    self.depth -= 1
    if !closed {
      self.error(
        "E004",
        "Unclosed or malformed composite value",
        joined_span(t.span, last),
      )
    }
    return Some(
      if t.kind == OpenList {
        List(list, joined_span(t.span, last))
      } else {
        Table(table, joined_span(t.span, last))
      },
    )
  }
  if t.kind == Colon {
    self.error("E004", "Unexpected colon", t.span)
  }
  if t.kind == Word &&
    (t.text.has_prefix("$") || t.text.has_prefix("[") || t.text.has_prefix("]")) {
    self.error("E004", "Reserved start of unquoted value", t.span)
  }
  Some(Scalar(t))
}

///|
fn Reader::unique(
  self : Reader,
  names : Map[String, Bool],
  tag : Token,
) -> Unit {
  if tag.text == "_" {
    self.error(
      "E004",
      "Data name must contain a character after underscore",
      tag.span,
    )
  }
  let key = name_key(tag.text)
  if names.contains(key) {
    self.error("E004", "Duplicate name in this scope", tag.span)
  }
  names[key] = true
}

///|
fn Reader::container(
  self : Reader,
  name : Token,
  frame? : Bool = false,
) -> Container {
  let entries : Array[Entry] = []
  let frames : Array[Container] = []
  let names : Map[String, Bool] = Map([])
  let frame_names : Map[String, Bool] = Map([])
  let mut frame_closed = !frame
  while self.pos < self.tokens.length() {
    let t = self.tokens[self.pos]
    let low = t.text.to_lower()
    if t.kind == Word && low.has_prefix("data_") {
      break
    }
    if t.kind == Word && low.has_prefix("save_") {
      if frame {
        if low == "save_" {
          self.pos += 1
          frame_closed = true
        } else {
          self.error("E004", "Nested save frames are forbidden", t.span)
        }
        break
      }
      self.pos += 1
      if low == "save_" {
        self.error("E004", "Unexpected save-frame terminator", t.span)
        self.raw_data.push(t)
        continue
      }
      self.unique(frame_names, t)
      frames.push(self.container(t, frame=true))
      continue
    }
    self.pos += 1
    if t.kind == Word && low == "loop_" {
      let tags : Array[Token] = []
      let vals : Array[Value] = []
      while self.pos < self.tokens.length() {
        let tag = self.tokens[self.pos]
        if tag.kind == Word && tag.text.has_prefix("_") {
          self.unique(names, tag)
          tags.push(tag)
          self.pos += 1
        } else {
          break
        }
      }
      while self.pos < self.tokens.length() {
        match self.value() {
          Some(v) => vals.push(v)
          None => break
        }
      }
      let end = if vals.is_empty() {
        t.span
      } else {
        vals[vals.length() - 1].span()
      }
      if tags.is_empty() ||
        vals.is_empty() ||
        vals.length() % tags.length() != 0 {
        self.error(
          "E003",
          "Loop values must form nonempty complete rows",
          joined_span(t.span, end),
        )
      }
      entries.push(Loop(tags, vals, joined_span(t.span, end)))
    } else if t.kind == Word && low.has_prefix("_") {
      self.unique(names, t)
      match self.value() {
        Some(v) => entries.push(Pair(t, v))
        None => self.error("E004", "Data name has no value", t.span)
      }
    } else {
      self.error(
        "E004",
        "Unexpected token in container; preserved as raw data",
        t.span,
      )
      self.raw_data.push(t)
    }
  }
  if !frame_closed {
    self.error("E004", "Missing save-frame terminator", name.span)
  }
  { name, entries, frames, }
}

///|
/// Recovery never invents loop cells: partial values, all tokens and input stay available.
pub fn parse_report(source : String, version? : Version = Auto) -> ParseReport {
  let l = lex(source, version)
  let tokens = l.tokens.filter(t => t.kind != Trivia && t.kind != Comment)
  let r : Reader = {
    tokens,
    pos: 0,
    diagnostics: l.diagnostics,
    raw_data: [],
    depth: 0,
  }
  // Comments cannot start a separator after a value. CIF2 allows them after
  // container openings/table colons, and its file grammar permits a final comment.
  for i in 1..<l.tokens.length() {
    let a = l.tokens[i - 1]
    let b = l.tokens[i]
    if b.kind == Comment &&
      a.span.end_offset == b.span.start_offset &&
      a.kind != Trivia &&
      !(l.version == Cif2 &&
      (
        a.kind == OpenList ||
        a.kind == OpenTable ||
        a.kind == Colon ||
        i == l.tokens.length() - 1
      )) {
      r.error("E004", "Comment requires preceding whitespace", b.span)
    }
  }
  // Enforce separators independently of quote contents and punctuation lookalikes.
  for i in 1..<tokens.length() {
    let a = tokens[i - 1]
    let b = tokens[i]
    if a.span.end_offset == b.span.start_offset &&
      !(a.kind == OpenList ||
      a.kind == OpenTable ||
      a.kind == Colon ||
      b.kind == CloseList ||
      b.kind == CloseTable ||
      b.kind == Colon) {
      r.error("E004", "Missing whitespace between CIF tokens", b.span)
    }
  }
  let blocks : Array[Container] = []
  let names : Map[String, Bool] = Map([])
  while r.pos < tokens.length() {
    let t = tokens[r.pos]
    r.pos += 1
    if t.kind == Word &&
      t.text.to_lower().has_prefix("data_") &&
      t.text.length() > 5 {
      r.unique(names, t)
      blocks.push(r.container(t))
    } else {
      r.error("E004", "Expected a named data block", t.span)
      r.raw_data.push(t)
    }
  }
  if l.version == Cif1 {
    for t in tokens {
      if t.kind == Word &&
        (
          t.text.has_prefix("_") ||
          t.text.to_lower().has_prefix("data_") ||
          t.text.to_lower().has_prefix("save_")
        ) &&
        t.text.char_length() > (if t.text.has_prefix("_") { 75 } else { 80 }) {
        r.error("E004", "CIF1 name exceeds 75 characters", t.span)
      }
    }
  }
  {
    file: { source, tokens: l.tokens, blocks, version: l.version, },
    diagnostics: r.diagnostics,
    raw_data: r.raw_data,
  }
}

///|
pub fn parse_string(
  source : String,
  version? : Version = Auto,
) -> Result[CifFile, Array[CifDiagnostic]] {
  let report = parse_report(source, version~)
  if report.is_valid() {
    Ok(report.file)
  } else {
    Err(report.diagnostics)
  }
}

///|
/// Namespace entry corresponding to the proposed contract; use parse_report for partial recovery.
pub struct CifParser {} derive(Debug)

///|
pub fn CifParser::parse_string(
  source : String,
) -> Result[CifFile, Array[CifDiagnostic]] {
  parse_string(source)
}

///|
pub fn CifParser::new() -> CifParser {
  CifParser::{ }
}
