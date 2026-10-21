From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec State Inputs Tasks Callbacks ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

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
 exists suffix, task_history (Callbacks.wake_after_result task) = task_history task ++ suffix.
Proof.
 intros task; unfold Callbacks.wake_after_result, Tasks.promote.
 destruct (task_lifecycle task) as [phase operations|phase operations|phase operations|];
 try destruct phase; try destruct calls; destruct (task_queued task); cbn;
 try (exists []; rewrite app_nil_r; reflexivity);
 eexists; reflexivity.
Qed.
Local Lemma a_decision_keeps_its_reviewer_record : forall owner pending actor outcome task,
 exists suffix,
 task_history (Callbacks.approval_decision owner pending actor outcome task) = task_history task ++
 ApprovalReceipt owner (operation_id pending) (operation_call pending) actor
   (Inputs.approval_json (ApprovalProtocol.normalize_outcome outcome)) :: suffix.
Proof.
 intros owner pending actor outcome task; unfold Callbacks.approval_decision.
 destruct (ApprovalProtocol.normalize_outcome outcome) as [reason|reason|reason].
 - exists []; rewrite changing_operations_keeps_history; reflexivity.
 - unfold Callbacks.settle_operation.
   destruct (waking_after_a_result_keeps_history
     (with_operations
       (remove_operation (operation_id pending)
         (task_operations (append_history
           [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor (Inputs.approval_json (Denied reason))] task)))
       (append_history [History.operation_result pending (State.failure "approval_denied" reason) true]
         (append_history [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor (Inputs.approval_json (Denied reason))] task)))) as [suffix Woken].
   exists (History.operation_result pending (State.failure "approval_denied" reason) true :: suffix).
   rewrite Woken, changing_operations_keeps_history.
   rewrite !appended_history_keeps_its_prefix; repeat rewrite <- app_assoc; reflexivity.
 - unfold Callbacks.settle_operation.
   destruct (waking_after_a_result_keeps_history
     (with_operations
       (remove_operation (operation_id pending)
         (task_operations (append_history
           [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor (Inputs.approval_json (ApprovalFailed reason))] task)))
       (append_history [History.operation_result pending (State.failure "approval_denied" reason) true]
         (append_history [ApprovalReceipt owner (operation_id pending) (operation_call pending) actor (Inputs.approval_json (ApprovalFailed reason))] task)))) as [suffix Woken].
   exists (History.operation_result pending (State.failure "approval_denied" reason) true :: suffix).
   rewrite Woken, changing_operations_keeps_history.
   rewrite !appended_history_keeps_its_prefix; repeat rewrite <- app_assoc; reflexivity.
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
 unfold Callbacks.approval_completed; rewrite Found, Selected.
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
 unfold Callbacks.review_approval; rewrite Found, Selected.
 eexists; split; [reflexivity|apply a_decision_keeps_its_reviewer_record].
Qed.

Theorem public_approval_history_exposes_the_recorded_reviewer : forall owner operation invocation actor outcome,
 field "reviewer" (Codec.message_json owner (ApprovalReceipt owner operation invocation actor outcome)) =
 Some (Codec.reviewer_json actor).
Proof. intros; reflexivity. Qed.
