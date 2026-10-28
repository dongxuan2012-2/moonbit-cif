///|
fn first_loop(file : @cif.CifFile) -> @cif.Entry {
  file.blocks[0].entries[0]
}

///|
fn append_error_unchanged(source : String, cells : Array[String]) -> Unit raise {
  let file = @cif.parse_string(source).unwrap()
  let copy = @cif.parse_string(source).unwrap()
  let original_cells = cells[:].to_owned()
  assert_true(
    file.append_loop_row(first_loop(file), cells, expected_source=source)
    is Err(_),
  )
  assert_eq(file, copy)
  assert_eq(cells, original_cells)
}

///|
test "append handwritten 96/82/16 byte relation and equivalent structural witness" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_lab\r\nloop_\r\n_sample_id\r\n_length_m\r\n_note\r\nA 1.230(4) ? # old\r\n_tail 'keep'\r\n"
  let expected = "\uFEFF#\\#CIF_2.0\r\ndata_lab\r\nloop_\r\n_sample_id\r\n_length_m\r\n_note\r\nA 1.230(4) ? # old\r\nB\r\n2.500(3)\r\n.\r\n_tail 'keep'\r\n"
  let file = @cif.parse_string(source).unwrap()
  let copy = @cif.parse_string(source).unwrap()
  let cells = ["B", "2.500(3)", "."]
  let edited = file
    .append_loop_row(
      first_loop(copy),
      cells,
      expected_source=source,
      newline="\r\n",
    )
    .unwrap()
  assert_eq(edited, expected)
  let bytes = @utf8.encode(edited)
  let old = @utf8.encode(source)
  assert_eq(old.length(), 96)
  assert_eq(bytes.length(), 112)
  assert_eq(bytes[:82], old[:82])
  assert_eq(bytes[82:98].to_owned(), b"B\r\n2.500(3)\r\n.\r\n")
  assert_eq(bytes[98:], old[82:])
  let after = @cif.parse_string(edited).unwrap()
  assert_eq(
    after
    .find_loop_rows("lab", ["_sample_id", "_length_m", "_note"])
    .unwrap()
    .map(row => row.map(v => v.to_json())),
    [
      [Json::string("A"), Json::string("1.230(4)"), Json::string("?")],
      [Json::string("B"), Json::string("2.500(3)"), Json::string(".")],
    ],
  )
  assert_true(
    after.blocks[0].entries is [@cif.Loop(_, values, span), @cif.Pair(tag, _)] &&
    values.length() == 6 &&
    span.start_offset == 25 &&
    span.end_offset == 96 &&
    tag.span.start_offset == 98,
  )
  assert_eq(file, copy)
  assert_eq(cells, ["B", "2.500(3)", "."])
}

///|
test "append protects exact snapshot and structural token value span alignment" {
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_v\n1\n_tail 'é'\n"
  let file = @cif.parse_string(source).unwrap()
  let target = first_loop(file)
  for
    stale in [source + "# later\n", source.replace_all(old="é", new="e\u0301")] {
    assert_true(
      file.append_loop_row(target, ["2"], expected_source=stale) is Err(_),
    )
  }
  let foreign = @cif.parse_string("#\\#CIF_2.0\ndata_other\nloop_\n_v\n1\n").unwrap()
  assert_true(
    file.append_loop_row(first_loop(foreign), ["2"], expected_source=source)
    is Err(_),
  )
  assert_true(
    file.append_loop_row(
      file.blocks[0].entries[1],
      ["2"],
      expected_source=source,
    )
    is Err(_),
  )
  guard target is @cif.Loop(headers, values, span) else { fail("loop witness") }
  let forged_span : @cif.Span = {
    start_line: span.start_line,
    start_col: span.start_col,
    end_line: span.end_line,
    end_col: span.end_col,
    start_offset: span.start_offset + 1,
    end_offset: span.end_offset,
  }
  let forged_header : @cif.Token = {
    kind: headers[0].kind,
    raw: "_forged",
    text: headers[0].text,
    span: headers[0].span,
  }
  guard values[0] is @cif.Scalar(token) else { fail("scalar") }
  let forged_token : @cif.Token = {
    kind: token.kind,
    raw: token.raw,
    text: "different",
    span: token.span,
  }
  for
    forged in [
      @cif.Loop(headers, values, forged_span),
      @cif.Loop([forged_header], values, span),
      @cif.Loop(headers, [@cif.Scalar(forged_token)], span),
    ] {
    assert_true(
      file.append_loop_row(forged, ["2"], expected_source=source) is Err(_),
    )
  }
  assert_true(
    file.append_loop_row(target, [], expected_source=source) is Err(_),
  )
  assert_true(
    file.append_loop_row(target, ["2", "3"], expected_source=source) is Err(_),
  )
  for separator in ["", "\r", " \n"] {
    assert_true(
      file.append_loop_row(
        target,
        ["2"],
        expected_source=source,
        newline=separator,
      )
      is Err(_),
    )
  }
  assert_eq(file, @cif.parse_string(source).unwrap())
}

