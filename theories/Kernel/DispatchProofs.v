From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Dispatch.
From Selvedge.Foundation Require Import Json RegistryProofs.
Import ListNotations.
Module C := Selvedge.Features.CompactionTypes.

Lemma task_cancellation_matches_every_owned_ticket : forall effects owner ticket,
 In (CancelTask owner) effects -> Dispatch.cancelled effects owner ticket = true.
Proof.
 intros effects owner ticket Present; unfold Dispatch.cancelled.
 apply existsb_exists; exists (CancelTask owner); split; [exact Present|].
 cbn; apply N.eqb_refl.
Qed.

Lemma maintenance_cancellation_matches_its_owned_ticket : forall effects owner ticket,
 In (MaintainContext (C.Cancel owner ticket)) effects ->
 Dispatch.cancelled effects owner ticket = true.
Proof.
 intros effects owner ticket Present; unfold Dispatch.cancelled.
 apply existsb_exists; exists (MaintainContext (C.Cancel owner ticket)); split; [exact Present|].
 cbn; now rewrite !N.eqb_refl.
Qed.

Lemma a_cancelled_request_is_not_live : forall value effects request owner ticket,
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 Dispatch.cancelled effects owner ticket = true ->
 Dispatch.live_request value effects request = false.
Proof.
 intros value effects request owner ticket Coordinate Cancelled.
 unfold Dispatch.live_request; rewrite Coordinate.
 destruct (find_task owner value) as [current|]; [|reflexivity].
 destruct (task_lifecycle current); try reflexivity; now rewrite Cancelled.
Qed.

Theorem a_cancelled_request_is_withdrawn : forall value reply effects request owner ticket,
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 Dispatch.cancelled effects owner ticket = true ->
 ~ In request (decision_effects (Dispatch.retain_live_effects (Decision value reply effects))).
Proof.
 intros value reply effects request owner ticket Coordinate Cancelled Included.
 cbn [Dispatch.retain_live_effects decision_effects decision_world] in Included.
 apply filter_In in Included as [_ Live].
 rewrite (a_cancelled_request_is_not_live value effects request owner ticket Coordinate Cancelled) in Live.
 discriminate.
Qed.

Theorem a_task_cancellation_withdraws_every_owned_request :
 forall value reply effects request owner ticket,
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 In (CancelTask owner) effects ->
 ~ In request (decision_effects (Dispatch.retain_live_effects (Decision value reply effects))).
Proof.
 intros value reply effects request owner ticket Coordinate Cancelled.
 apply (a_cancelled_request_is_withdrawn value reply effects request owner ticket Coordinate).
 now apply task_cancellation_matches_every_owned_ticket.
Qed.

(* These are the actual maintenance effect constructors. In particular, an
   unfreeze-created Scope is withdrawn if a later native archive clears its
   receiver, before CommitAdmission checks the final decision. *)
Theorem task_cancellation_withdraws_scope_measurement_and_compaction :
 forall value reply effects owner ticket input scope validating target progress,
 In (CancelTask owner) effects ->
 let retained := decision_effects (Dispatch.retain_live_effects (Decision value reply effects)) in
 ~ In (MaintainContext (C.Scope owner ticket input)) retained /\
 ~ In (MaintainContext (C.Measure owner ticket input scope validating)) retained /\
 ~ In (MaintainContext (C.Compact owner ticket input target progress scope)) retained.
Proof.
 intros value reply effects owner ticket input scope validating target progress Cancelled.
 cbn zeta; split.
 - eapply a_task_cancellation_withdraws_every_owned_request; [reflexivity|exact Cancelled].
 - split.
   + eapply a_task_cancellation_withdraws_every_owned_request; [reflexivity|exact Cancelled].
   + eapply a_task_cancellation_withdraws_every_owned_request; [reflexivity|exact Cancelled].
Qed.

(* A precise maintenance cancellation uses the same globally allocated task
   ticket as its provider request or context observation. The Cancel effect
   itself is retained and still has to pass its existing retirement authority. *)
Theorem a_maintenance_cancellation_withdraws_its_exact_request :
 forall value reply effects request owner ticket,
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 In (MaintainContext (C.Cancel owner ticket)) effects ->
 ~ In request (decision_effects (Dispatch.retain_live_effects (Decision value reply effects))).
