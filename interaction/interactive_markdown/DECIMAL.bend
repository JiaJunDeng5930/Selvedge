import Base

# NOTE: Decimal magnitudes are digit strings because scaled values and products
# exceed Base Nat's native 48-bit range. Every digit operation stays below 100.
def bool_equal(left: Bool, right: Bool) -> Bool:
  Bool.not(Bool.xor(left, right))

type Decimal is Data:
  Decimal{negative: Bool, magnitude: String}

def trim_zero(text: String) -> String:
  match text:
    case SCon{'0', rest}: trim_zero(rest)
    case rest: rest

def nonempty(text: String) -> String:
  match text:
    case SNil{}: "0"
    case rest: rest

def normalize(text: String) -> String:
  nonempty(trim_zero(text))

def magnitude_order_same(order: Cmp, left: String, right: String) -> Cmp:
  match order:
    case EQ{}: String.order(left, right)
    case other: other

def magnitude_order(+left: String, +right: String) -> Cmp:
  magnitude_order_same(Nat.cmp(String.length(left), String.length(right)), left, right)

def digit(char: Char) -> U32:
  U32.sub(Char.to_u32(char), 48)

def digit_char(value: U32) -> Char:
  Chr{U32.add(48, value)}

def add_digits(left: String, right: String, carry: U32) -> String:
  match left right:
    case SNil{} SNil{}:
      match carry:
        case 0: ""
        case n: SCon{digit_char(n), ""}
    case SCon{a, rest} SNil{}:
      +sum = U32.add(digit(a), carry)
      SCon{digit_char(U32.mod(sum, 10)), add_digits(rest, "", U32.div(sum, 10))}
    case SNil{} SCon{b, rest}:
      +sum = U32.add(digit(b), carry)
      SCon{digit_char(U32.mod(sum, 10)), add_digits("", rest, U32.div(sum, 10))}
    case SCon{a, ar} SCon{b, br}:
      +sum = U32.add(U32.add(digit(a), digit(b)), carry)
      SCon{digit_char(U32.mod(sum, 10)), add_digits(ar, br, U32.div(sum, 10))}

def magnitude_add(left: String, right: String) -> String:
  normalize(String.reverse(add_digits(String.reverse(left), String.reverse(right), 0)))

def subtract_digits(left: String, right: String, borrow: U32) -> String:
  match left right:
    case SNil{} _: ""
    case SCon{a, ar} SNil{}:
      +raw = U32.sub(U32.add(digit(a), 10), borrow)
      SCon{digit_char(U32.mod(raw, 10)), subtract_digits(ar, "", Bool.to_u32(U32.is_lt(raw, 10)))}
    case SCon{a, ar} SCon{b, br}:
      +raw = U32.sub(U32.sub(U32.add(digit(a), 10), digit(b)), borrow)
      SCon{digit_char(U32.mod(raw, 10)), subtract_digits(ar, br, Bool.to_u32(U32.is_lt(raw, 10)))}

def magnitude_subtract(left: String, right: String) -> String:
  normalize(String.reverse(subtract_digits(String.reverse(left), String.reverse(right), 0)))

def multiply_digit_go(left: String, +factor: U32, carry: U32) -> String:
  match left:
    case SNil{}:
      match carry:
        case 0: ""
        case n: SCon{digit_char(n), ""}
    case SCon{a, rest}:
      +raw = U32.add(U32.mul(digit(a), factor), carry)
      SCon{digit_char(U32.mod(raw, 10)), multiply_digit_go(rest, factor, U32.div(raw, 10))}

def multiply_digit(left: String, factor: U32) -> String:
  normalize(String.reverse(multiply_digit_go(String.reverse(left), factor, 0)))

def multiply_go(right: String, +left: String, suffix: String, accumulator: String) -> String:
  match right:
    case SNil{}: accumulator
    case SCon{d, rest}:
      +zeros = suffix
      multiply_go(rest, left, "0" ++ zeros, magnitude_add(accumulator, multiply_digit(left, digit(d)) ++ zeros))

