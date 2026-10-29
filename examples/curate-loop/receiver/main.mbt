///|
extern "js" fn read_text(path : String) -> String =
  #| path => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(process.getBuiltinModule('fs').readFileSync(path))

///|
struct Sink {
  mut result : @measure.MeasuredQuantity?
}

///|
impl @cif.UncertaintySink for Sink with fn accept(self, value, uncertainty) {
  self.result = match uncertainty {
    Some(u) =>
      @measure.MeasuredQuantity::checked_from_parts(value, u, @si.meter)
    None => None
  }
}

///|
fn measurement(
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
  let curated = args[3] == "curated"
  assert_true(curated || args[3] == "original")
  let source = read_text(args[4])
  let original = read_text(args[5])
  let expected = read_text(args[6])
  let bytes = @utf8.encode(source)
  let old = @utf8.encode(original)
  assert_eq(old.length(), if cif2 { 240 } else { 87 })
  if curated {
    assert_eq(bytes, @utf8.encode(expected))
    assert_eq(bytes.length(), if cif2 { 210 } else { 61 })
    let ranges = if cif2 {
      [(106, 107), (108, 117), (118, 126), (127, 139)]
    } else {
      [(35, 36), (37, 46), (47, 63)]
    }
    let mut old_at = 0
    let mut new_at = 0
    for (start, end) in ranges {
      let size = start - old_at
      assert_eq(bytes[new_at:new_at + size], old[old_at:start])
      old_at = end
      new_at += size
    }
    assert_eq(bytes[new_at:], old[old_at:])
  } else {
    assert_eq(bytes, old)
  }
  let file = @cif.parse_string(source).unwrap()
  let rows = if cif2 {
    assert_eq(file.blocks.length(), 2)
    assert_eq(
      file.find("curate", "_root").unwrap().to_json(),
      Json::string("keep"),
    )
    assert_eq(
      file.find("other", "_x").unwrap().to_json(),
      Json::string("untouched"),
    )
    assert_eq(
      file.blocks[1].name.span.start_offset,
      if curated {
        182
      } else {
        212
      },
    )
    let rows = file
      .find_loop_rows(
        "curate",
        ["_id", "_length_m", "_note", "_meta"],
        frame="run",
      )
      .unwrap()
    assert_eq(rows[0].map(v => v.to_json()), [
      Json::string("A"),
      Json::string("2.000(10)"),
      Json::string("?"),
      ["1"],
    ])
    let last = rows[rows.length() - 1]
    assert_eq(last.map(v => v.to_json()), [
      Json::string("C"),
      Json::string("4.000(20)"),
      Json::string("keep C"),
      [],
    ])
    measurement(rows[0][1], 2.0, 0.01)
    measurement(last[1], 4.0, 0.02)
    if !curated {
      assert_eq(rows[1].map(v => v.to_json()), [
        Json::string("B"),
        Json::string("999.0(50)"),
        Json::string("reject"),
        { "qc": "bad" },
      ])
      measurement(rows[1][1], 999.0, 5.0)
      assert_true(file.replace_values(rows[1].map(v => (v, ""))) is Err(_))
    }
    assert_true(
      file.blocks[0].frames[0].entries
      is [@cif.Loop(_, values, span), @cif.Pair(tail, value)] &&
      values.length() == (if curated { 8 } else { 12 }) &&
      span.start_offset == 50 &&
      span.end_offset == (if curated { 154 } else { 184 }) &&
      tail.span.start_offset == (if curated { 156 } else { 186 }) &&
      value.to_json() == { "k": ["1", "2"] },
    )
    rows
  } else {
    let rows = file
      .find_loop_rows("one", ["_id", "_length_m", "_note"])
      .unwrap()
    let last = rows[rows.length() - 1]
    assert_eq(last.map(v => v.to_json()), [
      Json::string("Y"),
      Json::string("1.250(5)"),
      Json::string("."),
    ])
    measurement(last[1], 1.25, 0.005)
    if !curated {
      assert_eq(rows[0][2].to_json(), Json::string("rejected\ntext"))
      measurement(rows[0][1], 8.0, 0.03)
      assert_true(file.replace_values(rows[0].map(v => (v, ""))) is Err(_))
    }
    assert_true(
      file.blocks[0].entries is [@cif.Loop(_, values, span)] &&
      values.length() == (if curated { 3 } else { 6 }) &&
      span.start_offset == 9 &&
      span.end_offset == (if curated { 50 } else { 76 }),
    )
    rows
  }
  assert_eq(
    rows.length(),
    if cif2 {
      if curated {
        2
      } else {
        3
      }
    } else if curated {
      1
    } else {
      2
    },
  )
  assert_eq(read_text(args[4]), source)
  assert_eq(read_text(args[5]), original)
  assert_eq(file.rewrite_original(), source)
  let receipt : Json = {
    "ok": true,
    "kind": args[2].to_json(),
    "mode": args[3].to_json(),
    "rows": rows.length().to_json(),
    "receivedBytes": bytes.length().to_json(),
    "publicApiOnly": true,
    "realLunar": true,
    "unitChosenByCaller": "m",
    "retainedMeasurementValues": (if cif2 { [2.0, 4.0] } else { [1.25] }).to_json(),
    "retainedUncertainties": (if cif2 { [0.01, 0.02] } else { [0.005] }).to_json(),
    "sourceReadOnly": true,
    "allOutsideRangesVerified": curated.to_json(),
  }
  println(receipt.stringify())
}
