From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import DecisionCompositionProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Foundation Require Import RegistryProofs Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks TaskChangesProofs FeatureAdmissionProofs.
From Selvedge.Features Require Import Domain Board BoardParameters BoardRelations Worktree WorktreeProofs Titles TitleRuntime.
Import ListNotations.
Open Scope list_scope.
Module F:=Selvedge.Features.Domain.

Lemma selecting_a_card_retains_the_observed_value : forall id revision value,
 Board.select_card id revision value = match Board.lookup id value with
 | Some card => if N.eqb revision (F.card_revision card) then CommandResult.Accepted card
   else CommandResult.refuse "card_conflict" "The card changed in another view or during execution. Refresh its current values before applying this edit."
 | None => CommandResult.refuse "card_not_found" "The board card does not exist" end.
Proof.
 intros id revision value; destruct (Board.lookup id value) as [card|] eqn:Found;
 unfold Board.select_card,Board.select_card_reference.
 - eapply observe_present; [exact Found|]; intros Observed.
   destruct (N.eqb revision (F.card_revision card)); reflexivity.
 - eapply observe_absent; [exact Found|]; intros Missing; reflexivity.
Qed.

Definition current_board_lease (ticket:N) (card:F.card) : Prop :=
 match F.card_enrichment card with
 | F.Enriching (RequestEnvelope.Envelope expected (revision, _)) =>
     ticket=expected /\ revision=F.card_revision card /\ F.card_archived card=false
 | _ => False
 end.

(** A well-formed callback with no current card lease is acknowledged as
    ignored, without changing the board or dispatching another turn. *)
Theorem board_text_without_current_lease_is_ignored : forall source value ok payload,
 string_field "kind" source=Some "board_text" ->
 bool_field "ok" source=Some ok ->
 Board.decode_completion_payload source ok=Some payload ->
 (forall card, Board.lookup (Board.completion_card payload) value=Some card ->
   ~ current_board_lease (Board.completion_ticket payload) card) ->
 exists result,
   Board.completion source value=Some (false,false,result) /\
   decision_reply result=success (JObject [("accepted"%string,JBool false)]) /\
   decision_world result=value /\ decision_effects result=[] /\
   Board.lookup (Board.completion_card payload) (decision_world result)=Board.lookup (Board.completion_card payload) value.
Proof.
 intros source value ok payload kind outcome Parsed no_lease.
 set (id:=Board.completion_card payload) in *; set (ticket:=Board.completion_ticket payload) in *.
 unfold Board.completion; rewrite kind, outcome, Parsed; cbn zeta; fold id ticket.
 destruct (Board.lookup id value) as [card|] eqn:found.
 - destruct (F.card_enrichment card) as [|[expected [revision retitle]]|reason] eqn:lease.
   + cbn. exists (Selvedge.Kernel.State.accept (JObject [("accepted"%string,JBool false)]) value []).
     repeat split; try reflexivity. exact found.
   + destruct (N.eqb ticket expected && N.eqb revision (F.card_revision card) && negb (F.card_archived card)) eqn:matches.
     * exfalso. specialize (no_lease card eq_refl). apply no_lease.
       unfold current_board_lease. rewrite lease. simpl.
       apply Bool.andb_true_iff in matches as [ticket_revision not_archived].
       apply Bool.andb_true_iff in ticket_revision as [ticket_matches version_matches].
       apply N.eqb_eq in ticket_matches. apply N.eqb_eq in version_matches.
       apply Bool.negb_true_iff in not_archived. repeat split; assumption.
     * cbn. exists (Selvedge.Kernel.State.accept (JObject [("accepted"%string,JBool false)]) value []).
       repeat split; try reflexivity. exact found.
   + cbn. exists (Selvedge.Kernel.State.accept (JObject [("accepted"%string,JBool false)]) value []).
     repeat split; try reflexivity. exact found.
 - cbn. exists (Selvedge.Kernel.State.accept (JObject [("accepted"%string,JBool false)]) value []).
   repeat split; try reflexivity. exact found.
Qed.

