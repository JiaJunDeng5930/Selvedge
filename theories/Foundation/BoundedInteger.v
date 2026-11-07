From Stdlib Require Import String Bool NArith ZArith DecimalString.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Programming Require Import Refinement.

Definition safe_integer_limit : Z := 9007199254740991%Z.
Definition within_safe_integer (value : Z) : bool :=
  ((- safe_integer_limit <=? value) && (value <=? safe_integer_limit))%Z.
Definition safe_integer := Refinement.checked within_safe_integer.
Definition integer_value (value : safe_integer) : Z := proj1_sig value.
Definition signed_magnitude (negative : bool) (magnitude : Z) :=
  if negative then (- magnitude)%Z else magnitude.
Definition exponent_digit_limit (lower upper : Z) : nat :=
  Nat.max (decimal_width (Decimal.abs (Z.to_int lower)))
          (decimal_width (Decimal.abs (Z.to_int upper))).
Definition parse_bounded_exponent (source : Decimal.int) (lower upper : Z) : option Z :=
  let normal := Decimal.norm source in
  (* DEFENSE: A wire exponent can contain an unbounded run of significant digits.
     Its decimal width is limited before conversion to an arbitrary-precision integer. *)
  if Nat.leb (decimal_width (Decimal.abs normal)) (exponent_digit_limit lower upper) then
    let value := Z.of_int normal in
    if ((lower <=? value) && (value <=? upper))%Z then Some value else None
  else None.
Definition decimal_zero (value : Decimal.uint) :=
  match Decimal.nzhead value with Decimal.Nil => true | _ => false end.
Definition integral_magnitude (coefficient : Decimal.uint) (shift : Z) : option Z :=
  if (shift <? 0)%Z then
    let remove := Z.to_nat (-shift) in
    if decimal_zero (Decimal.del_head (decimal_width coefficient - remove) coefficient)
    then Some (Z.of_uint (Decimal.del_tail remove coefficient)) else None
  else Some (Z.of_uint (Decimal.app coefficient (Nat.iter (Z.to_nat shift) Decimal.D0 Decimal.Nil))).
Definition coefficient_integer (capacity : nat) (negative : bool) (coefficient : Decimal.uint)
    (fraction_digits : nat) (exponent : Decimal.int) : option Z :=
  let significant := Decimal.nzhead coefficient in
  match significant with
  | Decimal.Nil => Some 0%Z
  | _ =>
      let fractional := Z.of_nat fraction_digits in
      let width := Z.of_nat (decimal_width significant) in
      match parse_bounded_exponent exponent (fractional + 1 - width) (fractional + Z.of_nat capacity - width) with
      | None => None
      | Some power => match integral_magnitude significant (power - fractional) with
        | None => None
        | Some magnitude => Some (signed_magnitude negative magnitude) end
      end
  end.
Definition decimal_components (value : Decimal.decimal) :=
  let '(whole,fraction,exponent) := match value with
    | Decimal.Decimal whole fraction => (whole,fraction,Decimal.Pos Decimal.Nil)
    | Decimal.DecimalExp whole fraction exponent => (whole,fraction,exponent) end in
  ((match whole with Decimal.Neg _ => true | _ => false end),
   Decimal.app (Decimal.abs whole) fraction, decimal_width fraction, exponent).
Definition decode_integer (capacity : nat) (source : string) : option Z :=
  match parse_decimal source with
  | Some decimal => let '(negative,coefficient,fraction,exponent) := decimal_components decimal in
    coefficient_integer capacity negative coefficient fraction exponent
  | None => None end.
Definition decode_safe_integer (source : string) : option safe_integer :=
  match decode_integer 16 source with
  | Some value => Refinement.admit within_safe_integer value
  | None => None end.
Definition decode_natural (capacity : nat) (source : string) : option N :=
  match decode_integer capacity source with
  | Some value => if (value <? 0)%Z then None else Some (Z.to_N value)
  | None => None end.
Definition unbounded_integer_capacity (source : string) : nat :=
  (* KNOWN LIMITATION: A short exponent can request astronomical allocation.
     Noncanonical unbounded inputs expand to at most 4096 or their input length
     decimal digits, whichever is larger. Canonical integers stay unrestricted. *)
  Nat.max 4096 (String.length source).
Definition decode_unbounded_natural (source : string) : option N :=
  (* Internal roundtrips and ordinary integer inputs take the direct digit path;
     decimal and exponent forms share the exact conversion used by bounded fields. *)
  match parse_natural source with
  | Some value => Some value
  | None => decode_natural (unbounded_integer_capacity source) source end.
Definition decode_unbounded_integer (source : string) : option Z :=
  match parse_integer source with
  | Some value => Some value
  | None => decode_integer (unbounded_integer_capacity source) source end.
