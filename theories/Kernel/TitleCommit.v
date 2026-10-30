From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Inputs TaskScope DeferredCommit.
From Selvedge.Features Require Import TitleRuntime.
Import ListNotations.
Module Reference := TaskScope.

Definition plan := FeatureRequestAdmission.resolved_title.
Definition reference := @FeatureRequestAdmission.title_reference.
Arguments reference {before}.
Definition select := FeatureRequestAdmission.resolve_title.
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
 DeferredCommit.continue_result before (CommandResult.Accepted (TitleRuntime.issue request)).
Definition packet {before : world} (request : plan before) (raw : json) :=
 DeferredCommit.packet (Some Continue) before (candidate request).
Definition enqueue (result : decision) :=
 match resolve (decision_world result) with
 | Some _ => Decision (decision_world result) (decision_reply result)
     (decision_effects result ++ [ContinueScheduling])
 | None => result
 end.
