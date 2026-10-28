///|
test "feature09 batch uses original UTF8 spans in arbitrary order" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_a 1 # keep\r\nloop_\r\n_id\r\n_n\r\nA 2\r\nB 3\r\n_note '😀'\r\n"
  let file = parse_string(source).unwrap()
  let cells = match file.blocks[0].entries[1] {
    Loop(_, values, _) => values
    _ => []
  }
  let a = file.find("测", "_a").unwrap()
  let edits = [(cells[3], "3333"), (a, "10.00(2)"), (cells[1], "22")]
  let expected = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_a 10.00(2) # keep\r\nloop_\r\n_id\r\n_n\r\nA 22\r\nB 3333\r\n_note '😀'\r\n"
  assert_eq(file.replace_values(edits).unwrap(), expected)
  assert_eq(
    file.replace_values([edits[2], edits[1], edits[0]]).unwrap(),
    expected,
  )
  assert_eq(edits[0].0, cells[3])
  assert_eq(file.rewrite_original(), source)
}

///|
test "feature09 batch reaches nested values frames and other blocks" {
  let source = "#\\#CIF_2.0\ndata_one\n_values [ 'x' {'k':7} ]\nsave_f\n_s 8\nsave_\ndata_two\n_t 9\n"
  let file = parse_string(source).unwrap()
  let items = match file.find("one", "_values").unwrap() {
    List(values, _) => values
    _ => []
  }
  let nested = match items[1] {
    Table(values, _) => values[0].1
    _ => items[0]
  }
  let frame = match file.blocks[0].frames[0].entries[0] {
    Pair(_, value) => value
    Loop(_, values, _) => values[0]
  }
  let edited = file
    .replace_values([
      (file.find("two", "_t").unwrap(), "90"),
      (items[0], "'changed'"),
      (nested, "70"),
      (frame, "80"),
    ])
    .unwrap()
  assert_eq(
    edited, "#\\#CIF_2.0\ndata_one\n_values [ 'changed' {'k':70} ]\nsave_f\n_s 80\nsave_\ndata_two\n_t 90\n",
  )
  assert_true(parse_string(edited) is Ok(_))
}

///|
test "feature09 batch rejects duplicate overlapping and foreign values" {
  let file = parse_string("#\\#CIF_2.0\ndata_x\n_v [2 3]\n_a 1\n").unwrap()
  let parent = file.find("x", "_v").unwrap()
  let children = match parent {
    List(values, _) => values
    _ => []
  }
  let a = file.find("x", "_a").unwrap()
  assert_true(file.replace_values([(a, "2"), (a, "3")]) is Err(_))
  assert_true(
    file.replace_values([(parent, "[4]"), (children[0], "5")]) is Err(_),
  )
  assert_true(
    file.replace_values([(children[0], "5"), (parent, "[4]")]) is Err(_),
  )
  let foreign = parse_string("data_foreign\n_value 100000\n")
    .unwrap()
    .find("foreign", "_value")
    .unwrap()
  assert_true(file.replace_values([(a, "2"), (foreign, "3")]) is Err(_))
}

///|
test "feature09 invalid later replacement aborts the batch" {
  let source = "data_x\n_a 1\n_b 2\n"
  let file = parse_string(source).unwrap()
  let a = file.find("x", "_a").unwrap()
  let b = file.find("x", "_b").unwrap()
  for invalid in ["3\ndata_extra\n_v 4", "'missing", "3 # hides source"] {
    assert_true(file.replace_values([(a, "1000"), (b, invalid)]) is Err(_))
    assert_eq(file.rewrite_original(), source)
  }
}

///|
test "feature09 batch checks the final lexical context" {
  let source = "data_x\n_a\nword\n_b 2\n"
  let file = parse_string(source).unwrap()
  let a = file.find("x", "_a").unwrap()
  let b = file.find("x", "_b").unwrap()
  assert_true(file.replace_values([(b, "20"), (a, ";bad")]) is Err(_))
  assert_eq(
    file.replace_values([(b, "20"), (a, " ;okay")]).unwrap(),
    "data_x\n_a\n ;okay\n_b 20\n",
  )
}

///|
test "feature09 combined physical line limit is validated" {
  let file = parse_string("data_x\n_a 'x' _b 'y'\n").unwrap()
  let a = file.find("x", "_a").unwrap()
  let b = file.find("x", "_b").unwrap()
  assert_true(
    file.replace_values([(a, "p".repeat(1100)), (b, "q".repeat(1100))])
    is Err(_),
  )
  let p = "p".repeat(1020)
  let q = "q".repeat(1021)
  let edited = file.replace_values([(a, p), (b, q)]).unwrap()
  assert_eq(edited, "data_x\n_a " + p + " _b " + q + "\n")
  assert_true(parse_string(edited) is Ok(_))
}

///|
test "feature09 identity and partial recovery editing remain available" {
  let source = "data_x\nloop_\n_a\n_b\n1\n_ok 2\n_tail 3\n"
  let file = parse_report(source).file
  assert_eq(file.replace_values([]).unwrap(), source)
  let edited = file
    .replace_values([
      (file.find("x", "_tail").unwrap(), "300"),
      (file.find("x", "_ok").unwrap(), "20"),
    ])
    .unwrap()
  assert_eq(edited, "data_x\nloop_\n_a\n_b\n1\n_ok 20\n_tail 300\n")
  assert_true(parse_report(edited).diagnostics.any(d => d.code == "E003"))
}
