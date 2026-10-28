///|
fn doubled(value : @cif.Value) -> String {
  let number = value.measurement().unwrap()
  // The caller explicitly chooses metres for these user-defined *_m fields.
  let measured = @measure.MeasuredQuantity::checked_from_parts(
    number.value.unwrap(),
    number.uncertainty.unwrap(),
    @si.meter,
  ).unwrap()
  let result = measured.scale(2.0)
  @cif.format_su(result.value(), result.uncertainty()).unwrap()
}

///|
fn main raise {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_É\r\n_length_m 9.999(1)\r\n_note 'root note'\r\nsave_Å\r\nloop_\r\n_LENGTH_M\r\n_NOTE\r\n_ID\r\n1.5423(12) 'keep A' A # keep A\r\n2.10(3) 'old B' B # keep B\r\n? 'unknown C' C\r\n3.33(4) 'old D' D # keep D\r\nloop_\r\n_unrelated_id\r\n_unrelated_value\r\nD 100\r\nC 200\r\nB 300\r\nA 400\r\nsave_\r\n"
  let note_b = "Lunar scale(2.0): \"meter\", operator O'Brien\n;reviewed ''' and \"\"\"\ntrailing slash\\\n"
  let file = @cif.parse_string(source).unwrap()
  let rows = file
    .find_loop_rows("e\u0301", ["_id", "_length_m", "_note"], frame="A\u030A")
    .unwrap()
  let edits : Array[(@cif.Value, String)] = []
  let selected : Array[Json] = []
  for row in rows {
    let id = row[0].to_json()
    if id == Json::string("B") || id == Json::string("D") {
      let numeric = doubled(row[1])
      let text = if id == Json::string("B") { note_b } else { "?" }
      let literal = @cif.format_string(text, version=file.version).unwrap()
      edits.push((row[1], numeric))
      edits.push((row[2], literal))
      selected.push({
        "id": id,
        "valueSpan": row[1].span().to_json(),
        "noteSpan": row[2].span().to_json(),
        "newNumeric": numeric,
        "noteText": text,
        "noteLiteral": literal,
      })
    }
  }
  assert_eq(edits.length(), 4)
  assert_true(
    file.replace_values([edits[0], edits[1], edits[2], (edits[3].0, "'broken")])
    is Err(_),
  )
  assert_eq(file.rewrite_original(), source)
  let edited = file
    .replace_values([edits[3], edits[2], edits[1], edits[0]])
    .unwrap()
  let again = @cif.parse_string(edited).unwrap()
  let notes = again.find_values("é", "_note", frame="å")
  assert_eq(notes.map(v => v.to_json()), [
    Json::string("keep A"),
    Json::string(note_b),
    Json::string("unknown C"),
    Json::string("?"),
  ])
  assert_true(notes[3].measurement() is Err(_))
  assert_eq(
    again.find_values("é", "_note")[0].to_json(),
    Json::string("root note"),
  )
  assert_eq(
    again.find_values("é", "_length_m", frame="å").map(v => v.to_json()),
    [
      Json::string("1.5423(12)"),
      Json::string("4.200(60)"),
      Json::string("?"),
      Json::string("6.660(80)"),
    ],
  )
  let output : Json = {
    "source": source,
    "edited": edited,
    "selected": selected.to_json(),
    "invalidBatchRejected": true,
  }
  println(output.stringify())
}
