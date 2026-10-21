From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Codec Tasks LifecycleProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem sandbox_update_keeps_frozen_execution : forall id before value patch sandbox,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 parse_sandbox_patch (settings_sandbox (task_current_settings before)) patch = Some sandbox ->
 exists after,
   find_task id (decision_world (configure_execution id None None (Some patch) None value)) = Some after /\
   task_current_profile after = task_current_profile before /\
   settings_approval (task_current_settings after) = settings_approval (task_current_settings before) /\
   task_contract after = task_contract before.
Proof.
 intros id before value patch sandbox Found Eligible Parsed.
 unfold configure_execution, configure_execution_with.
 rewrite Found, Eligible. cbn [execution_reasoning selected_reasoning]. rewrite Parsed.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split;
   [eapply find_put_task; exact Found | repeat split; reflexivity].
Qed.

Theorem default_effort_restores_frozen_configuration : forall id before value configured,
 find_task id value = Some before ->
 quiescent before && negb (String.eqb (task_status before) "archived") = true ->
 parse_profile (profile_metadata (task_current_profile before)) = Some configured ->
 exists after,
   find_task id (decision_world (configure_execution id None (Some "default") None None value)) = Some after /\
   profile_reasoning (task_current_profile after) = profile_reasoning configured /\
   profile_metadata (task_current_profile after) = profile_metadata (task_current_profile before) /\
   task_current_settings after = task_current_settings before /\
   task_contract after = task_contract before.
Proof.
 intros id before value configured Found Eligible Parsed.
 unfold configure_execution, configure_execution_with.
 rewrite Found, Eligible. cbn [execution_reasoning]. rewrite Parsed.
 match goal with |- context [if ?same then _ else _] => destruct same eqn:Same end.
 all: cbn -[put_task]; eexists; split;
   [eapply find_put_task; exact Found | repeat split; try reflexivity;
     destruct (task_current_settings before); reflexivity].
Qed.
