///|
/// Domain-neutral JSON view for command-line and external verification consumers.
pub fn inspect_json(source : String) -> Json {
  let report = parse_report(source)
  let blocks : Array[Json] = []
  for b in report.file.blocks {
    let fields : Map[String, Json] = Map([])
    for e in b.entries {
      match e {
        Pair(t, v) => fields[t.text] = v.to_json()
        Loop(tags, vals, _) =>
          for col in 0..<tags.length() {
            let values : Array[Json] = []
            let mut i = col
            while i < vals.length() {
              values.push(vals[i].to_json())
              i += tags.length()
            }
            fields[tags[col].text] = values.to_json()
          }
      }
    }
    blocks.push({
      "name": b.name.text,
      "fields": fields.to_json(),
      "frames": b.frames.length(),
    })
  }
  let diagnostics = report.diagnostics.map(d => d.to_json())
  {
    "valid": report.is_valid(),
    "blocks": blocks.to_json(),
    "diagnostics": diagnostics.to_json(),
    "tokens": report.file.tokens.length(),
    "original": source,
    "raw_count": report.raw_data.length(),
  }
}
