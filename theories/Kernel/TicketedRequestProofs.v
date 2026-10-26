From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Kernel Require Import TaskScope.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State TicketedRequest LifecycleProofs ModelRequestConstructionProofs.
Import ListNotations.

Definition registry_replace_other := @Selvedge.Foundation.RegistryProofs.registry_replace_other.

(* A resumed operation additionally records its actual wake in an existing
   maintenance receiver. The other task entries and the remaining frame are
   unchanged; the receiver update is specified exactly below. *)
Theorem issue_preserves_other_tasks : forall owner source before other,
 owner <> other ->
 find_task other (decision_world (TicketedRequest.issue owner source before)) = find_task other before.
Proof.
 intros owner source before other Different.
 unfold TicketedRequest.issue; cbn [allocate_identity next_identity].
 destruct (TicketedRequest.build owner (world_next_ticket before) (world_environment before) source).
 cbn [decision_world accept].
 destruct source; cbn; rewrite ?TaskWakeProofs.context_wake_preserves_every_task_lookup;
 unfold find_task, put_task, with_tasks, with_ticket; cbn.
 all: apply registry_replace_other; exact Different.
Qed.
Theorem issue_preserves_world_frame : forall owner source before,
 let after := decision_world (TicketedRequest.issue owner source before) in
 world_sequence after = world_sequence before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = (match source with
   | TicketedRequest.Resume _ _ _ current =>
     world_features (Tasks.mark_context_wake owner current before)
   | _ => world_features before end) /\
 world_next_ticket after = N.succ (world_next_ticket before) /\
 List.length (world_tasks after) = List.length (world_tasks before).
Proof.
 intros owner source before. unfold TicketedRequest.issue; cbn [allocate_identity next_identity].
 destruct (TicketedRequest.build owner (world_next_ticket before) (world_environment before) source).
 cbn [decision_world accept].
 destruct source; cbn; try (unfold Tasks.mark_context_wake;
   destruct (task_lifecycle task) as [phase operations|phase operations|phase operations|operations];
   try destruct phase);
 unfold put_task, with_tasks, with_ticket, with_features; cbn;
 repeat split; try reflexivity; apply registry_replace_length.
Qed.
Definition coordinate (request : effect) : option (N*N) := match request with
 | RequestModel request => Some (ModelRequest.owner request, ModelRequest.ticket request)
 | ObserveContext owner ticket _
 | RequestReasoning owner ticket _ | CheckTool owner ticket _ _ _
 | ExecuteTool owner ticket _ _ _ _ _ | RequestApproval owner ticket _ _ _
 | CheckResult owner ticket _ _ _ _ _ => Some (owner,ticket)
 | _ => None end.
Theorem every_issued_effect_uses_the_installed_ticket : forall owner source before request,
 In request (decision_effects (TicketedRequest.issue owner source before)) ->
 coordinate request = Some (owner,world_next_ticket before).
Proof.
 intros owner source before request Member.
 destruct source; try destruct authority.
 all: try match type of Member with
 | In _ (decision_effects (TicketedRequest.issue _ (TicketedRequest.Infer ?current) _)) =>
   destruct (ModelRequest.choose owner current) eqn:Chosen;
   unfold TicketedRequest.issue, TicketedRequest.build in Member; cbn [allocate_identity next_identity] in Member; rewrite Chosen in Member
 end.
 all: cbn [TicketedRequest.issue TicketedRequest.build decision_effects accept] in Member;
   try contradiction; destruct Member as [<-|Impossible]; try contradiction; reflexivity.
Qed.
Theorem an_issued_after_hook_keeps_the_operation_and_ticket : forall owner operation plugin pending result error task before,
 let decision := TicketedRequest.issue owner
   (TicketedRequest.After operation plugin pending result error task) before in
 decision_effects decision = [CheckResult owner (world_next_ticket before)
   (operation_id operation) plugin (operation_call operation) result error] /\
 decision_world decision = put_task owner
   (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id operation) (operation_call operation) (operation_announced operation)
       (AwaitingAfterHook (world_next_ticket before) plugin pending result error)) (task_operations task)) task)
   (with_ticket (N.succ (world_next_ticket before)) before).
Proof. intros; split; reflexivity. Qed.

Definition request_task (source : TicketedRequest.request) := match source with
 | TicketedRequest.Observe task | TicketedRequest.Infer task
 | TicketedRequest.Before _ _ _ _ _ task | TicketedRequest.Start _ _ _ _ task
 | TicketedRequest.Resume _ _ _ task | TicketedRequest.After _ _ _ _ _ task => task end.
Definition execution_identity := ModelRequestConstructionProofs.execution_identity.
Lemma activity_keeps_execution_identity : forall phase task,
 execution_identity (with_activity phase task) = execution_identity task.
Proof. intros phase [contract profile settings lifecycle history queued lineage parent cursor consumed]; destruct lifecycle; reflexivity. Qed.
Lemma operations_keep_execution_identity : forall operations task,
 execution_identity (with_operations operations task) = execution_identity task.
