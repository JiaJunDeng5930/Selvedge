From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskChange.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope TaskChangeProofs TaskWakeProofs TicketedRequest.
From Selvedge.Kernel Require Import ModelRequestConstructionProofs.
Import ListNotations.
Module S := TicketedRequest.Scoped.

(** One installation contract covers every admitted task instruction. The
    instruction contributes progress edits; it cannot replace an unrelated task
    or its creation fields. *)
Theorem issued_effects : forall before (request : S.plan before),
 decision_effects (S.issue request) = snd (S.build request (world_next_ticket before)).
Proof.
 intros; unfold S.issue; cbn [TicketedRequest.allocate_identity TicketedRequest.next_identity].
 destruct (S.build request (world_next_ticket before)); reflexivity.
Qed.
Theorem issued_task : forall before (request : S.plan before),
 find_task (TaskScope.owner (S.target request)) (decision_world (S.issue request)) =
 Some (TaskChange.apply (fst (S.build request (world_next_ticket before)))
   (TaskScope.selected (S.target request))).
Proof.
 intros; unfold S.issue; cbn [TicketedRequest.allocate_identity TicketedRequest.next_identity].
 destruct (S.build request (world_next_ticket before)); cbn [fst decision_world accept].
 destruct (S.intent request); rewrite ?context_wake_preserves_every_task_lookup;
 unfold find_task,put_task,with_tasks,with_ticket; cbn;
 eapply registry_replace_selected; exact (TaskScope.observed (S.target request)).
Qed.

Theorem fixed_inference_freezes_its_complete_context : forall before (request : S.plan before) chosen,
 S.intent request = S.InferTask ->
 let owner := TaskScope.owner (S.target request) in
 let source := TaskScope.selected (S.target request) in
 ReasoningPlan.next owner source = ReasoningPlan.Fixed chosen ->
 exists sent, decision_effects (S.issue request) = [RequestModel sent] /\
 ModelRequest.owner sent = owner /\ ModelRequest.ticket sent = world_next_ticket before /\
 ModelRequest.origin sent = source /\ ModelRequest.model (ModelRequest.selection sent) = chosen /\
 ModelRequest.history sent = task_history source /\
 task_model_cursor (ModelRequest.context_task sent) = List.length (task_history source) /\
 task_contract (ModelRequest.context_task sent) = task_contract source.
Proof.
 intros before request chosen Intent owner source Selected.
 destruct (choosing_a_fixed_profile owner source chosen Selected) as [choice [Chosen [Model Base]]].
 rewrite issued_effects. unfold S.build; rewrite Intent.
 fold owner source; rewrite Chosen.
 eexists; cbn [snd]. repeat split; try reflexivity.
 - exact Model.
 - cbn [ModelRequest.issue ModelRequest.history]. now rewrite Base.
 - unfold ModelRequest.context_task. cbn [ModelRequest.issue ModelRequest.selection ModelRequest.history].
   unfold Domain.with_history,with_model_cursor; cbn. now rewrite Base.
 - unfold ModelRequest.context_task. cbn [ModelRequest.issue ModelRequest.selection ModelRequest.history].
   unfold Domain.with_history,with_model_cursor; cbn. now rewrite Base.
Qed.

Theorem inference_plans_require_a_captured_running_context : forall before
 (request : TicketedRequest.Scoped.plan before),
 TicketedRequest.Scoped.intent request = TicketedRequest.Scoped.InferTask ->
 exists operations,
 task_lifecycle (TaskScope.selected (TicketedRequest.Scoped.target request)) =
   Running ReadyForModel operations /\
 TicketedRequest.Scoped.resources_available
   (TaskScope.selected (TicketedRequest.Scoped.target request)) before = true.
Proof.
 intros before [target intent Permission] Intent; cbn in Intent; subst intent.
 change (exists operations, task_lifecycle (TaskScope.selected target) = Running ReadyForModel operations /\
   TicketedRequest.Scoped.resources_available (TaskScope.selected target) before = true).
 cbn [TicketedRequest.Scoped.admitted_action] in Permission.
 unfold TicketedRequest.Scoped.can_infer in Permission.
 apply Bool.andb_true_iff in Permission as [Resources Phase].
 destruct (task_lifecycle (TaskScope.selected target)) as
   [phase operations|phase operations|phase operations|operations] eqn:Lifecycle;
   try discriminate Phase.
 destruct phase; try discriminate Phase.
 exists operations; split; [reflexivity|exact Resources].
Qed.

Theorem frozen_and_archived_cannot_construct_new_execution : forall before owner current source,
 (exists phase operations, task_lifecycle current = Frozen phase operations) \/
 (exists operations, task_lifecycle current = Archived operations) ->
 TicketedRequest.Scoped.admitted_action before owner current source ->
 exists operation plugin pending result error,
 source = TicketedRequest.Scoped.AfterOperation operation plugin pending result error /\
 TicketedRequest.Scoped.operation_at (operation_id operation) current = Some operation /\
 operation_stage operation = AfterHooksReady (plugin :: pending) result error.
Proof.
 intros before owner current source Paused Admitted.
 destruct Paused as [[phase [operations Lifecycle]]|[operations Lifecycle]];
 destruct source; cbn [TicketedRequest.Scoped.admitted_action] in Admitted.
 all: try (unfold TicketedRequest.Scoped.can_observe in Admitted;
   rewrite Lifecycle, andb_false_r in Admitted; discriminate).
 all: try (unfold TicketedRequest.Scoped.can_infer in Admitted;
   rewrite Lifecycle, andb_false_r in Admitted; discriminate).
 all: try (unfold TicketedRequest.Scoped.call_action, TicketedRequest.Scoped.can_execute in Admitted;
   rewrite Lifecycle in Admitted; discriminate).
 all: try (destruct Admitted as [Active _];
   unfold TicketedRequest.Scoped.can_execute in Active; rewrite Lifecycle in Active; discriminate).
 all: do 5 eexists; split; [reflexivity|exact Admitted].
Qed.
