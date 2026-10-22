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

(** The DOM's event composition flag and the retained editor composition session
    are separate observations. Both must admit a key before it becomes a product
    gesture: browsers can clear the event flag before compositionend arrives. *)
Definition editing_key value editor_composing :=
  negb (composing value || editor_composing || ime_key value).
Definition unmodified_editing_key value editor_composing :=
  editing_key value editor_composing &&
    negb (shift value || alt value || modified value).
Definition text_confirmation value editor_composing :=
  unmodified_editing_key value editor_composing && String.eqb (key value) "Enter".
Definition control_activation value editor_composing :=
  editing_key value editor_composing &&
    (String.eqb (key value) "Enter" || String.eqb (key value) " ").
Definition begins_input value editor_composing :=
  editing_key value editor_composing && negb (String.eqb (key value) "Process").
