///|
fn pair_error_unchanged(
  source : String,
  name : String,
  fragment : String,
) -> Unit raise {
  let file = @cif.parse_string(source).unwrap()
  let copy = @cif.parse_string(source).unwrap()
  assert_true(
    file.add_pair(file.blocks[0], name, fragment, expected_source=source)
    is Err(_),
  )
  assert_eq(file, copy)
}

///|
test "add missing Pair with independent complete BOM CRLF Unicode and scope expectation" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_meta\r\n_processing_note 'keep root'\r\nsave_run\r\n# original frame note\r\nloop_\r\n_id\r\n_length_m\r\nA 1.000(10)\r\nB 3.500(20)\r\nsave_\r\ndata_other\r\n_x keep\r\n"
  let expected = "\uFEFF#\\#CIF_2.0\r\ndata_meta\r\n_processing_note 'keep root'\r\nsave_run\r\n# original frame note\r\n_processing_note\n'已核对'\nloop_\r\n_id\r\n_length_m\r\nA 1.000(10)\r\nB 3.500(20)\r\nsave_\r\ndata_other\r\n_x keep\r\n"
  let file = @cif.parse_string(source).unwrap()
  let copy = @cif.parse_string(source).unwrap()
  let edited = file
    .add_pair(
      copy.blocks[0].frames[0],
      "_processing_note",
      @cif.format_string("已核对").unwrap(),
      expected_source=source,
    )
    .unwrap()
  assert_eq(edited, expected)
  let old = @utf8.encode(source)
  let bytes = @utf8.encode(edited)
  assert_eq(old.length(), 166)
  assert_eq(bytes.length(), 195)
  assert_eq(bytes[:89], old[:89])
  assert_eq(
    bytes[89:118].to_owned(),
    @utf8.encode("_processing_note\n'已核对'\n"),
  )
  assert_eq(bytes[118:], old[89:])
  let after = @cif.parse_string(edited).unwrap()
  assert_eq(
    after.find("meta", "_processing_note").unwrap().to_json(),
    Json::string("keep root"),
  )
  assert_eq(
    after.find_values("meta", "_processing_note", frame="run")[0].to_json(),
    Json::string("已核对"),
  )
  assert_true(
    after.blocks[0].frames[0].entries
    is [@cif.Pair(tag, value), @cif.Loop(_, _, span)] &&
    tag.span.start_offset == 89 &&
    tag.span.end_offset == 105 &&
    value.span().start_offset == 106 &&
    value.span().end_offset == 117 &&
    span.start_offset == 118 &&
    span.end_offset == 165,
  )
  assert_eq(after.blocks[1].name.span.start_offset, 174)
  assert_eq(file, copy)
}

///|
test "add Pair preserves leading indentation and EOF comment in CIF1 full output" {
  let source = "data_one\n# initial note\n  _length_m 2.500(5) # EOF"
  let file = @cif.parse_string(source).unwrap()
  let result = file
    .add_pair(
      file.blocks[0],
      "_processing_note",
      "'reviewed locally'",
      expected_source=source,
    )
    .unwrap()
  assert_eq(
    result, "data_one\n# initial note\n  \n_processing_note\n'reviewed locally'\n_length_m 2.500(5) # EOF",
  )
  assert_eq(@utf8.encode(result).length(), 87)
  let after = @cif.parse_string(result).unwrap()
  assert_true(
    after.blocks[0].entries is [@cif.Pair(tag, value), @cif.Pair(old_tag, _)] &&
    tag.span.start_offset == 27 &&
    value.span().end_offset == 62 &&
    old_tag.span.start_offset == 63,
  )
  assert_eq(file.source, source)
}

///|
test "add Pair to empty blocks and frames while retaining old leading comments" {
  for
    (source, expected) in [
      ("data_x", "data_x\n_new\n1\n"),
      ("data_x # keep", "data_x # keep\n_new\n1\n"),
    ] {
    let file = @cif.parse_string(source).unwrap()
    assert_eq(
      file
      .add_pair(file.blocks[0], "_new", "1", expected_source=source)
      .unwrap(),
      expected,
    )
  }
  let source = "data_x\nsave_a\n# scope\nsave_\n_tail keep\n"
  let file = @cif.parse_string(source).unwrap()
  assert_eq(
    file
    .add_pair(file.blocks[0].frames[0], "_new", "?", expected_source=source)
    .unwrap(),
    "data_x\nsave_a\n# scope\n_new\n?\nsave_\n_tail keep\n",
  )
  assert_eq(file, @cif.parse_string(source).unwrap())
}

///|
test "add Pair rejects direct scope canonical duplicates and invalid names fragments versions" {
  pair_error_unchanged("data_x\n_old 1\n", "_OLD", "2")
  pair_error_unchanged("data_x\nloop_\n_id\n1\n", "_ID", "2")
  pair_error_unchanged("#\\#CIF_2.0\ndata_x\n_Å 1\n", "_a\u030A", "2")
  let source = "data_x\n_old 1\n"
  for name in ["_", "new", "_a b", "_a\n_b", "_é"] {
    pair_error_unchanged(source, name, "2")
  }
  for
    fragment in [
      "", "1 2", "1\n_injected 2", "1\ndata_new\n_x 2", "1 # tail", "'broken", "[1 2]",
      "'é'",
    ] {
    pair_error_unchanged(source, "_new", fragment)
  }
}

///|
test "add Pair protects complete source and original structural scope witness atomically" {
  let source = "data_x\n_old 1\n"
  let file = @cif.parse_string(source).unwrap()
  assert_true(
    file.add_pair(
      file.blocks[0],
      "_new",
      "2",
      expected_source=source + "# changed\n",
    )
    is Err(_),
  )
  let foreign = @cif.parse_string("data_y\n_old 1\n").unwrap()
  assert_true(
    file.add_pair(foreign.blocks[0], "_new", "2", expected_source=source)
    is Err(_),
  )
  let fabricated : @cif.Container = {
    name: file.blocks[0].name,
    entries: [],
    frames: [],
  }
  assert_true(
    file.add_pair(fabricated, "_new", "2", expected_source=source) is Err(_),
  )
  assert_eq(file, @cif.parse_string(source).unwrap())
  let partial_source = "data_x\n_old\n"
  let partial = @cif.parse_report(partial_source).file
  assert_true(
    partial.add_pair(
      partial.blocks[0],
      "_new",
      "2",
      expected_source=partial_source,
    )
    is Err(_),
  )
  assert_eq(partial.source, partial_source)
}

///|
test "add Pair accepts encoded composite text markers and original legal line budgets" {
  let source = "#\\#CIF_2.0\ndata_x\n_old 1\n"
  let file = @cif.parse_string(source).unwrap()
  for
    fragment in [
      "[1 {'k':2}]",
      "\n;multi\nline\n;\n",
      "'?'",
      "?",
      "x".repeat(2048),
    ] {
    let edited = file
      .add_pair(file.blocks[0], "_new", fragment, expected_source=source)
      .unwrap()
    assert_eq(edited, "#\\#CIF_2.0\ndata_x\n_new\n" + fragment + "\n_old 1\n")
  }
  let name = "_" + "x".repeat(2047)
  assert_true(
    file.add_pair(file.blocks[0], name, "1", expected_source=source) is Ok(_),
  )
  pair_error_unchanged(source, name + "x", "1")
  pair_error_unchanged(source, "_new", "x".repeat(2049))
  pair_error_unchanged("data_x\n_old 1\n", "_" + "x".repeat(75), "1")
  assert_eq(file.source, source)
}
