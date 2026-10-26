From Selvedge.Kernel Require Import TicketSupplyProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant WorldInvariantProofs FeatureFrameProofs.
From Selvedge.Features Require Import Domain State TitleRuntime.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Lemma an_absent_title_has_no_previous_registry_entry : forall owner before,
 TitleRuntime.entry owner before = None ->
 filter (fun entry => negb (N.eqb owner (F.title_task entry))) (F.feature_titles (world_features before)) =
 F.feature_titles (world_features before).
Proof.
 intros owner before Absent. unfold TitleRuntime.entry,FeatureRequestAdmission.title_entry in Absent.
 remember (F.feature_titles (world_features before)) as entries in *.
 clear Heqentries. induction entries as [|entry rest IH]; cbn in *; [reflexivity|].
 destruct (N.eqb owner (F.title_task entry)) eqn:Same; [discriminate|].
 cbn. now rewrite IH.
Qed.

Lemma storing_a_fresh_title_allocates_one_feature_ticket : forall owner ticket selected prompt before,
 TitleRuntime.entry owner before = None ->
 feature_tickets (world_features (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before)) =
 ticket :: feature_tickets (world_features before).
Proof.
 intros owner ticket selected prompt before Absent.
 unfold TitleRuntime.store. cbn [with_features Selvedge.Features.State.with_titles set].
 rewrite (an_absent_title_has_no_previous_registry_entry owner before Absent).
 reflexivity.
Qed.

Lemma storing_a_title_preserves_every_other_world_requirement : forall owner status before,
 well_formed before ->
 titles_valid (TitleRuntime.store owner status before) = true ->
 tickets_valid (TitleRuntime.store owner status before) = true ->
 well_formed (TitleRuntime.store owner status before).
Proof.
 intros owner status before Valid Titles Tickets.
 apply unchanged_registries_preserve_other_world_requirements with before; try reflexivity; try assumption.
 assert (Graphs : graph_registry_valid (TitleRuntime.store owner status before) = graph_registry_valid before).
 { apply graph_registry_requirements_follow_entry_observations; reflexivity. }
 pose proof (well_formed_feature_requirements before Valid) as Features.
 unfold features_valid in *; rewrite Graphs.
 repeat rewrite andb_true_iff in *; intuition.
Qed.

Theorem a_fresh_title_preserves_global_ticket_ownership : forall owner selected prompt before,
 tickets_valid before = true -> TitleRuntime.entry owner before = None ->
 tickets_valid (TitleRuntime.store owner
   (F.TitlePending (world_next_ticket before) selected prompt)
   (with_ticket (N.succ (world_next_ticket before)) before)) = true.
Proof.
 intros owner selected prompt before Supply Absent.
 apply one_fresh_owner_preserves_the_ticket_supply with before; [exact Supply|reflexivity|].
 unfold allocated_tickets; cbn [world_tasks].
 rewrite storing_a_fresh_title_allocates_one_feature_ticket by exact Absent.
 apply Permutation_sym, Permutation_middle.
Qed.

Lemma storing_one_eligible_title_preserves_title_requirements :
 forall owner ticket selected prompt task before,
 titles_valid before = true -> TitleRuntime.entry owner before = None ->
 find_task owner before = Some task -> (ticket < world_next_ticket before)%N ->
 profile_valid selected = true -> TitleRuntime.capable selected = true ->
 (N.of_nat (String.length prompt) <= Titles.maximum_instruction_bytes +
  N.of_nat (String.length Titles.title_format) +
  (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format))))%N ->
 titles_valid (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before) = true.
Proof.
 intros owner ticket selected prompt task before Valid Absent Owned Bound Profile Capable Prompt.
 assert (NoOwner : ~ In owner (map F.title_task (F.feature_titles (world_features before)))).
 { intro Member. apply in_map_iff in Member as [entry [Identity Member]].
   unfold TitleRuntime.entry,FeatureRequestAdmission.title_entry in Absent.
   pose proof (find_none _ _ Absent entry Member) as Different.
   cbn in Different. rewrite Identity, N.eqb_refl in Different. discriminate. }
 assert (OldTitles : forallb (fun entry => title_valid entry (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before))
   (F.feature_titles (world_features before)) =
   forallb (fun entry => title_valid entry before) (F.feature_titles (world_features before))) by reflexivity.
 unfold titles_valid in Valid. repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[TaskPrompt AgentPrompt] Unique] Entries].
 unfold titles_valid. unfold TitleRuntime.store.
 cbn [with_features Selvedge.Features.State.with_titles set].
 rewrite (an_absent_title_has_no_previous_registry_entry owner before Absent).
 cbn [map forallb]. repeat rewrite andb_true_iff; repeat split; try assumption.
 - apply distinct_tickets_pass_the_uniqueness_checker. constructor; [exact NoOwner|].
   now apply unique_tickets_denotes_distinct_correlation_owners.
 - change (title_valid (F.TitleEntry owner (F.TitlePending ticket selected prompt)) before &&
     forallb (fun entry => title_valid entry before) (F.feature_titles (world_features before)) = true).
   rewrite Entries. apply andb_true_iff; split; [|reflexivity].
   unfold title_valid. cbn [F.title_value F.title_task]. rewrite Owned. cbn [present].
   repeat rewrite andb_true_iff. repeat split; try assumption;
     [now apply N.ltb_lt|now apply N.leb_le].
Qed.