(** Launch writes the identifier allocated by the shared Task creator and
    forwards that creator's complete effect list unchanged. *)
Theorem launch_links_and_preserves_created_task : forall id revision observed caller value card agent now
 (birth : Worktree.start_transition value value),
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.runnable card value=true ->
 Board.owner_agent (F.draft_owner (F.card_contents card)) value=Some agent ->
 let settings:=Board.launch_settings agent (F.card_contents card) in
 Worktree.create_selected_result (F.agent_profile agent) (Some (F.agent_reasoning agent))
   (Board.task_contents id (F.card_contents card) (F.agent_instructions agent))
   (Some settings) false caller None value = CommandResult.Accepted birth ->
 let launched:=Board.run id revision observed caller value in
 exists updated,
   Board.lookup id (decision_world launched)=Some updated /\
   F.card_task updated=Some (Worktree.transition_identity birth) /\
   Selvedge.Kernel.State.find_task (Worktree.transition_identity birth) (decision_world launched)=
     Selvedge.Kernel.State.find_task (Worktree.transition_identity birth) (Worktree.transition_world birth) /\
   world_tasks (decision_world launched)=world_tasks (Worktree.transition_world birth) /\
   decision_effects launched=Worktree.transition_effects birth.
Proof.
 intros id revision observed caller value card agent now birth found clock current runnable assigned settings Created launched.
 subst revision.
 unfold launched, Board.run, Board.run_result, Board.select_clock.
 rewrite selecting_a_card_retains_the_observed_value.
 rewrite clock,found,N.eqb_refl. cbn [CommandResult.bind].
 rewrite runnable,assigned. fold settings. rewrite Created.
 cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve CommandResult.accept
   CommandResult.change_world CommandResult.change_value CommandResult.change_effects accept decision_world decision_effects].
 assert (created_keeps_card : Board.lookup id (Worktree.transition_world birth)=Some card).
 { unfold Board.lookup,Board.registry. rewrite Worktree.transition_preserves_board. exact found. }
 exists (F.Card (N.succ (F.card_revision card))
   (Board.with_stage F.InProgress (F.card_contents card))
   (Some (Worktree.transition_identity birth)) false (F.card_created card) now
   F.NoEnrichment "" (F.card_pinned card)).
 split.
 - eapply BoardRelations.board_lookup_after_put_selected. exact created_keeps_card.
 - split; [reflexivity|]. split.
   + apply BoardRelations.task_lookup_after_board_put.
   + split; reflexivity.
Qed.

Lemma interrupt_is_authorized_for_nonarchived_task : forall target task value,
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_archived task=false ->
 Tasks.control_command target Tasks.Interrupt value=
   Selvedge.Kernel.State.accept (JObject [("task_id"%string,number target)])
     (Selvedge.Kernel.State.put_task target (Tasks.control_task Tasks.Interrupt task) value)
     [Selvedge.Kernel.State.CancelTask target].
Proof.
 intros target task value found not_archived.
 unfold Selvedge.Kernel.Domain.task_archived in not_archived.
 rewrite TaskChangesProofs.control_command_expression. rewrite found.
 unfold Tasks.control_target, Tasks.control_transition.
 destruct (Selvedge.Kernel.Domain.task_lifecycle task); simpl in *; try discriminate; reflexivity.
Qed.

Lemma interrupt_preserves_task_authority : forall task,
 Selvedge.Kernel.Domain.task_contract (Tasks.control_task Tasks.Interrupt task)=
   Selvedge.Kernel.Domain.task_contract task /\
 Selvedge.Kernel.Domain.task_current_profile (Tasks.control_task Tasks.Interrupt task)=
   Selvedge.Kernel.Domain.task_current_profile task /\
 Selvedge.Kernel.Domain.task_current_settings (Tasks.control_task Tasks.Interrupt task)=
   Selvedge.Kernel.Domain.task_current_settings task.
Proof.
 intros task; unfold Tasks.control_task.
 pose proof (TaskChangeProofs.field_changes_keep_the_immutable_task_identity
   (Tasks.control_changes Tasks.Interrupt task) task) as Identity.
 pose proof (TaskChangeProofs.field_changes_keep_execution_configuration
   (Tasks.control_changes Tasks.Interrupt task) task) as Configuration.
 tauto.
