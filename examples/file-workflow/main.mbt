///|
suberror WorkflowError {
  Invalid(String)
}

///|
fn[T] checked(result : Result[T, String]) -> T raise WorkflowError {
  match result {
    Ok(value) => value
    Err(message) => raise Invalid(message)
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise WorkflowError {
  match value {
    Json::Object(fields) => fields
    _ => raise Invalid("Expected a JSON object")
  }
}

///|
fn string_field(
  fields : Map[String, Json],
  key : String,
) -> String raise WorkflowError {
  match fields.get(key) {
    Some(Json::String(text)) => text
    _ => raise Invalid("Expected string field: " + key)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
) -> String raise WorkflowError {
  if fields.contains(key) {
    string_field(fields, key)
  } else {
    ""
  }
}

///|
fn parse_json(text : String) -> Json raise WorkflowError {
  @json.parse(text[:]) catch {
    e => raise Invalid("Invalid JSON: " + e.to_string())
  }
}

///|
fn host_result(text : String) -> Map[String, Json] raise WorkflowError {
  let fields = object(parse_json(text))
  if fields.get("ok") != Some(Json::boolean(true)) {
    raise Invalid(string_field(fields, "error"))
  }
  fields
}

///|
fn rows(
  file : @cif.CifFile,
  block : String,
  tags : Array[String],
  frame : String,
) -> Array[Array[@cif.Value]] raise WorkflowError {
  checked(file.find_loop_rows(block, tags, frame~))
}

///|
fn describe(value : @cif.Value, source : Bytes) -> Json raise WorkflowError {
  let span = value.span()
  let literal = @utf8.decode(
    source[span.start_offset:span.end_offset],
    ignore_bom=false,
  ) catch {
    _ => raise Invalid("Value span is not valid UTF8")
  }
  let kind = match value {
    @cif.Scalar(t) => if t.kind == @cif.Word { "word" } else { "string" }
    @cif.List(_, _) => "list"
    @cif.Table(_, _) => "table"
  }
  {
    "value": value.to_json(),
    "kind": kind,
    "literal": literal,
    "span": span.to_json(),
  }
}

///|
fn matches_id(value : @cif.Value, id : String) -> Bool {
  match value {
    @cif.Scalar(t) =>
      t.text == id && !(t.kind == @cif.Word && (t.text == "?" || t.text == "."))
    _ => false
  }
}

///|
fn run(args : Array[String]) -> Json raise WorkflowError {
  let usage = "catalog INPUT.cif | query INPUT.cif SCOPE.json | preview INPUT.cif PLAN.json | apply INPUT.cif PLAN.json NEW_OUTPUT.cif [--expect-result-sha256 SHA256] | append INPUT.cif ROW.json NEW_OUTPUT.cif [--expect-result-sha256 SHA256]"
  if args == ["--help"] {
    return { "ok": true, "usage": usage }
  }
  if args.length() == 2 && args[0] == "catalog" {
    return catalog_file(args[1])
  }
  if args.length() < 3 ||
    !((args[0] == "query" && args.length() == 3) ||
    (args[0] == "preview" && args.length() == 3) ||
    (
      (args[0] == "apply" || args[0] == "append") &&
      (
        args.length() == 4 ||
        (args.length() == 6 && args[4] == "--expect-result-sha256")
      )
    )) {
    raise Invalid(usage)
  }
  let input = host_result(host_read(args[1]))
  let source = string_field(input, "text")
  let source_hash = string_field(input, "sha256")
  let raw_plan = string_field(host_result(host_read(args[2])), "text")
  let plan_text = if raw_plan.has_prefix("\uFEFF") {
    raw_plan[1:].to_owned()
  } else {
    raw_plan
  }
  let plan = object(parse_json(plan_text))
  let report = @cif.parse_report(source)
  if !report.is_valid() {
    raise Invalid(
      "Invalid CIF: " +
      report.diagnostics.map(d => d.to_json()).to_json().stringify(),
    )
  }
  let file = report.file
  let block = string_field(plan, "block")
  let frame = optional_string(plan, "frame")
  if args[0] == "append" {
    return append_file(args, file, plan, source_hash, block, frame)
  }
  let id_tag = string_field(plan, "idTag")
  let _ = rows(file, block, [id_tag], frame)
  let source_bytes = @utf8.encode(source)
  if args[0] == "query" {
    let tags = [id_tag]
    match plan.get("columns") {
      None => ()
      Some(Json::Array(columns)) =>
        for column in columns {
          match column {
            Json::String(tag) => tags.push(tag)
            _ => raise Invalid("columns must contain strings")
          }
        }
      _ => raise Invalid("columns must be an array")
    }
    let projected = rows(file, block, tags, frame)
    let output : Array[Json] = []
    for row in projected {
      let cells : Array[Json] = []
      for value in row {
        cells.push(describe(value, source_bytes))
      }
      output.push(cells.to_json())
    }
    return {
      "ok": true,
      "sourceSha256": source_hash,
      "block": block,
      "frame": frame,
      "columns": tags.to_json(),
      "rows": output.to_json(),
    }
  }
  if string_field(plan, "sourceSha256") != source_hash {
    raise Invalid("sourceSha256 differs from the current input; query it again")
  }
  let requested = match plan.get("edits") {
    Some(Json::Array(edits)) => edits
    _ => raise Invalid("edits must be an array")
  }
  let edits : Array[(@cif.Value, String)] = []
  let receipt : Array[Json] = []
  for requested_edit in requested {
    let edit = object(requested_edit)
    let id = string_field(edit, "id")
    let tag = string_field(edit, "tag")
    let matching = rows(file, block, [id_tag, tag], frame).filter(row => {
      matches_id(row[0], id)
    })
    if matching.length() != 1 {
      raise Invalid("ID must identify exactly one row: " + id)
    }
    if edit.contains("cif") == edit.contains("text") {
      raise Invalid("Each edit requires exactly one of cif/text")
    }
    let replacement = if edit.contains("text") {
      checked(
        @cif.format_string(string_field(edit, "text"), version=file.version),
      )
    } else {
      string_field(edit, "cif")
    }
    let target = matching[0][1]
    edits.push((target, replacement))
    receipt.push({
      "id": id,
      "tag": tag,
      "original": describe(target, source_bytes),
      "replacement": replacement,
    })
  }
  let edited = checked(file.replace_values(edits))
  if args[0] == "preview" {
    let planned = host_result(host_text_identity(edited))
    return {
      "ok": true,
      "mode": "preview",
      "input": args[1],
      "block": block,
      "frame": frame,
      "idTag": id_tag,
      "sourceSha256": source_hash,
      "editCount": edits.length(),
      "edits": receipt.to_json(),
      "planned": planned.to_json(),
      "writesFiles": false,
    }
  }
  let disk = write_output(args, edited)
  {
    "ok": true,
    "input": args[1],
    "output": args[3],
    "sourceSha256": source_hash,
    "editCount": edits.length(),
    "edits": receipt.to_json(),
    "disk": disk,
  }
}

///|
fn main {
  let args = @env.args()
  println(run(args[2:].to_owned()).stringify()) catch {
    Invalid(message) => {
      let error : Json = { "ok": false, "error": message }
      println(error.stringify())
      fail_exit()
    }
  }
}
