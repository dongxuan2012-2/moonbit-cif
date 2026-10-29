///|
fn collect_append_targets(
  container : @cif.Container,
  headers : Array[String],
  first_row : Array[@cif.Value],
  block : String,
  frame : String,
  found : Array[(@cif.Entry, String, String)],
) -> Unit {
  for entry in container.entries {
    if entry is @cif.Loop(tags, values, _) &&
      tags.map(t => t.text) == headers &&
      values.length() >= headers.length() &&
      values[:headers.length()].to_owned() == first_row {
      found.push((entry, block, frame))
    }
  }
  for nested in container.frames {
    collect_append_targets(
      nested,
      headers,
      first_row,
      block,
      nested.name.text[5:].to_owned(),
      found,
    )
  }
}

///|
fn append_file(
  args : Array[String],
  file : @cif.CifFile,
  row : Map[String, Json],
  source_hash : String,
  block : String,
  frame : String,
) -> Json raise WorkflowError {
  if string_field(row, "sourceSha256") != source_hash {
    raise Invalid(
      "sourceSha256 differs from the current input; catalog it again",
    )
  }
  let headers = match row.get("headers") {
    Some(Json::Array(items)) => {
      let headers : Array[String] = []
      for item in items {
        match item {
          Json::String(text) => headers.push(text)
          _ => raise Invalid("headers must contain strings")
        }
      }
      headers
    }
    _ => raise Invalid("headers must be an array")
  }
  // Reuse the public scope and unique-loop selector. Its original first row
  // locates the structural witness; full headers must match catalog order/spelling.
  let original_rows = rows(file, block, headers, frame)
  let found : Array[(@cif.Entry, String, String)] = []
  for container in file.blocks {
    collect_append_targets(
      container,
      headers,
      original_rows[0],
      container.name.text[5:].to_owned(),
      "",
      found,
    )
  }
  if found.length() != 1 {
    raise Invalid(
      "headers must match one complete original loop in catalog order and spelling",
    )
  }
  let (target, actual_block, actual_frame) = found[0]
  let cells = match row.get("cells") {
    Some(Json::Array(items)) => {
      let cells : Array[String] = []
      for item in items {
        let cell = object(item)
        if cell.contains("cif") == cell.contains("text") {
          raise Invalid("Each cell requires exactly one of cif/text")
        }
        cells.push(
          if cell.contains("text") {
            checked(
              @cif.format_string(
                string_field(cell, "text"),
                version=file.version,
              ),
            )
          } else {
            string_field(cell, "cif")
          },
        )
      }
      cells
    }
    _ => raise Invalid("cells must be an array")
  }
  let newline = if row.contains("newline") {
    string_field(row, "newline")
  } else {
    "\n"
  }
  let edited = checked(
    file.append_loop_row(target, cells, expected_source=file.source, newline~),
  )
  let disk = write_output(args, edited)
  let span = match target {
    @cif.Loop(_, _, span) => span
    _ => raise Invalid("Selected target is not a loop")
  }
  {
    "ok": true,
    "mode": "append",
    "input": args[1],
    "output": args[3],
    "sourceSha256": source_hash,
    "block": actual_block,
    "frame": actual_frame,
    "target": {
      "headers": headers.to_json(),
      "span": span.to_json(),
      "rowCountBefore": original_rows.length().to_json(),
      "rowCountAfter": (original_rows.length() + 1).to_json(),
    },
    "cells": cells.to_json(),
    "disk": disk,
  }
}
