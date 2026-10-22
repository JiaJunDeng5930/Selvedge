From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Codec Workspace CommandExecution Queries LifecycleProofs.
Import ListNotations.
Open Scope string_scope.

(* Projects are birth defaults. Updating their registry never rewrites the
   execution settings or history of tasks already created from those defaults. *)
Theorem creating_a_project_preserves_all_existing_tasks : forall name workspace guidance worktree value,
 world_tasks (decision_world
  (CommandExecution.create_project name workspace guidance worktree value)) = world_tasks value.
Proof.
 intros; unfold CommandExecution.create_project.
 destruct (parse_workspace workspace); [|reflexivity].
 repeat match goal with
 | |- context [if ?condition then _ else _] => destruct condition
 end; reflexivity.
Qed.

Theorem updating_a_project_preserves_all_existing_tasks : forall id name workspace guidance worktree value,
 world_tasks (decision_world
  (CommandExecution.update_project id name workspace guidance worktree value)) = world_tasks value.
Proof.
 intros; unfold CommandExecution.update_project.
 destruct (registry_at id (world_projects value)) as [previous|]; [|reflexivity].
 destruct (project_deleted previous); [reflexivity|].
 destruct (match workspace with
  | Some source => parse_workspace source | None => Some (project_workspace previous) end);
 [|reflexivity].
 destruct (Workspace.valid_project_name
  (match name with Some name => name | None => project_name previous end) &&
  valid_guidance (match guidance with Some source => source | None => Domain.project_guidance previous end) &&
  guidance_member w (match guidance with Some source => source | None => Domain.project_guidance previous end));
 reflexivity.
Qed.

Theorem an_accepted_project_update_uses_the_requested_worktree_preference :
 forall id name workspace guidance requested value previous,
 registry_at id (world_projects value) = Some previous ->
 bool_default "ok" (decision_reply
  (CommandExecution.update_project id name workspace guidance requested value)) false = true ->
 exists updated,
  registry_at id (world_projects (decision_world
   (CommandExecution.update_project id name workspace guidance requested value))) = Some updated /\
  project_worktree updated =
   match requested with Some selected => selected | None => project_worktree previous end.
Proof.
 intros id name workspace guidance requested value previous Found Accepted.
 unfold CommandExecution.update_project in Accepted |- *; rewrite Found in Accepted |- *.
 destruct (project_deleted previous); [discriminate|].
 destruct (match workspace with
  | Some source => parse_workspace source | None => Some (project_workspace previous) end)
  as [space|]; [|discriminate].
 destruct (Workspace.valid_project_name
  (match name with Some name => name | None => project_name previous end) &&
  valid_guidance (match guidance with Some source => source | None => Domain.project_guidance previous end) &&
  guidance_member space (match guidance with Some source => source | None => Domain.project_guidance previous end));
 [|discriminate].
 pose (updated := Project (match name with Some name => name | None => project_name previous end) space
  (match guidance with Some source => source | None => Domain.project_guidance previous end)
  (match requested with Some selected => selected | None => project_worktree previous end) false).
 exists updated; split.
 - change (registry_at id (replace id updated (world_projects value)) = Some updated).
   eapply registry_replace_selected; exact Found.
 - reflexivity.
Qed.

Theorem deleting_a_project_preserves_all_existing_tasks : forall id value,
 world_tasks (decision_world (CommandExecution.delete_project id value)) = world_tasks value.
Proof.
 intros; unfold CommandExecution.delete_project.
 destruct (registry_at id (world_projects value)) as [previous|]; [|reflexivity].
 destruct (project_deleted previous); [reflexivity|].
 destruct (existsb (fun task => match settings_project (task_current_settings task) with
  | Some current => N.eqb id current | None => false end) (world_tasks value)); reflexivity.
Qed.

Theorem a_deleted_project_is_unavailable_to_the_public_query : forall id value,
 bool_default "ok" (decision_reply (CommandExecution.delete_project id value)) false = true ->
 Queries.read_project id (decision_world (CommandExecution.delete_project id value)) =
 State.failure "project_not_found" "The project does not exist".
Proof.
 intros id value Accepted; unfold CommandExecution.delete_project in Accepted |- *.
 destruct (registry_at id (world_projects value)) as [previous|] eqn:Found; [|discriminate].
 destruct (project_deleted previous); [discriminate|].
 destruct (existsb (fun task => match settings_project (task_current_settings task) with
  | Some current => N.eqb id current | None => false end) (world_tasks value)); [discriminate|].
 unfold Queries.read_project.
 unfold accept, with_projects; cbv [set]; cbn [decision_world world_projects].
 rewrite (registry_replace_selected project (world_projects value) id previous _ Found).
 reflexivity.
Qed.
