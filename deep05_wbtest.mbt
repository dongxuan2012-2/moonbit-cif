///|
test "deep05 rounding below positive half" {
  assert_eq(format_su(0.49999999999999994, 1.0, digits=1), Ok("0(1)"))
}

///|
test "deep05 rounding below negative half" {
  assert_eq(format_su(-0.49999999999999994, 1.0, digits=1), Ok("0(1)"))
}

///|
test "deep05 edit forbids injected block" {
  let f = parse_string("data_x\n_a 1\n_b 2\n").unwrap()
  assert_true(
    f.replace_value(f.find("x", "_a").unwrap(), "3\ndata_injected\n_v 4")
    is Err(_),
  )
}

///|
test "deep05 edit forbids injected frame" {
  let f = parse_string("data_x\n_a 1\n_b 2\n").unwrap()
  assert_true(
    f.replace_value(f.find("x", "_a").unwrap(), "3\nsave_injected\n_v 4\nsave_")
    is Err(_),
  )
}

///|
test "deep05 edit does not let comments hide untouched fields" {
  let f = parse_string("data_x\n_a 1 _b 2\n").unwrap()
  assert_true(
    f.replace_value(f.find("x", "_a").unwrap(), "3 # hidden") is Err(_),
  )
}

///|
test "deep05 CIF1 right bracket start is reserved" {
  assert_true(parse_string("data_x\n_a ]word\n", version=Cif1) is Err(_))
  assert_true(
    parse_string("data_x\n_a ']word'\n_b foo]bar\n", version=Cif1) is Ok(_),
  )
}

///|
test "deep05 contextual composite edits preserve legal values" {
  let source = "#\\#CIF_2.0\r\ndata_x\r\n_a [ 1 { 'k':2 } ] # keep\r\n_b 9\r\n"
  let f = parse_string(source).unwrap()
  let list = f.find("x", "_a").unwrap()
  guard list is List(values, _) else { fail("Expected fixture list") }
  let edited = f.replace_value(values[0], "[ 'changed' ]").unwrap()
  assert_true(parse_string(edited) is Ok(_))
  assert_true(edited.has_suffix(" # keep\r\n_b 9\r\n"))
  assert_eq(f.rewrite_original(), source)
  let field = f.replace_value(list, "\n;plain\\n literal\n;").unwrap()
  assert_eq(
    parse_string(field).unwrap().find("x", "_b").unwrap().to_json(),
    Json::string("9"),
  )
  let with_comment = f
    .replace_value(list, "[ 3 # internal comment\n4 ]")
    .unwrap()
  assert_true(parse_string(with_comment) is Ok(_))
}

///|
test "deep05 CIF1 stream quote boundary preserves partial loops" {
  let source = "data_x\n_v 'a dog's life'\nloop_\n_a\n_b\n1 2 3\ndata_ok\n_z 4\n"
  let bytes = @utf8.encode(source)
  for split in 0..<=bytes.length() {
    let stream = CifStream::new(version=Cif1)
    let a = stream.feed(bytes[:split].to_owned()).unwrap()
    let b = stream.feed(bytes[split:].to_owned()).unwrap()
    let report = stream.finish().unwrap()
    assert_true(report.diagnostics.any(d => d.code == "E003"))
    assert_eq(
      report.file.find("x", "_v").unwrap().to_json(),
      Json::string("a dog's life"),
    )
    assert_eq(
      report.file.find("ok", "_z").unwrap().to_json(),
      Json::string("4"),
    )
    assert_eq(report.file.rewrite_original(), source)
    let emitted = a + b
    for i in 0..<emitted.length() {
      assert_eq(emitted[i], report.file.tokens[i])
    }
    assert_true(
      report.file.blocks[0].entries[1] is Loop(tags, vals, _) &&
      tags.length() == 2 &&
      vals.length() == 3,
    )
  }
}

///|
test "deep05 UTF8 prefix folding and literal backslash chunks" {
  let source = "#\\#CIF_2.0\r\ndata_x\r\n_a\r\n;πφχ\\\\\r\nπφχstart\\\r\nπφχend\r\n;\r\n_b '\\n\\?\\.'\r\n"
  let bytes = @utf8.encode(source)
  for split in 0..<=bytes.length() {
    let stream = CifStream::new(version=Cif2)
    ignore(stream.feed(bytes[:split].to_owned()).unwrap())
    ignore(stream.feed(bytes[split:].to_owned()).unwrap())
    let report = stream.finish().unwrap()
    assert_true(report.is_valid())
    assert_eq(
      report.file.find("x", "_a").unwrap().to_json(),
      Json::string("startend"),
    )
    assert_eq(
      report.file.find("x", "_b").unwrap().to_json(),
      Json::string("\\n\\?\\."),
    )
    assert_eq(report.file.find("x", "_b").unwrap().span().start_line, 8)
    assert_eq(report.file.find("x", "_b").unwrap().span().start_col, 4)
  }
  let c1 = parse_string("data_x\n_a\n;prefix>\\\nprefix>literal\\n\n;\n").unwrap()
  assert_eq(
    c1.find("x", "_a").unwrap().to_json(),
    Json::string("prefix>\\\nprefix>literal\\n"),
  )
}

///|
priv struct Deep05Sink {
  mut called : Bool
  mut value : Double
  mut u : Double?
}

///|
impl UncertaintySink for Deep05Sink with fn accept(self, value, u) {
  self.called = true
  self.value = value
  self.u = u
}

///|
test "deep05 SU extremes and absent uncertainty preserve sink contract" {
  let sink : Deep05Sink = { called: false, value: 0.0, u: Some(99.0), }
  parse_su("12").unwrap().send_to(sink).unwrap()
  assert_true(sink.called)
  assert_eq(sink.value, 12.0)
  assert_eq(sink.u, None)
  parse_su("0.000(0)").unwrap().send_to(sink).unwrap()
  assert_eq(sink.u, Some(0.0))
  for text in ["?", ".", "1e308(9)", "1e-324(1)", "4.9406564584124654e-324(1)"] {
    sink.called = false
    let measurement = parse_su(text).unwrap()
    assert_eq(measurement.to_cif_string(), text)
    assert_true(measurement.send_to(sink) is Err(_))
    assert_false(sink.called)
  }
}
