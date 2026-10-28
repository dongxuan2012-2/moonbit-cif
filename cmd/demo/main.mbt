///|
fn main {
  let source = "#\\#CIF_2.0\ndata_lab\n_length 1.5423(12) # keep this note\n_labels [ 'Ti' 'O' ]\n"
  let file = @cif.parse_string(source).unwrap()
  let value = file.find("lab", "_length").unwrap()
  let measured = value.measurement().unwrap()
  println("Original: " + measured.to_cif_string())
  println("Standard uncertainty: " + measured.uncertainty.unwrap().to_string())
  let formatted = @cif.format_su(1.6, 0.002).unwrap()
  println(file.replace_value(value, formatted).unwrap())
}
