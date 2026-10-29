///|
extern "js" fn read_text(path : String) -> String =
  #| path => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(process.getBuiltinModule('fs').readFileSync(path))

///|
extern "js" fn emit_exact(text : String) -> Unit =
  #| text => { process.stdout.write(text); }

///|
fn main {
  let args = @env.args()
  let source = read_text(args[3])
  let file = @cif.parse_string(source).unwrap()
  // Caller policy for these supplied layouts: quarantine row1 in the first
  // frame's first loop (CIF2), or row0 in the block's first loop (CIF1).
  // The library never infers an ID, outlier rule or measurement policy.
  let (target, row) = if args[2] == "cif2" {
    (file.blocks[0].frames[0].entries[0], 1)
  } else {
    (file.blocks[0].entries[0], 0)
  }
  let result = file
    .remove_loop_row(target, row, expected_source=source)
    .unwrap()
  emit_exact(result)
}
