From Stdlib Require Import String List Bool NArith Lia.
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
  (match requested with Some selected => selected | None => project_worktree previous end)
  (Workspace.next_project_order (world_projects value)) false).
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

Lemma next_project_order_is_newer : forall projects previous,
 In previous projects ->
 (project_order previous < Workspace.next_project_order projects)%N.
Proof.
 intros projects; induction projects as [|first rest IH]; intros previous Present; [contradiction|].
 unfold Workspace.next_project_order in *; cbn.
 destruct Present as [<-|Present].
 - apply N.lt_succ_r; apply N.le_max_l.
 - specialize (IH previous Present).
   pose proof (N.le_max_r (project_order first)
    (fold_right (fun value order => N.max (project_order value) order) 0%N rest)); lia.
Qed.

Lemma inserting_a_project_retains_entries : forall entry entries item,
 In item (Workspace.insert_project entry entries) <-> item = entry \/ In item entries.
Proof.
 intros entry entries; induction entries as [|first rest IH]; intro item; cbn.
 - intuition congruence.
 - destruct (N.leb (project_order (snd first)) (project_order (snd entry))); cbn;
   [intuition congruence|rewrite IH; intuition congruence].
Qed.
Lemma ordering_projects_retains_entries : forall entries item,
 In item (fold_right Workspace.insert_project [] entries) <-> In item entries.
Proof.
 induction entries as [|first rest IH]; intro item; cbn; [tauto|].
 rewrite inserting_a_project_retains_entries, IH; intuition congruence.
Qed.

(* Every registry edit obtains a strictly newer position, so the same operation
   that updates birth defaults moves that project to the first displayed row. *)
Theorem newest_project_is_presented_first : forall entries newest,
 In newest entries ->
 (forall item, In item entries -> item = newest \/
   (project_order (snd item) < project_order (snd newest))%N) ->
 exists rest, fold_right Workspace.insert_project [] entries = newest :: rest.
Proof.
 induction entries as [|first entries IH]; intros newest Present Newest; [contradiction|].
 destruct Present as [<-|Present].
 - cbn. remember (fold_right Workspace.insert_project [] entries) as ordered eqn:Ordered.
   destruct ordered as [|head rest]; [exists []; reflexivity|].
   assert (Inside : In head entries).
   { apply ordering_projects_retains_entries. rewrite <- Ordered; left; reflexivity. }
   destruct (Newest head (or_intror Inside)) as [Same|Earlier].
   + subst head; cbn; rewrite N.leb_refl; eexists; reflexivity.
   + cbn. assert (Before : N.leb (project_order (snd head)) (project_order (snd first)) = true).
     { apply N.leb_le; apply N.lt_le_incl; exact Earlier. }
     rewrite Before; eexists; reflexivity.
 - destruct (IH newest Present) as [tail Ordered].
   { intros item Inside; apply Newest; right; exact Inside. }
   cbn; rewrite Ordered; cbn.
   destruct (Newest first (or_introl eq_refl)) as [Same|Earlier].
   + subst first; rewrite N.leb_refl; eexists; reflexivity.
   + assert (Before : N.leb (project_order (snd newest)) (project_order (snd first)) = false).
     { apply N.leb_gt; exact Earlier. }
     rewrite Before; eexists; reflexivity.
Qed.

Theorem query_and_snapshot_use_the_same_project_order : forall value,
 Queries.projects_json value = Observation.projects_json (world_projects value) (world_tasks value).
Proof. reflexivity. Qed.

Theorem project_query_reports_current_bindings : forall value id project,
 In (id, project) (Workspace.ordered_projects (world_projects value)) ->
 exists summary, In summary (Queries.projects_json value) /\
 field "task_count" summary = Some (number (N.of_nat (List.length
  (filter (fun task => match settings_project (task_current_settings task) with
   | Some selected => N.eqb selected id | None => false end) (world_tasks value))))) /\
 field "root_count" summary = Some (number (N.of_nat
  (List.length (workspace_roots (project_workspace project))))) /\
 field "primary_root" summary = Some (optional_string (workspace_primary (project_workspace project))).
Proof.
 intros value id project Present.
 exists (Observation.project_summary_json (world_tasks value) id project); split.
 - unfold Queries.projects_json, Observation.projects_json.
   apply in_map_iff; exists (id,project); split; [reflexivity|exact Present].
 - repeat split; reflexivity.
Qed.

Theorem reviewer_delegation_ignores_display_metadata : forall child parent child_metadata parent_metadata,
 Workspace.approval_bound
  (ReviewWith (set profile_metadata (fun _ => child_metadata) child))
  (ReviewWith (set profile_metadata (fun _ => parent_metadata) parent)) =
 Workspace.approval_bound (ReviewWith child) (ReviewWith parent).
Proof. reflexivity. Qed.
