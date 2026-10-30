From Stdlib Require Import List.
From Selvedge.Kernel Require Import State.
Import ListNotations.

(** A maintenance step can inspect effects already issued in this turn, for
    example a cancellation. Its result owns only the next world and newly
    emitted effects; the operation's reply and earlier effects are not writable. *)
Record update := Update {
 updated_world : world;
 appended_effects : list effect
}.
Definition step := world -> list effect -> update.
Definition unchanged (value : world) := Update value [].
Definition from_decision (result : decision) :=
 Update (decision_world result) (decision_effects result).
Definition world_only (change : world -> world) : step :=
 fun value _ => unchanged (change value).
Definition and_then (first second : step) : step := fun value effects =>
 let current := first value effects in
 let next := second (updated_world current) (effects ++ appended_effects current) in
 Update (updated_world next) (appended_effects current ++ appended_effects next).
Definition each {A : Type} (items : list A) (body : A -> step) : step :=
 fold_right (fun item rest => and_then (body item) rest)
   (fun value _ => unchanged value) items.
Definition run (maintenance : step) (result : decision) :=
 let next := maintenance (decision_world result) (decision_effects result) in
 Decision (updated_world next) (decision_reply result)
   (decision_effects result ++ appended_effects next).
Definition follow (first second : decision) :=
 run (fun _ _ => from_decision second) first.
