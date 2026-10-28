///|
fn doubled(value : @cif.Value) -> String {
  let number = value.measurement().unwrap()
  // This example explicitly chooses metres for its user-defined *_m fields.
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
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_É\r\n_length_m 9.999(1)\r\nsave_Å\r\nloop_\r\n_LENGTH_M\r\n_ID\r\n1.5423(12) A # keep A\r\n2.10(3) B # keep B\r\n? C\r\n3.33(4) D # keep D\r\nloop_\r\n_unrelated_id\r\n_unrelated_value\r\nD 100\r\nC 200\r\nB 300\r\nA 400\r\nsave_\r\n"
  let file = @cif.parse_string(source).unwrap()
  let rows = file
    .find_loop_rows("e\u0301", ["_id", "_length_m"], frame="A\u030A")
    .unwrap()
  assert_eq(rows.length(), 4)
  assert_true(
    file.find_loop_rows("é", ["_unrelated_id", "_length_m"], frame="å")
    is Err(_),
  )
  assert_true(file.find_loop_rows("é", ["_id", "_length_m"]) is Err(_))
  let edits : Array[(@cif.Value, String)] = []
  for row in rows {
    let id = row[0].to_json()
    if id == Json::string("B") || id == Json::string("D") {
      edits.push((row[1], doubled(row[1])))
    }
  }
  assert_eq(edits.length(), 2)
  assert_true(
    file.replace_values([(edits[0].0, edits[0].1), (edits[1].0, "'broken")])
    is Err(_),
  )
  assert_eq(file.rewrite_original(), source)
  let edited = file.replace_values([edits[1], edits[0]]).unwrap()
  assert_eq(
    edited, "\uFEFF#\\#CIF_2.0\r\ndata_É\r\n_length_m 9.999(1)\r\nsave_Å\r\nloop_\r\n_LENGTH_M\r\n_ID\r\n1.5423(12) A # keep A\r\n4.200(60) B # keep B\r\n? C\r\n6.660(80) D # keep D\r\nloop_\r\n_unrelated_id\r\n_unrelated_value\r\nD 100\r\nC 200\r\nB 300\r\nA 400\r\nsave_\r\n",
  )
  let again = @cif.parse_string(edited).unwrap()
  assert_eq(
    again
    .find_loop_rows("É", ["_id", "_length_m"], frame="Å")
    .unwrap()
    .map(row => row[1].to_json()),
    [
      Json::string("1.5423(12)"),
      Json::string("4.200(60)"),
      Json::string("?"),
      Json::string("6.660(80)"),
    ],
  )
  assert_eq(
    again.find_values("é", "_length_m")[0].to_json(),
    Json::string("9.999(1)"),
  )
  let output : Json = {
    "source": source,
    "edited": edited,
    "rowValues": rows.map(row => row.map(v => v.to_json()).to_json()).to_json(),
    "rowSpans": rows
    .map(row => row.map(v => v.span().to_json()).to_json())
    .to_json(),
    "crossLoopRejected": true,
    "invalidBatchRejected": true,
  }
  println(output.stringify())
}
