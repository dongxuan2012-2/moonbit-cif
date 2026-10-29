///|
extern "js" fn read_text(path : String) -> String =
  #| path => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(process.getBuiltinModule('fs').readFileSync(path))

///|
struct Sink {
  mut result : @measure.MeasuredQuantity?
}

///|
impl @cif.UncertaintySink for Sink with fn accept(self, value, uncertainty) {
  // Metres are declared by this recipient, not inferred from a CIF dictionary.
  self.result = match uncertainty {
    Some(u) =>
      @measure.MeasuredQuantity::checked_from_parts(value, u, @si.meter)
    None => None
  }
}

///|
fn check_measure(
  value : @cif.Value,
  number : Double,
  uncertainty : Double,
) -> Unit raise {
  let sink : Sink = { result: None, }
  value.measurement().unwrap().send_to(sink).unwrap()
  assert_eq(sink.result.unwrap().value(), number)
  assert_eq(sink.result.unwrap().uncertainty(), uncertainty)
}

///|
fn main raise {
  let args = @env.args()
  let cif2 = args[2] == "cif2"
  assert_true(cif2 || args[2] == "cif1")
  let appended = args[3] == "appended"
  assert_true(appended || args[3] == "original")
  let source = read_text(args[4])
  let original = read_text(args[5])
  let inserted = read_text(args[6])
  let expected = read_text(args[7])
  let bytes = @utf8.encode(source)
  let old = @utf8.encode(original)
  let addition = @utf8.encode(inserted)
  let at = if cif2 { 225 } else { 77 }
  assert_eq(old.length(), if cif2 { 279 } else { 77 })
  assert_eq(addition.length(), if cif2 { 33 } else { 26 })
  if appended {
    assert_eq(bytes, @utf8.encode(expected))
    assert_eq(bytes.length(), if cif2 { 312 } else { 103 })
    assert_eq(bytes[:at], old[:at])
    assert_eq(bytes[at:at + addition.length()].to_owned(), addition)
    assert_eq(bytes[at + addition.length():], old[at:])
  } else {
    assert_eq(bytes, old)
  }
  let file = @cif.parse_string(source).unwrap()
  let rows = if cif2 {
    assert_eq(file.blocks.length(), 2)
    assert_eq(
      file.find("实验", "_root").unwrap().to_json(),
      Json::string("keep"),
    )
    let background = file
      .find_loop_rows("实验", ["_background_id", "_background_m"])
      .unwrap()
    assert_eq(background.length(), 1)
    assert_eq(background[0][0].to_json(), Json::string("R"))
    check_measure(background[0][1], 9.0, 0.1)
    assert_eq(
      file.find("other", "_x").unwrap().to_json(),
      Json::string("untouched"),
    )
    assert_eq(
      file.blocks[1].name.span.start_offset,
      if appended {
        284
      } else {
        251
      },
    )
    let rows = file
      .find_loop_rows(
        "实验",
        ["_sample_id", "_length_m", "_note", "_meta"],
        frame="批次",
      )
      .unwrap()
    assert_eq(rows[0].map(v => v.to_json()), [
      Json::string("P"),
      Json::string("1.500(20)"),
      Json::string("?"),
      Json::array([]),
    ])
    assert_eq(rows[1].map(v => v.to_json()), [
      Json::string("Q"),
      Json::string("2.750(5)"),
      Json::string("old Q"),
      { "k": "1" },
    ])
    check_measure(rows[0][1], 1.5, 0.02)
    check_measure(rows[1][1], 2.75, 0.005)
    assert_true(
      file.blocks[0].frames[0].entries
      is [@cif.Loop(tags, values, span), @cif.Pair(tail, value)] &&
      tags.length() == 4 &&
      values.length() == (if appended { 12 } else { 8 }) &&
      span.start_offset == 101 &&
      span.end_offset == (if appended { 257 } else { 189 }) &&
      tail.span.start_offset == (if appended { 258 } else { 225 }) &&
      value.to_json() == ["1", { "k": "2" }],
    )
    if appended {
      assert_eq(rows[2].map(v => v.to_json()), [
        Json::string("R"),
        Json::string("6.250(12)"),
        Json::string("late R"),
        ["3", { "x": "4" }],
      ])
      check_measure(rows[2][1], 6.25, 0.012)
    }
    rows
  } else {
    assert_eq(file.blocks.length(), 1)
    assert_eq(
      file.find("one", "_title").unwrap().to_json(),
      Json::string("CIF1 original"),
    )
    let rows = file
      .find_loop_rows("one", ["_id", "_length_m", "_note"])
      .unwrap()
    assert_eq(rows[0].map(v => v.to_json()), [
      Json::string("X"),
      Json::string("0.500(10)"),
      Json::string("?"),
    ])
    check_measure(rows[0][1], 0.5, 0.01)
    assert_true(
      file.blocks[0].entries is [@cif.Pair(_, _), @cif.Loop(_, values, span)] &&
      values.length() == (if appended { 6 } else { 3 }) &&
      span.start_offset == 32 &&
      span.end_offset == (if appended { 101 } else { 71 }),
    )
    if appended {
      assert_eq(rows[1].map(v => v.to_json()), [
        Json::string("Y"),
        Json::string("7.000(25)"),
        Json::string("late Y"),
      ])
      check_measure(rows[1][1], 7.0, 0.025)
    }
    rows
  }
  assert_eq(
    rows.length(),
    if cif2 {
      if appended {
        3
      } else {
        2
      }
    } else if appended {
      2
    } else {
      1
    },
  )
  assert_true(
    rows[0][2] is @cif.Scalar(t) && t.kind == @cif.Word && t.raw == "?",
  )
  assert_eq(read_text(args[4]), source)
  assert_eq(read_text(args[5]), original)
  let receipt : Json = {
    "ok": true,
    "kind": args[2].to_json(),
    "mode": args[3].to_json(),
    "receivedBytes": bytes.length().to_json(),
    "rows": rows.length().to_json(),
    "publicApiOnly": true,
    "realLunar": true,
    "unitChosenByCaller": "m",
    "newValue": (if cif2 { 6.25 } else { 7.0 }).to_json(),
    "newUncertainty": (if cif2 { 0.012 } else { 0.025 }).to_json(),
    "newMeasurementReceived": appended.to_json(),
    "sourceReadOnly": true,
    "prefixInsertSuffixVerified": appended.to_json(),
    "unrelatedScopesPreserved": true,
  }
  println(receipt.stringify())
}
