///|
test "deep11 row projection follows requested columns and source rows" {
  let file = parse_string(
    "data_x\nloop_\n_length_m\n_id\n_flag\n2 A ?\n3 B .\n",
  ).unwrap()
  let rows = file.find_loop_rows("X", ["_ID", "_LENGTH_M"]).unwrap()
  assert_eq(rows.map(row => row.map(v => v.to_json())), [
    [Json::string("A"), Json::string("2")],
    [Json::string("B"), Json::string("3")],
  ])
  assert_eq(
    file.find_loop_rows("x", ["_flag"]).unwrap().map(row => row[0].to_json()),
    [Json::string("?"), Json::string(".")],
  )
  assert_eq(file.blocks[0].find_loop_rows(["_id"]).unwrap().length(), 2)
}

///|
test "deep11 row projection canonical scope and tags" {
  let file = parse_string(
    "#\\#CIF_2.0\ndata_É\nloop_\n_id\n_e\u0301\nroot 1\nsave_Å\nloop_\n_É\n_ID\n2 frame\nsave_\ndata_other\nloop_\n_id\n_é\nother 3\n",
  ).unwrap()
  assert_eq(
    file.find_loop_rows("e\u0301", ["_ID", "_É"]).unwrap()[0].map(v => {
      v.to_json()
    }),
    [Json::string("root"), Json::string("1")],
  )
  assert_eq(
    file.find_loop_rows("É", ["_id", "_é"], frame="A\u030A").unwrap()[0].map(v => {
      v.to_json()
    }),
    [Json::string("frame"), Json::string("2")],
  )
  assert_eq(
    file.find_loop_rows("other", ["_id", "_É"]).unwrap()[0].map(v => {
      v.to_json()
    }),
    [Json::string("other"), Json::string("3")],
  )
  assert_true(file.find_loop_rows("É", ["_id"], frame="missing") is Err(_))
  assert_true(file.find_loop_rows("missing", ["_id"]) is Err(_))
  assert_eq(file.find_values("É", "_id", frame="missing").length(), 0)
}

///|
test "deep11 row projection rejects incomplete and ambiguous selected loops" {
  for
    source in [
      "data_x\nloop_\n_a\n_b\n1 2 3\n", "data_x\nloop_\n_a\n_A\n1 2\n", "data_x\nloop_\n_a\n_b\n1 2\nloop_\n_a\n_b\n3 4\n",
      "data_x\nloop_\n_a\n", "data_x\nloop_\n1 2\n",
    ] {
    let report = parse_report(source)
    assert_true(!report.is_valid())
    assert_true(report.file.find_loop_rows("x", ["_a"]) is Err(_))
    assert_eq(report.file.rewrite_original(), source)
  }
  let partial = parse_report("data_x\nloop_\n_a\n_b\n1 2 3\n")
  assert_eq(partial.file.find_values("x", "_a").map(v => v.to_json()), [
    Json::string("1"),
    Json::string("3"),
  ])
}

///|
test "deep11 row projection never joins columns or broadcasts pairs" {
  let separate = parse_string("data_x\nloop_\n_id\nA B\nloop_\n_v\n2 3\n").unwrap()
  assert_eq(
    separate.find_values("x", "_id").length(),
    separate.find_values("x", "_v").length(),
  )
  assert_true(separate.find_loop_rows("x", ["_id", "_v"]) is Err(_))
  let pairs = parse_string("data_x\n_id A\n_v 2\n").unwrap()
  assert_true(pairs.find_loop_rows("x", ["_id", "_v"]) is Err(_))
  let file = parse_string("data_x\nloop_\n_a\n_b\n1 2\n").unwrap()
  assert_true(file.find_loop_rows("x", []) is Err(_))
  assert_true(file.find_loop_rows("x", ["_a", "_A"]) is Err(_))
  assert_true(file.find_loop_rows("x", ["_a", "_missing"]) is Err(_))
}

///|
test "deep11 projected compound cells remain original batch targets" {
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_cell\n_id\n[1 2] A\n{'k':3} B\n"
  let file = parse_string(source).unwrap()
  let rows = file.find_loop_rows("x", ["_id", "_cell"]).unwrap()
  assert_true(rows[0][1] is List(_, _))
  assert_true(rows[1][1] is Table(_, _))
  let edited = file
    .replace_values([(rows[1][1], "{'k':8}"), (rows[0][1], "[9]")])
    .unwrap()
  assert_eq(
    edited, "#\\#CIF_2.0\ndata_x\nloop_\n_cell\n_id\n[9] A\n{'k':8} B\n",
  )
  assert_eq(file.rewrite_original(), source)
}

///|
test "deep11 ID selective update preserves unselected UTF8 bytes and atomic failure" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\nloop_\r\n_length_m\r\n_id\r\n1.5423(12) A # keep\r\n2.10(3) B\r\n? C\r\n3.33(4) D\r\n"
  let file = parse_string(source).unwrap()
  let rows = file.find_loop_rows("测", ["_ID", "_LENGTH_M"]).unwrap()
  let b = rows[1][1]
  let d = rows[3][1]
  assert_true(file.replace_values([(b, "4.200(60)"), (d, "'broken")]) is Err(_))
  assert_eq(file.rewrite_original(), source)
  let edited = file
    .replace_values([(d, "6.660(80)"), (b, "4.200(60)")])
    .unwrap()
  assert_eq(
    edited, "\uFEFF#\\#CIF_2.0\r\ndata_测\r\nloop_\r\n_length_m\r\n_id\r\n1.5423(12) A # keep\r\n4.200(60) B\r\n? C\r\n6.660(80) D\r\n",
  )
}
