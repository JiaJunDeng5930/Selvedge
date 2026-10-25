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
 unfold TicketedRequest.Scoped.observe.
 rewrite (selected_result_erases_its_lookup_witness decision id before
   (fun candidate => TicketedRequest.Scoped.run (match candidate with
     | Some reference => TicketedRequest.Scoped.observe_selected publish reference
     | None => None end))
   (fun owner task => if TicketedRequest.Scoped.can_observe publish task before then TicketedRequest.issue owner
     (TicketedRequest.Observe (if publish then TicketedRequest.publish_operations (Tasks.promote task) else task)) before
     else State.ignored before)
   (State.ignored before)) by (intros; first [apply observe_selected_erases_its_capability|reflexivity]).
 now rewrite Found.
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
 unfold TicketedRequest.Scoped.model.
 rewrite (selected_result_erases_its_lookup_witness decision id before
   (fun candidate => TicketedRequest.Scoped.run (match candidate with
     | Some reference => TicketedRequest.Scoped.model_selected reference
     | None => None end))
   (fun owner task => if TicketedRequest.Scoped.can_infer task before then computed_model owner task before
     else State.ignored before) (State.ignored before))
   by (intros; first [apply model_selected_erases_its_capability|reflexivity]).
 now rewrite Found, Allowed.
Qed.

Theorem a_scoped_request_writes_only_its_actual_target : forall before
 (request : TicketedRequest.Scoped.plan before) other,
 TaskScope.owner (TicketedRequest.Scoped.target request) <> other ->
 find_task other (decision_world (TicketedRequest.Scoped.issue request)) = find_task other before.
Proof.
 intros before request other Different.
 apply TicketedRequestProofs.issue_preserves_other_tasks; exact Different.
Qed.

Definition erased_plan {before} (candidate : option (TicketedRequest.Scoped.plan before)) :=
 option_map (fun request => (TaskScope.owner (TicketedRequest.Scoped.target request),
   TaskScope.selected (TicketedRequest.Scoped.target request),
   TicketedRequest.Scoped.lower request)) candidate.
Definition identified_call {before} (reference : TaskScope.task_reference before)
 (source : option TicketedRequest.Scoped.action)
 (evidence : TicketedRequest.Scoped.call_action (TaskScope.selected reference) = source) :=
 match source as chosen return TicketedRequest.Scoped.call_action (TaskScope.selected reference) = chosen ->
   option (TicketedRequest.Scoped.plan before) with
 | Some (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining) => fun evidence =>
   Some (TicketedRequest.Scoped.Plan before reference
     (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining) evidence)
 | Some (TicketedRequest.Scoped.StartCall tool invocation remaining authority) => fun evidence =>
   Some (TicketedRequest.Scoped.Plan before reference
     (TicketedRequest.Scoped.StartCall tool invocation remaining authority) evidence)
 | _ => fun _ => None end evidence.
Definition computed_call (owner : N) (current : task) (source : option TicketedRequest.Scoped.action) := match source with
 | Some (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining) =>
   Some (owner,current,TicketedRequest.Before plugin tool invocation pending remaining current)
 | Some (TicketedRequest.Scoped.StartCall tool invocation remaining authority) =>
   Some (owner,current,TicketedRequest.Start tool invocation remaining authority current)
 | _ => None end.
Lemma identified_call_erases_its_evidence : forall before reference source evidence,
 erased_plan (@identified_call before reference source evidence) =
 computed_call (TaskScope.owner reference) (TaskScope.selected reference) source.
Proof. intros before reference [[]|] evidence; reflexivity. Qed.

Theorem next_call_uses_the_current_task : forall id before current,
 find_task id before = Some current ->
 erased_plan (TicketedRequest.Scoped.next_call id before) =
 computed_call id current (TicketedRequest.Scoped.call_action current).
Proof.
 intros id before current Found.
 unfold TicketedRequest.Scoped.next_call.
 change (erased_plan (match TaskScope.select id before with
 | Some reference => identified_call reference _ eq_refl | None => None end) = computed_call id current (TicketedRequest.Scoped.call_action current)).
 rewrite (selected_result_erases_its_lookup_witness _ id before
   (fun candidate => erased_plan (match candidate with
    | Some reference => identified_call reference _ eq_refl | None => None end))
   (fun owner current => computed_call owner current (TicketedRequest.Scoped.call_action current)) None)
   by (intros; first [apply identified_call_erases_its_evidence|reflexivity]).
 now rewrite Found.
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
 assert (Erases : Scheduler.start_external id before =
   match erased_plan (TicketedRequest.Scoped.next_call id before) with
   | Some (owner,current,TicketedRequest.Start tool invocation remaining authority _) =>
     if N.ltb (N.of_nat (List.length (task_operations current))) Limits.operation_limit then
       TicketedRequest.issue owner (TicketedRequest.Start tool invocation remaining authority current) before
     else Scheduler.call_error id invocation "operation_limit"
       "This task has reached its in-flight operation limit; wait for results or cancel an operation" remaining current before
   | _ => State.ignored before end).
 { unfold Scheduler.start_external, TicketedRequest.Scoped.start.
   destruct (TicketedRequest.Scoped.next_call id before) as [[reference source evidence]|]; [destruct source|]; reflexivity. }
 rewrite Erases, (next_call_uses_the_current_task id before current Found), Ready; reflexivity.
