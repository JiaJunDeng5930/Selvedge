From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.

Inductive outcome (A : Type) := Accepted (value : A) | Rejected (code message : string).
Arguments Accepted {A} _.
Arguments Rejected {A} _ _.
Definition render_outcome {A} (encode : A -> json) (result : outcome A) :=
  match result with Accepted value => success (encode value) | Rejected code message => failure code message end.
Definition bind {A B} (value : outcome A) (next : A -> outcome B) :=
  match value with Accepted value => next value | Rejected code message => Rejected code message end.
Fixpoint traverse {A B} (f : A -> outcome B) (values : list A) : outcome (list B) :=
  match values with [] => Accepted [] | value :: rest =>
    bind (f value) (fun head => bind (traverse f rest) (fun tail => Accepted (head :: tail))) end.
Definition reject {A} message : outcome A := Rejected "Error" message.

Definition next (previous continuation : json) :=
  if boolean_field previous "ok" then continuation else previous.
Definition admit (valid : bool) (message : string) := if valid then success JNull else err message.
