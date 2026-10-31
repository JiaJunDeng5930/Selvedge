From Stdlib Require Import List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State.
Import ListNotations.

(** Scheduling and delivery may withdraw effects, unlike append-only feature
    maintenance. The operation's reply is a read-only input in both languages. *)
Definition transformation := json -> world -> list effect -> world * list effect.
Definition transform (change : transformation) (result : decision) :=
 let next := change (decision_reply result) (decision_world result) (decision_effects result) in
 Decision (fst next) (decision_reply result) (snd next).
Definition compose (first second : transformation) : transformation := fun reply value effects =>
 let '(value,effects) := first reply value effects in second reply value effects.
Definition append (more : list effect) : transformation := fun _ value effects => (value,effects ++ more).
Definition fold {A : Type} (items : list A) (body : A -> transformation) : transformation :=
 fun reply value effects => fold_left
   (fun current item => body item reply (fst current) (snd current)) items (value,effects).

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
Definition maintain (maintenance : step) : transformation := fun _ value effects =>
 let next := maintenance value effects in
 (updated_world next,effects ++ appended_effects next).
Definition run (maintenance : step) := transform (maintain maintenance).
Definition follow (first second : decision) :=
 run (fun _ _ => from_decision second) first.