Qed.

(** Archiving a busy linked card keeps the association and the Task's frozen
    authority while the real Interrupt transition emits its cancellation. The
    resource admission premise is the same one required by public Interrupt. *)
Theorem archive_busy_card_retains_task_authority : forall id revision observed value card target task now,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.pending card=false ->
 F.card_task card=Some target ->
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_busy task=true ->
 Selvedge.Kernel.Domain.task_archived task=false ->
 Worktree.control_guard Tasks.Interrupt target value=None ->
 let archived:=Board.archive_card id revision observed true value in
 exists updated,
   Board.lookup id (decision_world archived)=Some updated /\
   F.card_archived updated=true /\
   F.card_task updated=Some target /\
   Selvedge.Kernel.State.find_task target (decision_world archived)=
     Some (Tasks.control_task Tasks.Interrupt task) /\
   Selvedge.Kernel.Domain.task_contract (Tasks.control_task Tasks.Interrupt task)=
     Selvedge.Kernel.Domain.task_contract task /\
   Selvedge.Kernel.Domain.task_current_profile (Tasks.control_task Tasks.Interrupt task)=
     Selvedge.Kernel.Domain.task_current_profile task /\
   Selvedge.Kernel.Domain.task_current_settings (Tasks.control_task Tasks.Interrupt task)=
     Selvedge.Kernel.Domain.task_current_settings task /\
   decision_effects archived=[Selvedge.Kernel.State.CancelTask target].
Proof.
 intros id revision observed value card target task now found clock current pending linked task_found busy not_archived admitted archived.
 subst revision.
 unfold archived, Board.archive_card, Board.at_clock, Board.select_clock, CommandResult.resolve. rewrite clock.
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found, N.eqb_refl.
 unfold Board.pending, BoardFacts.pending in pending |- *. rewrite pending.
 unfold Board.archive_interrupt_target.
 rewrite linked, task_found, busy, not_archived. cbn [andb negb]. rewrite admitted. cbn zeta.
 cbn [Board.save Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.accept].
 unfold set. cbn. rewrite linked.
 set (updated := F.Card (N.succ (F.card_revision card))
   (F.card_contents card) (Some target) true (F.card_created card) now
   F.NoEnrichment (F.card_start_error card) (F.card_pinned card)).
 exists updated.
 assert (interrupt : Tasks.control_command target Tasks.Interrupt
   (Board.put id updated value)=
   Selvedge.Kernel.State.accept (JObject [("task_id"%string,number target)])
     (Selvedge.Kernel.State.put_task target (Tasks.control_task Tasks.Interrupt task)
       (Board.put id updated value)) [Selvedge.Kernel.State.CancelTask target]).
 { eapply interrupt_is_authorized_for_nonarchived_task.
   - rewrite BoardRelations.task_lookup_after_board_put. exact task_found.
   - exact not_archived. }
 rewrite interrupt.
 cbn [andb Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.accept].
 repeat split.
 - rewrite BoardRelations.board_lookup_after_task_put.
   eapply BoardRelations.board_lookup_after_put_selected. exact found.
 - eapply BoardRelations.task_lookup_after_put_task with (previous:=task).
   rewrite BoardRelations.task_lookup_after_board_put. exact task_found.
 - exact (proj1 (interrupt_preserves_task_authority task)).
 - exact (proj1 (proj2 (interrupt_preserves_task_authority task))).
 - exact (proj2 (proj2 (interrupt_preserves_task_authority task))).
Qed.

(** Every resource refusal is returned before saving the card, rather than
    converting an invalid Interrupt into a saved card with a success reply. *)
Theorem archive_card_control_refusal_is_atomic : forall id revision observed value card target task now refused,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.pending card=false ->
 F.card_task card=Some target ->
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_busy task=true ->
 Selvedge.Kernel.Domain.task_archived task=false ->
 Worktree.control_guard Tasks.Interrupt target value=Some refused ->
 Board.archive_card id revision observed true value=refused.