Proof. intros operations [contract profile settings lifecycle history queued lineage parent cursor consumed]; destruct lifecycle; reflexivity. Qed.
Lemma cursor_keeps_execution_identity : forall cursor task,
 execution_identity (with_model_cursor cursor task) = execution_identity task.
Proof. reflexivity. Qed.
Lemma promote_keeps_execution_identity : forall task,
 execution_identity (Tasks.promote task) = execution_identity task.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
   try destruct phase; try destruct queued; try destruct calls; reflexivity.
Qed.
Lemma wake_keeps_execution_identity : forall task,
 execution_identity (Tasks.wake_after_result task) = execution_identity task.
Proof.
 intros task. rewrite TaskChangesProofs.waking_result_expression.
 destruct (task_lifecycle task) as [phase operations|phase operations|phase operations|operations];
 try destruct phase; try apply promote_keeps_execution_identity; reflexivity.
Qed.
Theorem request_can_only_change_its_tasks_progress : forall owner ticket environment source,
 execution_identity (fst (TicketedRequest.build owner ticket environment source)) =
 execution_identity (request_task source).
Proof.
 intros owner ticket environment source. destruct source; try destruct authority;
 cbn [TicketedRequest.build request_task fst];
 unfold TicketedRequest.append_operation;
 try (repeat rewrite promote_keeps_execution_identity;
   repeat rewrite wake_keeps_execution_identity;
   repeat rewrite activity_keeps_execution_identity;
   repeat rewrite operations_keep_execution_identity;
   repeat rewrite cursor_keeps_execution_identity; reflexivity).
 destruct (ModelRequest.choose owner task) as [choice|] eqn:Chosen; cbn [fst].
 - unfold execution_identity. rewrite pending_preserves_execution_identity.
   cbn [ModelRequest.issue ModelRequest.selection].
   eapply choosing_preserves_execution_identity; exact Chosen.
 - apply activity_keeps_execution_identity.
Qed.

Theorem fixed_inference_freezes_its_complete_context : forall owner source before chosen,
 ReasoningPlan.next owner source = ReasoningPlan.Fixed chosen ->
 exists request,
 decision_effects (TicketedRequest.issue owner (TicketedRequest.Infer source) before) = [RequestModel request] /\
 ModelRequest.owner request = owner /\
 ModelRequest.ticket request = world_next_ticket before /\
 ModelRequest.model (ModelRequest.selection request) = chosen /\
 ModelRequest.history request = task_history source /\
 task_model_cursor (ModelRequest.context_task request) = List.length (task_history source) /\
 task_contract (ModelRequest.context_task request) = task_contract source.
Proof.
 intros owner source before chosen Selected.
 destruct (choosing_a_fixed_profile owner source chosen Selected)
   as [choice [Chosen [Model Base]]].
 unfold TicketedRequest.issue, TicketedRequest.build; cbn [allocate_identity next_identity]. rewrite Chosen.
 eexists; cbn [decision_effects accept]. repeat split; try reflexivity.
 - exact Model.
 - cbn [ModelRequest.issue ModelRequest.history]. now rewrite Base.
 - unfold ModelRequest.context_task. cbn [ModelRequest.issue ModelRequest.selection ModelRequest.history].
   unfold Domain.with_history, with_model_cursor. cbn. rewrite Base; destruct source; reflexivity.
 - unfold ModelRequest.context_task. cbn [ModelRequest.issue ModelRequest.selection ModelRequest.history].
   unfold Domain.with_history, with_model_cursor. cbn. rewrite Base; destruct source; reflexivity.
Qed.

Theorem issued_model_selection_is_bound_to_its_actual_source : forall owner source before request,
 In (RequestModel request) (decision_effects (TicketedRequest.issue owner (TicketedRequest.Infer source) before)) ->
 ModelRequest.owner request = owner /\
 ModelRequest.ticket request = world_next_ticket before /\
 exists model remaining,
 ReasoningPlan.next owner source = ModelRequest.chosen_plan model remaining /\
 ModelRequest.model (ModelRequest.selection request) = model /\
 ModelRequest.base (ModelRequest.selection request) = ModelRequest.prepared owner source model remaining.
Proof.
 intros owner source before request Member.
 unfold TicketedRequest.issue, TicketedRequest.build in Member.
 destruct (ModelRequest.choose owner source) as [choice|] eqn:Chosen;
 cbn [decision_effects accept] in Member;
 destruct Member as [Equal|Impossible]; try contradiction; try discriminate.
 inversion Equal; subst request. split; [reflexivity|]. split; [reflexivity|].
 cbn [ModelRequest.issue ModelRequest.selection].
 eapply a_chosen_model_is_bound_to_the_actual_source; exact Chosen.
Qed.

(* Eligibility belongs to the plan, so interpreting it installs the receiver even
   when no scheduler guard or later effect filter runs. *)
