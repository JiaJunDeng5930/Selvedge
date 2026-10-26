From Selvedge.Foundation Require Import SequenceProofs.
From Selvedge.Kernel Require Import CallbackChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks History Callbacks
 LifecycleProofs WorldInvariant WorldInvariantProofs TaskWakeProofs.
Import ListNotations.
Open Scope list_scope.

(* Waking an owner may release already committed input. It cannot replace the
   result that woke it, or change the remaining operation rights. *)
Lemma waking_a_result_preserves_operations_and_only_releases_queued_input :
 forall task,
 task_operations (Tasks.wake_after_result task) = task_operations task /\
 exists released,
 task_history (Tasks.wake_after_result task) =
   task_history task ++ map UserMessage released /\
 (released = [] \/ released = task_queued task).
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|];
 try destruct phase as [ | | | observing revision | asking allowed mode | checking revision |
   calls | invocation plugins calls | checking plugin invocation plugins calls ];
 try destruct calls as [|first_call other_calls];
 destruct queued as [|first rest];
 cbn [Tasks.wake_after_result Tasks.wake_after_result_changes Tasks.promote Tasks.promote_changes TaskChange.apply TaskChange.apply_edit task_operations task_history task_queued
   with_lifecycle with_queued append_history with_history].
 all: split.
 all: try reflexivity.
 all: first
   [ solve [exists []; rewrite app_nil_r; auto]
   | solve [exists (first :: rest); split; [reflexivity|right; reflexivity]] ].
Qed.

Theorem tool_completion_without_after_hooks_settles_the_exact_owned_result :
 forall id ticket result error value task operation,
 find_task id value = Some task ->
 find (Callbacks.operation_executing ticket) (task_operations task) = Some operation ->
 Callbacks.after_plugins task = [] ->
 let completed := Callbacks.tool_completed id ticket result error value in
 decision_effects completed = [] /\
 exists updated released,
 find_task id (decision_world completed) = Some updated /\
 task_operations updated = Callbacks.remove_operation (operation_id operation) (task_operations task) /\
 task_history updated = task_history task ++
   [if operation_announced operation
    then OperationResult (operation_id operation) (operation_call operation) result error
    else FunctionOutput (call_id (operation_call operation)) result error] ++
   map UserMessage released /\
 (released = [] \/ released = task_queued task).
Proof.
 intros id ticket result error value task operation Found Owned Hooks.
 rewrite !tool_completed_expression; rewrite Found, Owned.
 unfold Callbacks.begin_result_plan; rewrite Hooks.
 change (Tasks.apply_result id task (Callbacks.settle_operation_plan operation result error) value)
   with (Tasks.mark_context_wake id task (put_task id (Callbacks.settle_operation operation result error task) value)).
 cbn [decision_effects decision_world acknowledged accept].
 rewrite context_wake_preserves_every_task_lookup, settle_operation_expression.
 split; [reflexivity|].
 set (settled := with_operations
   (Callbacks.remove_operation (operation_id operation) (task_operations task))
   (append_history [History.operation_result operation result error] task)).
 pose proof (waking_a_result_preserves_operations_and_only_releases_queued_input settled)
   as [Operations [released [History Released]]].
 exists (Tasks.wake_after_result settled), released; split.
 - apply find_put_task with task; exact Found.
 - unfold settled in *.
   destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   destruct lifecycle as [phase operations|phase operations|phase operations|];
   cbn [task_operations] in Owned; try discriminate;
   cbn [task_operations task_history task_queued with_operations append_history
     with_lifecycle with_history] in Operations, History, Released |- *;
   rewrite Operations, History; repeat split; try assumption; try reflexivity;
   cbn; rewrite <- app_assoc; reflexivity.
Qed.

Definition distinct_ticket_prefix_and_suffix := SequenceProofs.distinct_app_parts N.

Lemma executing_ticket_belongs_to_the_operation : forall ticket operation,
 Callbacks.operation_executing ticket operation = true ->
 In ticket (WorldInvariant.operation_tickets operation).
