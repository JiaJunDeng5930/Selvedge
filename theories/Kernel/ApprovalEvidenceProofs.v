From Selvedge.Kernel Require Import CallbackChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec State Inputs Tasks Callbacks ApprovalProtocol Scheduler Limits TicketedRequest ScopedRequestProofs.
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
 rewrite (ScopedRequestProofs.starting_uses_the_current_call owner value task tool invocation []
   (TicketedRequest.Scoped.external_authority_for task invocation) Found).
 2: { unfold TicketedRequest.Scoped.call_action, TicketedRequest.Scoped.can_execute; rewrite Running; rewrite Ready, Known; reflexivity. }
 rewrite Room. unfold TicketedRequest.Scoped.external_authority_for; rewrite Review, Elevated.
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
   cbn [Callbacks.find_pending_approval fold_right] in Found.
   destruct (operation_stage first) as [ticket|ticket reviewer|reviewer|ticket reviewer|hooks value error|ticket plugin hooks value error] eqn:Phase;
     try (apply Later; exact Found).
   destruct (selected (operation_id first) ticket reviewer) eqn:Chosen.
   + inversion Found; subst pending actor; exists ticket.
     split; [left; reflexivity|]. split; [exact Phase|exact Chosen].
   + apply Later; exact Found.
Qed.

Local Lemma appended_history_keeps_its_prefix : forall messages task,
 task_history (append_history messages task) = task_history task ++ messages.
Proof. intros; reflexivity. Qed.
Local Lemma changing_operations_keeps_history : forall operations task,
 task_history (with_operations operations task) = task_history task.
Proof.
 intros operations task; unfold with_operations; destruct (task_lifecycle task); reflexivity.
Qed.
Local Lemma waking_after_a_result_keeps_history : forall task,
 exists suffix, task_history (Tasks.wake_after_result task) = task_history task ++ suffix.
Proof.
 intros task; rewrite waking_result_expression; rewrite !promotion_expression.
 destruct (task_lifecycle task) as [phase operations|phase operations|phase operations|];
 try destruct phase; try destruct calls; destruct (task_queued task); cbn;
 try (exists []; rewrite app_nil_r; reflexivity);
 eexists; reflexivity.
Qed.
Local Lemma beginning_a_result_keeps_history : forall owner pending result error task,
 exists suffix,
 task_history (Callbacks.begin_result owner pending result error task) = task_history task ++ suffix.
Proof.
 intros owner pending result error task; rewrite !begin_result_expression.
 destruct (Callbacks.after_plugins task) as [|plugin rest].
 - rewrite !settle_operation_expression.
   destruct (waking_after_a_result_keeps_history
     (with_operations (remove_operation (operation_id pending) (task_operations task))
       (append_history [History.operation_result pending result error] task))) as [suffix Woken].
   exists (History.operation_result pending result error :: suffix).
   rewrite Woken, changing_operations_keeps_history, appended_history_keeps_its_prefix.
   rewrite <- app_assoc; reflexivity.
 - exists [ToolReceipt owner (operation_id pending) (operation_call pending) result error].
   rewrite changing_operations_keeps_history; reflexivity.
Qed.

Local Lemma a_decision_keeps_its_reviewer_record : forall owner pending actor outcome task,
 exists suffix,
 task_history (Callbacks.approval_decision owner pending actor outcome task) = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) actor
   (Inputs.approval_json (ApprovalProtocol.normalize_outcome outcome)) :: suffix.
Proof.
 intros owner pending actor outcome task; rewrite !approval_decision_expression.
 destruct (ApprovalProtocol.normalize_outcome outcome) as [reason|reason|reason]; cbn beta iota zeta.
 - exists []; rewrite changing_operations_keeps_history; reflexivity.
 - destruct (beginning_a_result_keeps_history owner pending
     (State.failure "approval_denied" ("Bash was not started. " ++ reason)) true
     (append_history [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor
       (Inputs.approval_json (Denied reason))] task)) as [suffix Kept].
   exists suffix; rewrite Kept, appended_history_keeps_its_prefix, <- app_assoc; reflexivity.
 - destruct (beginning_a_result_keeps_history owner pending
     (State.failure "approval_denied" ("Bash was not started. " ++ reason)) true
     (append_history [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor
       (Inputs.approval_json (ApprovalFailed reason))] task)) as [suffix Kept].
   exists suffix; rewrite Kept, appended_history_keeps_its_prefix, <- app_assoc; reflexivity.
Qed.

Theorem an_approval_denial_runs_the_frozen_result_chain :
 forall owner pending actor reason task plugin rest,
 ApprovalProtocol.normalize_outcome (Denied reason) = Denied reason ->
 Callbacks.after_plugins task = plugin :: rest ->
 task_operations (Callbacks.approval_decision owner pending actor (Denied reason) task) =
 map (fun current => if N.eqb (operation_id pending) (operation_id current)
   then Operation (operation_id current) (operation_call current) (operation_announced current)
     (AfterHooksReady (plugin :: rest)
       (State.failure "approval_denied" ("Bash was not started. " ++ reason)) true)
   else current) (task_operations task).
Proof.
 intros owner pending actor reason task plugin rest Normal Hooks.
 rewrite approval_decision_expression, Normal. cbn beta iota zeta.
 rewrite begin_result_expression.
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor model_cursor].
 destruct lifecycle; unfold Callbacks.after_plugins in *; cbn in *; rewrite Hooks; reflexivity.
Qed.

Theorem model_approval_completion_records_its_captured_reviewer :
 forall owner ticket pending profile outcome task value,
 find_task owner value = Some task ->
 Callbacks.find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end)
   (task_operations task) = Some (pending,ModelReviewer profile) ->
 exists updated,
 decision_world (Callbacks.approval_completed owner ticket outcome value) = put_task owner updated value /\
 exists suffix, task_history updated = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) (ModelReviewer profile)
   (Inputs.approval_json (ApprovalProtocol.normalize_outcome outcome)) :: suffix.
Proof.
 intros owner ticket pending profile outcome task value Found Selected.
 rewrite !approval_completed_expression; rewrite Found, Selected.
 eexists; split; [reflexivity|apply a_decision_keeps_its_reviewer_record].
Qed.

Theorem human_approval_command_records_its_actual_reviewer :
 forall owner operation pending outcome task value,
 find_task owner value = Some task ->
 Callbacks.find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end)
   (task_operations task) = Some (pending,HumanReviewer) ->
 exists updated,
 decision_world (Callbacks.review_approval owner operation outcome value) = put_task owner updated value /\
 exists suffix, task_history updated = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) HumanReviewer
   (Inputs.approval_json (ApprovalProtocol.normalize_outcome outcome)) :: suffix.
Proof.
 intros owner operation pending outcome task value Found Selected.
 rewrite !review_approval_expression; rewrite Found, Selected.
 eexists; split; [reflexivity|apply a_decision_keeps_its_reviewer_record].
Qed.

Theorem public_approval_history_exposes_the_recorded_reviewer : forall owner operation invocation actor outcome,
 field "reviewer" (Codec.message_json owner (ApprovalReceipt owner operation invocation actor outcome)) =
 Some (Codec.reviewer_json actor).
Proof. intros; reflexivity. Qed.