Proof.
 intros value reply effects request owner ticket Coordinate Cancelled.
 apply (a_cancelled_request_is_withdrawn value reply effects request owner ticket Coordinate).
 now apply maintenance_cancellation_matches_its_owned_ticket.
Qed.

Theorem an_uncancelled_request_keeps_its_owned_effect :
 forall value reply effects request owner ticket current,
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 find_task owner value = Some current -> task_archived current = false ->
 Dispatch.cancelled effects owner ticket = false -> In request effects ->
 In request (decision_effects (Dispatch.retain_live_effects (Decision value reply effects))).
Proof.
 intros value reply effects request owner ticket current Coordinate Found Unarchived Uncancelled Present.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 apply filter_In; split; [exact Present|].
 unfold Dispatch.live_request; rewrite Coordinate, Found.
 unfold task_archived in Unarchived.
 destruct (task_lifecycle current); try discriminate; now rewrite Uncancelled.
Qed.

Theorem task_cancellation_and_maintenance_controls_are_retained :
 forall value reply effects owner ticket deadline,
 let retained := decision_effects (Dispatch.retain_live_effects (Decision value reply effects)) in
 (In (CancelTask owner) effects -> In (CancelTask owner) retained) /\
 (In (MaintainContext (C.Cancel owner ticket)) effects ->
   In (MaintainContext (C.Cancel owner ticket)) retained) /\
 (In (MaintainContext (C.ArmClock deadline)) effects ->
   In (MaintainContext (C.ArmClock deadline)) retained).
Proof.
 intros value reply effects owner ticket deadline; cbn zeta; split.
 - intro Present; cbn [Dispatch.retain_live_effects decision_effects decision_world].
   apply filter_In; split; [exact Present|reflexivity].
 - split; intro Present.
   + cbn [Dispatch.retain_live_effects decision_effects decision_world].
     apply filter_In; split; [exact Present|reflexivity].
   + cbn [Dispatch.retain_live_effects decision_effects decision_world].
     apply filter_In; split; [exact Present|reflexivity].
Qed.

(* Result hooks are settlement rights, including after native self-archive.
   Their exact current operation, not an ordinary request cancellation, owns
   the callback. This remains true for arbitrary cancellation effects. *)
Theorem a_current_result_hook_survives_final_cancellation_withdrawal :
 forall value reply effects id ticket operation plugin invocation result error current pending
   expected_plugin remaining original original_error,
 find_task id value = Some current -> In pending (task_operations current) ->
 operation_id pending = operation ->
 operation_stage pending = AwaitingAfterHook ticket expected_plugin remaining original original_error ->
 In (CheckResult id ticket operation plugin invocation result error) effects ->
 In (CheckResult id ticket operation plugin invocation result error)
   (decision_effects (Dispatch.retain_live_effects (Decision value reply effects))).
Proof.
 intros value reply effects id ticket operation plugin invocation result error current pending
   expected_plugin remaining original original_error Found Pending Identity Stage Present.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 apply filter_In; split; [exact Present|].
 cbn [Dispatch.live_request Dispatch.request_coordinate]; rewrite Found.
 apply existsb_exists; exists pending; split; [exact Pending|].
 unfold RequestReceiver.operation_receiver; now rewrite Identity, Stage, !N.eqb_refl.
Qed.

(** Ordinary tasks and side conversations share the final context-capture
    operation. A later native result may extend either task before this
    decision is committed; no parent-membership premise is needed. *)
Theorem matching_uncommitted_context_captures_the_current_history :
 forall value owner ticket original current revision,
 find_task owner value = Some current ->
 task_activity current = ObservingContext ticket revision ->
 Dispatch.capture_request (ObserveContext owner ticket original) value =
   (put_task owner (Reasoning.capture ticket current) value,
    ObserveContext owner ticket (with_history (task_history current) original)).
Proof.
 intros value owner ticket original current revision Found Phase.
 unfold Dispatch.capture_request, RequestReceiver.pending_phase, RequestReceiver.phase_receiver; now rewrite Found, Phase, N.eqb_refl.
Qed.

