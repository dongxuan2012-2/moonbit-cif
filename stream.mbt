///|
/// Source-retaining streaming tokenizer. Prefixes are rescanned for simplicity (quadratic worst case).
/// feed emits complete stable tokens; finish is mandatory for structural validation.
pub struct CifStream {
  bytes : Array[Byte]
  mut emitted : Int
  mut closed : Bool
  version : Version
  max_bytes : Int
} derive(Debug)

///|
pub fn CifStream::new(
  version? : Version = Auto,
  max_bytes? : Int = 16777216,
) -> CifStream {
  { bytes: [], emitted: 0, closed: false, version, max_bytes, }
}

///|
fn incomplete_prefix(bytes : Bytes) -> Result[String, String] {
  for trim in 0..<=3 {
    if trim > bytes.length() {
      break
    }
    let end = bytes.length() - trim
    if trim > 0 {
      let lead = bytes[end].to_int()
      let wanted = if lead >= 0xC2 && lead <= 0xDF {
        2
      } else if lead >= 0xE0 && lead <= 0xEF {
        3
      } else if lead >= 0xF0 && lead <= 0xF4 {
        4
      } else {
        0
      }
      if wanted <= trim {
        continue
      }
      let mut good = true
      for i in (end + 1)..<bytes.length() {
        let b = bytes[i].to_int()
        if b < 0x80 || b > 0xBF {
          good = false
        }
      }
      if !good {
        continue
      }
    }
    try {
      return Ok(@utf8.decode(bytes[:end], ignore_bom=false))
    } catch {
      _ => ()
    }
  }
  Err("E004: malformed UTF-8 stream")
}

///|
pub fn CifStream::feed(
  self : CifStream,
  chunk : Bytes,
) -> Result[Array[Token], String] {
  if self.closed {
    return Err("Stream is already finished")
  }
  if chunk.length() > self.max_bytes - self.bytes.length() {
    self.closed = true
    return Err("E005: stream byte budget exceeded")
  }
  for b in chunk {
    self.bytes.push(b)
  }
  match incomplete_prefix(Bytes::from_array(self.bytes[:])) {
    Err(e) => {
      self.closed = true
      Err(e)
    }
    Ok(source) => {
      let l = lex(source, self.version, is_final=false)
      let out = l.tokens[self.emitted:].to_owned()
      self.emitted = l.tokens.length()
      Ok(out)
    }
  }
}

///|
pub fn CifStream::finish(self : CifStream) -> Result[ParseReport, String] {
  if self.closed {
    return Err("Stream is already finished")
  }
  self.closed = true
  Ok(
    parse_report(
      @utf8.decode(Bytes::from_array(self.bytes[:]), ignore_bom=false),
      version=self.version,
    ),
  ) catch {
    _ => Err("E004: incomplete or malformed UTF-8 at end of stream")
  }
}
