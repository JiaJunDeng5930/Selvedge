From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain State WorldInvariant WorldInvariantProofs CommitAdmission
 AfterHookAuthorizationProofs FeatureAuthorityProofs FeatureFrameProofs BoardCommit DeferredCommit DeferredCommitProofs Dispatch Delivery Notifications.
From Selvedge.Features Require Import Board Domain.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Lemma storing_board_keeps_task_requirements : forall board owner task before,
 WorldInvariant.task_valid owner task (Board.store board before) =
 WorldInvariant.task_valid owner task before.
Proof. reflexivity. Qed.

Lemma storing_board_keeps_registry_requirements : forall entries board owner before,
 WorldInvariant.tasks_valid owner entries (Board.store board before) =
 WorldInvariant.tasks_valid owner entries before.
Proof.
 induction entries; intros; cbn [WorldInvariant.tasks_valid]; [reflexivity|].
 rewrite storing_board_keeps_task_requirements, IHentries; reflexivity.
Qed.

Lemma storing_board_keeps_title_requirements : forall board before,
 WorldInvariant.titles_valid (Board.store board before) = WorldInvariant.titles_valid before.
Proof. reflexivity. Qed.
Lemma storing_board_keeps_worktree_requirements : forall board before,
 WorldInvariant.worktrees_valid (Board.store board before) = WorldInvariant.worktrees_valid before.
Proof. reflexivity. Qed.
Lemma storing_board_keeps_sharing_requirements : forall board before,
 WorldInvariant.sharing_valid (Board.store board before) = WorldInvariant.sharing_valid before.
Proof. reflexivity. Qed.
Lemma storing_board_keeps_graph_requirements : forall board before,
 WorldInvariant.graph_registry_valid (Board.store board before) = WorldInvariant.graph_registry_valid before.
Proof.
 intros; unfold WorldInvariant.graph_registry_valid.
 assert (Frame : forall entries owner,
   WorldInvariant.graphs_valid owner entries (Board.store board before) =
   WorldInvariant.graphs_valid owner entries before).
 { induction entries; intros; cbn [WorldInvariant.graphs_valid]; [reflexivity|].
   rewrite IHentries. destruct a; reflexivity. }
 rewrite Frame; reflexivity.
Qed.
Lemma storing_board_keeps_work_requirements : forall board before,
 WorldInvariant.works_valid (Board.store board before) = WorldInvariant.works_valid before.
Proof. reflexivity. Qed.
Lemma storing_board_keeps_compaction_requirements : forall board before,
 WorldInvariant.compaction_valid (Board.store board before) = WorldInvariant.compaction_valid before.
Proof. reflexivity. Qed.

Definition fresh_card (draft : F.card_draft) (now : N) :=
 F.Card 0 draft None false now now F.NoEnrichment "" false.
Definition fresh_card_id (before : world) :=
 N.of_nat (List.length (F.board_cards (Board.registry before))).
Definition append_card (draft : F.card_draft) (now : N) (before : world) :=
 Board.put (fresh_card_id before) (fresh_card draft now) before.

Lemma appending_a_card_keeps_its_original_registry_prefix : forall draft now before,
 F.board_cards (Board.registry (append_card draft now before)) =
 F.board_cards (Board.registry before) ++ [Some (fresh_card draft now)].
Proof.
 intros; unfold append_card, Board.put, Board.registry, Board.store, fresh_card_id,
   Selvedge.Features.State.with_board, with_features.
 cbv [Selvedge.ThirdParty.RecordUpdate.RecordSet.set]; cbn -[N.eqb N.of_nat List.length existsb app].
 rewrite N.eqb_refl; reflexivity.
Qed.

Lemma the_created_card_is_found_at_the_exact_returned_reference : forall draft now before,
 Board.lookup (fresh_card_id before) (append_card draft now before) = Some (fresh_card draft now).
Proof.
 intros; unfold Board.lookup.
 rewrite appending_a_card_keeps_its_original_registry_prefix.
 unfold fresh_card_id; rewrite registry_lookup_at_appended_index; reflexivity.
Qed.

Lemma appending_a_card_keeps_existing_draft_requirements : forall new_draft now draft before,
 Board.valid_draft draft (append_card new_draft now before) = Board.valid_draft draft before.
Proof. reflexivity. Qed.
Lemma appending_a_card_keeps_existing_card_requirements : forall draft now card before,
 WorldInvariant.card_valid card (append_card draft now before) = WorldInvariant.card_valid card before.
Proof. reflexivity. Qed.