Theorem nonmatching_context_capture_keeps_the_original_request :
 forall value owner ticket original current,
 find_task owner value = Some current ->
 (forall revision, task_activity current <> ObservingContext ticket revision) ->
 Dispatch.capture_request (ObserveContext owner ticket original) value =
   (value,ObserveContext owner ticket original).
Proof.
 intros value owner ticket original current Found WrongPhase.
 unfold Dispatch.capture_request, RequestReceiver.pending_phase, RequestReceiver.phase_receiver; rewrite Found.
 destruct (task_activity current) as
   [| | | expected revision | modelTicket callable mode
    | reasoningTicket length | calls | invocation pending remaining
    | hookTicket plugin invocation pending remaining] eqn:Phase; try reflexivity.
 destruct (N.eqb expected ticket) eqn:Matches; [|reflexivity].
 apply N.eqb_eq in Matches; subst expected.
 exfalso; apply (WrongPhase revision); reflexivity.
Qed.

Theorem a_prepared_context_read_has_the_committed_history_and_revision :
 forall value owner ticket original current revision,
 find_task owner value = Some current ->
 task_activity current = ObservingContext ticket revision ->
 let prepared := Dispatch.prepare value [ObserveContext owner ticket original] in
 exists committed snapshot,
   find_task owner (fst prepared) = Some committed /\
   snd prepared = [ObserveContext owner ticket snapshot] /\
   task_history snapshot = task_history committed /\
   task_activity committed = ObservingContext ticket (List.length (task_history committed)).
Proof.
 intros value owner ticket original current revision Found Phase.
 cbn zeta; unfold Dispatch.prepare; cbn [Dispatch.capture_requests].
 rewrite (matching_uncommitted_context_captures_the_current_history
   value owner ticket original current revision Found Phase).
 cbn [Dispatch.capture_requests fst snd].
 exists (Reasoning.capture ticket current), (with_history (task_history current) original).
 split.
 - unfold find_task, put_task, with_tasks; cbn.
   eapply registry_replace_selected; exact Found.
 - split; [reflexivity|].
   destruct current as [contract chosen settings lifecycle history queued lineage parent cursor consumed].
   destruct original as [original_contract original_chosen original_settings original_lifecycle original_history
     original_queued original_lineage original_parent original_cursor original_consumed].
   destruct lifecycle; cbn in Phase; try discriminate; split; reflexivity.
Qed.

Theorem a_retained_model_request_has_an_unarchived_owner :
 forall value effects request,
 let committed := value in
 let requests := decision_effects (Dispatch.retain_live_effects (Decision value (Json.JObject []) effects)) in
 In (RequestModel request) requests ->
 exists owner, find_task (ModelRequest.owner request) value = Some owner /\ task_archived owner = false.
Proof.
 intros value effects request.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task (ModelRequest.owner request) value) as [owner|] eqn:Owned; [|discriminate].
 exists owner; split; [reflexivity|].
 unfold task_archived. destruct (task_lifecycle owner); try reflexivity; discriminate.
Qed.
Theorem a_retained_result_callback_has_its_current_operation_right :
 forall value effects id ticket operation plugin invocation result error,
 let committed := value in
 let requests := decision_effects (Dispatch.retain_live_effects (Decision value (Json.JObject []) effects)) in
 In (CheckResult id ticket operation plugin invocation result error) requests ->
 exists owner pending expected_plugin remaining original original_error,
 find_task id value = Some owner /\ In pending (task_operations owner) /\
 operation_id pending = operation /\
 operation_stage pending = AwaitingAfterHook ticket expected_plugin remaining original original_error.
Proof.
 intros value effects id ticket operation plugin invocation result error.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task id value) as [owner|] eqn:Owned; [|discriminate].
 apply existsb_exists in Live as [pending [Member Checked]].
 apply andb_true_iff in Checked as [Identity Stage]. apply N.eqb_eq in Identity.
 unfold RequestReceiver.operation_receiver in Stage.
 destruct (operation_stage pending) as [execution|execution reviewer|reviewer|execution reviewer|chain original raw_error|expected expected_plugin remaining original original_error] eqn:Phase; try discriminate.
 apply N.eqb_eq in Stage; subst expected.
 exists owner,pending,expected_plugin,remaining,original,original_error; repeat split; try assumption; congruence.
Qed.
