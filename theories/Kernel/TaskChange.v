From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import Focus.
From Selvedge.Kernel Require Import Domain State TaskScope History.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope list_scope.

Inductive status := RunningStatus | FrozenStatus | StoppedStatus | ArchivedStatus.

(** Task operations can update execution progress and append receipts.  They
    cannot replace history or rewrite the creation contract and ancestry. *)
Record mutable := Mutable {
 current_lifecycle : lifecycle;
 current_queued : list content;
 current_side_cursor : N;
 current_model_cursor : nat
}.
Definition task_parts (value : task) :=
 ((Mutable (task_lifecycle value) (task_queued value) (task_side_cursor value) (task_model_cursor value),
   task_history value),
  (task_contract value, task_current_profile value, task_current_settings value,
   task_lineage value, task_side_parent value)).
Definition from_parts
 (parts : (mutable * list message) * (contract * profile * task_settings * list N * option N)) :=
 let '((current,history),(contract,profile,settings,lineage,parent)) := parts in
 Task contract profile settings
   (current_lifecycle current) history (current_queued current) lineage parent
   (current_side_cursor current) (current_model_cursor current).
Definition task_focus : Focus.t task (mutable * list message).
Proof.
 refine (Focus.Focus _ _ _ task_parts from_parts _ _).
 - intros []; reflexivity.
 - intros [[[] history] [[[[contract profile] settings] lineage] parent]]; reflexivity.
Defined.

Record edit := Edit {
 update : mutable -> mutable;
 appended : option (list message)
}.
Definition modify (change : mutable -> mutable) := Edit change None.
Definition ChangeStatus (next : status) := modify (fun current =>
 let '(phase,operations) := match current_lifecycle current with
 | Running phase operations | Frozen phase operations | Stopped phase operations => (phase,operations)
 | Archived operations => (Idle,operations) end in
 set current_lifecycle (fun _ => match next with
 | RunningStatus => Running phase operations | FrozenStatus => Frozen phase operations
 | StoppedStatus => Stopped phase operations | ArchivedStatus => Archived operations end) current).
Definition ChangePhase (next : activity) := modify (fun current =>
 set current_lifecycle (change_activity next) current).
Definition AppendHistory (messages : list message) := Edit (fun current => current) (Some messages).
Definition ReplaceQueued (messages : list content) := modify (set current_queued (fun _ => messages)).
Definition AppendQueued (message : content) := modify (set current_queued (fun queued => queued ++ [message])).
Definition ChangeModelCursor (cursor : nat) := modify (set current_model_cursor (fun _ => cursor)).
Definition ChangeSideCursor (cursor : N) := modify (set current_side_cursor (fun _ => cursor)).
Definition operation_change (change : list operation -> list operation) := modify
 (set current_lifecycle (change_operations change)).
Definition AddOperation (operation : operation) := operation_change (fun operations => operations ++ [operation]).
Definition ChangeOperationStage (identity : N) (stage : operation_state) := operation_change
 (map (fun operation => if N.eqb identity (operation_id operation)
   then Operation (operation_id operation) (operation_call operation) (operation_announced operation) stage
   else operation)).
Definition AnnounceOperation (identity : N) := operation_change
 (map (fun operation => if N.eqb identity (operation_id operation)
   then Operation (operation_id operation) (operation_call operation) true (operation_stage operation)
   else operation)).
Definition RemoveOperation (identity : N) := operation_change
 (filter (fun operation => negb (N.eqb identity (operation_id operation)))) .
Definition CompleteOperation (operation : operation) (result : Json.json) (error : bool) :=
 Edit (update (RemoveOperation (operation_id operation)))
   (Some [History.operation_result operation result error]).
Definition CancelOperation (operation : operation) :=
 Edit (update (RemoveOperation (operation_id operation)))
   (Some [History.cancelled_operation operation]).
Definition ClearOperations := operation_change (fun _ => []).
Definition edit_parts (change : edit) (parts : mutable * list message) :=
 (update change (fst parts), match appended change with
   | Some messages => snd parts ++ messages | None => snd parts end).
Definition apply_edit (change : edit) := Focus.modify task_focus (edit_parts change).
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

(** Reconfiguration is an explicit operation on a selected task.  Ordinary
    progress edits never receive these fields, including when new edits are
    defined outside this module.  The command owner supplies admitted settings. *)
Definition configure {before} (target : TaskScope.task_reference before)
 (profile : profile) (settings : task_settings) (receipt : option (list message)) :=
 let current := with_execution profile settings (TaskScope.selected target) in
 put_task (TaskScope.owner target)
   (match receipt with Some messages => append_history messages current | None => current end) before.