Proof.
 intros id revision observed value card target task now refused found clock current pending linked task_found busy not_archived rejected.
 subst revision.
 unfold Board.archive_card, Board.at_clock, Board.select_clock, CommandResult.resolve. rewrite clock.
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found, N.eqb_refl, pending.
 unfold Board.archive_interrupt_target.
 rewrite linked, task_found, busy, not_archived. cbn [andb negb].
 rewrite rejected. reflexivity.
Qed.

Theorem archive_card_pending_owner_rejected : forall id revision observed value card target task now tree,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.pending card=false ->
 F.card_task card=Some target ->
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_busy task=true ->
 Selvedge.Kernel.Domain.task_archived task=false ->
 Worktree.execution_allowed target value=true ->
 Worktree.lookup target value=Some tree ->
 Worktree.pending tree=true ->
 Board.archive_card id revision observed true value=
   reject "worktree_pending"%string
     "Wait for worktree creation or archive the task before changing its execution"%string value.
Proof.
 intros id revision observed value card target task now tree found clock current pending linked task_found busy not_archived executable owned preparing.
 eapply archive_card_control_refusal_is_atomic; try eassumption.
 eapply interrupt_pending_resource_is_rejected; eassumption.
Qed.

(** An already archived linked Task can retain pending operation records. The
    card archive must not turn those records into renewed interrupt authority. *)
Theorem archive_busy_archived_task_retains_task : forall id revision observed value card target task now,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.pending card=false ->
 F.card_task card=Some target ->
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_busy task=true ->
 Selvedge.Kernel.Domain.task_archived task=true ->
 let archived:=Board.archive_card id revision observed true value in
 exists updated,
   Board.lookup id (decision_world archived)=Some updated /\
   F.card_archived updated=true /\
   F.card_task updated=Some target /\
   Selvedge.Kernel.State.find_task target (decision_world archived)=Some task /\
   world_tasks (decision_world archived)=world_tasks value /\
   decision_effects archived=[].
Proof.
 intros id revision observed value card target task now found clock current pending linked task_found busy archived_lifecycle archived.
 subst revision.
 unfold archived, Board.archive_card, Board.at_clock, Board.select_clock, CommandResult.resolve. rewrite clock.
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found, N.eqb_refl.
 unfold Board.pending, BoardFacts.pending in pending |- *. rewrite pending.
 unfold Board.archive_interrupt_target.
 rewrite linked, task_found, busy, archived_lifecycle. cbn [andb negb].
 cbn [Board.save Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.accept].
 unfold set. cbn. rewrite linked.
 set (updated := F.Card (N.succ (F.card_revision card))
   (F.card_contents card) (Some target) true (F.card_created card) now
   F.NoEnrichment (F.card_start_error card) (F.card_pinned card)).
 exists updated.
 cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.decision_effects
   Selvedge.Kernel.State.accept].
 repeat split.
 - eapply BoardRelations.board_lookup_after_put_selected. exact found.
 - rewrite BoardRelations.task_lookup_after_board_put. exact task_found.
Qed.

(** Archiving an idle linked card retains the existing Task verbatim and
    emits no lifecycle effect. *)
Theorem archive_idle_card_retains_task : forall id revision observed value card target task now,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now ->
 revision=F.card_revision card ->
 Board.pending card=false ->
 F.card_task card=Some target ->
 Selvedge.Kernel.State.find_task target value=Some task ->
 Selvedge.Kernel.Domain.task_busy task=false ->
 let archived:=Board.archive_card id revision observed true value in
 exists updated,
   Board.lookup id (decision_world archived)=Some updated /\
   F.card_archived updated=true /\
   F.card_task updated=Some target /\
   Selvedge.Kernel.State.find_task target (decision_world archived)=Some task /\
   world_tasks (decision_world archived)=world_tasks value /\
   decision_effects archived=[].
