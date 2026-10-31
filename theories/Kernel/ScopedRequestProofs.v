From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require Import OptionObservationProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskScopeProofs TicketedRequest.
Module S := TicketedRequest.Scoped.

(** Selection establishes availability. The returned plan itself retains the
    selected source and admission; no second, unscoped request is constructed. *)
Theorem observing_selects_the_current_task : forall id before current publish,
 find_task id before = Some current -> S.can_observe publish current before = true ->
 exists request, S.observe id publish before = Some request /\
 owner (S.target request) = id /\ selected (S.target request) = current /\
 S.intent request = S.ObserveTask publish.
Proof.
 intros id before current publish Found Allowed.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold S.observe,S.observe_selected; rewrite Selected.
 pattern (S.observe_allowed publish reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.observe_allowed before publish reference)).
 intros condition Evidence.
 assert (condition = true) by (rewrite Current,Allowed in Evidence; symmetry; exact Evidence).
 revert Evidence; rewrite H; intro Evidence.
 eexists; split; [reflexivity|]. cbn; repeat split; assumption.
Qed.

Theorem model_selects_the_current_task : forall id before current,
 find_task id before = Some current -> S.can_infer current before = true ->
 exists request, S.model id before = Some request /\
 owner (S.target request) = id /\ selected (S.target request) = current /\
 S.intent request = S.InferTask.
Proof.
 intros id before current Found Allowed.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold S.model,S.model_selected; rewrite Selected.
 pattern (S.model_allowed reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.model_allowed before reference)).
 intros condition Evidence.
 assert (condition = true) by (rewrite Current,Allowed in Evidence; symmetry; exact Evidence).
 revert Evidence; rewrite H; intro Evidence.
 eexists; split; [reflexivity|]. cbn; repeat split; assumption.
Qed.

Theorem starting_selects_the_current_call : forall id before current tool invocation remaining authority,
 find_task id before = Some current ->
 S.call_action current = Some (S.StartCall tool invocation remaining authority) ->
 exists request, S.start id before = Some (request,invocation,remaining) /\
 owner (S.target request) = id /\ selected (S.target request) = current /\
 S.intent request = S.StartCall tool invocation remaining authority.
Proof.
 intros id before current tool invocation remaining authority Found Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold S.start,S.next_call; rewrite Selected.
 pattern (S.next_call_selected reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.next_call_selected before reference)).
 intros source Evidence.
 assert (source = Some (S.StartCall tool invocation remaining authority)) by
   (rewrite Current,Ready in Evidence; symmetry; exact Evidence).
 revert Evidence; rewrite H; intro Evidence.
 eexists; split; [reflexivity|]. cbn; repeat split; assumption.
Qed.

Theorem authorizing_selects_the_current_call : forall id before current plugin tool invocation pending remaining,
 find_task id before = Some current ->
 S.call_action current = Some (S.AuthorizeCall plugin tool invocation pending remaining) ->
 exists request, S.authorize id before = Some request /\
 owner (S.target request) = id /\ selected (S.target request) = current /\
 S.intent request = S.AuthorizeCall plugin tool invocation pending remaining.
Proof.
 intros id before current plugin tool invocation pending remaining Found Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold S.authorize,S.next_call; rewrite Selected.
 pattern (S.next_call_selected reference _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.next_call_selected before reference)).
 intros source Evidence.
 assert (source = Some (S.AuthorizeCall plugin tool invocation pending remaining)) by
   (rewrite Current,Ready in Evidence; symmetry; exact Evidence).
 revert Evidence; rewrite H; intro Evidence.
 eexists; split; [reflexivity|]. cbn; repeat split; assumption.
Qed.

Theorem after_selects_the_current_operation : forall id before current operation plugin pending result error,
 find_task id before = Some current ->
 S.operation_at (operation_id operation) current = Some operation ->
 operation_stage operation = AfterHooksReady (plugin :: pending) result error ->
 exists request, S.after id (operation_id operation) before = Some request /\
 owner (S.target request) = id /\ selected (S.target request) = current /\
 S.intent request = S.AfterOperation operation plugin pending result error.
Proof.
 intros id before current operation plugin pending result error Found Owned Ready.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [reference [Selected [Owner Current]]].
 unfold S.after; rewrite Selected.
 pattern (S.after_operation_selected reference (operation_id operation) _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.after_operation_selected before reference (operation_id operation))).
 intros found Evidence.
 assert (Present : found = Some operation) by (rewrite Current in Evidence; congruence).
 revert Evidence; rewrite Present; intro Evidence; cbn [S.after_operation_selected].
 pattern (S.after_stage_selected reference (operation_id operation) operation Evidence _ eq_refl).
 apply (@observed_value_elimination _ _ _ (@S.after_stage_selected before reference (operation_id operation) operation Evidence)).
 intros stage Stage.
 assert (Waiting : stage = AfterHooksReady (plugin :: pending) result error) by congruence.
 revert Stage; rewrite Waiting; intro Stage.
 eexists; split; [reflexivity|]. cbn; repeat split; assumption.
Qed.
