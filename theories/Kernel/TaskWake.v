From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require TaskChange.
From Selvedge.Features Require CompactionTypes Domain State.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope list_scope.

Definition promote_changes (task : task) : list TaskChange.edit :=
 match task_lifecycle task, task_queued task with
 | Running Idle operations, first :: rest | Running (PendingCalls []) operations, first :: rest
 | Running WantsModel operations, first :: rest =>
   [TaskChange.ChangePhase WantsModel; TaskChange.ReplaceQueued [];
    TaskChange.AppendHistory (map UserMessage (first :: rest))]
 | Stopped Idle operations, first :: rest | Stopped (PendingCalls []) operations, first :: rest =>
   [TaskChange.ChangePhase Idle; TaskChange.ReplaceQueued [];
    TaskChange.AppendHistory (map UserMessage (first :: rest))]
 | _,_ => [] end.
Definition promote (task : task) := TaskChange.apply (promote_changes task) task.
Definition wake_after_result_changes (task : task) : list TaskChange.edit :=
 match task_lifecycle task with
 | Running Idle _ | Frozen Idle _ => [TaskChange.ChangePhase WantsModel]
 | _ => promote_changes task end.
Definition wake_after_result (task : task) := TaskChange.apply (wake_after_result_changes task) task.

Definition wake_context_entry (owner ticket : N) (pair : N * Selvedge.Features.CompactionTypes.entry) :=
 let '(id,entry) := pair in
 if N.eqb owner id then match Selvedge.Features.CompactionTypes.entry_job entry with
   | Selvedge.Features.CompactionTypes.AwaitingContext expected purpose demand =>
     if N.eqb ticket expected then (id, set Selvedge.Features.CompactionTypes.entry_job
       (fun _ => Selvedge.Features.CompactionTypes.AwaitingContext expected purpose true) entry) else pair
   | _ => pair end else pair.
Definition mark_context_wake (owner : N) (current : task) (value : world) :=
 match task_lifecycle current with
 | Running (ObservingContext ticket _) _ | Frozen (ObservingContext ticket _) _ =>
   let features := world_features value in
   let state := Selvedge.Features.Domain.feature_compaction features in
   let entries := map (wake_context_entry owner ticket) (Selvedge.Features.CompactionTypes.maintenance_entries state) in
   with_features (Selvedge.Features.State.with_compaction
     (set Selvedge.Features.CompactionTypes.maintenance_entries (fun _ => entries) state) features) value
 | _ => value end.
