From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import Domain State.
Import ListNotations.
Open Scope list_scope.

Record birth_result (before : world) := BirthResult {
 birth_id : N;
 birth_task : task;
 birth_world : world;
 birth_fresh : birth_id = next_task before;
 birth_tasks : world_tasks birth_world = world_tasks before ++ [birth_task];
 birth_sequence : world_sequence birth_world = world_sequence before;
 birth_ticket : world_next_ticket birth_world = world_next_ticket before;
 birth_environment : world_environment birth_world = world_environment before;
 birth_projects : world_projects birth_world = world_projects before;
 birth_features : world_features birth_world = world_features before
}.
Arguments birth_id {before}.
Arguments birth_task {before}.
Arguments birth_world {before}.
Definition birth_prepared (created : task) (value : world) : birth_result value :=
 BirthResult value (next_task value) created (append_task created value)
   eq_refl eq_refl eq_refl eq_refl eq_refl eq_refl eq_refl.