Lemma a_new_card_has_its_declared_local_requirements : forall draft now before,
 Board.valid_draft draft before = true ->
 (match F.draft_owner draft with F.ProfileOwner key => Board.agent_profile_valid key | _ => true end) = true ->
 forallb (fun attachment => WorldInvariant.present
   (Selvedge.Features.BoardParameters.attachment
     (Selvedge.Features.Observation.attachment_json attachment))) (F.draft_attachments draft) = true ->
 WorldInvariant.card_valid (fresh_card draft now) (append_card draft now before) = true.
Proof.
 intros draft now before Valid Profile Files.
 unfold WorldInvariant.card_valid, fresh_card; cbn -[Board.valid_draft Board.agent_profile_valid Selvedge.Features.BoardParameters.attachment Selvedge.Features.Observation.attachment_json forallb].
 rewrite appending_a_card_keeps_existing_draft_requirements, Valid, Profile, Files.
 reflexivity.
Qed.

Theorem unassisted_card_creation_constructs_the_exact_card : forall input supplied profile before now draft,
 Board.clock supplied = Some now ->
 Board.parse_patch input Board.empty_draft = Some draft ->
 Board.valid_draft draft before = true ->
 Nat.ltb (List.length (filter (fun card => match card with Some _ => true | None => false end)
   (F.board_cards (Board.registry before)))) 512 = true ->
 N.ltb (fresh_card_id before) 4294967295 = true ->
 Board.create_card input supplied false profile before =
 accept (Board.result (fresh_card_id before) (fresh_card draft now)) (append_card draft now before) [].
Proof.
 intros input supplied profile before now draft Clock Parsed Valid Capacity Identity.
 unfold Board.create_card, Board.at_clock; rewrite Clock, Parsed; cbn -[Board.valid_draft Nat.ltb N.ltb List.length filter Board.registry].
 fold (fresh_card_id before). rewrite Valid, Capacity, Identity; reflexivity.
Qed.

Lemma present_cards_after_an_append : forall (entries : list (option F.card)) (card : F.card),
 fold_right (fun value rest => match value with Some card => card :: rest | None => rest end)
   [] (entries ++ [Some card]) =
 fold_right (fun value rest => match value with Some card => card :: rest | None => rest end)
   [] entries ++ [card].
Proof.
 induction entries as [|[first|] rest IH]; intros; cbn; [reflexivity|now rewrite IH|apply IH].
Qed.
Lemma appending_a_card_adds_exactly_one_present_card : forall draft now before,
 WorldInvariant.cards_present (Board.registry (append_card draft now before)) =
 WorldInvariant.cards_present (Board.registry before) ++ [fresh_card draft now].
Proof.
 intros; unfold WorldInvariant.cards_present.
 rewrite appending_a_card_keeps_its_original_registry_prefix, present_cards_after_an_append; reflexivity.
Qed.
Lemma counting_present_cards : forall entries,
 List.length (fold_right (fun value rest => match value with Some card => card :: rest | None => rest end)
   [] entries) =
 List.length (filter (fun (card : option F.card) => match card with Some _ => true | None => false end) entries).
Proof. induction entries as [|[first|] rest IH]; cbn; [reflexivity|now rewrite IH|exact IH]. Qed.

Theorem appending_an_unlinked_idle_card_preserves_board_requirements : forall draft now before,
 WorldInvariant.board_valid before = true ->
 Board.valid_draft draft before = true ->
 (match F.draft_owner draft with F.ProfileOwner key => Board.agent_profile_valid key | _ => true end) = true ->
 forallb (fun attachment => WorldInvariant.present
   (Selvedge.Features.BoardParameters.attachment
     (Selvedge.Features.Observation.attachment_json attachment))) (F.draft_attachments draft) = true ->
 Nat.ltb (List.length (filter (fun card => match card with Some _ => true | None => false end)
   (F.board_cards (Board.registry before)))) 512 = true ->
 N.ltb (fresh_card_id before) 4294967295 = true ->
 WorldInvariant.board_valid (append_card draft now before) = true.
