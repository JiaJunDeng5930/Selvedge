From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope TaskChange.
From Selvedge.Kernel Require TaskWake.
Import ListNotations.
Open Scope list_scope.

(* The same wake edit handles an idle task and an observation whose
   maintenance continuation needs to remember pending inference. *)
Inductive result_update := KeepDemand (changes : list TaskChange.edit) | WakeDemand (changes : list TaskChange.edit).
Definition result_changes (update : result_update) (current : task) := match update with
 | KeepDemand changes => changes
 | WakeDemand changes => changes ++ TaskWake.wake_after_result_changes (TaskChange.apply changes current) end.
Definition prefix_result (prefix : list TaskChange.edit) (update : result_update) := match update with
 | KeepDemand changes => KeepDemand (prefix ++ changes)
 | WakeDemand changes => WakeDemand (prefix ++ changes) end.
Definition apply_result (owner : N) (current : task) (update : result_update) (before : world) :=
 put_task owner (TaskChange.apply (result_changes update current) current) before.
Definition interpret_result {before} (target : TaskScope.task_reference before) (update : result_update) :=
 apply_result (TaskScope.owner target) (TaskScope.selected target) update before.
Definition commit_result (id : N) (update : task -> result_update) (before : world) :=
 match TaskScope.select id before with
 | Some target => interpret_result target (update (TaskScope.selected target))
 | None => before end.
