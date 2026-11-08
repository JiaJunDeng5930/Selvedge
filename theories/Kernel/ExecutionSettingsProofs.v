From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Codec Tasks LifecycleProofs ReasoningProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem default_effort_restores_frozen_configuration : forall id before value,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 exists after,
   find_task id (decision_world (configure_execution id None (Some "default") None None value)) = Some after /\
   profile_reasoning (task_current_profile after) = profile_default (task_current_profile before) /\
   profile_metadata (task_current_profile after) = profile_metadata (task_current_profile before) /\
   task_current_settings after = WorkspaceBinding.normalize_settings (task_current_settings before) value /\
   task_contract after = task_contract before.
Proof.
 intros id before value Found Eligible.
 rewrite TaskChangesProofs.configure_execution_expression; cbv beta zeta.
 rewrite Found, Eligible. cbn [execution_reasoning]. rewrite String.eqb_refl.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split;
   [eapply find_put_task; exact Found | repeat split; try reflexivity;
     destruct (task_current_settings before); reflexivity].
Qed.

Theorem admitted_execution_settings_take_effect :
 forall id before value name reasoning sandbox approval
   model chosen approval_settings,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 (match name with None => Some (task_current_profile before)
   | Some key => find_profile key (environment_profiles (world_environment value)) end) = Some model ->
 execution_reasoning reasoning model = Some chosen ->
 (match approval with None => Some (settings_approval (task_current_settings before))
   | Some source => approval_of_values model (environment_profiles (world_environment value)) source end) = Some approval_settings ->
 let current := task_current_settings before in
 let settings := WorkspaceBinding.normalize_settings
   (Settings (settings_workspace current) (settings_project current)
     (match sandbox with None => settings_sandbox current
      | Some source => sandbox_patch_of_values (settings_sandbox current) source end)
     approval_settings (settings_guidance current) (settings_worktree current)
     (settings_resource current) (settings_realtime_context current)) value in
 let result := configure_execution id name reasoning sandbox approval value in
 exists after,
   bool_default "ok" (decision_reply result) false = true /\
   find_task id (decision_world result) = Some after /\
   task_current_profile after = chosen /\
   task_current_settings after = settings /\
   (Domain.same_profile chosen (task_current_profile before) &&
    Json.equal (settings_json settings) (settings_json current) &&
    same_approval (settings_approval settings) (settings_approval current) = false ->
    History.history_lease id (task_history after) = History.NoLease).
Proof.
 intros id before value name reasoning sandbox approval model chosen approval_settings
   Found Eligible Model Reasoning Approval. cbv beta zeta.
 rewrite TaskChangesProofs.configure_execution_expression; cbv beta zeta.
 rewrite Found, Model; cbv beta zeta; rewrite Approval, Reasoning, Eligible.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split; [reflexivity|]; split;
   [eapply find_put_task; exact Found|]; repeat split; try reflexivity.
 - discriminate.
 - intros _. apply task_settings_revoke_a_reasoning_lease.
Qed.
