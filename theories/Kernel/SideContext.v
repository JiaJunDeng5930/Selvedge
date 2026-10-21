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
Definition parent_key (id : N) := ContextKey (parent_definition id) [("task_id",number_text id)].
Definition changed_field (name before after : string) :=
 if String.eqb before after then [] else [FieldPatch name [TextEdit 0 before after]].
Definition observe_parent (id : N) (parent value : task) :=
 let key := parent_key id in
 let previous := ContextUpdates.find_snapshot key (ContextUpdates.bindings (task_history value)) in
 let status := task_status parent in let phase := Domain.activity_name (task_activity parent) in
 let current := Snapshot key (number_text (N.succ (N.of_nat (List.length (task_history value)))))
  [("task_id",number_text id);("status",status);("phase",phase)] in
 let change := match previous with
 | None => Some (Introduce current)
 | Some previous =>
   let old_status := ContextUpdates.find_text "status" (snapshot_fields previous) in
   let old_phase := ContextUpdates.find_text "phase" (snapshot_fields previous) in
   match old_status,old_phase with
   | Some before_status,Some before_phase =>
     let patches := (changed_field "status" before_status status ++ changed_field "phase" before_phase phase)%list in
     match patches with [] => None | _ => Some (Amend key (snapshot_revision previous) (snapshot_revision current) patches) end
   | _,_ => Some (Introduce current) end
 end in match change with Some change => append_history [ContextObservation change] value | None => value end.
Definition reconcile_task (parents : list task) (value : task) :=
 match task_lifecycle value, task_side_parent value with
 | Archived,_ | _,None => value
 | _,Some id => match registry_at id parents with Some parent => observe_parent id parent value | None => value end end.
Definition reconcile (value : world) :=
 with_tasks (map (reconcile_task (world_tasks value)) (world_tasks value)) value.
