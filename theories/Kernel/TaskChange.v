From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import Domain State TaskScope.
Import ListNotations.
Open Scope list_scope.

Inductive status := RunningStatus | FrozenStatus | StoppedStatus | ArchivedStatus.
Inductive edit :=
 | ChangeStatus (next : status)
 | ChangePhase (next : activity)
 | AppendHistory (messages : list message)
 | ReplaceHistory (messages : list message)
 | ReplaceQueued (messages : list content)
 | AppendQueued (message : content)
 | ChangeExecution (profile : profile) (settings : task_settings)
 | ChangeModelCursor (cursor : nat)
 | ChangeSideCursor (cursor : N)
 | AddOperation (operation : operation)
 | ChangeOperationStage (identity : N) (stage : operation_state)
 | AnnounceOperation (identity : N)
 | RemoveOperation (identity : N)
 | ClearOperations.
Definition change_status (next : status) (current : task) :=
 let phase := task_activity current in
 let operations := task_operations current in
 with_lifecycle (match next with
 | RunningStatus => Running phase operations | FrozenStatus => Frozen phase operations
 | StoppedStatus => Stopped phase operations | ArchivedStatus => Archived operations end) current.
Definition apply_edit (change : edit) (current : task) := match change with
 | ChangeStatus next => change_status next current
 | ChangePhase next => with_activity next current
 | AppendHistory messages => append_history messages current
 | ReplaceHistory messages => with_history messages current
 | ReplaceQueued messages => with_queued messages current
 | AppendQueued message => with_queued (task_queued current ++ [message]) current
 | ChangeExecution profile settings => with_execution profile settings current
 | ChangeModelCursor cursor => with_model_cursor cursor current
 | ChangeSideCursor cursor => with_side_cursor cursor current
 | AddOperation operation => with_operations (task_operations current ++ [operation]) current
 | ChangeOperationStage identity stage => with_operations
    (map (fun operation => if N.eqb identity (operation_id operation)
      then Operation (operation_id operation) (operation_call operation) (operation_announced operation) stage
      else operation) (task_operations current)) current
 | AnnounceOperation identity => with_operations
    (map (fun operation => if N.eqb identity (operation_id operation)
      then Operation (operation_id operation) (operation_call operation) true (operation_stage operation)
      else operation) (task_operations current)) current
 | RemoveOperation identity => with_operations
    (filter (fun operation => negb (N.eqb identity (operation_id operation))) (task_operations current)) current
 | ClearOperations => with_operations [] current
 end.
Definition apply (changes : list edit) (current : task) :=
 fold_left (fun task change => apply_edit change task) changes current.
Record plan (before : world) := Plan {
 target : TaskScope.task_reference before;
 changes : list edit
}.
Arguments target {before}.
Arguments changes {before}.
Definition interpret {before} (change : plan before) :=
 put_task (TaskScope.owner (target change))
   (apply (changes change) (TaskScope.selected (target change))) before.
