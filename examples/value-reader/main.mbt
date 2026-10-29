///|
/// Bind the actual JSON delivery to the complete physical CIF and every span.
extern "js" fn bound_delivery(
  source_path : String,
  json_path : String,
) -> String =
  #| (sourcePath, jsonPath) => {
  #|   const fs = process.getBuiltinModule('fs');
  #|   const source = fs.readFileSync(sourcePath);
  #|   new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(source);
  #|   const text = new TextDecoder('utf-8', { fatal: true }).decode(fs.readFileSync(jsonPath));
  #|   const delivery = JSON.parse(text);
  #|   const hash = process.getBuiltinModule('crypto').createHash('sha256').update(source).digest('hex');
  #|   if (hash !== delivery.sourceSha256) throw new Error('Source SHA256 differs from delivered values');
  #|   if (delivery.ok !== true || delivery.mode !== 'values' || delivery.writesFiles !== false) throw new Error('Expected read-only values delivery');
  #|   for (const group of delivery.selections) for (const value of group.values) {
  #|     const { start_offset: start, end_offset: end } = value.span;
  #|     if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || end > source.length ||
  #|         !source.subarray(start, end).equals(Buffer.from(value.literal, 'utf8'))) throw new Error('Delivered literal span differs from physical source');
  #|   }
  #|   return text;
  #| }

///|
struct Sink {
  mut result : @measure.MeasuredQuantity?
}

///|
impl @cif.UncertaintySink for Sink with fn accept(self, value, uncertainty) {
  // This recipient's caller chooses metres, including for the sample loop field.
  self.result = match uncertainty {
    Some(u) =>
      @measure.MeasuredQuantity::checked_from_parts(value, u, @si.meter)
    None => None
  }
}

///|
fn object(value : Json) -> Map[String, Json] {
  match value {
    Json::Object(fields) => fields
    _ => abort("Expected object in values delivery")
  }
}

///|
fn array(value : Json) -> Array[Json] {
  match value {
    Json::Array(items) => items
    _ => abort("Expected array in values delivery")
  }
}

///|
fn string(value : Json) -> String {
  match value {
    Json::String(text) => text
    _ => abort("Expected string in values delivery")
  }
}

///|
fn main raise {
  let args = @env.args()
  assert_eq(args[4], "metre")
  let text = bound_delivery(args[2], args[3])
  let delivery = object(@json.parse(text[:]))
  let groups = array(delivery.get("selections").unwrap())
  let version = string(delivery.get("version").unwrap())
  let header = if version == "CIF2.0" { "#\\#CIF_2.0\n" } else { "" }
  let accepted : Array[Json] = []
  let rejected : Array[Json] = []
  for selection in groups {
    let group = object(selection)
    let tag = string(group.get("tag").unwrap())
    for description in array(group.get("values").unwrap()) {
      let item = object(description)
      let literal = string(item.get("literal").unwrap())
      let parsed = @cif.parse_string(
        header + "data_received\n_v\n" + literal + "\n",
      ).unwrap()
      let value = parsed.find("received", "_v").unwrap()
      assert_eq(value.to_json(), item.get("value").unwrap())
      let kind = match value {
        @cif.Scalar(token) =>
          if token.kind == @cif.Word {
            "word"
          } else {
            "string"
          }
        @cif.List(_, _) => "list"
        @cif.Table(_, _) => "table"
      }
      assert_eq(Json::string(kind), item.get("kind").unwrap())
      let sink : Sink = { result: None, }
      let sent = match value.measurement() {
        Ok(measured) => measured.send_to(sink) is Ok(_)
        Err(_) => false
      }
      if sent && sink.result is Some(quantity) {
        accepted.push({
          "tag": tag,
          "literal": literal,
          "value": quantity.value(),
          "uncertainty": quantity.uncertainty(),
        })
      } else {
        rejected.push({ "tag": tag, "literal": literal, "kind": kind })
      }
    }
  }
  let output : Json = {
    "ok": true,
    "sourceSha256": delivery.get("sourceSha256").unwrap(),
    "groupsReceived": groups.length(),
    "accepted": accepted.to_json(),
    "rejected": rejected.to_json(),
    "realLunar": true,
    "unitPolicy": "metre explicitly chosen by caller",
  }
  println(output.stringify())
}
