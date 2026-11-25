From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require CommandResult DecisionComposition.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Inputs.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Features Require Import TitleRuntime.
Import ListNotations.
Module Reference := TaskScope.

Definition plan := FeatureRequestAdmission.resolved_title.
Definition reference := @FeatureRequestAdmission.title_reference.
Arguments reference {before}.
Definition resolve (before : world) := TaskScope.first_matching before FeatureRequestAdmission.resolve_title_at.
Definition input (decoded : option Inputs.input) (before : world) :=
 match decoded with Some Continue => resolve before | _ => None end.
Definition candidate {before : world} (request : plan before) :=
 DeferredCommit.continue_result before (CommandResult.Accepted (TitleRuntime.issue request)).
Definition enqueue_title : DecisionComposition.transformation := fun _ value effects =>
 (value,match resolve value with Some _ => effects ++ [ContinueScheduling] | None => effects end).
