From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State TicketedRequest LifecycleProofs ModelRequestConstructionProofs.
Import ListNotations.

Lemma registry_replace_other : forall (A : Type) (values : list A) selected queried replacement,
 selected <> queried ->
 registry_at queried (replace selected replacement values) = registry_at queried values.
Proof.
 intros A values; induction values as [|head rest IH]; intros selected queried replacement Different; cbn; [reflexivity|].
 destruct (N.eqb selected 0) eqn:Selected; destruct (N.eqb queried 0) eqn:Queried;
   cbn; rewrite ?Queried; try reflexivity.
 - apply N.eqb_eq in Selected; apply N.eqb_eq in Queried; congruence.
 - apply IH. apply N.eqb_neq in Selected; apply N.eqb_neq in Queried; lia.
Qed.

(* The only writable world components are one selected registry entry and the
   fresh-ticket counter. This lift applies to every request variant. *)
Theorem issue_preserves_other_tasks : forall owner source before other,
 owner <> other ->
 find_task other (decision_world (TicketedRequest.issue owner source before)) = find_task other before.
Proof.
 intros owner source before other Different.
 unfold TicketedRequest.issue.
 destruct (TicketedRequest.build owner (world_next_ticket before) (world_environment before) source).
 cbn [decision_world accept].
 unfold find_task, put_task, with_tasks, with_ticket; cbn.
 apply registry_replace_other; exact Different.
Qed.
Theorem issue_preserves_world_frame : forall owner source before,
 let after := decision_world (TicketedRequest.issue owner source before) in
 world_sequence after = world_sequence before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = world_features before /\
 world_next_ticket after = N.succ (world_next_ticket before) /\
 List.length (world_tasks after) = List.length (world_tasks before).
Proof.
 intros owner source before. unfold TicketedRequest.issue.
 destruct (TicketedRequest.build owner (world_next_ticket before) (world_environment before) source).
 cbn [decision_world accept].
 unfold put_task, with_tasks, with_ticket; cbn.
 repeat split; try reflexivity. apply registry_replace_length.
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
   unfold TicketedRequest.issue, TicketedRequest.build in Member; rewrite Chosen in Member
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
 intros task. unfold Tasks.wake_after_result.
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
 unfold TicketedRequest.issue, TicketedRequest.build. rewrite Chosen.
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
