From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope TaskChange.
From Selvedge.Kernel Require TaskWake.
Import ListNotations.
Open Scope list_scope.

(* A result transition records whether it calls the shared wake operation.
   Its interpreter also preserves that demand when maintenance temporarily
   owns the task's ObservingContext phase. Running this interpreter keeps
   both consequences of an actual wake together. *)
Inductive result_update := KeepDemand (changes : list TaskChange.edit) | WakeDemand (changes : list TaskChange.edit).
Definition result_changes (update : result_update) (current : task) := match update with
 | KeepDemand changes => changes
 | WakeDemand changes => changes ++ TaskWake.wake_after_result_changes (TaskChange.apply changes current) end.
Definition prefix_result (prefix : list TaskChange.edit) (update : result_update) := match update with
 | KeepDemand changes => KeepDemand (prefix ++ changes)
 | WakeDemand changes => WakeDemand (prefix ++ changes) end.
Definition apply_result (owner : N) (current : task) (update : result_update) (before : world) :=
 let value := put_task owner (TaskChange.apply (result_changes update current) current) before in
 match update with
 | KeepDemand _ => value
 | WakeDemand _ => TaskWake.mark_context_wake owner current value end.
Definition interpret_result {before} (target : TaskScope.task_reference before) (update : result_update) :=
 apply_result (TaskScope.owner target) (TaskScope.selected target) update before.
Definition commit_result (id : N) (update : task -> result_update) (before : world) :=
 match TaskScope.select id before with
 | Some target => interpret_result target (update (TaskScope.selected target))
 | None => before end.
