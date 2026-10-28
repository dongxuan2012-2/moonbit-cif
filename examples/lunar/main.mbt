///|
struct Sink {
  mut result : @measure.MeasuredQuantity?
}

///|
impl @cif.UncertaintySink for Sink with fn accept(self, value, uncertainty) {
  // A CIF number has no unit metadata here; caller deliberately chooses metres.
  // Missing su is not silently treated as zero uncertainty.
  self.result = match uncertainty {
    Some(u) =>
      @measure.MeasuredQuantity::checked_from_parts(value, u, @si.meter)
    None => None
  }
}

///|
fn main raise {
  let file = @cif.parse_string("data_input\n_length 1.5423(12)\n").unwrap()
  let token = file.find("input", "_length").unwrap()
  let sink : Sink = { result: None, }
  token.measurement().unwrap().send_to(sink).unwrap()
  let measured = sink.result.unwrap()
  let doubled = measured.scale(2.0)
  assert_eq(doubled.value(), 3.0846)
  assert_eq(doubled.uncertainty(), 0.0024)
  let result = @cif.format_su(doubled.value(), doubled.uncertainty()).unwrap()
  println(file.replace_value(token, result).unwrap())
}