Proof.
 intros draft now before Before Draft Profile Files Capacity Identity.
 unfold WorldInvariant.board_valid in Before |- *.
 fold (Board.registry before) in Before. fold (Board.registry (append_card draft now before)).
 rewrite appending_a_card_adds_exactly_one_present_card.
 repeat rewrite andb_true_iff in Before |- *.
 destruct Before as [[[[[[[OldCount Agents] Registry] AgentRegistry] Cards] Unique] AgentValid] DraftProfile].
 repeat split.
 - rewrite length_app; cbn. apply Nat.leb_le.
   unfold WorldInvariant.cards_present. rewrite counting_present_cards.
   apply Nat.ltb_lt in Capacity; lia.
 - exact Agents.
 - unfold WorldInvariant.registry_bound, WorldInvariant.within_u32.
   rewrite appending_a_card_keeps_its_original_registry_prefix, length_app; cbn.
   apply N.leb_le. unfold fresh_card_id in Identity. apply N.ltb_lt in Identity.
   rewrite Nat2N.inj_add; cbn; lia.
 - exact AgentRegistry.
 - rewrite forallb_app; apply andb_true_iff; split.
   + apply forallb_forall; intros card Member.
     rewrite appending_a_card_keeps_existing_card_requirements.
     apply forallb_forall with (x := card) in Cards; assumption.
   + cbn; rewrite a_new_card_has_its_declared_local_requirements by assumption; reflexivity.
 - rewrite flat_map_app; cbn [fresh_card]; rewrite app_nil_r; exact Unique.
 - exact AgentValid.
 - exact DraftProfile.
Qed.

Theorem appending_an_idle_card_allocates_no_ticket : forall draft now before,
 WorldInvariant.feature_tickets (world_features (append_card draft now before)) =
 WorldInvariant.feature_tickets (world_features before).
Proof.
 intros; unfold WorldInvariant.feature_tickets.
 fold (Board.registry (append_card draft now before)).
 rewrite appending_a_card_adds_exactly_one_present_card, flat_map_app; cbn [fresh_card].
 rewrite app_nil_r; reflexivity.
Qed.

Theorem appending_a_card_retains_the_authority_of_every_original_card : forall draft now before,
 CommitAdmission.board_evolution (Board.registry before)
   (Board.registry (append_card draft now before)) = true.
Proof.
 intros; unfold CommitAdmission.board_evolution.
 rewrite appending_a_card_keeps_its_original_registry_prefix, length_app.
 repeat rewrite andb_true_iff; repeat split.
 - apply N.leb_le; rewrite Nat2N.inj_add; lia.
 - apply N.leb_refl.
 - apply AfterHookAuthorizationProofs.an_unchanged_board_registry_is_retained.
   intros offset card Found. rewrite N.add_0_l.
   apply registry_lookup_preserved_by_append; exact Found.
Qed.

Lemma storing_a_board_with_its_card_authority_preserves_feature_authority : forall board before,
 WorldInvariant.features_valid before = true ->
 CommitAdmission.board_evolution (Board.registry before) board = true ->
 CommitAdmission.features_evolution (world_features before)
   (world_features (Board.store board before)) = true.
Proof.
 intros board before Valid BoardAuthority.
 pose proof (AfterHookAuthorizationProofs.well_formed_features_admit_their_unchanged_configuration
   before Valid) as Original.
 unfold CommitAdmission.features_evolution in Original |- *.
 change (CommitAdmission.titles_evolution (world_features before) (world_features before) &&
   N.leb (F.remote_next_epoch (F.feature_remote (world_features before)))
     (F.remote_next_epoch (F.feature_remote (world_features before))) &&
   CommitAdmission.retained_worktrees (F.feature_worktrees (world_features before))
     (F.feature_worktrees (world_features before)) &&
   CommitAdmission.board_evolution (Board.registry before) board &&
   N.leb (F.sharing_next (F.feature_sharing (world_features before)))
     (F.sharing_next (F.feature_sharing (world_features before))) &&
   N.leb (N.of_nat (List.length (F.feature_graphs (world_features before))))
     (N.of_nat (List.length (F.feature_graphs (world_features before)))) &&
   CommitAdmission.compaction_evolution (F.feature_compaction (world_features before))
     (F.feature_compaction (world_features before)) &&
   N.leb (N.of_nat (List.length (F.feature_works (world_features before))))
     (N.of_nat (List.length (F.feature_works (world_features before)))) = true).
 repeat rewrite andb_true_iff in Original |- *; tauto.
Qed.

Lemma storing_a_board_preserves_every_other_world_requirement : forall board before,
 WorldInvariant.world_valid before = true ->
 WorldInvariant.board_valid (Board.store board before) = true ->
 WorldInvariant.feature_tickets (world_features (Board.store board before)) =
   WorldInvariant.feature_tickets (world_features before) ->
 WorldInvariant.world_valid (Board.store board before) = true.
