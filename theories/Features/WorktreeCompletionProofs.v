From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
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
 destruct queued as [|first rest]; unfold Worktree.completed_task;
 cbn [task_contract task_current_profile task_current_settings task_lifecycle
  task_history task_queued task_lineage task_side_parent task_side_cursor task_model_cursor
  Selvedge.Kernel.Tasks.promote];
 unfold with_lifecycle, with_queued, append_history, with_history; cbv [set]; cbn;
 split; try reflexivity; now rewrite <- app_assoc.
Qed.

Ltac finish_accepted_creation entered found pending :=
 match type of entered with
 | context [negb ?valid] =>
     destruct valid eqn:validated in entered; cbn in entered;
     [rewrite found, pending in entered; inversion entered; reflexivity | discriminate]
 end.

(** Once the native completion entry accepts a creation result for a pending
    owner, it dispatches the parsed host observations to the actual transition. *)
Theorem accepted_creation_completion_dispatches : forall source value id tree archived ok root space result,
 string_field "kind" source = Some "worktree_created" ->
 natural_field "task_id" source = Some id ->
 bool_field "ok" source = Some ok ->
 string_field "root" source = root ->
 (match field "workspace" source with Some encoded => parse_workspace encoded | None => None end) = space ->
 Worktree.lookup id value = Some tree ->
 F.worktree_phase tree = F.TreeCreating archived ->
 Worktree.completion source value = Some (true, true, result) ->
 result = Worktree.created tree ok root space (value_or_null "guidance" source)
   (text_default "message" source "") value.
Proof.
 intros source value id tree archived ok root space result kind identity reported root_field workspace_field found pending entered.
 unfold Worktree.completion in entered.
 rewrite kind, identity, reported, root_field, workspace_field in entered.
 cbn [String.eqb] in entered.
 destruct ok; cbn in entered.
 - destruct root as [root|].
   + destruct space as [space|].
     * finish_accepted_creation entered found pending.
     * rewrite Bool.andb_false_r in entered. cbn in entered. discriminate.
   + rewrite Bool.andb_false_r in entered. cbn in entered. discriminate.
 - finish_accepted_creation entered found pending.
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
(** A failed physical result or rejected workspace observation leaves the
    pending owner stopped and records the failed resource phase. *)
Theorem failed_creation_stops_owner : forall tree value task ok root space guidance message,
 find_task (F.worktree_task tree) value = Some task ->
 Worktree.archived task = false ->
 (match root, space with
  | Some root, Some space => ok && Worktree.created_valid root space guidance task
  | _, _ => false end) = false ->
 let result := Worktree.created tree ok root space guidance message value in
 decision_reply result = success (JObject [("accepted"%string, JBool true)]) /\
 exists failed,
   find_task (F.worktree_task tree) (decision_world result) = Some failed /\
   task_lifecycle failed = Stopped Idle [] /\
   exists failed_tree,
     Worktree.lookup (F.worktree_task tree) (decision_world result) = Some failed_tree /\
     F.worktree_phase failed_tree = F.TreeCreateFailed root (if ok then
       "Worktree creation returned an invalid workspace or guidance"%string else message).
Proof.
 intros tree value task ok root space guidance message found live failure.
 unfold Worktree.created. rewrite found, failure, live. cbn.
 split; [reflexivity|].
 exists (Worktree.failed_task
   (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message) task).
 split.
 - unfold Selvedge.Kernel.State.decision_world, Selvedge.Kernel.State.accept.
   unfold find_task. rewrite WorktreeProofs.store_preserves_tasks. fold find_task.
   eapply LifecycleProofs.find_put_task. exact found.
 - split.
   + apply failed_task_stops_live_owner; exact live.
   + exists (F.with_worktree_phase (F.TreeCreateFailed root
       (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message)) tree).
     split.
     * change (Worktree.lookup
         (F.worktree_task (F.with_worktree_phase (F.TreeCreateFailed root
           (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message)) tree))
         (Worktree.store (F.with_worktree_phase (F.TreeCreateFailed root
           (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message)) tree)
           (Selvedge.Kernel.State.put_task (F.worktree_task tree)
             (Worktree.failed_task
               (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message) task)
             value)) = Some (F.with_worktree_phase (F.TreeCreateFailed root
               (if ok then "Worktree creation returned an invalid workspace or guidance"%string else message)) tree)).
       apply WorktreeProofs.stored_resource_is_the_lookup.
     * reflexivity.
Qed.

Lemma successful_creation_records_completed_task : forall tree value task root space guidance message,
 find_task (F.worktree_task tree) value = Some task ->
 Worktree.created_valid root space guidance task = true ->
 Worktree.archived task = false ->
 find_task (F.worktree_task tree)
   (decision_world (Worktree.created tree true (Some root) (Some space) guidance message value)) =
 Some (Worktree.completed_task space guidance task).
Proof.
 intros tree value task root space guidance message found valid live.
 unfold Worktree.created. rewrite found. cbn. rewrite valid, live. cbn.
 unfold find_task. rewrite WorktreeProofs.store_preserves_tasks. fold find_task.
 eapply LifecycleProofs.find_put_task. exact found.
Qed.

(** The accepted callback is constrained through Worktree.completion itself.
    Its valid observed workspace and guidance become the completed task's
    current settings and frozen contract, and its owner reference resolves to
    the Ready resource. Every accepted non-success outcome stops that owner. *)
