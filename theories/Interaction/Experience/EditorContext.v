From Stdlib Require Import String NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Resource.
From Selvedge.Kernel Require Domain.
From Selvedge.Interaction Require Import Identity CommandAssessment.
From Selvedge.Interaction.Submission Require Draft.

(** Inputs to editor decisions are observations about a draft, its resources,
    and command admission. Each entry supplies these from its own session. *)
Record resources := Resources {
  editor_pending : editor -> bool;
  editor_preparing : editor -> bool;
  editor_uploading : editor -> bool;
  directory_entry : editor -> string;
  directory_result : Draft.draft -> option (sum string (Domain.workspace * json));
  git_observation : resource (editor * string) bool;
  cloud_repository_observation : resource (editor * string) bool;
  connected : bool;
  admission_revision : N;
  command_assessments : list (resource request observation);
  current_time : option N
}.
Record context := Context {
  current_draft : editor -> Draft.draft;
  observed : resources
}.
Definition with_draft draft context :=
  Context (fun owner => if same_editor owner (Draft.owner draft) then draft
                        else current_draft context owner) (observed context).
