From Stdlib Require Import String Ascii Bool NArith.
Open Scope string_scope.
Open Scope N_scope.

(* Enrollment is a deployment credential, separate from generated wire tokens. *)
Definition minimum_length : N := 32.
Definition maximum_length : N := 512.
Definition authorization_maximum_length : N := maximum_length + 7.
Fixpoint visible_ascii (text : string) : bool :=
  match text with
  | EmptyString => true
  | String character rest =>
      let code := N.of_nat (nat_of_ascii character) in
      (33 <=? code) && (code <=? 126) && visible_ascii rest
  end.
Definition valid (text : string) : bool :=
  let length := N.of_nat (String.length text) in
  (minimum_length <=? length) && (length <=? maximum_length) && visible_ascii text.
