///|
fn main {
  let args = @env.args()
  if args.length() > 1 {
    println(@cif.inspect_json(args[args.length() - 1]).stringify())
  } else {
    println("Usage: moon run cmd/inspect -- <CIF-text>")
  }
}
