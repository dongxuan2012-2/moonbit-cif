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
  let added = args[3] == "added"
  assert_true(cif2 || args[2] == "cif1")
  assert_true(added || args[3] == "original")
  let source = read_text(args[4])
  let original = read_text(args[5])
  let inserted = read_text(args[6])
  let expected = read_text(args[7])
  let bytes = @utf8.encode(source)
  let old = @utf8.encode(original)
  let addition = @utf8.encode(inserted)
  let at = if cif2 { 89 } else { 26 }
  assert_eq(old.length(), if cif2 { 166 } else { 50 })
  assert_eq(addition.length(), if cif2 { 29 } else { 37 })
  if added {
    assert_eq(bytes, @utf8.encode(expected))
    assert_eq(bytes.length(), if cif2 { 195 } else { 87 })
    assert_eq(bytes[:at], old[:at])
    assert_eq(bytes[at:at + addition.length()].to_owned(), addition)
    assert_eq(bytes[at + addition.length():], old[at:])
  } else {
    assert_eq(bytes, old)
  }
  let file = @cif.parse_string(source).unwrap()
  let notes = if cif2 {
    assert_eq(file.blocks.length(), 2)
    assert_eq(
      file.find("meta", "_processing_note").unwrap().to_json(),
      Json::string("keep root"),
    )
    assert_eq(file.find("other", "_x").unwrap().to_json(), Json::string("keep"))
    assert_eq(
      file.blocks[1].name.span.start_offset,
      if added {
        174
      } else {
        145
      },
    )
    let rows = file
      .find_loop_rows("meta", ["_id", "_length_m"], frame="run")
      .unwrap()
    assert_eq(rows.map(row => row.map(v => v.to_json())), [
      [Json::string("A"), Json::string("1.000(10)")],
      [Json::string("B"), Json::string("3.500(20)")],
    ])
    check_measure(rows[0][1], 1.0, 0.01)
    check_measure(rows[1][1], 3.5, 0.02)
    if !added {
      assert_true(
        file.replace_value(rows[0][1], "1.000(10)\n_processing_note 'injected'")
        is Err(_),
      )
    }
    let entries = file.blocks[0].frames[0].entries
    if added {
      assert_true(
        entries is [@cif.Pair(tag, value), @cif.Loop(_, _, span)] &&
        tag.text == "_processing_note" &&
        tag.span.start_offset == 89 &&
        tag.span.end_offset == 105 &&
        value.span().start_offset == 106 &&
        value.span().end_offset == 117 &&
        span.start_offset == 118 &&
        span.end_offset == 165,
      )
    } else {
      assert_true(
        entries is [@cif.Loop(_, _, span)] &&
        span.start_offset == 89 &&
        span.end_offset == 136,
      )
    }
    file.find_values("meta", "_processing_note", frame="run")
  } else {
    let value = file.find("one", "_length_m").unwrap()
    check_measure(value, 2.5, 0.005)
    if !added {
      assert_true(
        file.replace_value(value, "2.500(5)\n_processing_note 'injected'")
        is Err(_),
      )
    }
    if added {
      assert_true(
        file.blocks[0].entries is [@cif.Pair(tag, note), @cif.Pair(old_tag, _)] &&
        tag.span.start_offset == 27 &&
        tag.span.end_offset == 43 &&
        note.span().start_offset == 44 &&
        note.span().end_offset == 62 &&
        old_tag.span.start_offset == 63,
      )
    }
    file.find_values("one", "_processing_note")
  }
  assert_eq(notes.length(), if added { 1 } else { 0 })
  if added {
    assert_eq(
      notes[0].to_json(),
      (if cif2 { "已核对" } else { "reviewed locally" }).to_json(),
    )
    assert_true(notes[0].measurement() is Err(_))
  }
  assert_eq(read_text(args[4]), source)
  assert_eq(read_text(args[5]), original)
  assert_eq(file.rewrite_original(), source)
  let receipt : Json = {
    "ok": true,
    "kind": args[2].to_json(),
    "mode": args[3].to_json(),
    "receivedBytes": bytes.length().to_json(),
    "newNoteReceived": added.to_json(),
    "publicApiOnly": true,
    "realLunar": true,
    "unitChosenByCaller": "m",
    "values": (if cif2 { [1.0, 3.5] } else { [2.5] }).to_json(),
    "uncertainties": (if cif2 { [0.01, 0.02] } else { [0.005] }).to_json(),
    "oldBytesAndScopesPreserved": true,
    "sourceReadOnly": true,
  }
  println(receipt.stringify())
}
