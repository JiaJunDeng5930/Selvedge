From Stdlib Require Import String Ascii Bool NArith ZArith DecimalString.
Open Scope string_scope.

Definition is_digit (c : ascii) : bool :=
  let n := nat_of_ascii c in (48 <=? n)%nat && (n <=? 57)%nat.

Fixpoint skip_digits (text : string) : string :=
  match text with
  | EmptyString => EmptyString
  | String c rest => if is_digit c then skip_digits rest else text
  end.
Definition after_digits (text : string) : option string :=
  match text with
  | EmptyString => None
  | String c rest => if is_digit c then Some (skip_digits rest) else None
  end.
Definition after_integer (text : string) : option string :=
  match text with
  | String c rest =>
      if Ascii.eqb c "0" then Some rest
      else if is_digit c then Some (skip_digits rest) else None
  | _ => None
  end.
Definition after_fraction (text : string) : option string :=
  match text with
  | String c rest => if Ascii.eqb c "." then after_digits rest else Some text
  | _ => Some text
  end.
Definition after_exponent (text : string) : option string :=
  match text with
  | String c rest =>
      if Ascii.eqb c "e" || Ascii.eqb c "E" then
        match rest with
        | String sign digits =>
            after_digits (if Ascii.eqb sign "+" || Ascii.eqb sign "-" then digits else rest)
        | _ => None
        end
      else Some text
  | _ => Some text
  end.
Definition number_lexeme (text : string) : bool :=
  let unsigned := match text with
                  | String c rest => if Ascii.eqb c "-" then rest else text
                  | _ => text end in
  match after_integer unsigned with
  | Some rest => match after_fraction rest with
    | Some rest => match after_exponent rest with
      | Some EmptyString => true
      | _ => false end
    | None => false end
  | None => false end.

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
  if number_lexeme text then
    match NilZero.int_of_string text with
    | Some decimal => Some (Z.of_int decimal)
    | None => None
    end
  else None.
Definition show_integer (value : Z) : string :=
  NilZero.string_of_int (Z.to_int value).
Definition parse_nat (text : string) : option nat := option_map N.to_nat (parse_natural text).
Definition show_nat (value : nat) : string := show_natural (N.of_nat value).
