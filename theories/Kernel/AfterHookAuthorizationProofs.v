From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs JsonObjectsProofs.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs ContextSelection
 TicketedRequest TicketedRequestProofs LifecycleProofs WorldInvariant WorldInvariantProofs
 CommitAdmission.
Import ListNotations.

(* Admission observes immutable task configuration and history. Its frame is
   weaker than world validity, which also observes pending-operation stages. *)
Local Definition authorization_task_frame := with_operations [].

Local Lemma authorization_registry_replacement :
 forall (A : Type) (rel : A -> A -> Prop) values owner original replacement,
 (forall value, rel value value) ->
 registry_at owner values = Some original -> rel original replacement ->
 Forall2 rel values (replace owner replacement values).
Proof.
 intros A rel values; induction values as [|first rest IH]; intros owner original replacement
   Refl Found Same; [discriminate|].
 cbn in Found; cbn [replace]; destruct (N.eqb owner 0).
 - inversion Found; subst first; constructor; [exact Same|].
   clear IH Found Same. induction rest as [|value remaining IHrest]; constructor;
     [apply Refl|exact IHrest].
 - constructor; [apply Refl|eapply IH; eauto].
Qed.

Local Lemma issuing_after_retains_task_configuration :
 forall owner task before original plugin pending result error,
 find_task owner before = Some task ->
 Forall2 (fun old next => authorization_task_frame old = authorization_task_frame next)
   (world_tasks before)
   (world_tasks (decision_world (TicketedRequest.issue owner
     (TicketedRequest.After original plugin pending result error task) before))).
Proof.
 intros owner task before original plugin pending result error Found.
 change (Forall2 (fun old next => authorization_task_frame old = authorization_task_frame next) (world_tasks before)
   (replace owner (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original) (operation_announced original)
       (AwaitingAfterHook (world_next_ticket before) plugin pending result error)) (task_operations task)) task)
     (world_tasks before))).
 eapply authorization_registry_replacement; [intro; reflexivity|exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed];
   destruct lifecycle; reflexivity.
Qed.


Lemma the_same_profile_has_the_same_configuration : forall profile,
 CommitAdmission.same_profile profile profile = true.
Proof.
 intros; unfold CommitAdmission.same_profile.
 rewrite !equal_is_reflexive, String.eqb_refl; reflexivity.
Qed.
Lemma the_same_settings_have_the_same_configuration : forall settings,
 CommitAdmission.same_settings settings settings = true.
Proof.
 intros; unfold CommitAdmission.same_settings.
 rewrite !equal_is_reflexive, Bool.eqb_reflx; reflexivity.
Qed.
Lemma the_same_creation_contract_has_the_same_configuration : forall contract,
 CommitAdmission.same_contract contract contract = true.
Proof.
 intros; unfold CommitAdmission.same_contract, CommitAdmission.same_tools, CommitAdmission.same_reviewers.
 rewrite the_same_profile_has_the_same_configuration, the_same_settings_have_the_same_configuration,
   !equal_is_reflexive, !N.eqb_refl; reflexivity.
Qed.
Lemma the_same_lineage_has_the_same_ancestors : forall lineage,
 CommitAdmission.same_naturals lineage lineage = true.
Proof. induction lineage; cbn; [reflexivity|rewrite N.eqb_refl, IHlineage; reflexivity]. Qed.
Lemma the_same_history_retains_its_captured_prefix : forall history,
 ContextSelection.history_extends history history = true.
Proof.
 intros; unfold ContextSelection.history_extends, ContextSelection.history_json.
 rewrite length_map, Nat.leb_refl, <- length_map with (f:=Codec.message_json 0), firstn_all,
   equivalent_is_reflexive; reflexivity.
Qed.

Lemma the_same_queued_content_is_retained : forall queued,
 CommitAdmission.same_content_lists queued queued = true.
Proof. intros; unfold CommitAdmission.same_content_lists; apply equal_is_reflexive. Qed.

Lemma retained_task_allows_operation_progress : forall source raw before owner features old next,
 authorization_task_frame old = authorization_task_frame next ->
 CommitAdmission.retained_task source raw before owner features features old next = true.