Qed.

Theorem authorizing_uses_the_current_call : forall id before current plugin tool invocation pending remaining,
 find_task id before = Some current ->
 TicketedRequest.Scoped.call_action current =
   Some (TicketedRequest.Scoped.AuthorizeCall plugin tool invocation pending remaining) ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.authorize id before) =
 TicketedRequest.issue id (TicketedRequest.Before plugin tool invocation pending remaining current) before.
Proof.
 intros id before current plugin tool invocation pending remaining Found Ready.
 assert (Erases : TicketedRequest.Scoped.run (TicketedRequest.Scoped.authorize id before) =
   match erased_plan (TicketedRequest.Scoped.next_call id before) with
   | Some (owner,current,TicketedRequest.Before plugin tool invocation pending remaining _) =>
     TicketedRequest.issue owner (TicketedRequest.Before plugin tool invocation pending remaining current) before
   | _ => State.ignored before end).
 { unfold TicketedRequest.Scoped.authorize.
   destruct (TicketedRequest.Scoped.next_call id before) as [[reference source evidence]|]; [destruct source|]; reflexivity. }
 rewrite Erases, (next_call_uses_the_current_task id before current Found), Ready; reflexivity.
Qed.

Definition identified_after_stage {before} (reference : TaskScope.task_reference before)
 identity operation (owned : TicketedRequest.Scoped.operation_at identity
   (TaskScope.selected reference) = Some operation)
 (stage : operation_state) (ready : operation_stage operation = stage) :=
 match stage as selected return operation_stage operation = selected -> option (TicketedRequest.Scoped.plan before) with
 | AfterHooksReady (plugin :: pending) result error => fun ready =>
   Some (TicketedRequest.Scoped.Plan before reference
     (TicketedRequest.Scoped.AfterOperation operation plugin pending result error)
     (conj (eq_ind identity (fun key => TicketedRequest.Scoped.operation_at key
       (TaskScope.selected reference) = Some operation) owned (operation_id operation)
       (TicketedRequest.Scoped.operation_at_identity identity (TaskScope.selected reference) operation owned)) ready))
 | _ => fun _ => None end ready.
Definition computed_after_stage owner current operation stage before := match stage with
 | AfterHooksReady (plugin :: pending) result error =>
   TicketedRequest.issue owner (TicketedRequest.After operation plugin pending result error current) before
 | _ => State.ignored before end.
Lemma after_stage_erases_its_evidence : forall before reference identity operation owned stage ready,
 TicketedRequest.Scoped.run (@identified_after_stage before reference identity operation owned stage ready) =
 computed_after_stage (TaskScope.owner reference) (TaskScope.selected reference) operation stage before.
Proof.
 intros before reference identity operation owned [] ready; try reflexivity.
 destruct pending; reflexivity.
Qed.
Definition identified_after {before} (reference : TaskScope.task_reference before)
 identity (found : option operation)
 (owned : TicketedRequest.Scoped.operation_at identity (TaskScope.selected reference) = found) :=
 match found as selected return TicketedRequest.Scoped.operation_at identity
   (TaskScope.selected reference) = selected -> option (TicketedRequest.Scoped.plan before) with
 | Some operation => fun owned => identified_after_stage reference identity operation owned _ eq_refl
 | None => fun _ => None end owned.
Definition computed_after owner current found before := match found with
 | Some operation => computed_after_stage owner current operation (operation_stage operation) before
 | None => State.ignored before end.
Lemma after_operation_erases_its_evidence : forall before reference identity found owned,
 TicketedRequest.Scoped.run (@identified_after before reference identity found owned) =
 computed_after (TaskScope.owner reference) (TaskScope.selected reference) found before.
Proof.
 intros before reference identity [operation|] owned; cbn [identified_after computed_after];
 [apply after_stage_erases_its_evidence|reflexivity].
Qed.

Theorem after_uses_the_current_operation : forall id before current operation plugin pending result error,
 find_task id before = Some current ->
 TicketedRequest.Scoped.operation_at (operation_id operation) current = Some operation ->
 operation_stage operation = AfterHooksReady (plugin :: pending) result error ->
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.after id (operation_id operation) before) =
 TicketedRequest.issue id (TicketedRequest.After operation plugin pending result error current) before.
Proof.
 intros id before current operation plugin pending result error Found Owned Ready.
 unfold TicketedRequest.Scoped.after.
 change (TicketedRequest.Scoped.run (match TaskScope.select id before with
 | Some reference => identified_after reference (operation_id operation) _ eq_refl | None => None end) =
 TicketedRequest.issue id (TicketedRequest.After operation plugin pending result error current) before).
 rewrite (selected_result_erases_its_lookup_witness decision id before
   (fun candidate => TicketedRequest.Scoped.run (match candidate with
    | Some reference => identified_after reference (operation_id operation) _ eq_refl | None => None end))
   (fun owner current => computed_after owner current
     (TicketedRequest.Scoped.operation_at (operation_id operation) current) before) (State.ignored before))
   by (intros; first [apply after_operation_erases_its_evidence|reflexivity]).
 rewrite Found, Owned. unfold computed_after, computed_after_stage; now rewrite Ready.
Qed.
