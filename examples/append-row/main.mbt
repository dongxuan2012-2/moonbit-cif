///|
extern "js" fn emit_exact(text : String) -> Unit =
  #| text => { process.stdout.write(text); }

///|
fn main {
  let source = "\uFEFF#\\#CIF_2.0\r\ndata_lab\r\nloop_\r\n_sample_id\r\n_length_m\r\n_note\r\nA 1.230(4) ? # old\r\n_tail 'keep'\r\n"
  let file = @cif.parse_string(source).unwrap()
  // This caller explicitly selects this known loop and its original header order.
  let target = file.blocks[0].entries[0]
  let appended = file
    .append_loop_row(
      target,
      ["B", "2.500(3)", "."],
      expected_source=source,
      newline="\r\n",
    )
    .unwrap()
  emit_exact(appended)
}