Proof.
 intros board before Before BoardValid Tickets.
 unfold WorldInvariant.world_valid in Before |- *.
 change (WorldInvariant.environment_valid (world_environment (WorldInvariant.world_structure before)) &&
   WorldInvariant.projects_valid (WorldInvariant.world_structure before) &&
   WorldInvariant.tasks_valid 0 (world_tasks (WorldInvariant.world_structure before))
     (Board.store board (WorldInvariant.world_structure before)) &&
   WorldInvariant.tickets_valid (Board.store board (WorldInvariant.world_structure before)) &&
   WorldInvariant.features_valid (Board.store board (WorldInvariant.world_structure before)) = true).
 rewrite storing_board_keeps_registry_requirements.
 assert (TicketFrame : WorldInvariant.tickets_valid (Board.store board (WorldInvariant.world_structure before)) =
   WorldInvariant.tickets_valid (WorldInvariant.world_structure before)).
 { change (WorldInvariant.tickets_valid (Board.store board before) = WorldInvariant.tickets_valid before).
   unfold WorldInvariant.tickets_valid. rewrite Tickets; reflexivity. }
 rewrite TicketFrame.
 unfold WorldInvariant.features_valid in Before |- *.
 rewrite storing_board_keeps_title_requirements, storing_board_keeps_worktree_requirements,
   storing_board_keeps_sharing_requirements, storing_board_keeps_graph_requirements,
   storing_board_keeps_work_requirements, storing_board_keeps_compaction_requirements.
 repeat rewrite andb_true_iff in Before |- *; repeat split; tauto.
Qed.

Definition requested_patch (request : Commands.create_card_payload) :=
 Board.Patch
   (Commands.create_card_title request) (Commands.create_card_description request)
   (Commands.create_card_status request) (Commands.create_card_priority request)
   (Commands.create_card_assignee request) (Commands.create_card_project request)
   (Commands.create_card_labels request) (Commands.create_card_attachments request).

Theorem every_unassisted_command_constructs_its_exact_result : forall request before now draft,
 Board.retained (Commands.create_card_assisted request) false = false ->
 Board.clock (Commands.create_card_observed_at request) = Some now ->
 Board.parse_patch (requested_patch request) Board.empty_draft = Some draft ->
 Board.valid_draft draft before = true ->
 Nat.ltb (List.length (filter (fun card => match card with Some _ => true | None => false end)
   (F.board_cards (Board.registry before)))) 512 = true ->
 N.ltb (fresh_card_id before) 4294967295 = true ->
 BoardCommit.candidate request before =
 Decision (append_card draft now before)
   (success (Board.result (fresh_card_id before) (fresh_card draft now))) [ContinueScheduling].
Proof.
 intros request before now draft Assisted Clock Parsed Valid Capacity Identity.
 unfold BoardCommit.candidate, Board.handle_create_card.
 fold (requested_patch request); rewrite Assisted.
 rewrite (unassisted_card_creation_constructs_the_exact_card _ _ _ _ _ _
   Clock Parsed Valid Capacity Identity); reflexivity.
Qed.

Theorem an_unassisted_card_birth_preserves_all_world_requirements : forall draft now before,
 WorldInvariant.world_valid before = true ->
 Board.valid_draft draft before = true ->
 (match F.draft_owner draft with F.ProfileOwner key => Board.agent_profile_valid key | _ => true end) = true ->
 forallb (fun attachment => WorldInvariant.present
   (Selvedge.Features.BoardParameters.attachment
     (Selvedge.Features.Observation.attachment_json attachment))) (F.draft_attachments draft) = true ->
 Nat.ltb (List.length (filter (fun card => match card with Some _ => true | None => false end)
   (F.board_cards (Board.registry before)))) 512 = true ->
 N.ltb (fresh_card_id before) 4294967295 = true ->
 WorldInvariant.world_valid (append_card draft now before) = true.
Proof.
 intros draft now before Valid Draft Profile Files Capacity Identity.
 assert (BoardValid : WorldInvariant.board_valid before = true).
 { pose proof (features_requirement before
     (the_world_checker_establishes_all_requirements before Valid)) as Features.
   unfold WorldInvariant.features_valid in Features.
   repeat rewrite andb_true_iff in Features; tauto. }
 pose proof (appending_an_unlinked_idle_card_preserves_board_requirements
   draft now before BoardValid Draft Profile Files Capacity Identity) as Appended.
 pose proof (appending_an_idle_card_allocates_no_ticket draft now before) as Tickets.
 unfold append_card, Board.put in Appended, Tickets |- *.
 eapply storing_a_board_preserves_every_other_world_requirement; eauto.
