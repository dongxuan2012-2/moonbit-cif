///|
fn doubled(value : @cif.Value) -> String {
  let number = value.measurement().unwrap()
  // The example's *_m fields deliberately declare metres; no dictionary unit is inferred.
  let measured = @measure.MeasuredQuantity::checked_from_parts(
    number.value.unwrap(),
    number.uncertainty.unwrap(),
    @si.meter,
  ).unwrap()
  let result = measured.scale(2.0)
  @cif.format_su(result.value(), result.uncertainty()).unwrap()
}

///|
fn main raise {
  let source = "data_batch\n# keep lab notebook comment\n_operator 'reader'\n_calibration_m 1.5423(12)\nloop_\n_sample_id\n_length_m\nA 1.5423(12) # row A\nB 2.10(3)\nC ?\nD 4.200\n"
  let file = @cif.parse_string(source).unwrap()
  let edits : Array[(@cif.Value, String)] = []
  for value in file.find_values("BATCH", "_LENGTH_M") {
    let number = value.measurement().unwrap()
    // Query keeps original Values; the caller still chooses which measurements to calculate.
    if !number.is_unknown &&
      !number.is_inapplicable &&
      number.uncertainty_digits is Some(_) {
      edits.push((value, doubled(value)))
    }
  }
  let calibration = file.find("batch", "_calibration_m").unwrap()
  edits.push((calibration, doubled(calibration)))
  let edited = file.replace_values(edits).unwrap()
  assert_eq(
    edited, "data_batch\n# keep lab notebook comment\n_operator 'reader'\n_calibration_m 3.0846(24)\nloop_\n_sample_id\n_length_m\nA 3.0846(24) # row A\nB 4.200(60)\nC ?\nD 4.200\n",
  )
  assert_eq(file.rewrite_original(), source)
  println(edited)
}
