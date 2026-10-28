///|
fn check_string_literal(text : String, version : @cif.Version) -> Unit raise {
  let literal = @cif.format_string(text, version~).unwrap()
  let header = if version == @cif.Cif2 { "#\\#CIF_2.0\n" } else { "" }
  let file = @cif.parse_string(
    header + "data_x\n_note " + literal + "\n",
    version~,
  ).unwrap()
  let value = file.find("x", "_note").unwrap()
  assert_eq(value.to_json(), Json::string(text))
  assert_true(value.measurement() is Err(_))
  assert_true(value is @cif.Scalar(t) && t.kind != @cif.Word)
}

///|
test "deep12 literal strings never become missing numeric or reserved values" {
  for version in [@cif.Cif1, @cif.Cif2] {
    for
      text in [
        "", "?", ".", "1.23(4)", "data_other", "save_", "loop_", "# note", "_name",
        "[1 2]", " leading and trailing \t",
      ] {
      check_string_literal(text, version)
    }
  }
  assert_eq(@cif.format_string("").unwrap(), "''")
  assert_eq(@cif.format_string("?").unwrap(), "'?'")
}

///|
test "deep12 quote selection preserves literal delimiters and backslashes" {
  for version in [@cif.Cif1, @cif.Cif2] {
    for
      text in [
        "O'Brien", "a 'quote' and a \"quote\"", "ends'", "ends\"", "\\n is literal",
        "first\nsecond", "first\n\nlast\n",
      ] {
      check_string_literal(text, version)
    }
  }
  check_string_literal("三引号 ''' 与 \"\"\"\n;inside\nend\\", @cif.Cif2)
}

///|
test "deep12 prefixed folded text retains difficult newline and whitespace boundaries" {
  for tail in ["", "\n", "\n\n", "\\", "\\ \t", "\n\\\n"] {
    let text = "'''\"\"\"\n;must be text\n\\\n spaced \t" + tail
    check_string_literal(text, @cif.Cif2)
    let literal = @cif.format_string(text).unwrap()
    assert_true(literal.has_prefix("\n;> "))
  }
}

///|
test "deep12 long Unicode strings obey physical line budgets without scalar loss" {
  for
    text in [
      "a".repeat(2048),
      "é".repeat(2045) + "😀" + "x".repeat(2046),
      "😀".repeat(4096) + "\\ \t\n;end\n",
    ] {
    let literal = @cif.format_string(text).unwrap()
    for line in literal.split("\n") {
      assert_true(line.to_owned().to_array().length() <= 2048)
    }
    check_string_literal(text, @cif.Cif2)
  }
}

///|
test "deep12 unsupported text is explicit and old literal edits stay unchanged" {
  assert_true(@cif.format_string("x", version=@cif.Auto) is Err(_))
  assert_true(@cif.format_string("é", version=@cif.Cif1) is Err(_))
  assert_true(
    @cif.format_string("'''\"\"\"\n;inside", version=@cif.Cif1) is Err(_),
  )
  for text in ["a\rb", "a\r\nb", "\u0000", "\u007F", "\uFEFF"] {
    assert_true(@cif.format_string(text) is Err(_))
  }
  let file = @cif.parse_string("data_x\n_note 'old'\n").unwrap()
  let value = file.find("x", "_note").unwrap()
  let raw = @cif.parse_string(file.replace_value(value, "?").unwrap()).unwrap()
  assert_true(raw.find("x", "_note").unwrap().measurement().unwrap().is_unknown)
  assert_eq(file.rewrite_original(), "data_x\n_note 'old'\n")
}

///|
test "deep12 formatted notes compose with scoped original-span atomic batches" {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_note 'root'\r\nsave_Å\r\nloop_\r\n_id\r\n_note\r\nA 'keep A' # comment A\r\nB 'old B' # comment B\r\nC ?\r\nsave_\r\n"
  let file = @cif.parse_string(source).unwrap()
  let rows = file
    .find_loop_rows("测", ["_ID", "_NOTE"], frame="A\u030A")
    .unwrap()
  let text = "'''\"\"\"\n;processing note\nend\\"
  let literal = @cif.format_string(text, version=file.version).unwrap()
  assert_true(
    file.replace_values([(rows[1][1], literal), (rows[2][1], "'broken")])
    is Err(_),
  )
  assert_eq(file.rewrite_original(), source)
  let edited = file
    .replace_values([
      (rows[2][1], @cif.format_string("?").unwrap()),
      (rows[1][1], literal),
    ])
    .unwrap()
  let again = @cif.parse_string(edited).unwrap()
  let notes = again.find_values("测", "_note", frame="å")
  assert_eq(notes.map(v => v.to_json()), [
    Json::string("keep A"),
    Json::string(text),
    Json::string("?"),
  ])
  assert_true(notes[2].measurement() is Err(_))
  assert_eq(
    again.find_values("测", "_note")[0].to_json(),
    Json::string("root"),
  )
  assert_true(
    edited.has_prefix("\uFEFF#\\#CIF_2.0\r\ndata_测\r\n_note 'root'\r\n"),
  )
  assert_eq(file.rewrite_original(), source)
}
