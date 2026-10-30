From Selvedge.Kernel Require Import CallbackChangesProofs TaskWakeProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec State Inputs Tasks Callbacks ApprovalProtocol Scheduler Limits TicketedRequest ScopedRequestProofs TicketedRequestProofs LifecycleProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem model_approval_captures_queued_requests : forall owner tool invocation task value reviewer phase operations,
 find_task owner value = Some task ->
 task_activity task = ReadyForHooks invocation [] [] ->
 find_tool (call_name invocation) (contract_tools (task_contract task)) = Some tool ->
 task_lifecycle task = Running phase operations ->
 settings_approval (task_current_settings task) = ReviewWith reviewer ->
 (String.eqb (call_name invocation) "bash" &&
  String.eqb (Codec.text_default "sandbox_permissions" (call_arguments invocation) "use_default") "require_escalated") = true ->
 N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit = true ->
 exists captured,
 decision_effects (Scheduler.start_external owner value) =
  [RequestApproval owner (world_next_ticket value) reviewer invocation captured] /\
 task_history captured = task_history task ++ map UserMessage (task_queued task) /\
 task_queued captured = [].
Proof.
 intros owner tool invocation task value reviewer phase operations Found Ready Known Running Review Elevated Room.
 destruct (starting_selects_the_current_call owner value task tool invocation []
   (TicketedRequest.Scoped.external_authority_for task invocation) Found
   ltac:(unfold TicketedRequest.Scoped.call_action, TicketedRequest.Scoped.can_execute;
     rewrite Running,Ready,Known; reflexivity))
   as [request [Selected [Owner [Current Intent]]]].
 unfold Scheduler.start_external; rewrite Selected,Current,Room.
 rewrite issued_effects; unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current.
 unfold TicketedRequest.Scoped.external_authority_for; rewrite Review,Elevated; cbn [snd].
 rewrite TaskChangeProofs.apply_app.
 eexists; split; [reflexivity|].
 unfold Scheduler.append_operation, Tasks.promote.
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor model_cursor].
 cbn in Running; subst lifecycle; cbn; destruct queued; cbn; split; try reflexivity.
 now rewrite app_nil_r.
Qed.

(** Selection carries the reviewer stored by the pending operation itself.
    Neither completion path needs a current configuration lookup or a default
    reviewer for a nonpending operation. *)
Theorem pending_approval_selection_retains_the_frozen_actor :
 forall selected operations pending actor,
 Callbacks.find_pending_approval selected operations = Some (pending,actor) ->
 exists ticket,
 In pending operations /\ operation_stage pending = AwaitingApproval ticket actor /\
 selected (operation_id pending) ticket actor = true.
Proof.
 intros selected operations; induction operations as [|first rest IH]; intros pending actor Found.
 - discriminate.
 - assert (Later : Callbacks.find_pending_approval selected rest = Some (pending,actor) ->
     exists ticket, In pending (first::rest) /\
       operation_stage pending = AwaitingApproval ticket actor /\
       selected (operation_id pending) ticket actor = true).
   { intro Tail; destruct (IH pending actor Tail) as [ticket [Member [Phase Chosen]]].
     exists ticket; split; [right; exact Member|auto]. }
   cbn [Callbacks.find_pending_approval RequestReceiver.find_approval RequestReceiver.operation_receiver fold_right] in Found.
   destruct (operation_stage first) as [ticket|ticket reviewer|reviewer|ticket reviewer|hooks value error|ticket plugin hooks value error] eqn:Phase;
     try (apply Later; exact Found).
   destruct (selected (operation_id first) ticket reviewer) eqn:Chosen.
   + inversion Found; subst pending actor; exists ticket.
     split; [left; reflexivity|]. split; [exact Phase|exact Chosen].
   + apply Later; exact Found.
Qed.

Local Lemma a_decision_keeps_its_reviewer_record : forall owner pending actor outcome task,
 exists suffix,
 task_history (Callbacks.approval_decision owner pending actor outcome task) = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) actor
   (ApprovalProtocol.encode_outcome outcome) :: suffix.
Proof.
 intros owner pending actor outcome task.
 unfold Callbacks.approval_decision, Callbacks.approval_decision_changes, Callbacks.approval_decision_plan, OperationEvent.plan.
 apply prefixed_results_retain_their_history_record.
Qed.

Theorem an_approval_denial_runs_the_frozen_result_chain :
 forall owner pending actor reason task plugin rest,
 Callbacks.after_plugins task = plugin :: rest ->
 task_operations (Callbacks.approval_decision owner pending actor (Denied reason) task) =
 map (fun current => if N.eqb (operation_id pending) (operation_id current)
   then Operation (operation_id current) (operation_call current) (operation_announced current)
     (AfterHooksReady (plugin :: rest)
       (State.failure "approval_denied" ("Bash was not started. " ++ proj1_sig reason)) true)
   else current) (task_operations task).
