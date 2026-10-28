///|
/// Original Pair/Loop column values in source order, within this container only.
/// Partial input keeps present cells; no padding, conversion or nested-value flattening.
pub fn Container::find_values(self : Container, tag : String) -> Array[Value] {
  let key = name_key(tag)
  let out : Array[Value] = []
  for entry in self.entries {
    match entry {
      Pair(name, value) => if name_key(name.text) == key { out.push(value) }
      Loop(tags, values, _) =>
        if !tags.is_empty() {
          let wanted = tags.map(t => name_key(t.text) == key)
          if wanted.any(x => x) {
            for i in 0..<values.length() {
              if wanted[i % tags.length()] {
                out.push(values[i])
              }
            }
          }
        }
    }
  }
  out
}

///|
/// Query one block or an explicit frame, without crossing scopes or changing the source.
/// Codes omit data_/save_; missing scope/tag returns []. Empty frame selects block entries.
pub fn CifFile::find_values(
  self : CifFile,
  block : String,
  tag : String,
  frame? : String = "",
) -> Array[Value] {
  match self.query_container(block, frame) {
    Some(container) => container.find_values(tag)
    None => []
  }
}

///|
fn CifFile::query_container(
  self : CifFile,
  block : String,
  frame : String,
) -> Container? {
  let block_key = name_key("data_" + block)
  let frame_key = name_key("save_" + frame)
  for b in self.blocks {
    if name_key(b.name.text) == block_key {
      if frame.is_empty() {
        return Some(b)
      }
      for f in b.frames {
        if name_key(f.name.text) == frame_key {
          return Some(f)
        }
      }
      return None
    }
  }
  None
}

///|
/// Project requested columns from exactly one complete syntactic loop.
/// Rows follow source order; cells follow requested tag order. No joins or padding.
pub fn Container::find_loop_rows(
  self : Container,
  tags : Array[String],
) -> Result[Array[Array[Value]], String] {
  if tags.is_empty() {
    return Err("At least one loop column is required")
  }
  let requested = tags.map(name_key)
  let seen : Map[String, Bool] = Map([])
  for key in requested {
    if seen.contains(key) {
      return Err("Requested loop columns must be distinct")
    }
    seen[key] = true
  }
  let mut found : (Array[Token], Array[Value], Array[Int])? = None
  for entry in self.entries {
    if entry is Loop(headers, values, _) {
      let keys = headers.map(t => name_key(t.text))
      let columns : Array[Int] = []
      for key in requested {
        let mut column = -1
        for i in 0..<keys.length() {
          if keys[i] == key {
            column = i
            break
          }
        }
        if column >= 0 {
          columns.push(column)
        }
      }
      if columns.length() == requested.length() {
        if found is Some(_) {
          return Err("More than one loop matches the requested columns")
        }
        found = Some((headers, values, columns))
      }
    }
  }
  match found {
    None => Err("Requested columns are not present together in one loop")
    Some((headers, values, columns)) => {
      let unique : Map[String, Bool] = Map([])
      for header in headers {
        let key = name_key(header.text)
        if unique.contains(key) {
          return Err("Selected loop has duplicate headers")
        }
        unique[key] = true
      }
      let width = headers.length()
      if values.is_empty() || values.length() % width != 0 {
        return Err("Selected loop must contain nonempty complete rows")
      }
      let rows : Array[Array[Value]] = []
      let mut start = 0
      while start < values.length() {
        rows.push(columns.map(column => values[start + column]))
        start += width
      }
      Ok(rows)
    }
  }
}

///|
/// Row projection within one explicit block/frame; missing or unsuitable relation is Err.
pub fn CifFile::find_loop_rows(
  self : CifFile,
  block : String,
  tags : Array[String],
  frame? : String = "",
) -> Result[Array[Array[Value]], String] {
  match self.query_container(block, frame) {
    Some(container) => container.find_loop_rows(tags)
    None => Err("Data block or save frame not found")
  }
}
