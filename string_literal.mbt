///|
fn literal_preserves_string(
  literal : String,
  text : String,
  version : Version,
) -> Bool {
  let header = if version == Cif2 { "#\\#CIF_2.0\n" } else { "" }
  let report = parse_report(
    header + "data_string\n_v " + literal + "\n",
    version~,
  )
  if !report.is_valid() ||
    report.file.blocks.length() != 1 ||
    report.file.blocks[0].entries.length() != 1 ||
    !report.file.blocks[0].frames.is_empty() {
    return false
  }
  match report.file.blocks[0].entries[0] {
    Pair(_, Scalar(token)) => token.kind != Word && token.text == text
    _ => false
  }
}

///|
fn prefixed_folded_string(text : String) -> String {
  let slash = "\\"
  let physical : Array[String] = []
  for line in text.split("\n") {
    let chars = line.to_owned().to_array()
    if chars.is_empty() {
      physical.push("> " + slash)
    } else {
      let mut start = 0
      while start < chars.length() {
        let end = if start + 2045 < chars.length() {
          start + 2045
        } else {
          chars.length()
        }
        physical.push("> " + String::from_array(chars[start:end]) + slash)
        start = end
      }
    }
    // An unfolded blank line preserves a real LF; the final blank emits none.
    physical.push("> ")
  }
  "\n;> " + slash + slash + "\n" + physical.join("\n") + "\n;\n"
}

///|
/// Encode exact LF-normalized text as a quoted/text scalar, including '?' and numbers.
/// Pass the target file's Cif1/Cif2 version; Auto, CR and unrepresentable text are Err.
/// The fragment may contain surrounding newlines; final edit context is still validated.
pub fn format_string(
  text : String,
  version? : Version = Cif2,
) -> Result[String, String] {
  if version == Auto {
    return Err("Choose Cif1 or Cif2 for a new string literal")
  }
  if text.to_array().any(c => c == '\r') {
    return Err("String text must use normalized LF, not CR or CRLF")
  }
  let candidates = ["'" + text + "'", "\"" + text + "\""]
  if version == Cif2 {
    candidates.push("'''" + text + "'''")
    candidates.push("\"\"\"" + text + "\"\"\"")
  }
  candidates.push("\n;" + text + "\n;\n")
  for literal in candidates {
    if literal_preserves_string(literal, text, version) {
      return Ok(literal)
    }
  }
  if version == Cif2 {
    let literal = prefixed_folded_string(text)
    if literal_preserves_string(literal, text, version) {
      return Ok(literal)
    }
  }
  Err(
    "Text cannot be represented losslessly within the selected CIF string rules",
  )
}