def magnitude_multiply(left: String, right: String) -> String:
  multiply_go(String.reverse(right), left, "", "0")

type DigitDivision is Data:
  DigitDivision{digit: U32, remainder: String}

def quotient_digit(fuel: Nat, +divisor: String, +remainder: String, +quotient: U32) -> DigitDivision:
  match fuel:
    case 0n: DigitDivision{quotient, remainder}
    case 1n+rest:
      Bool.pick(DigitDivision, Cmp.is_lt(magnitude_order(remainder, divisor)),
        DigitDivision{quotient, remainder},
        quotient_digit(rest, divisor, magnitude_subtract(remainder, divisor), U32.add(quotient, 1)))

def division_digit(division: DigitDivision) -> U32:
  match division:
    case DigitDivision{d, remainder}: d

def division_remainder(division: DigitDivision) -> String:
  match division:
    case DigitDivision{d, remainder}: remainder

def divide_go(dividend: String, +divisor: String, quotient: String, remainder: String) -> String & String:
  match dividend:
    case SNil{}: (normalize(quotient), remainder)
    case SCon{d, rest}:
      +division = quotient_digit(10n, divisor, normalize(remainder ++ SCon{d, ""}), 0)
      divide_go(rest, divisor, quotient ++ SCon{digit_char(division_digit(division)), ""}, division_remainder(division))

def magnitude_divide(dividend: String, divisor: String) -> String & String:
  divide_go(dividend, divisor, "", "0")

def rounded_increment(+quotient: String, order: Cmp) -> String:
  match order:
    case LT{}: quotient
    case _: magnitude_add(quotient, "1")

def rounded_division_finish(+denominator: String, division: String & String) -> String:
  (+quotient, remainder) = division
  rounded_increment(quotient, magnitude_order(magnitude_multiply(remainder, "2"), denominator))

def rounded_division(numerator: String, +denominator: String) -> String:
  rounded_division_finish(denominator, magnitude_divide(numerator, denominator))

