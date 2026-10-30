From Stdlib Require Import String Ascii Bool NArith ZArith DecimalString.
From Selvedge.Foundation Require Import Numbers.
Open Scope string_scope.

(* JSON wire integers denote mathematical values. Domain natural keys retain
   their separate canonical-token contract in Numbers/Json. *)
Definition safe_integer_limit : Z := 9007199254740991%Z.
Definition within_safe_integer (value : Z) : bool :=
  ((- safe_integer_limit <=? value) && (value <=? safe_integer_limit))%Z.

Fixpoint without_leading_zeroes (source : string) : string :=
  match source with
  | String c rest => if Ascii.eqb c "0" then without_leading_zeroes rest else source
  | EmptyString => EmptyString
  end.
Definition take_digits (source : string) : string * string :=
  let remaining := skip_digits source in
  (substring 0 (String.length source - String.length remaining) source, remaining).
Definition unsigned_text (source : string) : bool * string :=
  match source with
  | String c rest =>
      if Ascii.eqb c "-" then (true,rest)
      else if Ascii.eqb c "+" then (false,rest)
      else (false,source)
  | _ => (false,source)
  end.
Definition normalized_decimal (source : string) : bool * string :=
  let '(negative,digits) := unsigned_text source in
  let magnitude := without_leading_zeroes digits in
  match magnitude with
  | EmptyString => (false,"0")
  | _ => (negative,magnitude)
  end.
Definition parse_signed_digits (negative : bool) (digits : string) : option Z :=
  option_map (fun numeral => Z.of_int (if negative then Decimal.Neg numeral else Decimal.Pos numeral))
    (NilZero.uint_of_string digits).
Definition exponent_digit_limit (lower upper : Z) : nat :=
  Nat.max (String.length (snd (normalized_decimal (show_integer lower))))
          (String.length (snd (normalized_decimal (show_integer upper)))).
Definition parse_bounded_exponent (source : string) (lower upper : Z) : option Z :=
  let '(negative,magnitude) := normalized_decimal source in
  (* DEFENSE: A wire exponent may contain arbitrarily many significant digits.
     Endpoint widths bound parsing work before the standard integer conversion. *)
  if Nat.leb (String.length magnitude) (exponent_digit_limit lower upper) then
    match parse_signed_digits negative magnitude with
    | Some value => if ((lower <=? value) && (value <=? upper))%Z then Some value else None
    | None => None end
  else None.
Fixpoint zeroes (count : nat) : string :=
  match count with O => EmptyString | S rest => String "0" (zeroes rest) end.
Fixpoint only_zeroes (source : string) : bool :=
  match source with
  | EmptyString => true
  | String c rest => if Ascii.eqb c "0" then only_zeroes rest else false
  end.
Definition integral_digits (coefficient : string) (shift : Z) : option string :=
  if (shift <? 0)%Z then
    let keep := (String.length coefficient - Z.to_nat (-shift))%nat in
    let suffix := substring keep (String.length coefficient) coefficient in
    if only_zeroes suffix then
      Some (substring 0 keep coefficient)
    else None
  else Some (coefficient ++ zeroes (Z.to_nat shift)).
Definition decode_coefficient (negative : bool) (coefficient : string)
    (fraction_digits : nat) (exponent : string) : option Z :=
  let significant := without_leading_zeroes coefficient in
  match significant with
  | EmptyString => Some 0%Z
  | _ =>
      let fractional := Z.of_nat fraction_digits in
      let width := Z.of_nat (String.length significant) in
      match parse_bounded_exponent exponent (fractional + 1 - width) (fractional + 16 - width) with
      | None => None
      | Some power =>
          match integral_digits significant (power - fractional) with
          | None => None
          | Some digits =>
              match parse_signed_digits negative digits with
              | Some value => if within_safe_integer value then Some value else None
              | None => None
              end
          end
      end
  end.
Definition decode_safe_integer (source : string) : option Z :=
  (* DEFENSE: JsonNumber is externally constructible, so its token must satisfy
     JSON grammar before the mathematical-value decoder is entered. *)
  if number_lexeme source then
    let '(negative,unsigned) := unsigned_text source in
    let '(whole,rest) := take_digits unsigned in
    let '(fraction,after_fraction) :=
      match rest with
      | String c digits => if Ascii.eqb c "." then take_digits digits else ("",rest)
      | _ => ("",rest)
      end in
    let exponent := match after_fraction with String _ digits => digits | _ => "0" end in
    decode_coefficient negative (whole ++ fraction) (String.length fraction) exponent
  else None.
