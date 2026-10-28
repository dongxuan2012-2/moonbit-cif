///|
priv struct Point {
  line : Int
  col : Int
  byte : Int
}

///|
priv struct Lexer {
  chars : Array[Char]
  points : Array[Point]
  mut pos : Int
  tokens : Array[Token]
  diagnostics : Array[CifDiagnostic]
  version : Version
}

///|
fn white(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn newline(c : Char) -> Bool {
  c == '\r' || c == '\n'
}

///|
fn Lexer::span(self : Lexer, a : Int, b : Int) -> Span {
  let p = self.points[a]
  let q = self.points[b]
  {
    start_line: p.line,
    start_col: p.col,
    start_offset: p.byte,
    end_line: q.line,
    end_col: q.col,
    end_offset: q.byte,
  }
}

///|
fn Lexer::slice(self : Lexer, a : Int, b : Int) -> String {
  String::from_array(self.chars[a:b])
}

///|
fn Lexer::emit(
  self : Lexer,
  kind : TokenKind,
  start : Int,
  text : String,
) -> Unit {
  self.tokens.push({
    kind,
    raw: self.slice(start, self.pos),
    text,
    span: self.span(start, self.pos),
  })
}

///|
fn Lexer::error(
  self : Lexer,
  code : String,
  msg : String,
  a : Int,
  b : Int,
) -> Unit {
  if self.diagnostics.length() < 100 {
    self.diagnostics.push({ code, message: msg, span: self.span(a, b), })
  }
}

///|
fn normalized_lines(s : String) -> String {
  s.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// Decode only CIF text protocols. Backslashes in other tokens stay literal.
fn text_protocol(s : String, v : Version) -> String {
  let raw = normalized_lines(s)
  if v != Cif2 {
    return raw
  }
  let lines = raw.split("\n").map(v => v.to_owned()).collect()
  let first = lines[0]
  let mut content = raw
  if first.find("\\") is Some(k) {
    let prefix = first[:k].to_owned()
    let tail = first[k:].to_owned().trim_end(chars=" \t").to_owned()
    if !prefix.is_empty() &&
      !prefix.has_prefix(";") &&
      (tail == "\\" || tail == "\\\\") &&
      lines[1:].iter().all(line => line.has_prefix(prefix)) {
      let stripped = lines[1:]
        .iter()
        .map(line => line[prefix.length():].to_owned())
        .collect()
        .join("\n")
      content = if tail == "\\\\" { "\\\n" + stripped } else { stripped }
    }
  }
  let parts = content.split("\n").map(v => v.to_owned()).collect()
  if parts[0].trim_end(chars=" \t").to_owned() != "\\" {
    return content
  }
  let mut out = ""
  for i in 1..<parts.length() {
    let part = parts[i]
    let t = part.trim_end(chars=" \t").to_owned()
    if i < parts.length() - 1 && t.has_suffix("\\") {
      out += t[:t.length() - 1].to_owned()
    } else {
      out += part
      if i < parts.length() - 1 {
        out += "\n"
      }
    }
  }
  out
}

///|
fn lex(source : String, version : Version, is_final? : Bool = true) -> Lexer {
  let chars = source.to_array()
  let points : Array[Point] = []
  let mut line = 1
  let mut col = 1
  let mut byte = 0
  let mut cr = false
  for c in chars {
    points.push({ line, col, byte, })
    let n = c.to_int()
    byte += if n < 128 {
      1
    } else if n < 2048 {
      2
    } else if n < 65536 {
      3
    } else {
      4
    }
    if c == '\r' {
      line += 1
      col = 1
      cr = true
    } else if c == '\n' {
      if !cr {
        line += 1
      }
      col = 1
      cr = false
    } else {
      col += 1
      cr = false
    }
  }
  points.push({ line, col, byte, })
  let actual = if version == Auto {
    if source.has_prefix("#\\#CIF_2.0") ||
      source.has_prefix("\uFEFF#\\#CIF_2.0") {
      Cif2
    } else {
      Cif1
    }
  } else {
    version
  }
  let l : Lexer = {
    chars,
    points,
    pos: 0,
    tokens: [],
    diagnostics: [],
    version: actual,
  }
  if actual == Cif2 && is_final {
    let h = if chars.length() > 0 && chars[0] == '\uFEFF' { 1 } else { 0 }
    let valid_magic = chars.length() >= h + 10 &&
      l.slice(h, h + 10) == "#\\#CIF_2.0"
    let mut good = valid_magic &&
      (chars.length() == h + 10 || white(chars[h + 10]))
    let mut i = h + 10
    while i < chars.length() && !newline(chars[i]) {
      if chars[i] != ' ' && chars[i] != '\t' {
        good = false
      }
      i += 1
    }
    if !good {
      l.error(
        "E004",
        "CIF2 requires an exact version header ending at EOF or followed by whitespace",
        0,
        chars.length(),
      )
    }
  }
  for i in 0..<chars.length() {
    let n = chars[i].to_int()
    let allowed = n == 9 ||
      n == 10 ||
      n == 13 ||
      (n >= 32 && n <= 126) ||
      (
        actual == Cif2 &&
        n >= 160 &&
        n <= 0x10FFFF &&
        n != 0xFEFF &&
        !(n >= 0xD800 && n <= 0xDFFF) &&
        !(n >= 0xFDD0 && n <= 0xFDEF) &&
        n % 65536 < 65534
      ) ||
      (i == 0 && n == 0xFEFF && actual == Cif2)
    if !allowed {
      l.error(
        "E004",
        "Character outside the selected CIF character set",
        i,
        i + 1,
      )
    }
    if points[i].col == 2049 && !newline(chars[i]) {
      l.error("E004", "Physical line exceeds 2048 characters", i, i + 1)
    }
  }
  while l.pos < chars.length() {
    let start = l.pos
    let c = chars[start]
    if (c == '\uFEFF' && start == 0) || white(c) {
      l.pos += 1
      while l.pos < chars.length() && white(chars[l.pos]) {
        l.pos += 1
      }
      if l.pos == chars.length() && !is_final {
        break
      }
      l.emit(Trivia, start, l.slice(start, l.pos))
      continue
    }
    if c == '#' {
      while l.pos < chars.length() && !newline(chars[l.pos]) {
        l.pos += 1
      }
      if l.pos == chars.length() && !is_final {
        break
      }
      l.emit(Comment, start, l.slice(start, l.pos))
      continue
    }
    if c == ';' && points[start].col == 1 {
      l.pos += 1
      let body = l.pos
      let mut close = -1
      while l.pos < chars.length() {
        if chars[l.pos] == ';' && points[l.pos].col == 1 {
          close = l.pos
          break
        }
        l.pos += 1
      }
      if close < 0 {
        if is_final {
          l.error("E002", "Unclosed semicolon text field", start, l.pos)
          l.emit(Text, start, l.slice(body, l.pos))
        }
        break
      }
      let mut end = close
      if end > body && chars[end - 1] == '\n' {
        end -= 1
      }
      if end > body && chars[end - 1] == '\r' {
        end -= 1
      }
      let text = text_protocol(l.slice(body, end), actual)
      l.pos += 1
      l.emit(Text, start, text)
      continue
    }
    if c == '\'' || c == '"' {
      let triple = actual == Cif2 &&
        start + 2 < chars.length() &&
        chars[start + 1] == c &&
        chars[start + 2] == c
      let width = if triple { 3 } else { 1 }
      l.pos += width
      let body = l.pos
      let mut close = -1
      while l.pos < chars.length() {
        if !triple && newline(chars[l.pos]) {
          break
        }
        if chars[l.pos] == c {
          if triple {
            if l.pos + 2 < chars.length() &&
              chars[l.pos + 1] == c &&
              chars[l.pos + 2] == c {
              close = l.pos
              break
            }
          } else if actual == Cif2 ||
            l.pos + 1 == chars.length() ||
            white(chars[l.pos + 1]) {
            close = l.pos
            break
          }
        }
        l.pos += 1
      }
      if close < 0 {
        if !is_final && l.pos == chars.length() {
          break
        }
        l.error("E001", "Unclosed quoted value", start, l.pos)
        l.emit(
          if triple {
            Triple
          } else {
            Quoted
          },
          start,
          l.slice(body, l.pos),
        )
        continue
      }
      if !is_final && close + width == chars.length() {
        break
      }
      let text = normalized_lines(l.slice(body, close))
      l.pos += width
      l.emit(if triple { Triple } else { Quoted }, start, text)
      if actual == Cif2 && l.pos < chars.length() && chars[l.pos] == ':' {
        let a = l.pos
        l.pos += 1
        l.emit(Colon, a, ":")
      }
      continue
    }
    if actual == Cif2 && (c == '[' || c == ']' || c == '{' || c == '}') {
      l.pos += 1
      l.emit(
        match c {
          '[' => OpenList
          ']' => CloseList
          '{' => OpenTable
          _ => CloseTable
        },
        start,
        c.to_string(),
      )
      continue
    }
    // CIF2 container codes and data names admit brackets; only values exclude them.
    let name_token = c == '_' ||
      (
        start + 5 <= chars.length() &&
        (
          l.slice(start, start + 5).to_lower() == "data_" ||
          l.slice(start, start + 5).to_lower() == "save_"
        )
      )
    l.pos += 1
    while l.pos < chars.length() &&
          !white(chars[l.pos]) &&
          !(actual == Cif2 &&
          !name_token &&
          (
            chars[l.pos] == '[' ||
            chars[l.pos] == ']' ||
            chars[l.pos] == '{' ||
            chars[l.pos] == '}'
          )) {
      l.pos += 1
    }
    if l.pos == chars.length() && !is_final {
      break
    }
    l.emit(Word, start, l.slice(start, l.pos))
  }
  l
}