Proof.
 intros source raw before owner features old next Erased.
 destruct old as [oc op os ol oh oq oa osp osc omc].
 destruct next as [nc np ns nl nh nq na nsp nsc nmc].
 destruct ol; destruct nl; cbn in Erased; inversion Erased; subst;
   unfold CommitAdmission.retained_task, CommitAdmission.same_archived_task,
     CommitAdmission.archived_suffix_valid;
   cbn -[CommitAdmission.same_content_lists]; rewrite ?the_same_lineage_has_the_same_ancestors,
     ?the_same_creation_contract_has_the_same_configuration,
     ?the_same_profile_has_the_same_configuration,
     ?the_same_settings_have_the_same_configuration,
     ?the_same_queued_content_is_retained,
     ?the_same_history_retains_its_captured_prefix, ?skipn_all, ?equal_is_reflexive;
   reflexivity.
Qed.

Lemma retained_tasks_allow_operation_progress : forall source raw before owner features old next,
 Forall2 (fun old next => authorization_task_frame old = authorization_task_frame next) old next ->
 CommitAdmission.retained_tasks_from source raw before owner features features old next = true.
Proof.
 intros source raw before owner features old next Related; revert owner.
 induction Related; intros; [reflexivity|].
 cbn; rewrite retained_task_allows_operation_progress by exact H.
 rewrite IHRelated; reflexivity.
Qed.

Lemma a_unique_registry_key_finds_its_own_entry : forall (A : Type) (key : A -> N) entries selected,
 NoDup (map key entries) -> In selected entries ->
 find (fun entry => N.eqb (key selected) (key entry)) entries = Some selected.
Proof.
 intros A key entries; induction entries as [|first rest IH]; intros selected Unique Member; [contradiction|].
 cbn in Unique; inversion Unique as [|? ? Fresh Tail]; subst.
 cbn; destruct Member as [<-|Member]; [rewrite N.eqb_refl; reflexivity|].
 destruct (N.eqb (key selected) (key first)) eqn:Same.
 - exfalso; apply Fresh; apply in_map_iff; exists selected; split; [apply N.eqb_eq; exact Same|exact Member].
 - apply IH; assumption.
Qed.

Lemma an_unchanged_title_state_is_retained : forall state,
 CommitAdmission.title_value_retained state (Some state) = true.
Proof.
 destruct state; cbn; rewrite ?N.eqb_refl, ?the_same_profile_has_the_same_configuration,
   ?String.eqb_refl; reflexivity.
Qed.

Lemma unchanged_titles_are_retained : forall entries todo,
 NoDup (map Selvedge.Features.Domain.title_task entries) ->
 (forall entry, In entry todo -> In entry entries) ->
 CommitAdmission.retained_titles todo entries = true.
Proof.
 intros entries todo; induction todo as [|first rest IH]; intros Unique Member; [reflexivity|].
 cbn. unfold CommitAdmission.title_entry_at.
 rewrite a_unique_registry_key_finds_its_own_entry; [|exact Unique|apply Member; left; reflexivity].
 cbn; rewrite an_unchanged_title_state_is_retained.
 rewrite IH; [reflexivity|exact Unique|intros; apply Member; right; assumption].
Qed.

Lemma unchanged_worktrees_are_retained : forall entries todo,
 NoDup (map Selvedge.Features.Domain.worktree_task entries) ->
 (forall entry, In entry todo -> In entry entries) ->
 CommitAdmission.retained_worktrees todo entries = true.
Proof.
 intros entries todo; induction todo as [|first rest IH]; intros Unique Member; [reflexivity|].
 cbn. unfold CommitAdmission.worktree_list_entry.
 rewrite a_unique_registry_key_finds_its_own_entry; [|exact Unique|apply Member; left; reflexivity].
 unfold CommitAdmission.retained_worktree; rewrite !String.eqb_refl; cbn.
 apply IH; [exact Unique|intros; apply Member; right; assumption].
Qed.

Lemma unchanged_compaction_entries_are_retained : forall entries todo,
 NoDup (map (@fst N Selvedge.Features.CompactionTypes.entry) entries) ->
 (forall entry, In entry todo -> In entry entries) ->
 CommitAdmission.retained_compaction_entries todo entries = true.