Proof.
 intros ticket operation Executing.
 unfold Callbacks.operation_executing, RequestReceiver.operation_executing, RequestReceiver.operation_receiver in Executing.
 unfold WorldInvariant.operation_tickets.
 destruct (operation_stage operation) as [expected|expected actor|actor|expected actor|pending result error|expected plugin pending result error];
   try discriminate;
 apply N.eqb_eq in Executing; subst expected;
 destruct (N.eqb ticket (operation_id operation)) eqn:Same.
 - apply N.eqb_eq in Same; subst ticket; cbn; auto.
 - cbn; auto.
 - apply N.eqb_eq in Same; subst ticket; cbn; auto.
 - cbn; auto.
Qed.

Lemma no_execution_after_removing_the_ticket_owner : forall operations ticket operation,
 NoDup (flat_map WorldInvariant.operation_tickets operations) ->
 find (Callbacks.operation_executing ticket) operations = Some operation ->
 find (Callbacks.operation_executing ticket)
   (Callbacks.remove_operation (operation_id operation) operations) = None.
Proof.
 intros operations; induction operations as [|first rest IH]; intros ticket operation Unique Owned;
   cbn in Owned; [discriminate|].
 cbn [flat_map] in Unique.
 destruct (distinct_ticket_prefix_and_suffix _ _ Unique) as [_ [Tail Disjoint]].
 destruct (Callbacks.operation_executing ticket first) eqn:Executes.
 - inversion Owned; subst operation.
   cbn [Callbacks.remove_operation filter]; rewrite N.eqb_refl; cbn.
   apply find_none_when_rejected; intros other Member.
   apply filter_In in Member as [Member _].
   destruct (Callbacks.operation_executing ticket other) eqn:Other; [|reflexivity].
   exfalso; apply (Disjoint ticket (executing_ticket_belongs_to_the_operation _ _ Executes)).
   apply in_flat_map; exists other; split; [exact Member|].
   exact (executing_ticket_belongs_to_the_operation _ _ Other).
 - cbn [Callbacks.remove_operation filter].
   destruct (negb (N.eqb (operation_id operation) (operation_id first))); cbn;
   try rewrite Executes; apply IH; assumption.
Qed.

Definition a_registry_lookup_is_a_member := @RegistryProofs.registry_lookup_is_member.

Lemma distinct_flattened_tickets_include_each_owner : forall (A : Type)
 (tickets : A -> list N) owners owner,
 NoDup (flat_map tickets owners) -> In owner owners -> NoDup (tickets owner).
Proof.
 intros A tickets owners; induction owners as [|first rest IH]; intros owner Unique Member;
   [contradiction|].
 cbn [flat_map] in Unique.
 destruct (distinct_ticket_prefix_and_suffix _ _ Unique) as [First [Tail _]].
 destruct Member as [Same|Later]; [subst; exact First|].
 apply IH; assumption.
Qed.

Lemma valid_world_execution_tickets_are_unique : forall id value task,
 WorldInvariant.tickets_valid value = true -> find_task id value = Some task ->
 NoDup (flat_map WorldInvariant.operation_tickets (task_operations task)).
Proof.
 intros id value task Valid Found.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners value Valid) as [Unique _].
 destruct (distinct_ticket_prefix_and_suffix _ _ Unique) as [Tasks _].
 assert (NoDup (WorldInvariant.task_tickets task)) as TaskTickets.
 { eapply distinct_flattened_tickets_include_each_owner; [exact Tasks|].
   eapply a_registry_lookup_is_a_member; exact Found. }
 unfold WorldInvariant.task_tickets in TaskTickets.
 destruct (distinct_ticket_prefix_and_suffix _ _ TaskTickets) as [_ [Operations _]].
 exact Operations.
Qed.

Theorem an_owned_tool_completion_is_consumed_once_without_after_hooks :
 forall id ticket result error value task operation,
 WorldInvariant.tickets_valid value = true ->
 find_task id value = Some task ->
 find (Callbacks.operation_executing ticket) (task_operations task) = Some operation ->
 Callbacks.after_plugins task = [] ->
 let completed := Callbacks.tool_completed id ticket result error value in
 forall repeated_result repeated_error,
 Callbacks.tool_completed id ticket repeated_result repeated_error (decision_world completed) =
   Callbacks.ignored (decision_world completed).
