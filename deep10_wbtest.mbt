///|
test "deep10 query unifies pairs and columns without changing scalar find" {
  for
    loop_text in [
      "_id\n_LENGTH_M\nA 2.0(3)\nB ?\nC 4.200\n", "_LENGTH_M\n_id\n2.0(3) A\n? B\n4.200 C\n",
    ] {
    let file = parse_string("data_x\n_scalar 1.0(2)\nloop_\n" + loop_text).unwrap()
    assert_eq(file.find_values("X", "_SCALAR").map(v => v.to_json()), [
      Json::string("1.0(2)"),
    ])
    let values = file.find_values("x", "_length_m")
    assert_eq(values.map(v => v.to_json()), [
      Json::string("2.0(3)"),
      Json::string("?"),
      Json::string("4.200"),
    ])
    assert_eq(values[0].measurement().unwrap().uncertainty, Some(0.3))
    assert_true(values[1].measurement().unwrap().is_unknown)
    assert_eq(values[2].measurement().unwrap().uncertainty_digits, None)
    assert_true(file.find("x", "_length_m") is None)
    assert_true(file.find("x", "_scalar") is Some(_))
    assert_eq(file.find_values("x", "_absent").length(), 0)
  }
}

///|
test "deep10 query canonical names and explicit frame scope" {
  let file = parse_string(
    "#\\#CIF_2.0\ndata_É[1]\n_STRASSE 1\n_shared root\nsave_Å{1}\n_e\u0301 2\n_shared frame\nsave_\ndata_other\n_shared other\n",
  ).unwrap()
  assert_eq(file.find_values("e\u0301[1]", "_Straße").map(v => v.to_json()), [
    Json::string("1"),
  ])
  assert_eq(
    file.find_values("é[1]", "_É", frame="A\u030A{1}").map(v => v.to_json()),
    [Json::string("2")],
  )
  assert_eq(file.find_values("É[1]", "_shared").map(v => v.to_json()), [
    Json::string("root"),
  ])
  assert_eq(
    file.find_values("É[1]", "_shared", frame="å{1}").map(v => v.to_json()),
    [Json::string("frame")],
  )
  assert_eq(file.find_values("other", "_shared").map(v => v.to_json()), [
    Json::string("other"),
  ])
  assert_eq(file.find_values("É[1]", "_shared", frame="missing").length(), 0)
  assert_eq(file.find_values("missing", "_shared").length(), 0)
  assert_eq(file.blocks[0].find_values("_shared").map(v => v.to_json()), [
    Json::string("root"),
  ])
  assert_eq(
    file.blocks[0].frames[0].find_values("_shared").map(v => v.to_json()),
    [Json::string("frame")],
  )
}

///|
test "deep10 query preserves compound cells and quoted sentinels" {
  let file = parse_string(
    "#\\#CIF_2.0\ndata_x\nloop_\n_cell\n_id\n[1 2] A\n{'k':3} B\n'?' C\n. D\n",
  ).unwrap()
  let values = file.find_values("x", "_CELL")
  assert_eq(values.length(), 4)
  assert_true(values[0] is List(_, _))
  assert_true(values[1] is Table(_, _))
  assert_true(values[2].measurement() is Err(_))
  assert_true(values[3].measurement().unwrap().is_inapplicable)
  assert_eq(file.find_values("x", "_id").map(v => v.to_json()), [
    Json::string("A"),
    Json::string("B"),
    Json::string("C"),
    Json::string("D"),
  ])
  assert_eq(file.find_values("x", "k").length(), 0)
}

///|
test "deep10 partial query keeps present cells in source order" {
  let report = parse_report("data_x\nloop_\n_a\n_b\n1 2 3\n_a 4\n")
  assert_true(!report.is_valid())
  assert_eq(report.file.find_values("x", "_a").map(v => v.to_json()), [
    Json::string("1"),
    Json::string("3"),
    Json::string("4"),
  ])
  assert_eq(report.file.find_values("x", "_b").map(v => v.to_json()), [
    Json::string("2"),
  ])
  let duplicate = parse_report("data_x\nloop_\n_a\n_A\n1 2 3 4\n")
  assert_true(!duplicate.is_valid())
  assert_eq(duplicate.file.find_values("x", "_a").map(v => v.to_json()), [
    Json::string("1"),
    Json::string("2"),
    Json::string("3"),
    Json::string("4"),
  ])
  let headerless = parse_report("data_x\nloop_\n1 2\n_end 3\n")
  assert_true(!headerless.is_valid())
  assert_eq(headerless.file.find_values("x", "_a").length(), 0)
  assert_eq(headerless.file.find_values("x", "_end").map(v => v.to_json()), [
    Json::string("3"),
  ])
}

///|
test "deep10 queried original values feed atomic UTF8 batch edits" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\nloop_\r\n_id\r\n_length_m\r\nA 1.5423(12) # retained\r\nB 2.10(3)\r\n_note '😀'\r\n"
  let file = parse_string(source).unwrap()
  let values = file.find_values("测", "_LENGTH_M")
  assert_eq(values.length(), 2)
  let edited = file
    .replace_values([(values[1], "4.200(60)"), (values[0], "3.0846(24)")])
    .unwrap()
  assert_eq(
    edited, "\uFEFF#\\#CIF_2.0\r\ndata_测\r\nloop_\r\n_id\r\n_length_m\r\nA 3.0846(24) # retained\r\nB 4.200(60)\r\n_note '😀'\r\n",
  )
  assert_eq(file.rewrite_original(), source)
  assert_true(
    file.replace_values([(values[0], "3"), (values[1], "4 # hides source")])
    is Err(_),
  )
}
