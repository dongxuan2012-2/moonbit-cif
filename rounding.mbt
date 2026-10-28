///|
/// Exact binary64 fraction for decimal formatting, not a measurement propagation engine.
fn binary_fraction(x : Double) -> (@bigint.BigInt, @bigint.BigInt) {
  let bits = x.abs().reinterpret_as_uint64()
  let exponent = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFUL
  let mantissa = if exponent == 0 {
    fraction
  } else {
    fraction + 0x10000000000000UL
  }
  let shift = if exponent == 0 { -1074 } else { exponent - 1075 }
  let n = @bigint.BigInt::from_uint64(mantissa)
  let one = @bigint.BigInt::from_int(1)
  if shift >= 0 {
    (n << shift, one)
  } else {
    (n, one << -shift)
  }
}

///|
fn pow10_integer(exponent : Int) -> @bigint.BigInt {
  @bigint.BigInt::from_int(10).pow(@bigint.BigInt::from_int(exponent))
}

///|
fn decimal_fraction(
  x : Double,
  places : Int,
) -> (@bigint.BigInt, @bigint.BigInt) {
  let (n, d) = binary_fraction(x)
  if places >= 0 {
    (n * pow10_integer(places), d)
  } else {
    (n, d * pow10_integer(-places))
  }
}

///|
/// No floating-point add/divide before deciding the rounding side of a tie.
fn round_decimal_abs(x : Double, places : Int) -> @bigint.BigInt {
  let (n, d) = decimal_fraction(x, places)
  let q = n / d
  if n % d * @bigint.BigInt::from_int(2) >= d {
    q + @bigint.BigInt::from_int(1)
  } else {
    q
  }
}

///|
fn decimal_order(x : Double) -> Int {
  let mut scaled = x
  let mut order = 0
  while scaled >= 10.0 {
    scaled /= 10.0
    order += 1
  }
  while scaled < 1.0 {
    scaled *= 10.0
    order -= 1
  }
  // Correct the estimate without allowing repeated binary divisions to choose a decimal decade.
  while true {
    let (n, d) = decimal_fraction(x, -order)
    if n < d {
      order -= 1
    } else if n >= d * @bigint.BigInt::from_int(10) {
      order += 1
    } else {
      break
    }
  }
  order
}