Proof.
 intros id revision observed value card target task now found clock current pending linked task_found idle archived.
 subst revision.
 unfold archived, Board.archive_card, Board.at_clock, Board.select_clock, CommandResult.resolve. rewrite clock.
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found, N.eqb_refl.
 unfold Board.pending, BoardFacts.pending in pending |- *. rewrite pending.
 unfold Board.archive_interrupt_target.
 rewrite linked, task_found, idle. cbn [andb negb].
 cbn [andb Board.save Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.accept].
 unfold set. cbn. rewrite linked.
 set (updated := F.Card (N.succ (F.card_revision card))
   (F.card_contents card) (Some target) true (F.card_created card) now
   F.NoEnrichment (F.card_start_error card) (F.card_pinned card)).
 exists updated.
 repeat split.
 - eapply BoardRelations.board_lookup_after_put_selected. exact found.
 - rewrite BoardRelations.task_lookup_after_board_put. exact task_found.
Qed.

Theorem stale_card_is_atomic : forall id expected value card run,
 Board.lookup id value = Some card -> expected <> F.card_revision card ->
 Board.with_card id expected value run =
 reject "card_conflict"%string "The card changed in another view or during execution. Refresh its current values before applying this edit."%string value.
Proof.
 intros id expected value card run found different.
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found. apply N.eqb_neq in different. rewrite different. reflexivity.
Qed.

(** Wiring to the shared drafting policy does not depend on linkage. Profile
    admission and the actual positive request are established separately. *)
Lemma idle_regeneration_uses_drafting_policy : forall id value card profile now observed
 (Found : Board.lookup id value=Some card)
 (Clock : Board.clock observed=Some now) (Mutable : Board.mutable card value=true),
 Board.regenerate id (F.card_revision card) observed profile value =
 Board.request_text (BoardDrafting.revised_target value id (BoardDrafting.CardReference card Found)
   now (Board.observed_clock_is_bounded observed now Clock) Mutable) profile.
Proof.
 intros id value card profile now observed Found Clock Mutable.
 unfold Board.regenerate,Board.regenerate_result.
 eapply observe_present; [exact Clock|]; intros ObservedClock.
 unfold Board.select_card_reference.
 eapply observe_present; [exact Found|]; intros ObservedCard.
 rewrite N.eqb_refl; cbn [CommandResult.bind].
 eapply require_satisfied; [exact Mutable|]; intros Editable.
 reflexivity.
Qed.
(** An existing ordinary endpoint and a current editable card suffice to emit
    the real request. The effect freezes identity, lease, profile, prompt and
    draft; model success or request acceptance is not assumed. *)
Theorem admitted_regeneration_emits_frozen_request : forall id revision value card profile_name selected now observed,
 Board.lookup id value=Some card -> revision=F.card_revision card ->
 Board.clock observed=Some now -> BoardFacts.mutable card value=true ->
 Tasks.find_profile
   (if String.eqb profile_name "" then F.board_draft_profile (Board.registry value) else profile_name)
   (environment_profiles (world_environment value))=Some selected ->
 TitleRuntime.ordinary selected=true ->
 decision_effects (Board.regenerate id revision observed profile_name value)=
 [SuggestCard id (RequestEnvelope.Envelope (world_next_ticket value) ((N.succ (F.card_revision card)), true)) selected (Titles.board_prompt (F.title_task_prompt (F.feature_title_settings (world_features value)))
     (F.draft_title (F.card_contents card)) (F.draft_description (F.card_contents card)) true) (F.card_contents card)].
Proof.
 intros id revision value card profile_name selected now observed Found Current Clock Mutable Available Ordinary.
 subst revision. rewrite (idle_regeneration_uses_drafting_policy id value card profile_name now observed Found Clock Mutable).
 unfold Board.request_text,Board.request_text_result.
 eapply observe_present; [exact Available|]; intros Selected.
 eapply require_satisfied; [exact Ordinary|]; intros Capable.
 reflexivity.
Qed.

(** A title result retains the linked Task identifier in the saved card. *)
Theorem card_title_result_preserves_conversation : forall value card ok title description reason,
 F.card_task (Board.suggestion ok true title description reason card value)=F.card_task card.
Proof. reflexivity. Qed.

