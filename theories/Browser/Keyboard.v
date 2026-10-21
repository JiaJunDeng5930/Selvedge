From Stdlib Require Import String Bool.
Open Scope string_scope.

(** Native observations stay separate from the product action selected by an
    element. IME confirmation is text input, never a submit command. *)
Record observation := Observe {
  key : string; composing : bool; ime_key : bool;
  shift : bool; alt : bool; modified : bool
}.
Record decision := Decide { submit : bool; prevent_default : bool }.

Definition confirmation value :=
  String.eqb (key value) "Enter" && negb (composing value) &&
    negb (ime_key value) && negb (shift value) && negb (alt value).
Definition normalize value multiline enabled pending :=
  let confirm := confirmation value in
  Decide (confirm && (multiline || modified value) && enabled && negb pending) confirm.