Theorem scoped_observation_installs_its_receiver : forall before
 (request : TicketedRequest.Scoped.plan before) publish,
 TicketedRequest.Scoped.intent request = TicketedRequest.Scoped.ObserveTask publish ->
 let owner := TaskScope.owner (TicketedRequest.Scoped.target request) in
 let source := match TicketedRequest.Scoped.lower request with
   | TicketedRequest.Observe source => source | _ => TaskScope.selected (TicketedRequest.Scoped.target request) end in
 exists waiting,
 find_task owner (decision_world (TicketedRequest.Scoped.issue request)) = Some waiting /\
 task_activity waiting = ObservingContext (world_next_ticket before) (List.length (task_history source)) /\
 decision_effects (TicketedRequest.Scoped.issue request) =
   [ObserveContext owner (world_next_ticket before) source].
Proof.
 intros before [[owner current Found] intent Permission] publish Intent.
 cbn in Intent; subst intent.
 change (let source := if publish then TicketedRequest.publish_operations (Tasks.promote current) else current in
 exists waiting,
 find_task owner (decision_world (TicketedRequest.issue owner (TicketedRequest.Observe source) before)) = Some waiting /\
 task_activity waiting = ObservingContext (world_next_ticket before) (List.length (task_history source)) /\
 decision_effects (TicketedRequest.issue owner (TicketedRequest.Observe source) before) =
   [ObserveContext owner (world_next_ticket before) source]).
 cbn zeta.
 cbn [TicketedRequest.Scoped.admitted_action] in Permission.
 eexists; split.
 - unfold TicketedRequest.issue, TicketedRequest.build; cbn [decision_world accept].
   eapply find_put_task. exact Found.
 - split; [|reflexivity].
   unfold TicketedRequest.Scoped.can_observe in Permission.
   cbn [TaskScope.selected] in Permission.
   apply Bool.andb_true_iff in Permission as [_ Phase].
   destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   destruct lifecycle as [phase operations|phase operations|phase operations|operations];
     try discriminate Phase.
   destruct publish; cbn in Phase.
   + destruct phase; try discriminate Phase.
     destruct queued; reflexivity.
   + destruct phase; try discriminate Phase; reflexivity.
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

Lemma preparing_a_model_preserves_lifecycle : forall owner current model remaining,
 task_lifecycle (ModelRequest.prepared owner current model remaining) = task_lifecycle current.
Proof.
 intros owner current model [remaining|]; [|reflexivity].
 unfold ModelRequest.prepared, ModelRequest.Plans.generation.
 repeat match goal with |- context[if ?condition then _ else _] => destruct condition end;
 reflexivity.
Qed.

Theorem scoped_inference_installs_its_receiver : forall before
 (request : TicketedRequest.Scoped.plan before),
 TicketedRequest.Scoped.intent request = TicketedRequest.Scoped.InferTask ->
 exists waiting,
 find_task (TaskScope.owner (TicketedRequest.Scoped.target request))
   (decision_world (TicketedRequest.Scoped.issue request)) = Some waiting /\
 match decision_effects (TicketedRequest.Scoped.issue request) with
 | [RequestModel model] => task_activity waiting = ModelRequest.request_activity model
 | [RequestReasoning _ ticket snapshot] =>
   task_activity waiting = EvaluatingReasoning ticket (List.length (task_history snapshot))
 | _ => False end.
Proof.
 intros before request Intent.
 destruct (inference_plans_require_a_captured_running_context before request Intent)
   as [operations [Lifecycle Resources]].
 destruct request as [[owner current Found] intent Permission].
 cbn in Intent; subst intent.
 change (task_lifecycle current = Running ReadyForModel operations) in Lifecycle.
 change (exists waiting,
   find_task owner (decision_world (TicketedRequest.issue owner (TicketedRequest.Infer current) before)) = Some waiting /\
   match decision_effects (TicketedRequest.issue owner (TicketedRequest.Infer current) before) with
   | [RequestModel model] => task_activity waiting = ModelRequest.request_activity model
   | [RequestReasoning _ ticket snapshot] => task_activity waiting = EvaluatingReasoning ticket (List.length (task_history snapshot))
   | _ => False end).
 unfold TicketedRequest.issue, TicketedRequest.build; cbn [allocate_identity next_identity].
 destruct (ModelRequest.choose owner current) as [choice|] eqn:Chosen;
   eexists; split; cbn [decision_world decision_effects accept].
 - eapply find_put_task; exact Found.
 - apply ModelRequestConstructionProofs.installing_a_running_model_request_uses_its_sent_phase with
     (phase := ReadyForModel) (operations := operations).
   destruct (ModelRequestConstructionProofs.a_chosen_model_is_bound_to_the_actual_source owner current choice Chosen)
     as [model [remaining [_ [_ Base]]]].
   change (task_lifecycle (ModelRequest.base choice) = Running ReadyForModel operations).
   rewrite Base, preparing_a_model_preserves_lifecycle; exact Lifecycle.
 - eapply find_put_task; exact Found.
 - unfold with_activity; rewrite Lifecycle; reflexivity.
Qed.
