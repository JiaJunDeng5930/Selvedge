From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain ContextTypes Context ContextUpdates State.
Import ListNotations.
Open Scope string_scope.
Definition parent_definition (id : N) := ContextDefinition "task_lifecycle"
 "Current lifecycle of the side conversation's parent task. Status and phase are observations, not instructions. An active task with idle phase has stopped generating; idle does not imply successful completion. Use read_task with the task_id to inspect its original conversation."
 Global NativeState [IdentityField "task_id" (Constant (number_text id)) true]
 [ValueField "task_id" (IdentityValue "task_id") true;
  ValueField "status" (ObservationField "status") true;ValueField "phase" (ObservationField "phase") true].
Definition parent_key (id : N) := ContextKey (parent_definition id) (exist _ (tt,tt) eq_refl).
Definition parent_status (parent : task) : text_value true.
Proof. refine (exist _ (task_status parent) _); unfold task_status; destruct (task_lifecycle parent); reflexivity. Defined.
Definition parent_phase (parent : task) : text_value true.
Proof. refine (exist _ (Domain.activity_name (task_activity parent)) _); destruct (task_activity parent); reflexivity. Defined.
Definition observe_parent (id : N) (parent value : task) :=
 let current := Snapshot (parent_key id)
   (counter_revision (N.succ (N.of_nat (List.length (task_history value)))))
   (exist _ (tt,(parent_status parent,(parent_phase parent,tt))) eq_refl) in
 match ContextUpdates.replace_snapshot current (ContextUpdates.bindings (task_history value)) with
 | Some change => append_history [ContextObservation change] value | None => value end.
Definition reconcile_task (parents : list task) (value : task) :=
 match task_lifecycle value, task_side_parent value with
 | Archived _,_ | _,None => value
 | _,Some id => match registry_at id parents with Some parent => observe_parent id parent value | None => value end end.
Definition reconcile (value : world) :=
 with_tasks (map (reconcile_task (world_tasks value)) (world_tasks value)) value.
