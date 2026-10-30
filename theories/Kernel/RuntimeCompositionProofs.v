From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State StateProofs Scheduler Packet RequestDeliveryProofs.
From Selvedge.Features Require Import Runtime Worktree TaskGraph Board TitleRuntime Compaction BoardProofs CompactionProofs.
Import ListNotations.

(* No quiet-world or identity-maintenance premise: the actual Packet entry
   retains the operation's reply through either bounded scheduling or durable
   callback deferral, including request normalization and feature finalization. *)
Theorem the_production_runtime_preserves_the_exact_operation_result :
 forall schedules source before current,
 decision_reply (Packet.prepare schedules source (Runtime.after_transition before current)) =
   decision_reply current.
Proof.
 intros schedules source before current; unfold Packet.prepare.
 destruct schedules; [|reflexivity].
 destruct (Packet.callback_input source).
 - rewrite deferred_delivery_preserves_reply; reflexivity.
 - rewrite bounded_scheduling_preserves_reply; reflexivity.
Qed.

(* A scoped observation can be followed across an arbitrarily busy scheduler.
   Each premise is a local obligation of the actual reconciliation or selected
   transition, including its exact before/after world. No premise constrains
   unselected tasks to be idle or disables the native command executor. *)
Theorem scheduling_preserves_a_local_observation :
 forall (kept : world -> Prop) execute permitted,
 (forall value, kept value -> kept (SideContext.reconcile value)) ->
 (forall value advanced,
   kept value ->
   Scheduler.find_step execute permitted 0 (world_tasks value) value = Some advanced ->
   kept (decision_world advanced)) ->
 forall fuel value effects,
 kept value -> kept (fst (Scheduler.schedule fuel execute permitted value effects)).
Proof.
 intros kept execute permitted Reconcile Step fuel; induction fuel; intros value effects Holds.
 - cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted].
   destruct (existsb Scheduler.effect_requires_commit effects); cbn;
     [exact Holds|apply Reconcile; exact Holds].
 - cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted].
   destruct (existsb Scheduler.effect_requires_commit effects); [exact Holds|].
   destruct (Scheduler.first_native_fork permitted 0
     (world_tasks (SideContext.reconcile value)) (SideContext.reconcile value));
     [cbn; apply Reconcile; exact Holds|].
   destruct (Scheduler.find_step execute permitted 0
      (world_tasks (SideContext.reconcile value)) (SideContext.reconcile value))
      as [advanced|] eqn:Next.
   + apply IHfuel. eapply Step; [apply Reconcile; exact Holds|exact Next].
   + cbn; apply Reconcile; exact Holds.
Qed.

Lemma each_selected_step_preserves_a_local_observation :
 forall (kept : world -> Prop) execute permitted value,
 kept value ->
 (forall owner task selected advanced,
   In task (world_tasks value) ->
   Scheduler.next_runnable_step permitted owner task value = Some selected ->
   Scheduler.interpret_step execute owner task value selected = Some advanced ->
   kept (decision_world advanced)) ->
 forall tasks first advanced,
 (forall task, In task tasks -> In task (world_tasks value)) ->
 Scheduler.find_step execute permitted first tasks value = Some advanced ->
 kept (decision_world advanced).
Proof.
 intros kept execute permitted value Holds Step tasks.
 induction tasks as [|task rest IH]; intros first advanced Present Selected; [discriminate|].
 cbn [Scheduler.find_step] in Selected.
 destruct (Scheduler.next_runnable_step permitted first task value) as [step|] eqn:Next.
 - destruct (Scheduler.interpret_step execute first task value step) as [result|] eqn:Result.
   + inversion Selected; subst. eapply Step; [apply Present; now left|exact Next|exact Result].
   + eapply IH; [intros; apply Present; now right|exact Selected].
 - eapply IH; [intros; apply Present; now right|exact Selected].
Qed.

(* A read may select one operation, registry entry, resource binding or field.
   The frame law speaks only about that read, so the same turn may freely
   change every unrelated task and feature registry. *)
Theorem a_scoped_read_survives_all_scheduling_steps :
 forall A (read : world -> A) execute permitted observed,
 (forall value, read value = observed -> read (SideContext.reconcile value) = observed) ->
 (forall value owner task selected advanced,
   read value = observed -> In task (world_tasks value) ->
   Scheduler.next_runnable_step permitted owner task value = Some selected ->
   Scheduler.interpret_step execute owner task value selected = Some advanced ->
   read (decision_world advanced) = observed) ->
 forall fuel value effects,
 read value = observed ->
 read (fst (Scheduler.schedule fuel execute permitted value effects)) = observed.
Proof.
 intros A read execute permitted observed Reconcile Step fuel value effects Holds.
 eapply scheduling_preserves_a_local_observation with (kept:=fun current => read current = observed); [exact Reconcile| |exact Holds].
 intros current advanced Retained Selected.
 eapply each_selected_step_preserves_a_local_observation; [exact Retained| | |exact Selected].
 - intros owner task selected result Member Next Interpreted.
   eapply Step; eauto.
 - auto.
Qed.
