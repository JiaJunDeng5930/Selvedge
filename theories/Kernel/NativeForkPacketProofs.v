From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs InputDecoder Packet
 NativeForkCommit NativeForkCommitProofs DeferredCommit DeferredCommitProofs
 Dispatch Delivery Notifications NotificationsProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem a_selected_native_fork_commits_within_its_delivery_budget :
 forall raw before (accepted : NativeForkCommit.plan before),
 InputDecoder.decode raw = Some Continue ->
 Delivery.fits_json raw = true ->
 NativeForkCommit.resolve Continue before = Some accepted ->
 Delivery.fits true (NativeForkCommit.candidate accepted) = true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (NativeForkCommit.candidate accepted)),
  Notifications.envelope true true (Some Continue) before (NativeForkCommit.candidate accepted)).
Proof.
 intros raw before accepted Decoded InputFits Selected OutputFits.
 unfold Packet.packet, Packet.select; fold (Delivery.fits_json raw).
 rewrite InputFits, Decoded.
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate
   BoardCommit.input ConnectionCommit.input Packet.native_fork_input].
 rewrite Selected.
 apply a_constructed_candidate_with_its_actual_budget_is_committed; [|exact OutputFits].
 destruct (a_native_fork_transaction_acknowledges_its_delivery before accepted) as [_ Effects].
 destruct (NativeForkCommit.candidate accepted) as [next reply effects].
 cbn in Effects; subst effects; reflexivity.
Qed.

(** A refused native business operation still completes its accepted invocation.
    Its durable acknowledgement lets independent work continue after the error. *)
Theorem a_refused_native_fork_keeps_its_error_in_the_committed_task :
 forall raw before (accepted : NativeForkCommit.plan before) code reason,
 InputDecoder.decode raw = Some Continue ->
 Delivery.fits_json raw = true ->
 NativeForkCommit.resolve Continue before = Some accepted ->
 NativeForkCommit.business_result accepted = CommandResult.Rejected (CommandResult.Refusal code reason) ->
 Delivery.fits true (NativeForkCommit.candidate accepted) = true ->
 let step := NativeForkCommit.planned_step accepted in
 let original := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 exists settled,
 find_task (Scheduler.native_fork_owner step) (fst (Packet.packet raw before)) = Some settled /\
 task_history settled = task_history original ++
   match OperationEvent.after_plugins original with
   | [] => [FunctionOutput (call_id (Scheduler.native_fork_invocation step)) (failure code reason) true]
   | _ => [ToolReceipt (Scheduler.native_fork_owner step) (world_next_ticket before)
       (Scheduler.native_fork_invocation step) (failure code reason) true] end /\
 field "reply" (snd (Packet.packet raw before)) = Some (success JNull) /\
 field "durable" (snd (Packet.packet raw before)) = Some (JBool true).
Proof.
 intros raw before accepted code reason Decoded InputFits Selected Refused OutputFits step original.
 rewrite a_selected_native_fork_commits_within_its_delivery_budget with (accepted:=accepted) by assumption.
 cbn [fst snd].
 destruct (a_refused_native_call_records_its_error_and_releases_its_continuation
   before accepted code reason Refused) as [settled [Owned [History [Reply Effects]]]].
 exists settled; split; [exact Owned|].
 split; [exact History|]. split.
 - rewrite notification_envelopes_preserve_the_committed_reply; now rewrite Reply.
 - apply notification_envelopes_preserve_the_durability_flag.
Qed.
