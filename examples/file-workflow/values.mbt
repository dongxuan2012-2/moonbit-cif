///|
/// Read each requested tag independently; no ID selection or cross-column join.
fn values_file(
  file : @cif.CifFile,
  scope : Map[String, Json],
  source_hash : String,
  block : String,
  frame : String,
  source : Bytes,
) -> Json raise WorkflowError {
  let tags = match scope.get("tags") {
    Some(Json::Array(items)) => items
    _ => raise Invalid("tags must be an array")
  }
  let selections : Array[Json] = []
  for item in tags {
    let tag = match item {
      Json::String(text) => text
      _ => raise Invalid("tags must contain strings")
    }
    let values : Array[Json] = []
    for value in file.find_values(block, tag, frame~) {
      values.push(describe(value, source))
    }
    selections.push({ "tag": tag, "values": values.to_json() })
  }
  {
    "ok": true,
    "mode": "values",
    "sourceSha256": source_hash,
    "version": if file.version == @cif.Cif2 {
      "CIF2.0"
    } else {
      "CIF1.1"
    },
    "block": block,
    "frame": frame,
    "selections": selections.to_json(),
    "writesFiles": false,
  }
}
