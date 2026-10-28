///|
test "CIF1 and CIF2 reference semantic values, literal backslash" {
  let f = parse_string(
    "#\\#CIF_2.0\ndata_lab\n_length 1.5423(12)\n_note \"literal\\n\"\n_values [ 1 ? . [ 2 3] {\"key\":4}]\n_triple \"\"\"first\nsecond\"\"\"\nloop_\n_atom\n_x\nC 0.25\nO 0.5\n",
  ).unwrap()
  assert_eq(
    f.find("lab", "_note").unwrap().to_json(),
    Json::string("literal\\n"),
  )
  assert_eq(
    f.find("lab", "_triple").unwrap().to_json(),
    Json::string("first\nsecond"),
  )
  assert_eq(
    f.find("lab", "_length").unwrap().measurement().unwrap().uncertainty,
    Some(0.0012),
  )
  let c1 = parse_string(
    "data_x\n_title 'don't stop'\n_note\n;hello\nworld\n;\n",
  ).unwrap()
  assert_eq(
    c1.find("x", "_title").unwrap().to_json(),
    Json::string("don't stop"),
  )
  assert_eq(
    c1.find("x", "_note").unwrap().to_json(),
    Json::string("hello\nworld"),
  )
}

///|
test "source preserving rewrite and quoted missing-value distinction" {
  let s = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_x 1.5423(12) # 😀\r\n_y '?'\r\n"
  let f = parse_string(s).unwrap()
  assert_eq(f.rewrite_original(), s)
  assert_true(f.find("测", "_y").unwrap().measurement() is Err(_))
  let x = f.find("测", "_x").unwrap()
  assert_eq(
    f.replace_value(x, "2.000(10)").unwrap(),
    s.replace_all(old="1.5423(12)", new="2.000(10)"),
  )
  assert_true(f.replace_value(x, "1\n_z 2") is Err(_))
}

///|
test "byte spans, scalar columns, CRLF, tabs and invalid UTF8" {
  let s = "#\\#CIF_2.0\r\ndata_x\r\n_测\t'😀'\r\n_a 'bad\n_b 1\n"
  let r = parse_report(s)
  let token = r.file.tokens.filter(t => t.text == "😀")[0]
  assert_eq(token.span.start_line, 3)
  assert_eq(token.span.start_col, 4)
  assert_eq(token.span.end_col, 7)
  assert_eq(token.span.end_offset - token.span.start_offset, 6)
  assert_true(
    r.diagnostics.any(d => {
      d.code == "E001" && d.span.start_line == 4 && d.span.start_col == 4
    }),
  )
  let stream = CifStream::new()
  assert_true(stream.feed(b"\xff") is Err(_))
}