Theorem accepted_creation_completion_binds_or_stops : forall source value id tree task ok root space result,
 string_field "kind" source = Some "worktree_created" ->
 natural_field "task_id" source = Some id ->
 bool_field "ok" source = Some ok ->
 string_field "root" source = root ->
 (match field "workspace" source with Some encoded => parse_workspace encoded | None => None end) = space ->
 Worktree.lookup id value = Some tree ->
 F.worktree_phase tree = F.TreeCreating false ->
 find_task id value = Some task ->
 Worktree.archived task = false ->
 settings_resource (task_current_settings task) = Some (F.worktree_task tree) ->
 Worktree.completion source value = Some (true, true, result) ->
 (exists observed_root observed_space completed ready,
   root = Some observed_root /\
   space = Some observed_space /\
   Worktree.created_valid observed_root observed_space (value_or_null "guidance" source) task = true /\
   decision_reply result = success (JObject [("accepted"%string, JBool true)]) /\
   find_task (F.worktree_task tree) (decision_world result) = Some completed /\
   task_current_settings completed = Worktree.selected_settings observed_space
     (value_or_null "guidance" source) (task_current_settings task) /\
   contract_settings (task_contract completed) = Worktree.selected_settings
     (Worktree.selected_workspace (Worktree.primary observed_space)
       (settings_workspace (contract_settings (task_contract task))))
     (value_or_null "guidance" source) (contract_settings (task_contract task)) /\
   Worktree.lookup (F.worktree_task tree) (decision_world result) = Some ready /\
   WorkspaceBinding.for_task (F.worktree_task tree) (decision_world result) = Some ready /\
   F.worktree_phase ready = F.TreeReady observed_root (Worktree.primary observed_space)) \/
  (exists failed failed_tree,
   decision_reply result = success (JObject [("accepted"%string, JBool true)]) /\
   find_task (F.worktree_task tree) (decision_world result) = Some failed /\
   task_lifecycle failed = Stopped Idle [] /\
   Worktree.lookup (F.worktree_task tree) (decision_world result) = Some failed_tree /\
   F.worktree_phase failed_tree = F.TreeCreateFailed root
     (if ok then "Worktree creation returned an invalid workspace or guidance"%string
      else text_default "message" source "")).
Proof.
 intros source value id tree task ok root space result kind identity reported root_field workspace_field
   found pending task_found live resource entered.
 assert (tree_owner : F.worktree_task tree = id) by
   (eapply WorktreeProofs.lookup_has_owner; exact found).
 set (guidance := value_or_null "guidance" source).
 set (message := text_default "message" source "").
 assert (dispatch : result = Worktree.created tree ok root space guidance message value).
 { unfold guidance, message. eapply accepted_creation_completion_dispatches; eassumption. }
 subst result.
 assert (owner_task : find_task (F.worktree_task tree) value = Some task) by
   (rewrite tree_owner; exact task_found).
 destruct ok as [|] eqn:reported_ok.
 - destruct root as [observed_root|].
   + destruct space as [observed_space|].
     * destruct (Worktree.created_valid observed_root observed_space guidance task) eqn:valid.
       -- pose proof (WorktreeProofs.successful_creation_installs_ready_resource
            tree value task observed_root observed_space guidance message owner_task valid live)
            as success.
          destruct success as [reply [ready [ready_lookup [ready_phase backend]]]].
          left. exists observed_root, observed_space, (Worktree.completed_task observed_space guidance task), ready.
          repeat split; try reflexivity; try assumption.
          ++ eapply successful_creation_records_completed_task; eassumption.
          ++ apply WorktreeProofs.completed_task_current_settings.
          ++ apply WorktreeProofs.completed_task_contract_settings.
          ++ unfold WorkspaceBinding.for_task.
             rewrite (successful_creation_records_completed_task tree value task observed_root
               observed_space guidance message owner_task valid live).
             unfold WorkspaceBinding.resolve.
             rewrite WorktreeProofs.completed_task_current_settings.
             unfold Worktree.selected_settings.
             rewrite resource.
             unfold WorkspaceBinding.owned. exact ready_lookup.
       -- right.
          destruct (failed_creation_stops_owner tree value task true (Some observed_root)
            (Some observed_space) guidance message owner_task live ltac:(cbn; rewrite valid; reflexivity))
            as [reply [failed [failed_found [stopped [failed_tree [failed_lookup failed_phase]]]]]].
          exists failed, failed_tree. repeat split; assumption.
     * right.
       destruct (failed_creation_stops_owner tree value task true (Some observed_root) None
         guidance message owner_task live ltac:(reflexivity))
         as [reply [failed [failed_found [stopped [failed_tree [failed_lookup failed_phase]]]]]].
       exists failed, failed_tree. repeat split; assumption.
   + right.
     destruct (failed_creation_stops_owner tree value task true None space guidance message owner_task live
       ltac:(reflexivity)) as [reply [failed [failed_found [stopped [failed_tree [failed_lookup failed_phase]]]]]].
     exists failed, failed_tree. repeat split; assumption.
 - right.
   destruct (failed_creation_stops_owner tree value task false root space guidance message owner_task live
     ltac:(destruct root, space; reflexivity))
     as [reply [failed [failed_found [stopped [failed_tree [failed_lookup failed_phase]]]]]].
   exists failed, failed_tree. repeat split; assumption.
Qed.
