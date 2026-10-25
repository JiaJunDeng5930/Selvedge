From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Inputs TaskScope DeferredCommit.
From Selvedge.Features Require Import TitleRuntime.
Import ListNotations.
Module Reference := TaskScope.

Definition proposal {before : world} (selected : Reference.task_reference before) :=
 TitleRuntime.start (Reference.owner selected) (Reference.selected selected)
   (accept JNull before []).
Definition ready {before : world} (selected : Reference.task_reference before) :=
 match decision_effects (proposal selected) with [_] => true | _ => false end.
Record plan (before : world) := Plan {
 reference : Reference.task_reference before;
 eligible : ready reference = true
}.
Arguments reference {before}.
Arguments Plan {before}.

Definition select (owner : N) (before : world) : option (plan before) :=
 match Reference.select owner before with
 | None => None
 | Some reference => match Bool.bool_dec (ready reference) true with
   | left proof => Some (Plan reference proof) | right _ => None end
 end.
Fixpoint first (owners : list nat) (before : world) : option (plan before) :=
 match owners with
 | [] => None
 | owner :: rest => match select (N.of_nat owner) before with
   | Some request => Some request | None => first rest before end
 end.
Definition resolve (before : world) := first (seq 0 (List.length (world_tasks before))) before.
Definition input (decoded : option Inputs.input) (before : world) :=
 match decoded with Some Continue => resolve before | _ => None end.
Definition candidate {before : world} (request : plan before) :=
 DeferredCommit.continue (proposal (reference request)).
Definition packet {before : world} (request : plan before) (raw : json) :=
 DeferredCommit.packet (Some Continue) raw before (candidate request).
Definition enqueue (result : decision) :=
 match resolve (decision_world result) with
 | Some _ => Decision (decision_world result) (decision_reply result)
     (decision_effects result ++ [ContinueScheduling])
 | None => result
 end.
