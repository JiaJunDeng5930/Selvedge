From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Codec Tasks LifecycleProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem sandbox_update_keeps_frozen_execution : forall id before value patch sandbox,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 History.history_lease id (task_history before) = History.NoLease ->
 parse_sandbox_patch (settings_sandbox (task_current_settings before)) patch = Some sandbox ->
 exists after,
   find_task id (decision_world (configure_execution id None None (Some patch) None value)) = Some after /\
   task_current_profile after = task_current_profile before /\
   settings_approval (task_current_settings after) = settings_approval (task_current_settings before) /\
   task_contract after = task_contract before.
Proof.
 intros id before value patch sandbox Found Eligible Lease Parsed.
 unfold configure_execution; rewrite TaskChangesProofs.configure_execution_with_expression; cbv beta zeta.
 rewrite Found, Eligible, Lease. cbn [andb execution_reasoning selected_reasoning]. rewrite Parsed.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split;
   [eapply find_put_task; exact Found | repeat split; reflexivity].
Qed.

Theorem default_effort_restores_frozen_configuration : forall id before value configured,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 History.history_lease id (task_history before) = History.NoLease ->
 parse_profile (profile_metadata (task_current_profile before)) = Some configured ->
 exists after,
   find_task id (decision_world (configure_execution id None (Some "default") None None value)) = Some after /\
   profile_reasoning (task_current_profile after) = profile_reasoning configured /\
   profile_metadata (task_current_profile after) = profile_metadata (task_current_profile before) /\
   task_current_settings after = task_current_settings before /\
   task_contract after = task_contract before.
Proof.
 intros id before value configured Found Eligible Lease Parsed.
 unfold configure_execution; rewrite TaskChangesProofs.configure_execution_with_expression; cbv beta zeta.
 rewrite Found, Eligible, Lease. cbn [andb execution_reasoning]. rewrite Parsed.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split;
   [eapply find_put_task; exact Found | repeat split; try reflexivity;
     destruct (task_current_settings before); reflexivity].
Qed.

Theorem a_recorded_reasoning_lease_blocks_execution_reconfiguration :
 forall normalize id before value effort remaining name reasoning sandbox approval
   model chosen sandbox_settings approval_settings,
 find_task id value = Some before ->
 History.history_lease id (task_history before) = History.Lease effort remaining ->
 (match name with None => Some (task_current_profile before)
   | Some key => find_profile key (environment_profiles (world_environment value)) end) = Some model ->
 execution_reasoning reasoning model = Some chosen ->
 (match sandbox with None => Some (settings_sandbox (task_current_settings before))
   | Some source => parse_sandbox_patch (settings_sandbox (task_current_settings before)) source end) = Some sandbox_settings ->
 (match approval with None => Some (settings_approval (task_current_settings before))
   | Some source => parse_approval model (environment_profiles (world_environment value)) source end) = Some approval_settings ->
 configure_execution_with normalize id name reasoning sandbox approval value =
 reject "task_busy" "Execution settings require a quiescent unarchived task without a live reasoning lease" value.
Proof.
 intros normalize id before value effort remaining name reasoning sandbox approval
  model chosen sandbox_settings approval_settings Found Lease Model Reasoning Sandbox Approval.
 rewrite TaskChangesProofs.configure_execution_with_expression; cbv beta zeta. rewrite Found, Model; cbv beta zeta; rewrite Approval, Reasoning, Sandbox, Lease, andb_false_r.
 reflexivity.
Qed.
