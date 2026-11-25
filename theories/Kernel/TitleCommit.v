From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require CommandResult DecisionComposition.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require OptionList.
From Selvedge.Kernel Require Import Numbers Domain State Inputs.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Features Require Import TitleRuntime.
Import ListNotations.
Module Reference := TaskScope.

Definition plan := FeatureRequestAdmission.resolved_title.
Definition reference := @FeatureRequestAdmission.title_reference.
Arguments reference {before}.
Definition title_profiles_available before :=
 let profiles := environment_profiles (world_environment before) in
 match Selvedge.Features.Domain.title_agent_profile
   (Selvedge.Features.Domain.feature_title_settings (world_features before)) with
 | Some key => match FeatureRequestAdmission.explicit_title_profile key profiles with
   | Some _ => true | None => false end
 | None => existsb FeatureRequestAdmission.capable_profile profiles end.
Definition resolve_waiting before :=
 OptionList.find_map (fun '(id, _) => FeatureRequestAdmission.resolve_title id before) (title_tasks before).
Definition resolve (before : world) :=
 if title_profiles_available before then resolve_waiting before else None.
Definition input (decoded : option Inputs.input) (before : world) :=
 match decoded with Some Continue => resolve before | _ => None end.
Definition candidate {before : world} (request : plan before) :=
 DeferredCommit.continue_result before (CommandResult.Accepted (TitleRuntime.issue request)).
Definition enqueue_title : DecisionComposition.transformation := fun _ value effects =>
 (value,match resolve value with Some _ => effects ++ [ContinueScheduling] | None => effects end).
