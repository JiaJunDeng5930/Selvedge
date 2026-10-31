From Selvedge.Kernel Require TaskWake.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskResult TaskScope.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Workspace Codec LifecycleProofs.
From Selvedge.Features Require Import Domain Worktree WorktreeProofs WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Module F := Selvedge.Features.Domain.

(* Preparation freezes a task before its first request. Every request accepted
   into that queue must join the history captured immediately after setup. *)
Theorem successful_setup_commits_queued_input_before_request_capture :
 forall space guidance task operations,
 task_lifecycle task = Frozen WantsModel operations ->
 let completed := Worktree.completed_task space guidance task in
 task_queued completed = [] /\
 task_history completed =
  (task_history task ++
   [SettingsMessage (Worktree.selected_settings space guidance (task_current_settings task))
     (profile_key (task_current_profile task)) (profile_reasoning (task_current_profile task))] ++
   map UserMessage (task_queued task))%list.
Proof.
 intros space guidance [contract profile settings lifecycle history queued lineage parent side_cursor model_cursor]
   operations Waiting; cbn in Waiting; subst lifecycle.
 destruct queued as [|first rest]; unfold Worktree.completed_task, Worktree.install_workspace;
 cbn [task_contract task_current_profile task_current_settings task_lifecycle
  task_history task_queued task_lineage task_side_parent task_side_cursor task_model_cursor
  Selvedge.Kernel.TaskWake.promote];
 unfold with_lifecycle, with_queued, append_history, with_history; cbv [set]; cbn;
 split; try reflexivity; now rewrite <- app_assoc.
Qed.

Lemma failed_task_stops_live_owner : forall message task,
 Worktree.archived task = false ->
 task_lifecycle (Worktree.failed_task message task) = Stopped Idle [].
Proof.
 intros message [contract profile settings lifecycle history queued lineage parent side_cursor model_cursor] live.
 unfold Worktree.archived, Worktree.failed_task in *.
 destruct lifecycle; cbn in *; try discriminate;
   unfold Selvedge.Kernel.Domain.with_lifecycle, Selvedge.Kernel.Domain.append_history,
     Selvedge.Kernel.Domain.with_history;
   cbv [set]; reflexivity.
Qed.

(** The receiver and terminal phase are supplied by Completion. This remaining
    property describes Worktree's own effect on the task: admitted setup installs
    its observed workspace, while a failed setup stops the live owner. *)
Theorem received_creation_binds_or_stops : forall before (reference:TaskScope.task_reference before)
 (observed:ArgumentDeclaration.checked (Worktree.creation_contract (TaskScope.selected reference)))
 (received:Completion.Row.receipt (Worktree.completion_path (TaskScope.owner reference))
   F.contents_phase F.TreeCreating Completion.Owner tt
   (fun _ _=>Some (Worktree.creation_finished (proj1_sig observed))) before),
 Worktree.archived (TaskScope.selected reference)=false ->
 let result:=Worktree.finish_creation reference observed received in
 match proj1_sig observed with
 | Worktree.CreatedWorkspace root space guidance =>
   Worktree.created_valid root space (TaskScope.selected reference)=true /\
   find_task (TaskScope.owner reference) (decision_world result)=
     Some (Worktree.completed_task space guidance (TaskScope.selected reference))
 | Worktree.CreationFailure _ message =>
   find_task (TaskScope.owner reference) (decision_world result)=
     Some (Worktree.failed_task message (TaskScope.selected reference)) /\
   task_lifecycle (Worktree.failed_task message (TaskScope.selected reference))=Stopped Idle []
 end.
Proof.
 intros before reference [observed Allowed] received Live; cbn zeta.
 destruct observed as [root space guidance|root message];
 unfold Worktree.finish_creation; cbn [proj1_sig]; rewrite Live; cbn zeta;
 cbn [Selvedge.Kernel.State.accept decision_world].
 - split; [exact Allowed|].
   eapply LifecycleProofs.find_put_task with (before:=TaskScope.selected reference).
   eapply WorktreeProofs.completing_bindings_preserves_the_owner.
   change (find_task (TaskScope.owner reference) before=Some (TaskScope.selected reference)).
   apply TaskScope.observed.
 - split.
   + eapply LifecycleProofs.find_put_task with (before:=TaskScope.selected reference).
     change (find_task (TaskScope.owner reference) before=Some (TaskScope.selected reference)).
     apply TaskScope.observed.
   + apply failed_task_stops_live_owner; exact Live.
Qed.
