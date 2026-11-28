From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Numbers.
From Selvedge.Programming Require TaskChange.
From Selvedge.Features Require CompactionTypes Domain State.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope list_scope.

Definition wait_result (invocation : call) :=
 FunctionOutput (call_id invocation) (number 0) false.
Definition finish_wait (invocation : call) (remaining : list call) :=
 [TaskChange.AppendHistory [wait_result invocation]; TaskChange.ChangePhase (PendingCalls remaining)].
Definition wait_for_input (invocation : call) (remaining : list call) (task : task) :=
 if waiting_input_available task
 then finish_wait invocation remaining
 else [TaskChange.ChangePhase (WaitingForInput invocation remaining)].
Definition receive_waiting (invocation : call) (remaining : list call) (queued : list content) :=
 finish_wait invocation remaining ++
 [TaskChange.AppendHistory (map UserMessage queued); TaskChange.ReplaceQueued []].

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
Definition promote_scheduled_input (task : task) :=
 match task_activity task with
 | WaitingForInput invocation remaining => receive_waiting invocation remaining (task_queued task)
 | _ => promote_changes task end.
Definition wake_after_result_changes (task : task) : list TaskChange.edit :=
 match task_lifecycle task with
 | Running Idle _ | Frozen Idle _ => [TaskChange.ChangePhase WantsModel]
 | Running (ObservingContext ticket revision (ForMaintenance purpose false)) _
 | Frozen (ObservingContext ticket revision (ForMaintenance purpose false)) _ =>
   [TaskChange.ChangePhase (ObservingContext ticket revision (ForMaintenance purpose true))]
 | _ => promote_changes task end.

(* An input commits the suspended call's receipt before appending its payload. *)
Definition resume_for_input (task : task) :=
 match task_lifecycle task with
 | Running (WaitingForInput invocation remaining) _
 | Frozen (WaitingForInput invocation remaining) _ => finish_wait invocation remaining
 | _ => [] end.
