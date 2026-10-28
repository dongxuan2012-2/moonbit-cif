///|
extern "js" fn read_text(path : String) -> String =
  #| path => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(process.getBuiltinModule('fs').readFileSync(path))

///|
struct Sink {
  mut result : @measure.MeasuredQuantity?
}

///|
impl @cif.UncertaintySink for Sink with fn accept(self, value, uncertainty) {
  // The recipient explicitly declares metres, with no dictionary/unit inference.
  self.result = match uncertainty {
    Some(u) =>
      @measure.MeasuredQuantity::checked_from_parts(value, u, @si.meter)
    None => None
  }
}

///|
fn main raise {
  let args = @env.args()
  let source = read_text(args[2])
  let original = read_text(args[3])
  let inserted = read_text(args[4])
  let is_original = args[5] == "original"
  let bytes = @utf8.encode(source)
  let old = @utf8.encode(original)
  assert_eq(old.length(), 96)
  assert_eq(@utf8.encode(inserted).length(), 16)
  if is_original {
    assert_eq(bytes, old)
  } else {
    assert_eq(bytes.length(), 112)
    assert_eq(bytes[0:82], old[0:82])
    assert_eq(bytes[82:98].to_owned(), @utf8.encode(inserted))
    assert_eq(bytes[98:112], old[82:96])
  }
  let file = @cif.parse_string(source).unwrap()
  let rows = file
    .find_loop_rows("lab", ["_sample_id", "_length_m", "_note"])
    .unwrap()
  assert_eq(rows.length(), if is_original { 1 } else { 2 })
  assert_eq(rows[0].map(v => v.to_json()), [
    Json::string("A"),
    Json::string("1.230(4)"),
    Json::string("?"),
  ])
  assert_true(
    rows[0][2] is @cif.Scalar(t) && t.kind == @cif.Word && t.raw == "?",
  )
  let sink : Sink = { result: None, }
  rows[0][1].measurement().unwrap().send_to(sink).unwrap()
  assert_eq(sink.result.unwrap().value(), 1.23)
  assert_eq(sink.result.unwrap().uncertainty(), 0.004)
  if is_original {
    assert_true(
      file.replace_value(rows[0][1], "1.230(4)\nB 2.500(3) .") is Err(_),
    )
    assert_eq(file.rewrite_original(), original)
  } else {
    assert_eq(rows[1].map(v => v.to_json()), [
      Json::string("B"),
      Json::string("2.500(3)"),
      Json::string("."),
    ])
    assert_true(
      rows[1][2] is @cif.Scalar(t) && t.kind == @cif.Word && t.raw == ".",
    )
    rows[1][1].measurement().unwrap().send_to(sink).unwrap()
    assert_eq(sink.result.unwrap().value(), 2.5)
    assert_eq(sink.result.unwrap().uncertainty(), 0.003)
    assert_true(
      file.blocks[0].entries
      is [@cif.Loop(tags, values, span), @cif.Pair(tag, value)] &&
      tags.length() == 3 &&
      values.length() == 6 &&
      span.start_offset == 25 &&
      span.end_offset == 96 &&
      tag.text == "_tail" &&
      tag.span.start_offset == 98 &&
      value.to_json() == Json::string("keep"),
    )
  }
  assert_eq(read_text(args[2]), source)
  let receipt : Json = {
    "ok": true,
    "receiver": "public API in an external MoonBit module with real Lunar",
    "mode": (if is_original { "original" } else { "appended" }).to_json(),
    "receivedBytes": bytes.length().to_json(),
    "rows": rows.length().to_json(),
    "value": sink.result.unwrap().value().to_json(),
    "uncertainty": sink.result.unwrap().uncertainty().to_json(),
    "unitChosenByCaller": "m",
    "sourceReadOnly": true,
    "rawByteRelationVerified": true,
  }
  println(receipt.stringify())
}