Proof.
 intros id ticket result error value task operation Valid Found Owned Hooks completed
   repeated_result repeated_error.
 pose proof (tool_completion_without_after_hooks_settles_the_exact_owned_result
   id ticket result error value task operation Found Owned Hooks)
   as [_ [updated [released [Updated [Operations _]]]]].
 unfold completed; rewrite tool_completed_expression at 1; rewrite Updated, Operations.
 rewrite no_execution_after_removing_the_ticket_owner with (operation := operation).
 - reflexivity.
 - eapply valid_world_execution_tickets_are_unique; eauto.
 - exact Owned.
Qed.

(* A result records demand while frozen; resuming uses that phase rather than
   inferring pending work from the historical messages. *)
Theorem a_frozen_idle_result_records_demand_and_keeps_its_operations :
 forall task operations,
 task_lifecycle task = Frozen Idle operations ->
 task_lifecycle (Tasks.wake_after_result task) = Frozen WantsModel operations /\
 task_operations (Tasks.wake_after_result task) = operations.
Proof.
 intros task operations Frozen; unfold Tasks.wake_after_result, Tasks.wake_after_result_changes.
 rewrite Frozen; cbn [TaskChange.apply TaskChange.apply_edit fold_left].
 unfold with_activity; rewrite Frozen.
 split; reflexivity.
Qed.

Theorem freezing_settling_and_unfreezing_preserves_the_result_demand :
 forall task operations operation result error,
 task_lifecycle task = Running Idle operations ->
 let settled := Callbacks.settle_operation operation result error
   (Tasks.control_task Tasks.Freeze task) in
 task_lifecycle settled = Frozen WantsModel (Callbacks.remove_operation (operation_id operation) operations) /\
 task_lifecycle (Tasks.control_task Tasks.Unfreeze settled) =
   Running WantsModel (Callbacks.remove_operation (operation_id operation) operations).
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed]
  operations operation result error Idle; cbn in Idle; subst lifecycle.
 split; reflexivity.
Qed.

Theorem an_owned_tool_completion_while_frozen_keeps_the_unfreeze_demand :
 forall id ticket result error value task operations operation,
 find_task id value = Some task ->
 task_lifecycle task = Frozen Idle operations ->
 find (Callbacks.operation_executing ticket) (task_operations task) = Some operation ->
 Callbacks.after_plugins task = [] ->
 exists settled,
 find_task id (decision_world (Callbacks.tool_completed id ticket result error value)) = Some settled /\
 task_lifecycle settled = Frozen WantsModel (Callbacks.remove_operation (operation_id operation) operations) /\
 task_lifecycle (Tasks.control_task Tasks.Unfreeze settled) =
   Running WantsModel (Callbacks.remove_operation (operation_id operation) operations).
Proof.
 intros id ticket result error value task operations operation Found Frozen Owned Hooks.
 rewrite !tool_completed_expression; rewrite Found, Owned.
 unfold Callbacks.begin_result_plan; rewrite Hooks.
 change (Tasks.apply_result id task (Callbacks.settle_operation_plan operation result error) value)
   with (Tasks.mark_context_wake id task (put_task id (Callbacks.settle_operation operation result error task) value)).
 cbn [decision_world acknowledged accept].
 rewrite context_wake_preserves_every_task_lookup.
 exists (Callbacks.settle_operation operation result error task); split.
 - apply find_put_task with task; exact Found.
 - destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   cbn in Frozen; subst lifecycle; split; reflexivity.
Qed.

Theorem an_owned_cancellation_while_frozen_keeps_the_unfreeze_demand :
 forall id identity value task operations operation,
 find_task id value = Some task ->
 task_lifecycle task = Frozen Idle operations ->
 find (fun pending => N.eqb identity (operation_id pending)) (task_operations task) = Some operation ->
 exists settled,
 find_task id (decision_world (Tasks.cancel_operation id identity value)) = Some settled /\
 task_lifecycle settled = Frozen WantsModel
   (filter (fun pending => negb (N.eqb identity (operation_id pending))) operations) /\
 task_lifecycle (Tasks.control_task Tasks.Unfreeze settled) = Running WantsModel
   (filter (fun pending => negb (N.eqb identity (operation_id pending))) operations).
Proof.
 intros id identity value task operations operation Found Frozen Owned.
 rewrite TaskChangesProofs.cancel_operation_expression, Found, Owned.
 cbn [decision_world accept]. rewrite context_wake_preserves_every_task_lookup.
 eexists; split; [apply find_put_task with task; exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 cbn in Frozen; subst lifecycle; split; reflexivity.
Qed.