(** The same card store used by completion cannot overwrite conversations or
    their independent generated-name registry. *)
Theorem saving_card_preserves_conversations_and_their_titles : forall id card value,
 world_tasks (Board.put id card value)=world_tasks value /\
 F.feature_titles (world_features (Board.put id card value))=F.feature_titles (world_features value).
Proof. intros. split; reflexivity. Qed.
(** Once linked, edits cannot change the execution request, even when idle. *)
Theorem linked_execution_inputs_are_immutable : forall id expected value card target observed input,
 Board.lookup id value = Some card -> F.card_task card = Some target ->
 Board.changes_execution input = true ->
 decision_world (Board.update_card id expected observed input value) = value.
Proof.
 intros id expected value card target observed input found linked changed.
 unfold Board.update_card, Board.at_clock, Board.select_clock, CommandResult.resolve. destruct (Board.clock observed); [|reflexivity].
 unfold Board.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found. destruct (N.eqb expected (F.card_revision card)); [|reflexivity].
 destruct (Board.parse_patch input (F.card_contents card)); [|reflexivity].
 unfold Board.unlinked, BoardFacts.unlinked. rewrite linked, changed. simpl.
 rewrite Bool.andb_false_r. reflexivity.
Qed.

(** Stopping suppresses the next model turn; committed asynchronous work
    still owns its Board concurrency slot until its callbacks settle. *)
Theorem stopped_operation_keeps_card_locked : forall card value task phase first rest,
 BoardFacts.linked_task card value=Some task ->
 Selvedge.Kernel.Domain.task_lifecycle task=Selvedge.Kernel.Domain.Stopped phase (first::rest) ->
 BoardFacts.mutable card value=false /\ BoardFacts.runnable card value=false.
Proof.
 intros card value task phase first rest linked stopped.
 assert (busy:BoardFacts.busy card value=true).
 { unfold BoardFacts.busy. rewrite linked. unfold BoardFacts.busy_task, Selvedge.Kernel.Domain.task_busy, Selvedge.Kernel.Domain.task_activity, Selvedge.Kernel.Domain.task_operations. rewrite stopped. apply Bool.orb_true_r. }
 assert (locked:BoardFacts.mutable card value=false).
 { unfold BoardFacts.mutable. rewrite busy. repeat rewrite Bool.orb_true_r. reflexivity. }
 split; [exact locked|]. unfold BoardFacts.runnable. now rewrite locked.
Qed.

(** Each bounded batch is composed from the real one-attempt operation.  A
    stalled batch remains stalled; splitting the budget cannot lose a launch. *)
Lemma pump_stalled : forall fuel result,
 Board.next (decision_world result)=None -> Board.pump fuel result=result.
Proof. intros fuel result idle. destruct fuel; [reflexivity|]. cbn [Board.pump]. now rewrite idle. Qed.

Lemma pump_missing_selection : forall fuel result id,
 Board.next (decision_world result)=Some id ->
 Board.lookup id (decision_world result)=None -> Board.pump fuel result=result.
Proof.
 intros fuel result id selected missing. destruct fuel; [reflexivity|].
 cbn [Board.pump]. now rewrite selected,missing.
Qed.

Theorem pump_batches_compose : forall first remaining result,
 Board.pump (first+remaining) result=Board.pump remaining (Board.pump first result).
Proof.
 induction first as [|first IH]; intros remaining result; [reflexivity|].
 cbn [Nat.add Board.pump].
 destruct (Board.next (decision_world result)) as [id|] eqn:selected.
 - destruct (Board.lookup id (decision_world result)) as [card|] eqn:found.
   + apply IH.
   + symmetry. eapply pump_missing_selection; eauto.
 - symmetry. now apply pump_stalled.
Qed.

(** An accepted launch appends its complete effect list in order.  A rejected
    launch contributes no effects; its selected card is blocked instead. *)
Theorem pump_one_success_effects : forall result id card,
 Board.next (decision_world result)=Some id ->
 Board.lookup id (decision_world result)=Some card ->
 let advanced:=Board.run id (F.card_revision card)
   (Some (F.decimal_text (F.card_updated card))) None (decision_world result) in
 bool_default "ok" (decision_reply advanced) false=true ->
 decision_effects (Board.pump 1 result)=decision_effects result++decision_effects advanced.
