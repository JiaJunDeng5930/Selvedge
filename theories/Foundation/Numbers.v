From Stdlib Require Import String Ascii Bool NArith ZArith DecimalString.
Open Scope string_scope.

(* Keep moderate natural literals compact through extraction. With the default
   threshold, 4096 becomes thousands of nested successors and overflows the
   JavaScript parser before the extracted program can start. *)
Number Notation nat Init.Nat.of_num_uint Init.Nat.to_num_uint (abstract after 32) : nat_scope.

Definition is_digit (c : ascii) : bool :=
  let n := nat_of_ascii c in (48 <=? n)%nat && (n <=? 57)%nat.

(** The JSON number language retains decimal digits until a consumer chooses a
    bounded numerical interpretation. Opaque JSON continues to keep its token. *)
Fixpoint decimal_digits_acc (source : string) (reversed : Decimal.uint) : Decimal.uint * string :=
  match source with
  | EmptyString => (Decimal.rev reversed, EmptyString)
  | String head rest => match uint_of_char head (Some reversed) with
    | Some next => decimal_digits_acc rest next
    | None => (Decimal.rev reversed, source) end
  end.
Fixpoint decimal_width_acc (digits : Decimal.uint) (count : nat) : nat :=
  match digits with
  | Decimal.Nil => count
  | Decimal.D0 rest | Decimal.D1 rest | Decimal.D2 rest | Decimal.D3 rest | Decimal.D4 rest
  | Decimal.D5 rest | Decimal.D6 rest | Decimal.D7 rest | Decimal.D8 rest | Decimal.D9 rest =>
    decimal_width_acc rest (S count) end.
Definition decimal_width digits := decimal_width_acc digits O.
Definition decimal_digits source := decimal_digits_acc source Decimal.Nil.
Definition required_decimal_digits source :=
  match decimal_digits source with (Decimal.Nil, _) => None | parsed => Some parsed end.
Definition decimal_integer source := match source with
  | String head rest => if Ascii.eqb head "0" then Some (Decimal.D0 Decimal.Nil,rest)
    else required_decimal_digits source
  | _ => None end.
Definition decimal_fraction source := match source with
  | String head rest => if Ascii.eqb head "." then required_decimal_digits rest
    else Some (Decimal.Nil,source)
  | _ => Some (Decimal.Nil,source) end.
Definition decimal_exponent source := match source with
  | EmptyString => Some None
  | String head rest => if Ascii.eqb head "e" || Ascii.eqb head "E" then
    let '(negative,digits) := match rest with
      | String sign tail => if Ascii.eqb sign "-" then (true,tail)
        else if Ascii.eqb sign "+" then (false,tail) else (false,rest)
      | _ => (false,rest) end in
    match required_decimal_digits digits with
    | Some (value,EmptyString) => Some (Some (if negative then Decimal.Neg value else Decimal.Pos value))
    | _ => None end
    else None
  end.
Definition parse_decimal source : option Decimal.decimal :=
  let '(negative,unsigned) := match source with
    | String sign rest => if Ascii.eqb sign "-" then (true,rest) else (false,source)
    | _ => (false,source) end in
  match decimal_integer unsigned with
  | Some (whole,rest) => match decimal_fraction rest with
    | Some (fraction,rest) => match decimal_exponent rest with
      | Some exponent => let whole := if negative then Decimal.Neg whole else Decimal.Pos whole in
        Some (match exponent with None => Decimal.Decimal whole fraction
          | Some exponent => Decimal.DecimalExp whole fraction exponent end)
      | None => None end
    | None => None end
  | None => None end.
Definition number_lexeme text := match parse_decimal text with Some _ => true | None => false end.

Definition parse_natural (text : string) : option N :=
  match text with
  | EmptyString => None
  | String _ _ =>
      match NilZero.uint_of_string text with
      | Some decimal => Some (N.of_uint decimal)
      | None => None
      end
  end.
Definition show_natural (value : N) : string :=
  NilZero.string_of_uint (N.to_uint value).
Definition parse_integer (text : string) : option Z :=
  match parse_decimal text with
  | Some (Decimal.Decimal whole Decimal.Nil) => Some (Z.of_int whole)
  | _ => None end.
Definition show_integer (value : Z) : string :=
  NilZero.string_of_int (Z.to_int value).
Definition parse_nat (text : string) : option nat := option_map N.to_nat (parse_natural text).
Definition show_nat (value : nat) : string := show_natural (N.of_nat value).
