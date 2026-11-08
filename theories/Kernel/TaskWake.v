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
 | Running (ObservingContext ticket revision (ForMaintenance purpose false)) _
 | Frozen (ObservingContext ticket revision (ForMaintenance purpose false)) _ =>
   [TaskChange.ChangePhase (ObservingContext ticket revision (ForMaintenance purpose true))]
 | _ => promote_changes task end.
