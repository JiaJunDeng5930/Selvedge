From Selvedge.Kernel Require Import TaskScopeProofs.
From Selvedge.Kernel Require Import TaskScope.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Tasks ReasoningPlan TicketedRequest TicketedRequestProofs Scheduler Limits.
Import ListNotations.
Open Scope string_scope.

Definition selected_result_erases_its_lookup_witness := @TaskScopeProofs.selected_result_erases_its_lookup_witness.

Lemma observe_selected_erases_its_capability : forall before publish reference,
 TicketedRequest.Scoped.run (@TicketedRequest.Scoped.observe_selected before publish reference) =
 if TicketedRequest.Scoped.can_observe publish (TaskScope.selected reference) before then
 TicketedRequest.issue (TaskScope.owner reference)
   (TicketedRequest.Observe (if publish then TicketedRequest.publish_operations
     (Tasks.promote (TaskScope.selected reference)) else TaskScope.selected reference)) before
 else State.ignored before.
Proof.
 intros before publish reference.
 assert (Erase : forall allowed evidence,
   TicketedRequest.Scoped.run (@TicketedRequest.Scoped.observe_allowed before publish reference allowed evidence) =
   if allowed then TicketedRequest.issue (TaskScope.owner reference)
    (TicketedRequest.Observe (if publish then TicketedRequest.publish_operations
     (Tasks.promote (TaskScope.selected reference)) else TaskScope.selected reference)) before
   else State.ignored before).
 { intros [] evidence; reflexivity. }
 apply Erase.
Qed.

Theorem observing_resolves_the_current_task : forall id before current publish,
 find_task id before = Some current ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.observe id publish before) =
 if TicketedRequest.Scoped.can_observe publish current before then
 TicketedRequest.issue id
   (TicketedRequest.Observe (if publish then TicketedRequest.publish_operations (Tasks.promote current) else current)) before
 else State.ignored before.
Proof.
 intros id before current publish Found.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold TicketedRequest.Scoped.observe; rewrite Selected, observe_selected_erases_its_capability.
 now rewrite ?Owner, ?Current.
Qed.

Theorem observing_uses_the_current_task : forall id before current publish,
 find_task id before = Some current ->
 TicketedRequest.Scoped.can_observe publish current before = true ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.observe id publish before) =
 TicketedRequest.issue id
   (TicketedRequest.Observe (if publish then TicketedRequest.publish_operations (Tasks.promote current) else current)) before.
Proof.
 intros id before current publish Found Allowed.
 rewrite (observing_resolves_the_current_task id before current publish Found), Allowed; reflexivity.
Qed.

Definition computed_model owner current before :=
 TicketedRequest.issue owner (TicketedRequest.Infer current) before.
Lemma model_selected_erases_its_capability : forall before reference,
 TicketedRequest.Scoped.run (@TicketedRequest.Scoped.model_selected before reference) =
 if TicketedRequest.Scoped.can_infer (TaskScope.selected reference) before then
 computed_model (TaskScope.owner reference) (TaskScope.selected reference) before
 else State.ignored before.
Proof.
 intros before reference.
 assert (Erase : forall allowed evidence,
   TicketedRequest.Scoped.run (@TicketedRequest.Scoped.model_allowed before reference allowed evidence) =
   if allowed then computed_model (TaskScope.owner reference)
     (TaskScope.selected reference) before else State.ignored before).
 { intros [] evidence; reflexivity. }
 apply Erase.
Qed.

Theorem model_selection_uses_the_current_task : forall id before current,
 find_task id before = Some current ->
 TicketedRequest.Scoped.can_infer current before = true ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.model id before) = computed_model id current before.
Proof.
 intros id before current Found Allowed.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold TicketedRequest.Scoped.model; rewrite Selected, model_selected_erases_its_capability.
 now rewrite Owner, Current, Allowed.
Qed.

Theorem a_scoped_request_writes_only_its_actual_target : forall before
 (request : TicketedRequest.Scoped.plan before) other,
 TaskScope.owner (TicketedRequest.Scoped.target request) <> other ->
 find_task other (decision_world (TicketedRequest.Scoped.issue request)) = find_task other before.
Proof.
 intros before request other Different.
 apply TicketedRequestProofs.issue_preserves_other_tasks; exact Different.
Qed.

