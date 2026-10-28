///|
/// Original decimal text is authoritative; Double projections may be unavailable.
pub(all) struct SuReal {
  lexeme : String
  value : Double?
  uncertainty : Double?
  uncertainty_digits : String?
  is_unknown : Bool
  is_inapplicable : Bool
} derive(Debug)

///|
fn finite(x : Double) -> Bool {
  x == x && x.abs() <= 1.7976931348623157e308
}

///|
fn digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn project(s : String) -> Double? {
  try {
    let x = @string.parse_double(s)
    let mut nonzero = false
    for c in s.to_array() {
      if c == 'e' || c == 'E' {
        break
      }
      if c >= '1' && c <= '9' {
        nonzero = true
      }
    }
    if finite(x) && !(x == 0.0 && nonzero) {
      Some(x)
    } else {
      None
    }
  } catch {
    _ => None
  }
}

///|
/// Parse CIF number grammar (exponent before appended uncertainty), not arbitrary host floats.
pub fn parse_su(s : String) -> Result[SuReal, String] {
  let unknown = s == "?"
  let inapplicable = s == "."
  if unknown || inapplicable {
    return Ok({
      lexeme: s,
      value: None,
      uncertainty: None,
      uncertainty_digits: None,
      is_unknown: unknown,
      is_inapplicable: inapplicable,
    })
  }
  let a = s.to_array()
  let n = a.length()
  let mut i = 0
  let mut digits = 0
  let mut decimal = 0
  if i < n && (a[i] == '+' || a[i] == '-') {
    i += 1
  }
  while i < n && digit(a[i]) {
    i += 1
    digits += 1
  }
  if i < n && a[i] == '.' {
    i += 1
    while i < n && digit(a[i]) {
      i += 1
      digits += 1
      decimal += 1
    }
  }
  if digits == 0 {
    return Err("Not a CIF numeric token")
  }
  let mut exponent = 0
  if i < n && (a[i] == 'e' || a[i] == 'E') {
    i += 1
    let mut negative = false
    if i < n && (a[i] == '+' || a[i] == '-') {
      negative = a[i] == '-'
      i += 1
    }
    let start = i
    while i < n && digit(a[i]) {
      if exponent < 1000000 {
        exponent = exponent * 10 + a[i].to_int() - 48
      }
      i += 1
    }
    if i == start {
      return Err("Exponent requires digits")
    }
    if negative {
      exponent = -exponent
    }
  }
  let base = String::from_array(a[0:i])
  let mut su : String? = None
  if i < n && a[i] == '(' {
    i += 1
    let start = i
    while i < n && digit(a[i]) {
      i += 1
    }
    if i == start || i >= n || a[i] != ')' {
      return Err("Uncertainty requires decimal digits and closing parenthesis")
    }
    su = Some(String::from_array(a[start:i]))
    i += 1
  }
  if i != n {
    return Err("Trailing content in numeric token")
  }
  let value = project(base)
  let uncertainty = match su {
    None => None
    Some(d) => project(d + "e" + (exponent - decimal).to_string())
  }
  Ok({
    lexeme: s,
    value,
    uncertainty,
    uncertainty_digits: su,
    is_unknown: false,
    is_inapplicable: false,
  })
}

///|
/// Quoted '?', '.', and quoted numbers are strings, never automatically measured values.
pub fn Value::measurement(self : Value) -> Result[SuReal, String] {
  match self {
    Scalar(t) =>
      if t.kind == Word {
        parse_su(t.text)
      } else {
        Err("Quoted/text values are not numeric tokens")
      }
    _ => Err("Composite value is not a scalar measurement")
  }
}

///|
/// Exact source spelling, including exponent, significant zeros and absent uncertainty.
pub fn SuReal::to_cif_string(self : SuReal) -> String {
  self.lexeme
}

///|
fn decimal_text(integer : Int64, places : Int) -> String {
  let negative = integer < 0L
  let s = (if negative { -integer } else { integer }).to_string()
  let prefix = if negative { "-" } else { "" }
  if places <= 0 {
    return prefix + s + "0".repeat(-places)
  }
  if s.length() <= places {
    return prefix + "0." + "0".repeat(places - s.length()) + s
  }
  prefix +
  s[:s.length() - places].to_owned() +
  "." +
  s[s.length() - places:].to_owned()
}

///|
/// Finite computed results only; 1..9 su digits, half away from zero.
/// Integer scaling is bounded to 2^53; out-of-range formatting returns Err, never truncates.
pub fn format_su(
  value : Double,
  su : Double,
  digits? : Int = 2,
) -> Result[String, String] {
  if !finite(value) || !finite(su) || su < 0.0 || digits < 1 || digits > 9 {
    return Err("Finite value, nonnegative uncertainty and 1..9 digits required")
  }
  if su == 0.0 {
    return Ok(value.to_string() + "(0)")
  }
  let exponent = decimal_order(su)
  let mut places = digits - 1 - exponent
  let unit = @math.pow(10.0, -places.to_double())
  if unit == 0.0 || !finite(unit) {
    return Err("Decimal formatting scale outside Double range")
  }
  let mut u = round_decimal_abs(su, places)
  if u >= pow10_integer(digits) {
    places -= 1
    u = round_decimal_abs(su, places)
  }
  let magnitude = round_decimal_abs(value, places)
  if magnitude > @bigint.BigInt::from_int64(9007199254740992L) {
    return Err("Scaled integer exceeds exact Double integer range")
  }
  let rounded = magnitude.to_int64() * (if value < 0.0 { -1L } else { 1L })
  Ok(
    (if places < 0 {
      rounded.to_string() + "e" + (-places).to_string()
    } else {
      decimal_text(rounded, places)
    }) +
    "(" +
    u.to_string() +
    ")",
  )
}

