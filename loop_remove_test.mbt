///|
fn removal_error_unchanged(source : String, row : Int) -> Unit raise {
  let file = @cif.parse_string(source).unwrap()
  let original = @cif.parse_string(source).unwrap()
  assert_true(
    file.remove_loop_row(file.blocks[0].entries[0], row, expected_source=source)
    is Err(_),
  )
  assert_eq(file, original)
}

///|
test "remove one logical row preserves all independently handwritten retained bytes" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_curate\r\n_root keep\r\nsave_run\r\nloop_\r\n_id\r\n_length_m\r\n_note\r\n_meta\r\nA 2.000(10) ? [1]\r\nB 999.0(50) 'reject' {'qc':'bad'} # retain annotation\r\nC 4.000(20) \"keep C\" []\r\n_tail {'k':[1 2]}\r\nsave_\r\ndata_other\r\n_x 'untouched'\r\n"
  let expected = "\uFEFF#\\#CIF_2.0\r\ndata_curate\r\n_root keep\r\nsave_run\r\nloop_\r\n_id\r\n_length_m\r\n_note\r\n_meta\r\nA 2.000(10) ? [1]\r\n    # retain annotation\r\nC 4.000(20) \"keep C\" []\r\n_tail {'k':[1 2]}\r\nsave_\r\ndata_other\r\n_x 'untouched'\r\n"
  let file = @cif.parse_string(source).unwrap()
  let copy = @cif.parse_string(source).unwrap()
  let witness = copy.blocks[0].frames[0].entries[0]
  let edited = file.remove_loop_row(witness, 1, expected_source=source).unwrap()
  assert_eq(edited, expected)
  let old = @utf8.encode(source)
  let bytes = @utf8.encode(edited)
  assert_eq(old.length(), 240)
  assert_eq(bytes.length(), 210)
  assert_eq(bytes[:106], old[:106])
  assert_eq(bytes[106:107], old[107:108])
  assert_eq(bytes[107:108], old[117:118])
  assert_eq(bytes[108:109], old[126:127])
  assert_eq(bytes[109:], old[139:])
  let after = @cif.parse_string(edited).unwrap()
  let rows = after
    .find_loop_rows("curate", ["_id", "_length_m"], frame="run")
    .unwrap()
  assert_eq(rows.map(r => r.map(v => v.to_json())), [
    [Json::string("A"), Json::string("2.000(10)")],
    [Json::string("C"), Json::string("4.000(20)")],
  ])
  assert_true(
    after.blocks[0].frames[0].entries
    is [@cif.Loop(_, _, span), @cif.Pair(tail, _)] &&
    span.start_offset == 50 &&
    span.end_offset == 154 &&
    tail.span.start_offset == 156,
  )
  assert_eq(after.blocks[1].name.span.start_offset, 182)
  assert_eq(file, copy)
}

///|
test "remove first middle last rows from a shared physical line without deleting trivia" {
  let source = "data_x\nloop_\n_a\n_b\n1 2 3 4 5 6 # note\n"
  let file = @cif.parse_string(source).unwrap()
  for
    (index, expected) in [
      (0, "data_x\nloop_\n_a\n_b\n  3 4 5 6 # note\n"),
      (1, "data_x\nloop_\n_a\n_b\n1 2   5 6 # note\n"),
      (2, "data_x\nloop_\n_a\n_b\n1 2 3 4   # note\n"),
    ] {
    assert_eq(
      file
      .remove_loop_row(file.blocks[0].entries[0], index, expected_source=source)
      .unwrap(),
      expected,
    )
  }
  assert_eq(file.source, source)
}

