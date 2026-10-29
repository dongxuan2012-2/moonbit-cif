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
  // Caller-owned policy for the supplied layouts, not an inferred namespace.
  let (scope, text) = if args[2] == "cif2" {
    (file.blocks[0].frames[0], "已核对")
  } else {
    (file.blocks[0], "reviewed locally")
  }
  let fragment = @cif.format_string(text, version=file.version).unwrap()
  emit_exact(
    file
    .add_pair(scope, "_processing_note", fragment, expected_source=source)
    .unwrap(),
  )
}
