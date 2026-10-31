From Stdlib Require Import NArith.
From Selvedge.Programming Require Import Constructor.

(** A pending receiver and its external request share this value.  The
    correlation identity and frozen input cannot be selected independently
    when the receiver is installed and the request is emitted. *)
Record t (payload : Type) := Envelope {
 identity : N;
 input : payload
}.
Arguments Envelope {payload} _ _.
Arguments identity {payload} _.
Arguments input {payload} _.

(** These operations use their fixed owner as correlation identity. Their
    payload has no ticket; choosing this form is explicit at issuance. *)
Record owned (payload : Type) := Owned { owned_input : payload }.
Arguments Owned {payload} _.
Arguments owned_input {payload} _.

Definition as_pair {payload} (request : t payload) := (identity request,input request).
#[global] Instance pair_view payload : Constructor.View (@as_pair payload) := {
 Constructor.project := fun pair => Some (Envelope (fst pair) (snd pair));
 Constructor.project_inject := fun request => match request with Envelope _ _ => eq_refl end
}.