///|
test "append selected Unicode frame leaves root other loops and save data boundaries" {
  let source = "#\\#CIF_2.0\r\ndata_é\r\nloop_\r\n_root\r\n0\r\nsave_Å\r\nloop_\r\n_v\r\n1 # old\r\nsave_\r\ndata_next\r\n_tail 2\r\n"
  let expected = "#\\#CIF_2.0\r\ndata_é\r\nloop_\r\n_root\r\n0\r\nsave_Å\r\nloop_\r\n_v\r\n1 # old\r\n'?'\nsave_\r\ndata_next\r\n_tail 2\r\n"
  let file = @cif.parse_string(source).unwrap()
  let target = file.blocks[0].frames[0].entries[0]
  let edited = file
    .append_loop_row(
      target,
      [@cif.format_string("?").unwrap()],
      expected_source=source,
    )
    .unwrap()
  assert_eq(edited, expected)
  let after = @cif.parse_string(edited).unwrap()
  let rows = after.find_loop_rows("e\u0301", ["_V"], frame="a\u030A").unwrap()
  assert_eq(rows.length(), 2)
  assert_true(rows[1][0].measurement() is Err(_))
  assert_eq(file, @cif.parse_string(source).unwrap())
}

///|
test "append inserts after original comments trivia and final text or compound cells" {
  for
    (source, cell, expected) in [
      ("data_x\nloop_\n_v\n1", "9", "data_x\nloop_\n_v\n1\n9\n"),
      ("data_x\nloop_\n_v\n1 # old", "9", "data_x\nloop_\n_v\n1 # old\n9\n"),
      ("data_x\nloop_\n_v\n1 # old\n", "9", "data_x\nloop_\n_v\n1 # old\n9\n"),
      (
        "data_x\nloop_\n_v\n1\n  _tail 2\n", "9", "data_x\nloop_\n_v\n1\n  \n9\n_tail 2\n",
      ),
      (
        "data_x\nloop_\n_v\n1\nloop_\n_w\n2\n", "9", "data_x\nloop_\n_v\n1\n9\nloop_\n_w\n2\n",
      ),
      (
        "data_x\nloop_\n_v\n1\ndata_y\n_t 2\n", "9", "data_x\nloop_\n_v\n1\n9\ndata_y\n_t 2\n",
      ),
      (
        "data_x\nloop_\n_v\n;text\n;\n_tail 'keep'\n", "'x'", "data_x\nloop_\n_v\n;text\n;\n'x'\n_tail 'keep'\n",
      ),
      (
        "#\\#CIF_2.0\ndata_x\nloop_\n_v\n[1 {'k':[2]}] # c\n", "{'k':[3 4]}", "#\\#CIF_2.0\ndata_x\nloop_\n_v\n[1 {'k':[2]}] # c\n{'k':[3 4]}\n",
      ),
    ] {
    let file = @cif.parse_string(source).unwrap()
    assert_eq(
      file
      .append_loop_row(first_loop(file), [cell], expected_source=source)
      .unwrap(),
      expected,
    )
    assert_eq(file, @cif.parse_string(source).unwrap())
  }
}

