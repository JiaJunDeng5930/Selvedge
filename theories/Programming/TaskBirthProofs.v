From Stdlib Require Import String List NArith.
From Selvedge.Programming Require TaskBirth.
From Selvedge.Foundation Require Import RegistryProofs Json.
From Selvedge.Kernel Require Import Domain State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem a_birth_installs_its_exact_fresh_reference : forall before (born : TaskBirth.birth_result before),
 find_task (TaskBirth.birth_id born) (TaskBirth.birth_world born) = Some (TaskBirth.birth_task born).
Proof.
 intros before born. unfold find_task.
 rewrite (TaskBirth.birth_fresh before born), (TaskBirth.birth_tasks before born).
 apply registry_lookup_at_appended_index.
Qed.

Theorem a_birth_preserves_every_other_reference : forall before (born : TaskBirth.birth_result before) other,
 other <> TaskBirth.birth_id born ->
 find_task other (TaskBirth.birth_world born) = find_task other before.
Proof.
 intros before born other Different. unfold find_task.
 rewrite (TaskBirth.birth_tasks before born). apply registry_append_preserves_other_lookup.
 rewrite (TaskBirth.birth_fresh before born) in Different; exact Different.
Qed.

Theorem a_birth_cannot_modify_the_world_frame : forall before (born : TaskBirth.birth_result before),
 world_sequence (TaskBirth.birth_world born) = world_sequence before /\
 world_next_ticket (TaskBirth.birth_world born) = world_next_ticket before /\
 world_environment (TaskBirth.birth_world born) = world_environment before /\
 world_projects (TaskBirth.birth_world born) = world_projects before /\
 world_features (TaskBirth.birth_world born) = world_features before.
Proof.
 intros; repeat split; [apply TaskBirth.birth_sequence | apply TaskBirth.birth_ticket | apply TaskBirth.birth_environment
   | apply TaskBirth.birth_projects | apply TaskBirth.birth_features].
Qed.
