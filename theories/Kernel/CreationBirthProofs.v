From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State Tasks.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

Theorem each_planned_start_appends_exactly_its_one_fresh_task :
 forall before (plan : Worktree.planned_start before),
 exists created,
 world_tasks (decision_world (Worktree.consume_planned_start plan before)) =
   world_tasks before ++ [created].
Proof.
 intros before [intent start resource admitted].
 unfold Worktree.consume_planned_start, Worktree.interpret_planned_birth, Worktree.born_decision, Worktree.born_world, Worktree.born_effects, Worktree.born_identity; cbn [Worktree.planned_task Worktree.planned_resource].
 destruct resource; eexists; reflexivity.
Qed.

Theorem each_planned_start_keeps_every_existing_task :
 forall before (plan : Worktree.planned_start before) owner existing,
 find_task owner before = Some existing ->
 find_task owner (decision_world (Worktree.consume_planned_start plan before)) = Some existing.
Proof.
 intros before plan owner existing Found.
 destruct (each_planned_start_appends_exactly_its_one_fresh_task before plan) as [created Registry].
 unfold find_task in *; rewrite Registry.
 eapply registry_lookup_preserved_by_append; exact Found.
Qed.

Theorem each_planned_start_installs_its_reported_fresh_reference :
 forall before (plan : Worktree.planned_start before),
 exists created,
 find_task (next_task before) (decision_world (Worktree.consume_planned_start plan before)) = Some created /\
 List.length (world_tasks (decision_world (Worktree.consume_planned_start plan before))) =
   S (List.length (world_tasks before)).
Proof.
 intros before plan.
 destruct (each_planned_start_appends_exactly_its_one_fresh_task before plan) as [created Registry].
 exists created; split.
 - unfold find_task,next_task; rewrite Registry. apply registry_lookup_at_appended_index.
 - rewrite Registry,length_app; cbn; apply PeanoNat.Nat.add_1_r.
Qed.

Theorem a_refused_start_is_atomic : forall entry cause before,
 decision_world (refuse_start entry cause before) = before /\
 decision_effects (refuse_start entry cause before) = [].
Proof. intros; split; reflexivity. Qed.