Proof.
 intros entries todo; induction todo as [|[owner first] rest IH]; intros Unique Member; [reflexivity|].
 cbn. unfold CommitAdmission.compaction_entry_at.
 change (CommitAdmission.retained_compaction_entry first
   (option_map snd (find (fun entry => N.eqb (fst (owner,first)) (fst entry)) entries)) &&
     CommitAdmission.retained_compaction_entries rest entries = true).
 rewrite a_unique_registry_key_finds_its_own_entry; [|exact Unique|apply Member; left; reflexivity].
 cbn [option_map snd CommitAdmission.retained_compaction_entry]. rewrite !N.leb_refl; cbn.
 apply IH; [exact Unique|intros; apply Member; right; assumption].
Qed.

Local Lemma registry_lookup_after_first : forall (A : Type) (first : A) rest offset,
 registry_at (N.succ offset) (first :: rest) = registry_at offset rest.
Proof.
 intros. change ((if N.eqb (N.succ offset) 0 then Some first
   else registry_at (N.pred (N.succ offset)) rest) = registry_at offset rest).
 assert (Positive : N.eqb (N.succ offset) 0 = false) by (apply N.eqb_neq; lia).
 rewrite Positive, N.pred_succ; reflexivity.
Qed.

Lemma an_unchanged_board_registry_is_retained : forall entries todo owner,
 (forall offset card, registry_at offset todo = Some card -> registry_at (owner + offset) entries = Some card) ->
 CommitAdmission.retained_board_cards todo entries owner = true.
Proof.
 intros entries todo; induction todo as [|first rest IH]; intros owner Lookup; [reflexivity|].
 cbn [CommitAdmission.retained_board_cards].
 assert (Found : registry_at owner entries = Some first).
 { replace owner with (owner + 0)%N by lia. apply Lookup; reflexivity. }
 unfold CommitAdmission.board_card_at at 1; rewrite Found.
 destruct first as [card|].
 - unfold CommitAdmission.retained_card, CommitAdmission.same_option_card_task.
   rewrite N.leb_refl; destruct (Selvedge.Features.Domain.card_task card); rewrite ?N.eqb_refl; cbn;
     apply IH; intros offset other Later;
     replace (N.succ owner + offset)%N with (owner + N.succ offset)%N by lia;
     apply Lookup; rewrite registry_lookup_after_first; exact Later.
 - unfold CommitAdmission.board_card_at; rewrite Found; cbn.
   apply IH; intros offset other Later.
   replace (N.succ owner + offset)%N with (owner + N.succ offset)%N by lia.
   apply Lookup; rewrite registry_lookup_after_first; exact Later.
Qed.

Theorem well_formed_features_admit_their_unchanged_configuration : forall before,
 WorldInvariant.features_valid before = true ->
 CommitAdmission.features_evolution (world_features before) (world_features before) = true.
Proof.
 intros before Valid.
 unfold WorldInvariant.features_valid in Valid; repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works] Maintenance].
 unfold WorldInvariant.titles_valid in Titles; repeat rewrite andb_true_iff in Titles.
 destruct Titles as [[[TaskPrompt AgentPrompt] UniqueTitles] TitleEntries].
 unfold WorldInvariant.worktrees_valid in Trees; apply andb_true_iff in Trees as [UniqueTrees TreeEntries].
 unfold WorldInvariant.compaction_valid in Maintenance; apply andb_true_iff in Maintenance as [UniqueMaintenance MaintenanceEntries].
 apply unique_tickets_denotes_distinct_correlation_owners in UniqueTitles, UniqueTrees, UniqueMaintenance.
 unfold CommitAdmission.features_evolution, CommitAdmission.titles_evolution,
   CommitAdmission.same_title_prompts, CommitAdmission.compaction_evolution, CommitAdmission.board_evolution.
 rewrite !N.leb_refl, !N.eqb_refl, !String.eqb_refl; cbn.
 rewrite unchanged_titles_are_retained by (intros; assumption).
 rewrite unchanged_worktrees_are_retained by (intros; assumption).
 rewrite unchanged_compaction_entries_are_retained by (intros; assumption).
 rewrite an_unchanged_board_registry_is_retained.
 - reflexivity.
 - intros offset card Found; cbn; exact Found.
Qed.

Lemma replacing_an_existing_operation_installs_its_lookup :
 forall operations original replacement,
 In original operations -> operation_id replacement = operation_id original ->
 find (fun operation => N.eqb (operation_id original) (operation_id operation))
   (TicketedRequest.replace_operation replacement operations) = Some replacement.
