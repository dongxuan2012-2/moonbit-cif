///|
test "deep08 comment cannot start a separator after quoted values" {
  for
    source in [
      "#\\#CIF_2.0\ndata_x\n_v 'a'#comment\n_b 2\n", "#\\#CIF_2.0\ndata_x\n_v '''a'''#comment\n_b 2\n",
    ] {
    assert_true(parse_string(source) is Err(_))
  }
}

///|
test "deep08 comments cannot hide missing composite separators" {
  for
    value in [
      "[1]", "{'k':1}", "['a'#comment\n'b']", "{'k':'v'#comment\n'x':2}",
    ] {
    let source = "#\\#CIF_2.0\ndata_x\n_v " + value + "#comment\n_b 2\n"
    assert_true(parse_string(source) is Err(_))
  }
}

///|
test "deep08 text closing delimiter needs separation before comments" {
  for header in ["", "#\\#CIF_2.0\n"] {
    let source = header + "data_x\n_v\n;text\n;#comment\n_b 2\n"
    assert_true(parse_string(source) is Err(_))
  }
}

///|
test "deep08 comment whitespace exceptions preserve legal input" {
  for
    body in [
      "'a' #comment\n_b 2\n", "[ #comment\n1] #comment\n_b 2\n", "[#comment\n1]\n",
      "{#comment\n'k':1}\n", "{'k':#comment\n1}\n", "{'k':'v' #comment\n'x':2}\n",
      "['a' #comment\n'b']\n", "\n;text\n; #comment\n_b 2\n",
    ] {
    let source = "#\\#CIF_2.0\ndata_x\n_v " + body
    assert_eq(parse_string(source).unwrap().rewrite_original(), source)
  }
  // The CIF2 file grammar has a final optional comment, without a required EOL.
  for body in ["'a'", "'''a'''", "[1]", "{'k':1}", "\n;text\n;"] {
    let source = "#\\#CIF_2.0\ndata_x\n_v " + body + "#EOF"
    assert_eq(parse_string(source).unwrap().rewrite_original(), source)
  }
  for header in ["", "#\\#CIF_2.0\n"] {
    let source = header + "data_x\n_hash#name a#literal\n_v '#quoted'\n"
    let file = parse_string(source).unwrap()
    assert_eq(
      file.find("x", "_hash#name").unwrap().to_json(),
      Json::string("a#literal"),
    )
    assert_eq(file.find("x", "_v").unwrap().to_json(), Json::string("#quoted"))
    assert_true(
      parse_string(header + "data_x\n_v\n;text\n; #comment\n_b 2\n") is Ok(_),
    )
  }
}

///|
test "deep08 comment diagnosis and stable chunks preserve recovery" {
  let source = "#\\#CIF_2.0\r\ndata_测\r\n_v '😀'#comment\r\n_b 2\r\n"
  let expected = parse_report(source)
  assert_true(
    expected.diagnostics.any(d => {
      d.code == "E004" && d.message == "Comment requires preceding whitespace"
    }),
  )
  assert_eq(
    expected.file.find("测", "_b").unwrap().to_json(),
    Json::string("2"),
  )
  let bytes = @utf8.encode(source)
  for split in 0..<=bytes.length() {
    let stream = CifStream::new()
    let emitted = stream.feed(bytes[:split].to_owned()).unwrap() +
      stream.feed(bytes[split:].to_owned()).unwrap()
    let report = stream.finish().unwrap()
    assert_eq(report.file, expected.file)
    assert_eq(report.diagnostics, expected.diagnostics)
    for i in 0..<emitted.length() {
      assert_eq(emitted[i], expected.file.tokens[i])
    }
    assert_eq(report.file.rewrite_original(), source)
  }
}

///|
test "deep08 exact UTF8 byte budgets and terminal stream states" {
  let source = "#\\#CIF_2.0\ndata_测\n_v '😀'\n"
  let bytes = @utf8.encode(source)
  assert_eq(bytes.length(), 30)
  for budget in [30, 31] {
    for split in 0..<=bytes.length() {
      let stream = CifStream::new(max_bytes=budget)
      ignore(stream.feed(bytes[:split].to_owned()).unwrap())
      ignore(stream.feed(bytes[split:].to_owned()).unwrap())
      ignore(stream.feed(b"").unwrap())
      let report = stream.finish().unwrap()
      assert_true(report.is_valid())
      assert_eq(report.file.rewrite_original(), source)
      assert_true(stream.feed(b"") is Err(_))
      assert_true(stream.finish() is Err(_))
    }
  }
  for split in [0, 29] {
    let stream = CifStream::new(max_bytes=29)
    ignore(stream.feed(bytes[:split].to_owned()).unwrap())
    assert_true(
      stream.feed(bytes[split:].to_owned()) is Err(e) && e.has_prefix("E005:"),
    )
    assert_true(stream.feed(b"") is Err(_))
    assert_true(stream.finish() is Err(_))
  }
  let empty = CifStream::new(max_bytes=0)
  assert_eq(empty.feed(b"").unwrap().length(), 0)
  assert_true(empty.finish().unwrap().is_valid())
  let zero = CifStream::new(max_bytes=0)
  assert_true(zero.feed(b"x") is Err(e) && e.has_prefix("E005:"))
  assert_true(zero.finish() is Err(_))
  for invalid in [b"\xff", b"\xf4\x90\x80\x80"] {
    let stream = CifStream::new()
    assert_true(stream.feed(invalid) is Err(e) && e.has_prefix("E004:"))
    assert_true(stream.finish() is Err(_))
  }
  let incomplete = CifStream::new()
  ignore(incomplete.feed(b"\xe6").unwrap())
  assert_true(incomplete.finish() is Err(e) && e.has_prefix("E004:"))
  assert_true(incomplete.feed(b"\xb5\x8b") is Err(_))
}

///|
test "deep08 value height budget includes scalar leaves" {
  for height in [127, 128, 129] {
    let mut mixed = "0"
    for i in 1..<height {
      mixed = if i % 2 == 0 { "[" + mixed + "]" } else { "{'k':" + mixed + "}" }
    }
    for
      value in [
        "[".repeat(height - 1) + "0" + "]".repeat(height - 1),
        "[".repeat(height) + "]".repeat(height),
        "{'k':".repeat(height - 1) + "{}" + "}".repeat(height - 1),
        mixed,
      ] {
      let source = "#\\#CIF_2.0\ndata_x\n_v " + value + "\n_next 2\n"
      let report = parse_report(source)
      assert_eq(report.is_valid(), height <= 128)
      assert_eq(report.diagnostics.any(d => d.code == "E005"), height > 128)
      assert_eq(report.file.rewrite_original(), source)
      assert_eq(
        report.file.find("x", "_next").unwrap().to_json(),
        Json::string("2"),
      )
    }
  }
}