///|
test "remove text and compound cells keeps external comments and deletes internal cell comments" {
  let source = "data_one\nloop_\n_id\n_length_m\n_note\nX 8.000(30)\n;rejected\ntext\n;\nY 1.250(5) . # stay EOF"
  let file = @cif.parse_string(source).unwrap()
  assert_eq(
    file
    .remove_loop_row(file.blocks[0].entries[0], 0, expected_source=source)
    .unwrap(),
    "data_one\nloop_\n_id\n_length_m\n_note\n \n\nY 1.250(5) . # stay EOF",
  )
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_v\n[1 # inside\n 2] # outside\n{'k':3}\n"
  let file = @cif.parse_string(source).unwrap()
  assert_eq(
    file
    .remove_loop_row(file.blocks[0].entries[0], 0, expected_source=source)
    .unwrap(),
    "#\\#CIF_2.0\ndata_x\nloop_\n_v\n # outside\n{'k':3}\n",
  )
}

///|
test "remove only selected frame row and retain old markers raw quoted strings and other loops" {
  let source = "#\\#CIF_2.0\ndata_x\nsave_a\nloop_\n_v\n? '?' .\nsave_\nsave_b\nloop_\n_v\n'?' .\nsave_\nloop_\n_root\n9\n"
  let file = @cif.parse_string(source).unwrap()
  let edited = file
    .remove_loop_row(
      file.blocks[0].frames[0].entries[0],
      0,
      expected_source=source,
    )
    .unwrap()
  assert_eq(
    edited, "#\\#CIF_2.0\ndata_x\nsave_a\nloop_\n_v\n '?' .\nsave_\nsave_b\nloop_\n_v\n'?' .\nsave_\nloop_\n_root\n9\n",
  )
  let rows = @cif.parse_string(edited)
    .unwrap()
    .find_loop_rows("x", ["_v"], frame="a")
    .unwrap()
  assert_true(
    rows[0][0] is @cif.Scalar(t) &&
    t.kind == @cif.Quoted &&
    t.raw == "'?'" &&
    rows[1][0] is @cif.Scalar(u) &&
    u.kind == @cif.Word &&
    u.raw == ".",
  )
  assert_eq(file, @cif.parse_string(source).unwrap())
}

///|
test "remove rejects source witness index singleton and invalid original without mutation" {
  let source = "data_x\nloop_\n_v\n1 2\n_tail keep\n"
  let file = @cif.parse_string(source).unwrap()
  let target = file.blocks[0].entries[0]
  assert_true(
    file.remove_loop_row(target, 0, expected_source=source + "# stale\n")
    is Err(_),
  )
  assert_true(
    file.remove_loop_row(file.blocks[0].entries[1], 0, expected_source=source)
    is Err(_),
  )
  let foreign = @cif.parse_string("data_other\nloop_\n_v\n1 2\n").unwrap()
  assert_true(
    file.remove_loop_row(
      foreign.blocks[0].entries[0],
      0,
      expected_source=source,
    )
    is Err(_),
  )
  guard target is @cif.Loop(tags, values, span) else { fail("loop") }
  let fake : @cif.Token = {
    kind: tags[0].kind,
    raw: "_different",
    text: tags[0].text,
    span: tags[0].span,
  }
  assert_true(
    file.remove_loop_row(
      @cif.Loop([fake], values, span),
      0,
      expected_source=source,
    )
    is Err(_),
  )
  for index in [-1, 2, 2147483647] {
    assert_true(
      file.remove_loop_row(target, index, expected_source=source) is Err(_),
    )
  }
  assert_eq(file, @cif.parse_string(source).unwrap())
  removal_error_unchanged("data_x\nloop_\n_v\n1\n", 0)
  let bad = "data_x\nloop_\n_a\n_b\n1\n"
  let partial = @cif.parse_report(bad).file
  assert_true(
    partial.remove_loop_row(
      partial.blocks[0].entries[0],
      0,
      expected_source=bad,
    )
    is Err(_),
  )
  assert_eq(partial.source, bad)
}

///|
test "remove validates retained physical line after a multiline cell is deleted" {
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_v\n" +
    "x".repeat(1200) +
    " '''cut\nmore''' " +
    "y".repeat(1000) +
    "\n"
  removal_error_unchanged(source, 1)
}
