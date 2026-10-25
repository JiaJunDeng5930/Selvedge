From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State WorldInvariant.
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
Proof.
 induction entries; intros; cbn [tasks_valid]; [reflexivity|].
 rewrite task_valid_with_ticket, IHentries; reflexivity.
Qed.

Lemma title_valid_with_ticket : forall entry before next,
 (world_next_ticket before <= next)%N -> title_valid entry before = true ->
 title_valid entry (with_ticket next before) = true.
Proof.
 intros entry before next Hle Hvalid.
 unfold title_valid, find_task, with_ticket in *; cbv [set] in *; cbn in *.
 destruct (F.title_value entry); cbn in *; try assumption.
 repeat rewrite andb_true_iff in *.
 intuition auto.
 eapply ticket_bound_monotone; eassumption.
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

Lemma card_valid_with_ticket : forall entry before next,
 (world_next_ticket before <= next)%N -> card_valid entry before = true ->
 card_valid entry (with_ticket next before) = true.
Proof.
 intros entry before next Hle Hvalid.
 unfold card_valid, find_task, with_ticket in *; cbv [set] in *; cbn in *.
 destruct (F.card_enrichment entry); cbn in *; try assumption.
 repeat rewrite andb_true_iff in *.
 intuition auto.
 eapply ticket_bound_monotone; eassumption.
Qed.

Lemma board_valid_with_ticket : forall before next,
 (world_next_ticket before <= next)%N -> board_valid before = true ->
 board_valid (with_ticket next before) = true.
Proof.
 intros before next Hle Hvalid.
 unfold board_valid, with_ticket in *; cbv [set] in *; cbn in *.
 repeat rewrite andb_true_iff in *.
 destruct Hvalid as [[[[[[[Hcards Hagents] Hcardbound] Hagentbound] Hentries] Hunique] Hstored] Hprofile].
 repeat split; try assumption.
 apply forallb_forall; intros entry Hin.
 apply card_valid_with_ticket; [exact Hle|].
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

Lemma graphs_valid_with_ticket : forall entries owner before next,
 graphs_valid owner entries (with_ticket next before) = graphs_valid owner entries before.
Proof.
 induction entries; intros; cbn [graphs_valid]; [reflexivity|].
 rewrite IHentries; destruct a; reflexivity.
Qed.

Lemma graph_registry_valid_with_ticket : forall before next,
 graph_registry_valid (with_ticket next before) = graph_registry_valid before.
Proof.
 intros; unfold graph_registry_valid; rewrite graphs_valid_with_ticket; reflexivity.
Qed.

Lemma features_valid_with_ticket : forall before next,
 (world_next_ticket before <= next)%N -> features_valid before = true ->
 features_valid (with_ticket next before) = true.
Proof.
 intros before next Hle Hvalid.
 unfold features_valid in *; repeat rewrite andb_true_iff in *.
 destruct Hvalid as [[[[[[[Htitles Hremote] Htrees] Hboard] Hsharing] Hgraphs] Hworks] Hcompaction].
 repeat split; try assumption.
 - now apply titles_valid_with_ticket.
 - now apply board_valid_with_ticket.
 - now rewrite graph_registry_valid_with_ticket.
Qed.

Theorem well_formed_with_ticket : forall before next,
 well_formed before -> (world_next_ticket before <= next)%N ->
 well_formed (with_ticket next before).
Proof.
 intros before next Hvalid Hle; destruct Hvalid as [He Hp Ht Htickets Hf].
 constructor.
 - exact He.
 - exact Hp.
 - change (tasks_valid 0 (world_tasks (world_structure before))
     (with_ticket next (world_structure before)) = true).
   now rewrite tasks_valid_with_ticket.
 - change (tickets_valid (with_ticket next (world_structure before)) = true).
   now apply tickets_valid_with_ticket.
 - change (features_valid (with_ticket next (world_structure before)) = true).
   now apply features_valid_with_ticket.
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