///|
test "all byte split points preserve tree and raw lexemes" {
  let s = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_a [ '😀' \"\"\"ab\r\ncd\"\"\" ]\r\n_b\r\n;field\r\n;\r\n"
  let expected = parse_string(s).unwrap()
  let bytes = @utf8.encode(s)
  for split in 0..<=bytes.length() {
    let stream = CifStream::new()
    let first = stream.feed(bytes[:split].to_owned()).unwrap()
    let second = stream.feed(bytes[split:].to_owned()).unwrap()
    let report = stream.finish().unwrap()
    assert_true(report.is_valid())
    assert_eq(report.file, expected)
    let emitted = first + second
    for i in 0..<emitted.length() {
      assert_eq(emitted[i], expected.tokens[i])
    }
  }
}

///|
test "stream bytewise progress, finalization and resource budget" {
  let bytes = b"data_x\n_a 12(3)\n"
  let stream = CifStream::new()
  let emitted : Array[Token] = []
  for b in bytes {
    emitted.append(stream.feed(Bytes::from_array([b])).unwrap())
  }
  assert_true(emitted.length() > 0)
  assert_true(stream.finish().unwrap().is_valid())
  assert_true(stream.feed(b"x") is Err(_))
  assert_true(stream.finish() is Err(_))
  let bounded = CifStream::new(max_bytes=2)
  assert_true(bounded.feed(b"abc") is Err(_))
  let partial = CifStream::new()
  ignore(partial.feed(b"\xe6").unwrap())
  assert_true(partial.finish() is Err(_))
}

///|
test "non destructive loop recovery retains rows and next block" {
  let source = "data_bad\nloop_\n_a\n_b\n1 2 3\ndata_ok\n_c 4\n"
  let r = parse_report(source)
  assert_true(r.diagnostics.any(d => d.code == "E003"))
  assert_eq(r.file.blocks.length(), 2)
  assert_eq(r.file.find("ok", "_c").unwrap().to_json(), Json::string("4"))
  assert_eq(r.file.rewrite_original(), source)
  assert_true(
    r.file.blocks[0].entries[0] is Loop(tags, vals, _) &&
    tags.length() == 2 &&
    vals.length() == 3,
  )
  assert_true(parse_string(source) is Err(_))
}

///|
test "canonical caseless scope uniqueness and frames" {
  let r = parse_report(
    "#\\#CIF_2.0\ndata_x\n_é 1\n_E\u0301 2\n_STRASSE 1\n_straße 2\n",
  )
  assert_eq(
    r.diagnostics
    .filter(d => d.message == "Duplicate name in this scope")
    .length(),
    2,
  )
  let f = parse_string("data_x\nsave_a\n_tag 1\nsave_\n_tag 2\n").unwrap()
  assert_eq(f.blocks[0].frames.length(), 1)
  assert_true(parse_string("data_x\nsave_a\n_tag 1\n") is Err(_))
}

///|
test "text prefix and line folding are distinct from string escapes" {
  let a = parse_string(
    "#\\#CIF_2.0\ndata_x\n_v\n;CIF>\\\nCIF>data_example\nCIF>;inside\n;\n",
  ).unwrap()
  assert_eq(
    a.find("x", "_v").unwrap().to_json(),
    Json::string("data_example\n;inside"),
  )
  let b = parse_string("#\\#CIF_2.0\ndata_x\n_v\n;\\\nfirst\\  \nsecond\n;\n").unwrap()
  assert_eq(b.find("x", "_v").unwrap().to_json(), Json::string("firstsecond"))
}

///|
test "numeric grammar, unknowns, huge exponents and no float syntax leakage" {
  assert_eq(parse_su("12(3)").unwrap().uncertainty, Some(3.0))
  assert_eq(parse_su("3.456e+20(7)").unwrap().uncertainty, Some(7.0e17))
  assert_eq(parse_su("-0.001(02)").unwrap().to_cif_string(), "-0.001(02)")
  assert_eq(parse_su("1e9999(2)").unwrap().value, None)
  assert_eq(parse_su("1e-9999(2)").unwrap().value, None)
  assert_true(parse_su("?").unwrap().is_unknown)
  assert_true(parse_su(".").unwrap().is_inapplicable)
  for bad in ["NaN", "inf", "0x12", "1.2(3)e4", "1(2.0)", "1e+", "1 "] {
    assert_true(parse_su(bad) is Err(_))
  }
}

///|
test "computed decimal formatting, carry and error domain" {
  assert_eq(format_su(1.5423, 0.0012).unwrap(), "1.5423(12)")
  assert_eq(format_su(-1.25, 0.1, digits=1).unwrap(), "-1.3(1)")
  assert_eq(format_su(12000.0, 1200.0).unwrap(), "120e2(12)")
  assert_eq(
    parse_su(format_su(12000.0, 1200.0).unwrap()).unwrap().uncertainty,
    Some(1200.0),
  )
  assert_true(format_su(1.0, -1.0) is Err(_))
  assert_true(format_su(1.0, 0.1, digits=0) is Err(_))
}

///|
test "invalid structures encoding profile and diagnostics" {
  for
    source in [
      "data_x\n_a [ 1 ]\n", "data_x\nloop_\n_a\n", "data_x\n_a 1\n_A 2\n", "data_x\n_a\n;missing",
      "data_x\n_a $ref\n", "global_\n_a 1\n",
    ] {
    assert_true(parse_string(source) is Err(_))
  }
  assert_true(
    parse_report("data_x\n_a\n;missing").diagnostics.any(d => d.code == "E002"),
  )
  assert_true(parse_string("data_x\n_a 1\n", version=Cif2) is Err(_))
  assert_true(parse_string("#\\#CIF_2.0\ndata_x\n_a { 'x' : 1 }\n") is Err(_))
  assert_true(parse_string("#\\#CIF_2.0\ndata_x\n_a [ 1 2\n_b 3\n") is Err(_))
}

///|
test "COMCIFS text protocol boundary regressions" {
  let s = "#\\#CIF_2.0\ndata_x\n_a\n;\\\nfinal\\\n;\n_b\n;>>\\\n;\n_c [. ? 1]\n"
  let f = parse_string(s).unwrap()
  assert_eq(f.find("x", "_a").unwrap().to_json(), Json::string("final\\"))
  assert_eq(f.find("x", "_b").unwrap().to_json(), Json::string(""))
  assert_true(f.find("x", "_c").unwrap() is List(v, _) && v.length() == 3)
  let other = parse_string("data_y\n_v 9999\n")
    .unwrap()
    .find("y", "_v")
    .unwrap()
  assert_true(f.replace_value(other, "1") is Err(_))
}