def zeros(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+rest: "0" ++ zeros(rest)

def valid_digits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{d, rest}: Char.is_digit(d) && valid_digits(rest)

def split_dot(text: String, whole: String) -> String & String:
  match text:
    case SNil{}: (whole, "")
    case SCon{'.', rest}: (whole, rest)
    case SCon{d, rest}: split_dot(rest, whole ++ SCon{d, ""})

def valid_whole(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'0', SNil{}}: True{}
    case SCon{'0', rest}: False{}
    case rest: valid_digits(rest)

def checked_order(negative: Bool, +magnitude: String, order: Cmp) -> Result<&2, &2, String, Decimal>:
  match order:
    case GT{}: Fail{"decimal overflow"}
    case _:
      Done{Decimal{negative && Bool.not(String.eq(magnitude, "0")), magnitude}}

def checked_decimal(negative: Bool, +magnitude: String) -> Result<&2, &2, String, Decimal>:
  checked_order(negative, magnitude, magnitude_order(magnitude, "1000000000000000"))

def parsed_parts(negative: Bool, +whole: String, +fraction: String, valid: Bool) -> Result<&2, &2, String, Decimal>:
  match valid:
    case False{}: Fail{"invalid fixed decimal"}
    case True{}:
      checked_decimal(negative, normalize(whole ++ fraction ++ zeros(Nat.sub(6n, String.length(fraction)))))

def parse_parts(negative: Bool, parts: String & String) -> Result<&2, &2, String, Decimal>:
  (+whole, +fraction) = parts
  parsed_parts(negative, whole, fraction, valid_whole(whole) && valid_digits(fraction) && Nat.is_le(String.length(fraction), 6n))

def read_unchecked(text: String) -> Result<&2, &2, String, Decimal>:
  match text:
    case SCon{'-', rest}: parse_parts(True{}, split_dot(rest, ""))
    case rest: parse_parts(False{}, split_dot(rest, ""))

def spelling_within_limit(fuel: Nat, text: String) -> Bool:
  match fuel text:
    case _ SNil{}: True{}
    case 0n _: False{}
    case 1n+remaining SCon{char, rest}: spelling_within_limit(remaining, rest)

def read_admitted(+text: String, allowed: Bool) -> Result<&2, &2, String, Decimal>:
  match allowed:
    case False{}: Fail{"invalid fixed decimal: spelling exceeds 18 characters"}
    case True{}:
      Bool.pick((Result<&2, &2, String, Decimal>), String.ends_with(text, "."),
        Fail{"decimal point requires fractional digits"}, read_unchecked(text))

def read(+text: String) -> Result<&2, &2, String, Decimal>:
  # No valid spelling exceeds -1000000000.000000. Reject impossible long raw
  # input before digit validation or constructor recursion in the numeric parser.
  read_admitted(text, spelling_within_limit(18n, text))

def trim_fraction(text: String) -> String:
  String.reverse(trim_zero(String.reverse(text)))

def signed_text(negative: Bool, value: String) -> String:
  match negative:
    case True{}: "-" ++ value
    case False{}: value

def show_parts(negative: Bool, whole: String, fraction: String) -> String:
  match fraction:
    case SNil{}: signed_text(negative, whole)
    case rest: signed_text(negative, whole ++ "." ++ rest)

def show(value: Decimal) -> String:
  match value:
    case Decimal{negative, +magnitude}:
      +padded = zeros(Nat.sub(7n, String.length(magnitude))) ++ magnitude
      +whole_count = Nat.sub(String.length(padded), 6n)
      show_parts(negative, String.take(padded, whole_count), trim_fraction(String.drop(padded, whole_count)))

def parse_result(result: Result<&2, &2, String, Decimal>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{show(value)}

def parse(text: String) -> Result<&2, &2, String, String>:
  parse_result(read(text))

def negate(value: Decimal) -> Decimal:
  match value:
    case Decimal{negative, +magnitude}: Decimal{Bool.not(negative) && Bool.not(String.eq(magnitude, "0")), magnitude}

def add_different(negative: Bool, +left: String, +right: String, order: Cmp) -> Result<&2, &2, String, Decimal>:
  match order:
    case EQ{}: Done{Decimal{False{}, "0"}}
    case GT{}: checked_decimal(negative, magnitude_subtract(left, right))
    case LT{}: checked_decimal(Bool.not(negative), magnitude_subtract(right, left))

def add_signed(ln: Bool, +lm: String, +rm: String, same: Bool) -> Result<&2, &2, String, Decimal>:
  match same:
    case True{}: checked_decimal(ln, magnitude_add(lm, rm))
    case False{}: add_different(ln, lm, rm, magnitude_order(lm, rm))

def add(left: Decimal, right: Decimal) -> Result<&2, &2, String, Decimal>:
  match left right:
    case Decimal{+ln, +lm} Decimal{rn, +rm}:
      add_signed(ln, lm, rm, bool_equal(ln, rn))

def integral_division(division: String & String) -> Bool:
  (whole, remainder) = division
  String.eq(remainder, "0")

def integral_magnitude(magnitude: String) -> Bool:
  integral_division(magnitude_divide(magnitude, "1000000"))

# NOTE: A step distance may reach 2e9, so its scaled magnitude bypasses checked_decimal.
def step_difference(+left: String, +right: String, order: Cmp) -> String:
  match order:
    case EQ{}: "0"
    case GT{}: magnitude_subtract(left, right)
    case LT{}: magnitude_subtract(right, left)

def step_distance(value: Decimal, anchor: Decimal) -> String:
  match value anchor:
    case Decimal{False{}, left} Decimal{True{}, right}: magnitude_add(left, right)
    case Decimal{True{}, left} Decimal{False{}, right}: magnitude_add(left, right)
    case Decimal{negative, +left} Decimal{other_negative, +right}:
      step_difference(left, right, magnitude_order(left, right))

def step_nonzero(value: Decimal, anchor: Decimal, magnitude: String, zero: Bool) -> Bool:
  match zero:
    case True{}: False{}
    case False{}: integral_division(magnitude_divide(step_distance(value, anchor), magnitude))

def step_results(value: Result<&2, &2, String, Decimal>, anchor: Result<&2, &2, String, Decimal>, step: Result<&2, &2, String, Decimal>) -> Bool:
  match value anchor step:
    case Done{current} Done{origin} Done{Decimal{False{}, +magnitude}}:
      step_nonzero(current, origin, magnitude, String.eq(magnitude, "0"))
    case _ _ _: False{}

def step_matches(value: String, anchor: String, step: String) -> Bool:
  step_results(read(value), read(anchor), read(step))

def divide_checked(negative: Bool, lm: String, rm: String, zero: Bool) -> Result<&2, &2, String, Decimal>:
  match zero:
    case True{}: Fail{"division by zero"}
    case False{}: checked_decimal(negative, rounded_division(lm ++ "000000", rm))

def remainder_value(negative: Bool, division: String & String) -> Result<&2, &2, String, Decimal>:
  (quotient, remainder) = division
  checked_decimal(negative, remainder)

def remainder_checked(negative: Bool, lm: String, rm: String, valid: Bool) -> Result<&2, &2, String, Decimal>:
  match valid:
    case False{}: Fail{"remainder requires integers and nonzero divisor"}
    case True{}:
      remainder_value(negative, magnitude_divide(lm, rm))

def operate(op: String, left: Decimal, right: Decimal) -> Result<&2, &2, String, Decimal>:
  match op left right:
    case "+" l r: add(l, r)
    case "-" l r: add(l, negate(r))
    case "*" Decimal{ln, lm} Decimal{rn, rm}:
      checked_decimal(Bool.not(bool_equal(ln, rn)), rounded_division(magnitude_multiply(lm, rm), "1000000"))
    case "/" Decimal{ln, lm} Decimal{rn, +rm}:
      divide_checked(Bool.not(bool_equal(ln, rn)), lm, rm, String.eq(rm, "0"))
    case "%" Decimal{ln, +lm} Decimal{rn, +rm}:
      remainder_checked(ln, lm, rm, integral_magnitude(lm) && integral_magnitude(rm) && Bool.not(String.eq(rm, "0")))
    case _ _ _: Fail{"unknown decimal operation"}

def arithmetic_results(op: String, left: Result<&2, &2, String, Decimal>, right: Result<&2, &2, String, Decimal>) -> Result<&2, &2, String, String>:
  match left right:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{l} Done{r}: parse_result(operate(op, l, r))

def arithmetic(op: String, left: String, right: String) -> Result<&2, &2, String, String>:
  arithmetic_results(op, read(left), read(right))

def reverse_order(order: Cmp) -> Cmp:
  match order:
    case LT{}: GT{}
    case EQ{}: EQ{}
    case GT{}: LT{}

def decimal_order(left: Decimal, right: Decimal) -> Cmp:
  match left right:
    case Decimal{False{}, lm} Decimal{True{}, rm}: GT{}
    case Decimal{True{}, lm} Decimal{False{}, rm}: LT{}
    case Decimal{False{}, lm} Decimal{False{}, rm}: magnitude_order(lm, rm)
    case Decimal{True{}, lm} Decimal{True{}, rm}: reverse_order(magnitude_order(lm, rm))

def compare_order(op: String, +order: Cmp) -> Result<&2, &2, String, Bool>:
  match op:
    case "<": Done{Cmp.is_lt(order)}
    case "<=": Done{Cmp.is_le(order)}
    case ">": Done{Cmp.is_gt(order)}
    case ">=": Done{Cmp.is_ge(order)}
    case "==": Done{Cmp.is_eq(order)}
    case "!=": Done{Bool.not(Cmp.is_eq(order))}
    case _: Fail{"unknown decimal comparison"}

def compare_results(op: String, left: Result<&2, &2, String, Decimal>, right: Result<&2, &2, String, Decimal>) -> Result<&2, &2, String, Bool>:
  match left right:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{l} Done{r}: compare_order(op, decimal_order(l, r))

def compare(op: String, left: String, right: String) -> Result<&2, &2, String, Bool>:
  compare_results(op, read(left), read(right))

def integral_result(result: Result<&2, &2, String, Decimal>) -> Bool:
  match result:
    case Fail{error}: False{}
    case Done{Decimal{negative, magnitude}}: integral_magnitude(magnitude)

def integral(number: String) -> Bool:
  integral_result(read(number))

def round_checked(negative: Bool, magnitude: String, places: Nat, valid: Bool) -> Result<&2, &2, String, Decimal>:
  match valid:
    case False{}: Fail{"round precision must be 0..6"}
    case True{}:
      +suffix = zeros(Nat.sub(6n, places))
      checked_decimal(negative, normalize(rounded_division(magnitude, "1" ++ suffix) ++ suffix))

def round_decimal(value: Decimal, +places: Nat) -> Result<&2, &2, String, Decimal>:
  match value:
    case Decimal{negative, magnitude}:
      round_checked(negative, magnitude, places, Nat.is_le(places, 6n))

def round_result(result: Result<&2, &2, String, Decimal>, places: Nat) -> Result<&2, &2, String, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: parse_result(round_decimal(value, places))

def round(number: String, places: Nat) -> Result<&2, &2, String, String>:
  round_result(read(number), places)

def group_digits(text: String, remaining: Nat) -> String:
  match text:
    case SNil{}: ""
    case SCon{d, rest}:
      match remaining:
        case 0n: "," ++ SCon{d, group_digits(rest, 2n)}
        case 1n+left: SCon{d, group_digits(rest, left)}

def group_whole(+text: String) -> String:
  String.reverse(group_digits(String.reverse(text), 3n))

def formatted_parts(negative: Bool, whole: String, fraction: String, prefix: String, suffix: String) -> String:
  signed_text(negative, prefix ++ group_whole(whole) ++ fraction ++ suffix)

def format_fraction(negative: Bool, whole: String, fraction: String, suffix: String) -> Result<&2, &2, String, String>:
  match fraction:
    case SNil{}: Done{formatted_parts(negative, whole, "", "", suffix)}
    case rest: Done{formatted_parts(negative, whole, "." ++ rest, "", suffix)}

def decimal_format(value: Decimal, style: String) -> Result<&2, &2, String, String>:
  match value style:
    case Decimal{negative, +magnitude} "number":
      +padded = zeros(Nat.sub(7n, String.length(magnitude))) ++ magnitude
      +whole_count = Nat.sub(String.length(padded), 6n)
      +fraction = trim_fraction(String.drop(padded, whole_count))
      format_fraction(negative, String.take(padded, whole_count), fraction, "")
    case Decimal{negative, magnitude} "percent":
      +hundred = normalize(magnitude ++ "00")
      +padded = zeros(Nat.sub(7n, String.length(hundred))) ++ hundred
      +whole_count = Nat.sub(String.length(padded), 6n)
      +fraction = trim_fraction(String.drop(padded, whole_count))
      format_fraction(negative, String.take(padded, whole_count), fraction, "%")
    case Decimal{negative, magnitude} "currency:USD":
      +cents = rounded_division(magnitude, "10000")
      +padded = zeros(Nat.sub(3n, String.length(cents))) ++ cents
      +whole_count = Nat.sub(String.length(padded), 2n)
      Done{formatted_parts(negative, String.take(padded, whole_count), "." ++ String.drop(padded, whole_count), "$", "")}
    case Decimal{negative, magnitude} "currency:CNY":
      +cents = rounded_division(magnitude, "10000")
      +padded = zeros(Nat.sub(3n, String.length(cents))) ++ cents
      +whole_count = Nat.sub(String.length(padded), 2n)
      Done{formatted_parts(negative, String.take(padded, whole_count), "." ++ String.drop(padded, whole_count), "¥", "")}
    case _ _: Fail{"unknown number format"}

def format_result(result: Result<&2, &2, String, Decimal>, style: String) -> Result<&2, &2, String, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: decimal_format(value, style)

def format(number: String, style: String) -> Result<&2, &2, String, String>:
  format_result(read(number), style)