Qed.

Theorem an_unassisted_card_birth_constructs_its_cross_state_authority :
 forall source raw draft now before,
 WorldInvariant.world_valid before = true ->
 CommitAdmission.transition_authorized true source raw before
   (Decision (append_card draft now before)
     (success (Board.result (fresh_card_id before) (fresh_card draft now))) [ContinueScheduling]) = true.
Proof.
 intros source raw draft now before Valid.
 pose proof (features_requirement before
   (the_world_checker_establishes_all_requirements before Valid)) as Features.
 pose proof (appending_a_card_retains_the_authority_of_every_original_card draft now before) as BoardAuthority.
 assert (FeatureAuthority : CommitAdmission.features_evolution (world_features before)
   (world_features (append_card draft now before)) = true).
 { unfold append_card, Board.put in BoardAuthority |- *.
   apply storing_a_board_with_its_card_authority_preserves_feature_authority.
   - apply FeatureFrameProofs.well_formed_feature_requirements, the_world_checker_establishes_all_requirements; exact Valid.
   - exact BoardAuthority. }
 unfold CommitAdmission.transition_authorized, CommitAdmission.world_evolution.
 cbn [decision_world decision_effects].
 assert (TaskAuthority : CommitAdmission.retained_tasks source raw before (append_card draft now before) = true).
 { unfold CommitAdmission.retained_tasks.
   apply unchanged_tasks_keep_authority_across_other_features. }
 rewrite TaskAuthority, FeatureAuthority.
 change (true && N.leb (world_next_ticket before) (world_next_ticket before) &&
   N.leb (N.of_nat (List.length (world_projects before)))
     (N.of_nat (List.length (world_projects before))) && true && true && true = true).
 rewrite !N.leb_refl; reflexivity.
Qed.

Record card_birth_requirements (request : Commands.create_card_payload) (before : world)
 (now : N) (draft : F.card_draft) : Prop := CardBirthRequirements {
 birth_world : WorldInvariant.world_valid before = true;
 birth_unassisted : Board.retained (Commands.create_card_assisted request) false = false;
 birth_clock : Board.clock (Commands.create_card_observed_at request) = Some now;
 birth_fields : Board.parse_patch (requested_patch request) Board.empty_draft = Some draft;
 birth_draft : Board.valid_draft draft before = true;
 birth_profile : (match F.draft_owner draft with F.ProfileOwner key => Board.agent_profile_valid key | _ => true end) = true;
 birth_files : forallb (fun attachment => WorldInvariant.present
   (Selvedge.Features.BoardParameters.attachment
     (Selvedge.Features.Observation.attachment_json attachment))) (F.draft_attachments draft) = true;
 birth_capacity : Nat.ltb (List.length (filter (fun card => match card with Some _ => true | None => false end)
   (F.board_cards (Board.registry before)))) 512 = true;
 birth_identity : N.ltb (fresh_card_id before) 4294967295 = true
}.

Definition constructed_card_decision (draft : F.card_draft) (now : N) (before : world) :=
 Decision (append_card draft now before)
   (success (Board.result (fresh_card_id before) (fresh_card draft now))) [ContinueScheduling].

Theorem every_unassisted_card_command_with_a_real_output_budget_commits : forall request raw before now draft,
 card_birth_requirements request before now draft ->
 Delivery.fits true (constructed_card_decision draft now before) = true ->
 BoardCommit.packet request raw before =
 (with_sequence (N.succ (world_sequence before)) (append_card draft now before),
  Notifications.envelope true true (Some (Inputs.UserCommand (Commands.Cmd_create_card request))) before
    (constructed_card_decision draft now before)).
Proof.
 intros request raw before now draft Requirements Budget.
 destruct Requirements as [Valid Assisted Clock Fields Draft Profile Files Capacity Identity].
 pose proof (every_unassisted_command_constructs_its_exact_result request before now draft
   Assisted Clock Fields Draft Capacity Identity) as Constructed.
 pose proof (an_unassisted_card_birth_preserves_all_world_requirements draft now before
   Valid Draft Profile Files Capacity Identity) as World.
 pose proof (an_unassisted_card_birth_constructs_its_cross_state_authority
   (Some (Inputs.UserCommand (Commands.Cmd_create_card request))) raw draft now before Valid) as Authority.
 unfold BoardCommit.packet. rewrite Constructed.
 apply a_constructed_candidate_with_its_actual_budget_is_committed.
 - reflexivity.
 - exact World.
 - exact Authority.
 - exact Budget.
Qed.