Theorem starting_uses_the_current_call : forall id before current tool invocation remaining authority,
 find_task id before = Some current ->
 TicketedRequest.Scoped.call_action current = Some (TicketedRequest.Scoped.StartCall tool invocation remaining authority) ->
 Scheduler.start_external id before =
 if N.ltb (N.of_nat (List.length (task_operations current))) Limits.operation_limit then
   TicketedRequest.issue id (TicketedRequest.Start tool invocation remaining authority current) before
 else Scheduler.call_error id invocation "operation_limit"
   "This task has reached its in-flight operation limit; wait for results or cancel an operation" remaining current before.
Proof.
 intros id before current tool invocation remaining authority Found Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold Scheduler.start_external, TicketedRequest.Scoped.start, TicketedRequest.Scoped.next_call; rewrite Selected.
 pattern (TicketedRequest.Scoped.next_call_selected reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@TicketedRequest.Scoped.next_call_selected before reference)); intros source Evidence.
 assert (Source : source = Some (TicketedRequest.Scoped.StartCall tool invocation remaining authority)).
 { rewrite Current in Evidence; congruence. }
 revert Evidence; rewrite Source; intro Evidence; cbn [TicketedRequest.Scoped.next_call_selected TicketedRequest.Scoped.intent
   TicketedRequest.Scoped.target TicketedRequest.Scoped.issue TicketedRequest.Scoped.lower].
 unfold TicketedRequest.Scoped.issue, TicketedRequest.Scoped.lower.
 cbn [TicketedRequest.Scoped.target TicketedRequest.Scoped.intent].
 now rewrite ?Owner, ?Current.
Qed.

Theorem authorizing_uses_the_current_call : forall id before current plugin tool invocation pending remaining,
 find_task id before = Some current ->
 TicketedRequest.Scoped.call_action current =
   Some (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining) ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.authorize id before) =
 TicketedRequest.issue id (TicketedRequest.Before plugin tool invocation pending remaining current) before.
Proof.
 intros id before current plugin tool invocation pending remaining Found Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold TicketedRequest.Scoped.authorize, TicketedRequest.Scoped.next_call; rewrite Selected.
 pattern (TicketedRequest.Scoped.next_call_selected reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@TicketedRequest.Scoped.next_call_selected before reference)); intros source Evidence.
 assert (Source : source = Some (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining)).
 { rewrite Current in Evidence; congruence. }
 revert Evidence; rewrite Source; intro Evidence; cbn [TicketedRequest.Scoped.next_call_selected TicketedRequest.Scoped.intent
   TicketedRequest.Scoped.run TicketedRequest.Scoped.target TicketedRequest.Scoped.issue TicketedRequest.Scoped.lower].
 unfold TicketedRequest.Scoped.issue, TicketedRequest.Scoped.lower.
 cbn [TicketedRequest.Scoped.target TicketedRequest.Scoped.intent].
 now rewrite ?Owner, ?Current.
Qed.

Theorem after_uses_the_current_operation : forall id before current operation plugin pending result error,
 find_task id before = Some current ->
 TicketedRequest.Scoped.operation_at (operation_id operation) current = Some operation ->
 operation_stage operation = AfterHooksReady (plugin :: pending) result error ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.after id (operation_id operation) before) =
 TicketedRequest.issue id (TicketedRequest.After operation plugin pending result error current) before.
Proof.
 intros id before current operation plugin pending result error Found Owned Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold TicketedRequest.Scoped.after; rewrite Selected.
 pattern (TicketedRequest.Scoped.after_operation_selected reference (operation_id operation) _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@TicketedRequest.Scoped.after_operation_selected before reference (operation_id operation))); intros found Evidence.
 assert (Present : found = Some operation) by (rewrite Current in Evidence; congruence).
 revert Evidence; rewrite Present; intro Evidence; cbn [TicketedRequest.Scoped.after_operation_selected].
 pattern (TicketedRequest.Scoped.after_stage_selected reference (operation_id operation) operation Evidence _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@TicketedRequest.Scoped.after_stage_selected before reference (operation_id operation) operation Evidence)); intros stage Stage.
 assert (Waiting : stage = AfterHooksReady (plugin :: pending) result error) by congruence.
 revert Stage; rewrite Waiting; intro Stage; cbn [TicketedRequest.Scoped.after_stage_selected TicketedRequest.Scoped.run
   TicketedRequest.Scoped.target TicketedRequest.Scoped.intent TicketedRequest.Scoped.issue TicketedRequest.Scoped.lower].
 unfold TicketedRequest.Scoped.issue, TicketedRequest.Scoped.lower.
 cbn [TicketedRequest.Scoped.target TicketedRequest.Scoped.intent].
 now rewrite ?Owner, ?Current.
Qed.