Proof.
 intros owner pending actor reason task plugin rest Hooks.
 unfold Callbacks.approval_decision, Callbacks.approval_decision_changes, Callbacks.approval_decision_plan, OperationEvent.plan.
 rewrite prefixed_results_apply_the_prefix_once; cbn [TaskChange.apply TaskChange.apply_edit fold_left].
 unfold OperationEvent.returned, OperationEvent.settle, Tasks.result_changes.
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor model_cursor].
 destruct lifecycle; unfold Callbacks.after_plugins, OperationEvent.after_plugins in *; cbn in *; rewrite Hooks; reflexivity.
Qed.

Theorem model_approval_completion_records_its_captured_reviewer :
 forall owner ticket pending profile outcome task value,
 find_task owner value = Some task ->
 Callbacks.find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end)
   (task_operations task) = Some (pending,ModelReviewer profile) ->
 exists updated,
 decision_world (Callbacks.approval_completed owner ticket outcome value) =
   (match Callbacks.approval_decision_plan owner pending (ModelReviewer profile) outcome task with
    | Tasks.KeepDemand _ => put_task owner updated value
    | Tasks.WakeDemand _ => Tasks.mark_context_wake owner task (put_task owner updated value) end) /\
 find_task owner (decision_world (Callbacks.approval_completed owner ticket outcome value)) = Some updated /\
 exists suffix, task_history updated = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) (ModelReviewer profile)
   (ApprovalProtocol.encode_outcome outcome) :: suffix.
Proof.
 intros owner ticket pending profile outcome task value Found Selected.
 rewrite !approval_completed_expression; rewrite Found, Selected.
 exists (Callbacks.approval_decision owner pending (ModelReviewer profile) outcome task).
 cbn [Callbacks.acknowledged accept decision_world]. split.
 - unfold Tasks.apply_result, Callbacks.approval_decision, Callbacks.approval_decision_changes.
   destruct (Callbacks.approval_decision_plan owner pending (ModelReviewer profile) outcome task); reflexivity.
 - split.
   + unfold Tasks.apply_result, Callbacks.approval_decision, Callbacks.approval_decision_changes.
     destruct (Callbacks.approval_decision_plan owner pending (ModelReviewer profile) outcome task);
       rewrite ?TaskWakeProofs.context_wake_preserves_every_task_lookup;
       eapply find_put_task; exact Found.
   + apply a_decision_keeps_its_reviewer_record.
Qed.

Theorem human_approval_command_records_its_actual_reviewer :
 forall owner operation pending outcome task value,
 find_task owner value = Some task ->
 Callbacks.find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end)
   (task_operations task) = Some (pending,HumanReviewer) ->
 exists updated,
 decision_world (Callbacks.review_approval owner operation outcome value) =
   (match Callbacks.approval_decision_plan owner pending HumanReviewer outcome task with
    | Tasks.KeepDemand _ => put_task owner updated value
    | Tasks.WakeDemand _ => Tasks.mark_context_wake owner task (put_task owner updated value) end) /\
 find_task owner (decision_world (Callbacks.review_approval owner operation outcome value)) = Some updated /\
 exists suffix, task_history updated = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) HumanReviewer
   (ApprovalProtocol.encode_outcome outcome) :: suffix.
Proof.
 intros owner operation pending outcome task value Found Selected.
 rewrite !review_approval_expression; rewrite Found, Selected.
 exists (Callbacks.approval_decision owner pending HumanReviewer outcome task).
 cbn [Callbacks.acknowledged accept decision_world]. split.
 - unfold Tasks.apply_result, Callbacks.approval_decision, Callbacks.approval_decision_changes.
   destruct (Callbacks.approval_decision_plan owner pending HumanReviewer outcome task); reflexivity.
 - split.
   + unfold Tasks.apply_result, Callbacks.approval_decision, Callbacks.approval_decision_changes.
     destruct (Callbacks.approval_decision_plan owner pending HumanReviewer outcome task);
       rewrite ?TaskWakeProofs.context_wake_preserves_every_task_lookup;
       eapply find_put_task; exact Found.
   + apply a_decision_keeps_its_reviewer_record.
Qed.

Theorem public_approval_history_exposes_the_recorded_reviewer : forall owner operation invocation actor outcome,
 field "reviewer" (Codec.message_json owner (ApprovalReceipt owner operation invocation actor outcome)) =
 Some (Codec.reviewer_json actor).
Proof. intros; reflexivity. Qed.
