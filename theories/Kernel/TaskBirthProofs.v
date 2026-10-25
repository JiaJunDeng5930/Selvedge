From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import RegistryProofs Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem a_birth_installs_its_exact_fresh_reference : forall before (born : birth_result before),
 find_task (birth_id born) (birth_world born) = Some (birth_task born).
Proof.
 intros before born. unfold find_task.
 rewrite (birth_fresh before born), (birth_tasks before born).
 apply registry_lookup_at_appended_index.
Qed.

Theorem a_birth_preserves_every_other_reference : forall before (born : birth_result before) other,
 other <> birth_id born ->
 find_task other (birth_world born) = find_task other before.
Proof.
 intros before born other Different. unfold find_task.
 rewrite (birth_tasks before born). apply registry_append_preserves_other_lookup.
 rewrite (birth_fresh before born) in Different; exact Different.
Qed.

Theorem a_birth_cannot_modify_the_world_frame : forall before (born : birth_result before),
 world_sequence (birth_world born) = world_sequence before /\
 world_next_ticket (birth_world born) = world_next_ticket before /\
 world_environment (birth_world born) = world_environment before /\
 world_projects (birth_world born) = world_projects before /\
 world_features (birth_world born) = world_features before.
Proof.
 intros; repeat split; [apply birth_sequence | apply birth_ticket | apply birth_environment
   | apply birth_projects | apply birth_features].
Qed.

Theorem every_resolved_start_installs_the_reported_task : forall plan before,
 let created := interpret_start plan before in
 decision_reply created = success (JObject [("task_id",number (next_task before))]) /\
 decision_effects created = [] /\
 find_task (next_task before) (decision_world created) = Some (start_task plan).
Proof.
 intros plan before; cbn [interpret_start birth_start birth_prepared birth_id birth_world
   birth_task decision_reply decision_effects decision_world accept].
 repeat split; try reflexivity. unfold find_task, append_task, with_tasks; cbn.
 apply registry_lookup_at_appended_index.
Qed.

Theorem a_refused_start_is_atomic : forall entry cause before,
 decision_world (refuse_start entry cause before) = before /\
 decision_effects (refuse_start entry cause before) = [].
Proof. intros; split; reflexivity. Qed.