Proof.
 induction operations as [|first rest IH]; intros original replacement Member Identity; [contradiction|].
 cbn [TicketedRequest.replace_operation map]; rewrite Identity.
 destruct (N.eqb (operation_id original) (operation_id first)) eqn:Same.
 - cbn [find]; rewrite Identity, N.eqb_refl; reflexivity.
 - cbn [find]; rewrite Same.
   assert (RestMember : In original rest).
   { destruct Member as [<-|Member]; [rewrite N.eqb_refl in Same; discriminate|exact Member]. }
   specialize (IH original replacement RestMember Identity).
   unfold TicketedRequest.replace_operation in IH; rewrite Identity in IH; exact IH.
Qed.

Theorem an_issued_after_hook_has_its_actual_operation_authority :
 forall owner original plugin pending result error task before,
 find_task owner before = Some task ->
 In original (task_operations task) ->
 CommitAdmission.after_effect_valid owner (world_next_ticket before) (operation_id original)
   plugin (operation_call original) result error
   (decision_world (TicketedRequest.issue owner
     (TicketedRequest.After original plugin pending result error task) before)) = true.
Proof.
 intros owner original plugin pending result error task before Found Member.
 unfold CommitAdmission.after_effect_valid, TicketedRequest.issue, TicketedRequest.build.
 cbn [decision_world accept].
 rewrite find_put_task with (before:=task) by exact Found.
 unfold CommitAdmission.operation_at.
 assert (Ops : forall operations, task_operations (with_operations operations task) = operations).
 { intros operations. destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed];
     destruct lifecycle; reflexivity. }
 rewrite Ops.
 rewrite replacing_an_existing_operation_installs_its_lookup with (original:=original) by (try exact Member; reflexivity).
 cbn [operation_call operation_stage].
 unfold CommitAdmission.same_call.
 rewrite !N.eqb_refl, !equal_is_reflexive, Bool.eqb_reflx; reflexivity.
Qed.

Theorem an_archived_after_request_has_transition_authority :
 forall durable source raw owner task before original plugin pending result error,
 WorldInvariant.well_formed before ->
 find_task owner before = Some task ->
 In original (task_operations task) ->
 CommitAdmission.transition_authorized durable source raw before
   (TicketedRequest.issue owner (TicketedRequest.After original plugin pending result error task) before) = true.
Proof.
 intros durable source raw owner task before original plugin pending result error WellFormed Found Member.
 pose proof (issuing_after_retains_task_configuration
   owner task before original plugin pending result error Found) as Related.
 pose proof (issue_preserves_world_frame owner
   (TicketedRequest.After original plugin pending result error task) before)
   as [Sequence [Environment [Projects [Features [Next Length]]]]].
 unfold CommitAdmission.transition_authorized.
 repeat rewrite andb_true_iff; repeat split.
 - unfold CommitAdmission.world_evolution, CommitAdmission.retained_tasks.
   rewrite Features, Projects, Next, N.leb_refl.
   rewrite retained_tasks_allow_operation_progress by exact Related.
   assert (FeatureFrame : CommitAdmission.features_evolution
     (world_features before) (world_features before) = true).
   { exact (well_formed_features_admit_their_unchanged_configuration
       (WorldInvariant.world_structure before) (WorldInvariant.features_requirement before WellFormed)). }
   rewrite FeatureFrame, !andb_true_r; apply N.leb_le; lia.
 - unfold CommitAdmission.effect_tickets_fresh.
   change (forallb (fun effect => match CommitAdmission.effect_ticket effect with
     | Some ticket => (world_next_ticket before <=? ticket)%N &&
       (ticket <? N.succ (world_next_ticket before))%N | None => true end)
     [CheckResult owner (world_next_ticket before) (operation_id original) plugin (operation_call original) result error] &&
     CommitAdmission.unique_effect_tickets
       [CheckResult owner (world_next_ticket before) (operation_id original) plugin (operation_call original) result error] = true).
   cbn; rewrite N.leb_refl, !andb_true_r, !andb_true_l. apply N.ltb_lt; lia.
 - change (CommitAdmission.after_effect_valid owner (world_next_ticket before)
     (operation_id original) plugin (operation_call original) result error
     (decision_world (TicketedRequest.issue owner
       (TicketedRequest.After original plugin pending result error task) before)) && true = true).
   rewrite an_issued_after_hook_has_its_actual_operation_authority by assumption; reflexivity.
Qed.
