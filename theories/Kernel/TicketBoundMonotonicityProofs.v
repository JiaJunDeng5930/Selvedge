From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State WorldInvariant FeatureFrameProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Module F := Selvedge.Features.Domain.

(* Allocation raises upper bounds on live tickets. The registries, request
   ownership and every ticket identity remain unchanged. *)

Local Opaque Titles.valid_instructions profile_valid TitleRuntime.capable
 Titles.maximum_instruction_bytes Titles.title_format Titles.prompt_bytes
 Titles.instructions Titles.maximum_characters BoardParameters.limited.

Lemma ticket_bound_monotone : forall ticket previous next,
 (previous <= next)%N -> (ticket <? previous)%N = true ->
 (ticket <? next)%N = true.
Proof.
 intros ticket previous next Hle Hlt; apply N.ltb_lt in Hlt.
 apply N.ltb_lt; exact (N.lt_le_trans _ _ _ Hlt Hle).
Qed.

Lemma task_valid_with_ticket : forall owner task before next,
 task_valid owner task (with_ticket next before) = task_valid owner task before.
Proof. reflexivity. Qed.

Lemma tasks_valid_with_ticket : forall entries owner before next,
 tasks_valid owner entries (with_ticket next before) = tasks_valid owner entries before.
Proof. intros; apply registry_requirements_read_only_the_task_and_project_registries; reflexivity. Qed.

Lemma title_valid_with_ticket : forall entry before next,
 (world_next_ticket before <= next)%N -> title_valid entry before = true ->
 title_valid entry (with_ticket next before) = true.
Proof.
 intros entry before next Later Valid.
 apply (title_survives_the_task_frame before (with_ticket next before)); try assumption.
 intros owner old Found; exists old; split; [exact Found|reflexivity].
Qed.

Lemma titles_valid_with_ticket : forall before next,
 (world_next_ticket before <= next)%N -> titles_valid before = true ->
 titles_valid (with_ticket next before) = true.
Proof.
 intros before next Hle Hvalid.
 unfold titles_valid, with_ticket in *; cbv [set] in *; cbn in *.
 repeat rewrite andb_true_iff in *.
 destruct Hvalid as [[[Htask Hagent] Hunique] Hentries].
 repeat split; try assumption.
 apply forallb_forall; intros entry Hin.
 apply title_valid_with_ticket; [exact Hle|].
 exact (proj1 (forallb_forall _ _) Hentries entry Hin).
Qed.

Lemma tickets_valid_with_ticket : forall before next,
 (world_next_ticket before <= next)%N -> tickets_valid before = true ->
 tickets_valid (with_ticket next before) = true.
Proof.
 intros before next Hle Hvalid.
 unfold tickets_valid, with_ticket in *; cbv [set] in *; cbn in *.
 apply andb_true_iff in Hvalid as [Hunique Hbounds].
 apply andb_true_iff; split; [exact Hunique|].
 apply forallb_forall; intros ticket Hin.
 apply (ticket_bound_monotone _ _ _ Hle).
 exact (proj1 (forallb_forall _ _) Hbounds ticket Hin).
Qed.

Lemma features_valid_with_ticket : forall before next,
 (world_next_ticket before <= next)%N -> features_valid before = true ->
 features_valid (with_ticket next before) = true.
Proof.
 intros before next Later.
 apply feature_requirements_follow_task_observations; try reflexivity; try assumption.
 - intros owner old Found; exists old; split; [exact Found|reflexivity].
 - intros entry Valid; exact Valid.
 - intros entry Valid; exact Valid.
Qed.

Theorem well_formed_with_ticket : forall before next,
 well_formed before -> (world_next_ticket before <= next)%N ->
 well_formed (with_ticket next before).
Proof.
 intros before next Valid Later.
 apply unchanged_registries_preserve_other_world_requirements with before; try reflexivity; [exact Valid| |].
 - apply tickets_valid_with_ticket; [exact Later|exact (tickets_requirement before Valid)].
 - apply features_valid_with_ticket; [exact Later|now apply well_formed_feature_requirements].
Qed.

Corollary with_ticket_passes_world_checker : forall before next,
 well_formed before -> (world_next_ticket before <= next)%N ->
 world_valid (with_ticket next before) = true.
Proof.
 intros before next Hvalid Hle.
 destruct (well_formed_with_ticket before next Hvalid Hle)
   as [He Hp Htasks Htickets Hfeatures].
 unfold world_valid; rewrite He, Hp, Htasks, Htickets, Hfeatures; reflexivity.
Qed.