Proof.
 intros result id card selected found advanced accepted.
 unfold advanced,Board.run in accepted |- *.
 cbn [Board.pump]. rewrite selected,found.
 destruct (Board.run_result id (F.card_revision card)
   (Some (F.decimal_text (F.card_updated card))) None (decision_world result));
 [reflexivity|discriminate].
Qed.

Theorem pump_retains_reply_and_effects : forall fuel result,
 retains_reply_and_effects result (Board.pump fuel result).
Proof.
 induction fuel as [|fuel IH]; intros result; [apply retention_is_reflexive|].
 cbn [Board.pump].
 destruct (Board.next (decision_world result)) as [id|]; [|apply retention_is_reflexive].
 destruct (Board.lookup id (decision_world result)) as [card|]; [|apply retention_is_reflexive].
 destruct (Board.run_result id (F.card_revision card)
   (Some (F.decimal_text (F.card_updated card))) None (decision_world result)).
 - eapply retention_is_transitive; [apply following_retains_reply_and_effects|apply IH].
 - eapply retention_is_transitive; [apply replacing_world_retains_reply_and_effects|apply IH].
Qed.

(** Finishing never drops an earlier effect.  A continuation is appended only
    for runnable remaining work and only when none has already been emitted. *)
Theorem finish_effects : forall result,
 decision_reply (Board.finish result)=decision_reply result /\
 (decision_effects (Board.finish result)=decision_effects result \/
  decision_effects (Board.finish result)=decision_effects result++[ContinueScheduling]).
Proof.
 intros result. unfold Board.finish. split; [reflexivity|].
 destruct (match Board.next (Board.synchronize (decision_world result)) with Some _=>true | None=>false end &&
   negb (existsb (fun effect=>match effect with ContinueScheduling=>true | _=>false end) (decision_effects result))) eqn:more;
   [right|left]; reflexivity.
Qed.

Theorem finish_schedules_remaining_work : forall result id,
 Board.next (Board.synchronize (decision_world result))=Some id ->
 In ContinueScheduling (decision_effects (Board.finish result)).
Proof.
 intros result id remaining. unfold Board.finish. rewrite remaining. cbn.
 destruct (existsb (fun effect=>match effect with ContinueScheduling=>true | _=>false end)
   (decision_effects result)) eqn:continuing; cbn.
 - apply existsb_exists in continuing. destruct continuing as [effect [present is_continue]].
   destruct effect; cbn in is_continue; try discriminate. exact present.
 - apply in_or_app. right. now left.
Qed.

Theorem finish_retains_existing_continuation : forall result,
 In ContinueScheduling (decision_effects result) ->
 decision_effects (Board.finish result)=decision_effects result.
Proof.
 intros result continuing. unfold Board.finish.
 assert (present:existsb (fun effect=>match effect with ContinueScheduling=>true | _=>false end)
   (decision_effects result)=true).
 { apply existsb_exists. exists ContinueScheduling. now split. }
 rewrite present. cbn. now rewrite Bool.andb_false_r.
Qed.

Theorem after_transition_retains_reply_and_effects : forall before result,
 decision_reply (Board.after_transition before result)=decision_reply result /\
 exists appended, decision_effects (Board.after_transition before result)=decision_effects result++appended.
Proof.
 intros before result. unfold Board.after_transition.
 exact (pump_retains_reply_and_effects 8
   (Decision (Board.synchronize (decision_world result)) (decision_reply result) (decision_effects result))).
Qed.

Lemma successful_run_links_selected_card : forall id revision observed caller value card,
 Board.lookup id value=Some card ->
 bool_default "ok" (decision_reply (Board.run id revision observed caller value)) false=true ->
 exists updated,
 Board.lookup id (decision_world (Board.run id revision observed caller value))=Some updated /\
 F.card_task updated=Some (Selvedge.Kernel.State.next_task value).
