From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Sequence.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition byte (character : ascii) : N := N.of_nat (nat_of_ascii character).
Definition octet (value : N) : ascii := ascii_of_nat (N.to_nat value).
Record decoded := Decoded { scalar : N; encoded : string; remaining : string }.
Fixpoint continuation (count : nat) (value : N) (prefix source : string) : option decoded :=
  match count,source with
  | O,_ => Some (Decoded value prefix source)
  | S count,String character rest =>
    let code := byte character in
    if (128 <=? code) && (code <=? 191)
    then continuation count (64*value+code-128) (prefix ++ String character "") rest
    else None
  | _,_ => None
  end.
Definition scalar_valid (value : N) :=
  (value <=? 1114111) && negb ((55296 <=? value) && (value <=? 57343)).
Definition bounded (minimum maximum : N) (value : option decoded) : option decoded :=
  match value with
  | Some result => if (minimum <=? result.(scalar)) && (result.(scalar) <=? maximum) && scalar_valid result.(scalar)
                   then Some result else None
  | None => None
  end.
Definition decode_one (source : string) : option decoded :=
  match source with
  | EmptyString => None
  | String character rest =>
    let code := byte character in let prefix := String character "" in
    if code <? 128 then Some (Decoded code prefix rest)
    else if (194 <=? code) && (code <=? 223)
      then bounded 128 2047 (continuation 1%nat (code-192) prefix rest)
    else if (224 <=? code) && (code <=? 239)
      then bounded 2048 65535 (continuation 2%nat (code-224) prefix rest)
    else if (240 <=? code) && (code <=? 244)
      then bounded 65536 1114111 (continuation 3%nat (code-240) prefix rest)
    else None
  end.
Definition byte_length := String.length.
Fixpoint chunks_acc (fuel : nat) (source : string) (reversed : list (N * string)) : option (list (N * string)) :=
  match source with
  | EmptyString => Some (List.rev_append reversed [])
  | _ => match fuel with
    | O => None
    | S fuel => match decode_one source with
      | None => None
      | Some result => chunks_acc fuel result.(remaining) ((result.(scalar),result.(encoded))::reversed)
      end
    end
  end.
Definition chunks_fuel fuel source := chunks_acc fuel source [].
Definition chunks (source : string) := chunks_fuel (byte_length source) source.
Definition decode (source : string) := option_map (fun values => List.rev_append
  (fold_left (fun reversed value => fst value::reversed) values []) []) (chunks source).
Fixpoint validate_fuel (fuel : nat) (source : string) : bool :=
  match source with EmptyString => true | _ => match fuel with O => false | S fuel =>
    match decode_one source with None => false | Some result => validate_fuel fuel result.(remaining) end end end.
Definition well_formed (source : string) := validate_fuel (byte_length source) source.
Fixpoint no_nul (source : string) : bool :=
  match source with EmptyString => true | String c rest =>
    if Ascii.eqb c (ascii_of_nat 0) then false else no_nul rest end.
Fixpoint count_fuel (fuel : nat) (source : string) (count : nat) : option nat :=
  match source with EmptyString => Some count | _ => match fuel with O => None | S fuel =>
    match decode_one source with None => None | Some result => count_fuel fuel result.(remaining) (S count) end end end.
Definition scalar_count (source : string) := count_fuel (byte_length source) source 0%nat.
Definition render_chunks (values : list (N * string)) := String.concat "" (List.rev_append
  (fold_left (fun reversed value => snd value::reversed) values []) []).
Definition take (count : nat) (source : string) : option string :=
  option_map (fun values => render_chunks (Sequence.take count values)) (chunks source).
Definition encode (value : N) : option string :=
  if scalar_valid value then
    if value <? 128 then Some (String (octet value) "")
    else if value <? 2048 then Some (String (octet (192+value/64)) (String (octet (128+value mod 64)) ""))
    else if value <? 65536 then Some (String (octet (224+value/4096))
      (String (octet (128+(value/64) mod 64)) (String (octet (128+value mod 64)) "")))
    else Some (String (octet (240+value/262144)) (String (octet (128+(value/4096) mod 64))
      (String (octet (128+(value/64) mod 64)) (String (octet (128+value mod 64)) ""))))
  else None.
Definition whitespace (value : N) :=
  ((9 <=? value) && (value <=? 13)) || N.eqb value 32 || N.eqb value 160 || N.eqb value 5760 ||
  ((8192 <=? value) && (value <=? 8202)) || N.eqb value 8232 || N.eqb value 8233 || N.eqb value 8239 ||
  N.eqb value 8287 || N.eqb value 12288 || N.eqb value 65279.
Definition nonblank (source : string) :=
  match decode source with Some values => existsb (fun value => negb (whitespace value)) values | None => false end.
