///|
fn catalog_scope(container : @cif.Container) -> Json {
  let pairs : Array[Json] = []
  let loops : Array[Json] = []
  for entry in container.entries {
    match entry {
      @cif.Pair(tag, value) =>
        pairs.push({
          "tag": tag.text,
          "tagSpan": tag.span.to_json(),
          "valueSpan": value.span().to_json(),
        })
      @cif.Loop(tags, values, span) =>
        loops.push({
          "tags": tags.map(t => t.text).to_json(),
          "tagSpans": tags.map(t => t.span.to_json()).to_json(),
          "columnCount": tags.length(),
          "valueCount": values.length(),
          "rowCount": values.length() / tags.length(),
          "span": span.to_json(),
        })
    }
  }
  {
    "name": container.name.text[5:].to_owned(),
    "header": container.name.text,
    "nameSpan": container.name.span.to_json(),
    "pairs": pairs.to_json(),
    "loops": loops.to_json(),
    "frames": container.frames.map(catalog_scope).to_json(),
  }
}

///|
fn catalog_file(path : String) -> Json raise WorkflowError {
  let input = host_result(host_read(path))
  let report = @cif.parse_report(string_field(input, "text"))
  if !report.is_valid() {
    raise Invalid(
      "Invalid CIF: " +
      report.diagnostics.map(d => d.to_json()).to_json().stringify(),
    )
  }
  {
    "ok": true,
    "sourceSha256": string_field(input, "sha256"),
    "version": if report.file.version == @cif.Cif2 {
      "CIF2.0"
    } else {
      "CIF1.1"
    },
    "blocks": report.file.blocks.map(catalog_scope).to_json(),
  }
}