///|
test "append one logical row accepts multiline strings and nested single cells" {
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_a\n_b\n_c\n1 ? .\n"
  let file = @cif.parse_string(source).unwrap()
  let cells = ["'?'", "\".\"", "'''both ' and \"\nsecond'''"]
  let expected = "#\\#CIF_2.0\ndata_x\nloop_\n_a\n_b\n_c\n1 ? .\n'?'\n\".\"\n'''both ' and \"\nsecond'''\n"
  let after = @cif.parse_string(
    file
    .append_loop_row(first_loop(file), cells, expected_source=source)
    .unwrap(),
  ).unwrap()
  assert_eq(after.source, expected)
  let rows = after.find_loop_rows("x", ["_a", "_b", "_c"]).unwrap()
  assert_eq(rows.length(), 2)
  assert_true(
    rows[1][0].measurement() is Err(_) && rows[1][1].measurement() is Err(_),
  )
  assert_eq(rows[1][2].to_json(), Json::string("both ' and \"\nsecond"))
  let compound = "#\\#CIF_2.0\ndata_x\nloop_\n_a\n_b\n0 1\n"
  let file = @cif.parse_string(compound).unwrap()
  assert_eq(
    file
    .append_loop_row(
      first_loop(file),
      ["[1 {'k':2}]", "{'k':[3 4]}"],
      expected_source=compound,
    )
    .unwrap(),
    "#\\#CIF_2.0\ndata_x\nloop_\n_a\n_b\n0 1\n[1 {'k':2}]\n{'k':[3 4]}\n",
  )
  let text = "data_x\nloop_\n_v\n1\n"
  let file = @cif.parse_string(text).unwrap()
  assert_eq(
    file
    .append_loop_row(
      first_loop(file),
      ["\n;new\nline\n;\n"],
      expected_source=text,
    )
    .unwrap(),
    "data_x\nloop_\n_v\n1\n\n;new\nline\n;\n\n",
  )
}

///|
test "append rejects invalid originals injection CIF1 encoding and final context atomically" {
  for
    source in [
      "data_x\nloop_\n_v\n", "data_x\nloop_\n1\n", "data_x\nloop_\n_v\n_w\n1\n",
      "data_x\nloop_\n_v\n_V\n1 2\n",
    ] {
    let file = @cif.parse_report(source).file
    assert_true(
      file.append_loop_row(first_loop(file), ["2"], expected_source=source)
      is Err(_),
    )
    assert_eq(file.source, source)
  }
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_v\n1\n"
  for
    cell in [
      "2 3", "2\ndata_y\n_v 3", "2\nsave_f\n_v 3\nsave_", "2\n_x 4", "2 # tail",
      "'broken", "\u0000",
    ] {
    append_error_unchanged(source, [cell])
  }
  append_error_unchanged("data_x\nloop_\n_v\n1\n", ["'é'"])
  assert_true(@cif.format_string("é", version=@cif.Cif1) is Err(_))
  // This is legal only with the adjacent comment ending at EOF. Inserting a
  // newline changes that context, so preservation requires a complete Err.
  append_error_unchanged("#\\#CIF_2.0\ndata_x\nloop_\n_v\n'x'#EOF", ["2"])
}

///|
test "append retains existing 2048 scalar line and depth budgets without a probe prefix tax" {
  let source = "#\\#CIF_2.0\ndata_x\nloop_\n_v\n1\n"
  let file = @cif.parse_string(source).unwrap()
  let longest = "x".repeat(2048)
  assert_eq(
    file
    .append_loop_row(first_loop(file), [longest], expected_source=source)
    .unwrap(),
    source + longest + "\n",
  )
  append_error_unchanged(source, ["x".repeat(2049)])
  let deepest = "[".repeat(127) + "0" + "]".repeat(127)
  assert_eq(
    file
    .append_loop_row(first_loop(file), [deepest], expected_source=source)
    .unwrap(),
    source + deepest + "\n",
  )
  append_error_unchanged(source, ["[".repeat(128) + "0" + "]".repeat(128)])
}