///|
/// Downstream adapters choose units and correlation models. No propagation is performed here.
pub(open) trait UncertaintySink {
  fn accept(Self, Double, Double?) -> Unit
}

///|
pub fn[S : UncertaintySink] SuReal::send_to(
  self : SuReal,
  sink : S,
) -> Result[Unit, String] {
  if self.is_unknown || self.is_inapplicable {
    return Err("Missing measurement cannot be sent to numeric sink")
  }
  match self.value {
    None => Err("Decimal value cannot be projected to finite Double")
    Some(v) => {
      if self.uncertainty_digits is Some(_) && self.uncertainty is None {
        return Err("Uncertainty cannot be projected to finite Double")
      }
      sink.accept(v, self.uncertainty)
      Ok(())
    }
  }
}

///|
/// Replace one parsed value, preserving all other bytes. Replacement must be one legal value.
pub fn CifFile::replace_value(
  self : CifFile,
  value : Value,
  replacement : String,
) -> Result[String, String] {
  self.replace_values([(value, replacement)])
}

///|
fn validate_replacement(
  version : Version,
  replacement : String,
) -> Result[Unit, String] {
  let prefix = (if version == Cif2 { "#\\#CIF_2.0\n" } else { "" }) +
    "data_edit\n_v "
  let check = parse_report(prefix + replacement + "\n", version~)
  if !check.is_valid() ||
    check.file.blocks.length() != 1 ||
    check.file.blocks[0].entries.length() != 1 ||
    !check.file.blocks[0].frames.is_empty() {
    return Err("Replacement must be a single legal CIF value")
  }
  let replacement_span = match check.file.blocks[0].entries[0] {
    Pair(_, v) => v.span()
    _ => return Err("Replacement must be a single legal CIF value")
  }
  let prefix_size = @utf8.encode(prefix).length()
  if check.file.tokens.any(t => {
      t.kind == Comment &&
      t.span.start_offset >= prefix_size &&
      !(t.span.start_offset >= replacement_span.start_offset &&
      t.span.end_offset <= replacement_span.end_offset)
    }) {
    return Err(
      "Comments outside the replacement value could hide untouched source",
    )
  }
  Ok(())
}

///|
/// Atomically replace disjoint values anchored to this original source snapshot.
/// Input order is arbitrary; repeated/overlapping values and any invalid edit return Err.
/// This returns text only and never mutates the parsed file or writes to disk.
pub fn CifFile::replace_values(
  self : CifFile,
  edits : Array[(Value, String)],
) -> Result[String, String] {
  if edits.is_empty() {
    return Ok(self.source)
  }
  let ordered = edits[:].to_owned()
  ordered.sort_by_key(edit => edit.0.span().start_offset)
  let bytes = @utf8.encode(self.source)
  for i in 0..<ordered.length() {
    let (value, replacement) = ordered[i]
    if validate_replacement(self.version, replacement) is Err(e) {
      return Err(e)
    }
    if !self.blocks.any(b => container_has(b, value)) {
      return Err("Value is not part of this parsed file")
    }
    let span = value.span()
    if span.start_offset < 0 ||
      span.end_offset > bytes.length() ||
      span.start_offset > span.end_offset {
      return Err("Span outside this source")
    }
    if i > 0 && span.start_offset < ordered[i - 1].0.span().end_offset {
      return Err("Selected values overlap or repeat")
    }
  }
  try {
    let pieces : Array[String] = []
    let mut cursor = 0
    for (value, replacement) in ordered {
      let span = value.span()
      let old = @utf8.decode(
        bytes[span.start_offset:span.end_offset],
        ignore_bom=false,
      )
      let original = self.tokens
        .filter(t => {
          t.span.start_offset >= span.start_offset &&
          t.span.end_offset <= span.end_offset
        })
        .map(t => t.raw)
        .join("")
      if old != original {
        return Err("Value is not aligned to tokens in this file")
      }
      pieces.push(
        @utf8.decode(bytes[cursor:span.start_offset], ignore_bom=false),
      )
      pieces.push(replacement)
      cursor = span.end_offset
    }
    pieces.push(@utf8.decode(bytes[cursor:], ignore_bom=false))
    let edited = pieces.join("")
    if parse_report(self.source, version=self.version).is_valid() &&
      !parse_report(edited, version=self.version).is_valid() {
      return Err("Replacement conflicts with its original lexical context")
    }
    Ok(edited)
  } catch {
    _ => Err("Span must align to UTF-8 boundaries")
  }
}

///|
fn value_has(root : Value, target : Value) -> Bool {
  if root == target {
    return true
  }
  match root {
    Scalar(_) => false
    List(items, _) => items.any(v => value_has(v, target))
    Table(items, _) => items.any(p => value_has(p.1, target))
  }
}

///|
fn container_has(container : Container, value : Value) -> Bool {
  container.entries.any(e => {
    match e {
      Pair(_, v) => value_has(v, value)
      Loop(_, vs, _) => vs.any(v => value_has(v, value))
    }
  }) ||
  container.frames.any(f => container_has(f, value))
}