Proof.
 intros id revision observed caller value card found accepted.
 unfold Board.run,Board.run_result,Board.select_clock in accepted |- *.
 rewrite selecting_a_card_retains_the_observed_value in accepted |- *.
 destruct (Board.clock observed) as [now|]; [|discriminate].
 cbn [CommandResult.bind] in accepted |- *. rewrite found in accepted |- *.
 destruct (N.eqb revision (F.card_revision card)); [|discriminate].
 cbn [CommandResult.bind] in accepted |- *.
 destruct (negb (Board.runnable card value)); [discriminate|].
 destruct (Board.owner_agent (F.draft_owner (F.card_contents card)) value) as [agent|]; [|discriminate].
 cbn zeta in accepted |- *.
 destruct (Worktree.create_selected_result (F.agent_profile agent) (Some (F.agent_reasoning agent))
   (Board.task_contents id (F.card_contents card) (F.agent_instructions agent))
   (Some (Board.launch_settings agent (F.card_contents card))) false caller None value)
   as [birth|reply] eqn:Created.
 - cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve CommandResult.accept
     CommandResult.change_value CommandResult.change_world CommandResult.change_effects decision_world accept]. eexists. split.
   + eapply BoardRelations.board_lookup_after_put_selected.
     unfold Board.lookup,Board.registry. rewrite Worktree.transition_preserves_board. exact found.
   + cbn. rewrite Worktree.transition_identity_is_fresh. reflexivity.
 - discriminate.
Qed.

(** A real one-attempt batch removes its selected card from the runnable
    queue: success links it to its new Task, while failure blocks it. *)
Theorem pump_one_resolves_selected_card : forall result id card,
 Board.next (decision_world result)=Some id ->
 Board.lookup id (decision_world result)=Some card ->
 exists updated,
 Board.lookup id (decision_world (Board.pump 1 result))=Some updated /\
 Board.ready updated (decision_world (Board.pump 1 result))=false.
Proof.
 intros result id card selected found. cbn [Board.pump]. rewrite selected,found.
 destruct (Board.run_result id (F.card_revision card)
   (Some (F.decimal_text (F.card_updated card))) None (decision_world result))
   as [advanced|reason] eqn:Outcome; cbn [decision_world].
 - assert (Accepted : bool_default "ok" (decision_reply
     (Board.run id (F.card_revision card) (Some (F.decimal_text (F.card_updated card))) None (decision_world result))) false = true).
   { unfold Board.run; rewrite Outcome; reflexivity. }
   destruct (successful_run_links_selected_card id (F.card_revision card)
     (Some (F.decimal_text (F.card_updated card))) None (decision_world result) card found Accepted)
     as [updated [linked task_id]].
   unfold Board.run in linked; rewrite Outcome in linked; cbn [CommandResult.decide CommandResult.resolve CommandResult.accept decision_world accept] in linked.
   exists updated. split; [exact linked|].
   unfold Board.ready,Board.runnable,BoardFacts.runnable,BoardFacts.unlinked,Board.unlinked.
   rewrite task_id. rewrite Bool.andb_false_r. reflexivity.
 - eexists. split.
   + eapply BoardRelations.board_lookup_after_put_selected. exact found.
   + unfold Board.ready. cbn [F.card_contents F.draft_stage F.card_enrichment Board.with_stage].
     now repeat rewrite Bool.andb_false_r.
Qed.

Theorem completed_board_batch_retains_reply_and_effects : forall before result,
 let completed:=Board.finish (Board.after_transition before result) in
 decision_reply completed=decision_reply result /\
 exists appended, decision_effects completed=decision_effects result++appended.
Proof.
 intros before result completed.
 change (retains_reply_and_effects result completed); unfold completed.
 eapply retention_is_transitive; [apply after_transition_retains_reply_and_effects|].
 destruct (finish_effects (Board.after_transition before result)) as [Reply [Same|Continued]];
   split; [exact Reply| |exact Reply|].
 - exists []; now rewrite Same, app_nil_r.
 - exists [ContinueScheduling]; exact Continued.
Qed.
