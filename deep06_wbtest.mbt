///|
test "deep06 CIF2 punctuation belongs to identifiers" {
  let source = "#\\#CIF_2.0\ndata_d[1]\n_v[2]{x} 12(3)\nsave_s{3}\n_inside[4] world\nsave_\n"
  let file = parse_string(source).unwrap()
  assert_eq(file.blocks[0].name.text, "data_d[1]")
  assert_eq(
    file.find("d[1]", "_v[2]{x}").unwrap().measurement().unwrap().uncertainty,
    Some(3.0),
  )
  assert_eq(file.blocks[0].frames[0].name.text, "save_s{3}")
  assert_true(
    file.blocks[0].frames[0].entries[0] is Pair(tag, value) &&
    tag.text == "_inside[4]" &&
    value.to_json() == Json::string("world"),
  )
  assert_eq(file.rewrite_original(), source)
}

///|
test "deep06 smallest CIF2 document ends at version header" {
  for source in ["#\\#CIF_2.0", "\uFEFF#\\#CIF_2.0", "#\\#CIF_2.0 \t"] {
    let file = parse_string(source).unwrap()
    assert_eq(file.version, Cif2)
    assert_eq(file.blocks.length(), 0)
    assert_eq(file.rewrite_original(), source)
  }
}

///|
test "deep06 BOM is only an encoding artifact at file start" {
  // Byte locations are independently counted from the UTF-8 fixture bytes.
  for
    (source, start) in [
      ("#\\#CIF_2.0\ndata_x\n_v 'first\uFEFFlast'\n", 27),
      ("#\\#CIF_2.0\ndata_x\n# embedded\uFEFF\n_v 1\n", 28),
    ] {
    assert_true(parse_string(source) is Err(_))
    let report = parse_report(source)
    assert_eq(report.diagnostics.length(), 1)
    assert_eq(report.diagnostics[0].code, "E004")
    assert_eq(report.diagnostics[0].span.start_offset, start)
    assert_eq(report.diagnostics[0].span.end_offset, start + 3)
    assert_eq(report.file.rewrite_original(), source)
    let bytes = @utf8.encode(source)
    for split in 0..<=bytes.length() {
      let stream = CifStream::new()
      ignore(stream.feed(bytes[:split].to_owned()).unwrap())
      ignore(stream.feed(bytes[split:].to_owned()).unwrap())
      assert_eq(stream.finish().unwrap().diagnostics, report.diagnostics)
    }
  }
}

///|
test "deep06 CIF2 container names and loop tags" {
  // Original synthetic fixture; the upstream LGPL fixture remains in the report.
  let source = "#\\#CIF_2.0\ndata_phase[7]\n_species copper\nsave_site{8}\n_label Cu1\nsave_\n"
  let file = parse_string(source).unwrap()
  assert_eq(file.blocks.length(), 1)
  assert_eq(
    file.find("phase[7]", "_species").unwrap().to_json(),
    Json::string("copper"),
  )
  assert_eq(file.blocks[0].frames.length(), 1)
  assert_eq(file.blocks[0].frames[0].name.text, "save_site{8}")
  assert_true(
    file.blocks[0].frames[0].entries[0] is Pair(tag, value) &&
    tag.text == "_label" &&
    value.to_json() == Json::string("Cu1"),
  )
  let looped = parse_string(
    "#\\#CIF_2.0\nDaTa_d{[x]}\nloop_\n_a[0]\n_b{1}\n1 2\n3 4\nSaVe_f[0]\n_c{2} 5\nsave_\n",
  ).unwrap()
  assert_true(
    looped.blocks[0].entries[0] is Loop(tags, values, _) &&
    tags.map(t => t.text) == ["_a[0]", "_b{1}"] &&
    values.map(v => v.to_json()) ==
    [Json::string("1"), Json::string("2"), Json::string("3"), Json::string("4")],
  )
  assert_eq(looped.blocks[0].frames[0].name.text, "SaVe_f[0]")
}

///|
test "deep06 name punctuation preserves stream tokens at every split" {
  for
    source in [
      "\uFEFF#\\#CIF_2.0\r\nDaTa_测[1]\r\n_v{2} 12(3)\r\nSaVe_帧{3}\r\n_inside[4] '😀'\r\nsave_\r\n",
      "#\\#CIF_2.0", "\uFEFF#\\#CIF_2.0",
    ] {
    let expected = parse_string(source).unwrap()
    let bytes = @utf8.encode(source)
    for version in [Auto, Cif2] {
      for split in 0..<=bytes.length() {
        let stream = CifStream::new(version~)
        let emitted = stream.feed(bytes[:split].to_owned()).unwrap() +
          stream.feed(bytes[split:].to_owned()).unwrap()
        let report = stream.finish().unwrap()
        assert_true(report.is_valid())
        assert_eq(report.file, expected)
        for i in 0..<emitted.length() {
          assert_eq(emitted[i], expected.tokens[i])
        }
      }
      let stream = CifStream::new(version~)
      let emitted : Array[Token] = []
      for byte in bytes {
        emitted.append(stream.feed(Bytes::from_array([byte])).unwrap())
      }
      assert_eq(stream.finish().unwrap().file, expected)
      for i in 0..<emitted.length() {
        assert_eq(emitted[i], expected.tokens[i])
      }
    }
  }
}

///|
test "deep06 names keep caseless identity and contextual edits" {
  let source = "#\\#CIF_2.0\ndata_É[1]\n_V{2} 12(3) # keep\n_tail [1 2]\n"
  let file = parse_string(source).unwrap()
  let value = file.find("e\u0301[1]", "_v{2}").unwrap()
  let edited = file.replace_value(value, "24(6)").unwrap()
  assert_eq(
    edited, "#\\#CIF_2.0\ndata_É[1]\n_V{2} 24(6) # keep\n_tail [1 2]\n",
  )
  assert_eq(
    parse_string(edited)
    .unwrap()
    .find("é[1]", "_V{2}")
    .unwrap()
    .measurement()
    .unwrap().uncertainty,
    Some(6.0),
  )
  for
    source in [
      "#\\#CIF_2.0\ndata_É[1]\ndata_e\u0301[1]\n", "#\\#CIF_2.0\ndata_x\n_É{1} 1\n_e\u0301{1} 2\n",
      "#\\#CIF_2.0\ndata_x\nsave_É[1]\nsave_\nsave_e\u0301[1]\nsave_\n",
    ] {
    assert_true(parse_string(source) is Err(_))
  }
}

///|
test "deep06 value bracket and version boundaries remain strict" {
  for
    source in [
      "#\\#CIF_2.0\ndata_x\n_v foo[bar]\n", "#\\#CIF_2.0\ndata_x\n_v foo{bar}\n",
      "#\\#CIF_2.0junk", "#\\#CIF_2.0 extra\n",
    ] {
    assert_true(parse_string(source) is Err(_))
  }
  assert_true(parse_string("data_x\n_v 1\n", version=Cif2) is Err(_))
  assert_true(parse_string("\uFEFFdata_x\n_v 1\n", version=Cif1) is Err(_))
  let c2 = parse_string(
    "#\\#CIF_2.0\ndata_x\n_a 'foo[bar]{}'\n_b [1 {'k':2}]\n",
  ).unwrap()
  assert_eq(c2.find("x", "_a").unwrap().to_json(), Json::string("foo[bar]{}"))
  let c1 = parse_string("data_x\n_a foo[bar]{}\n").unwrap()
  assert_eq(c1.find("x", "_a").unwrap().to_json(), Json::string("foo[bar]{}"))
}
