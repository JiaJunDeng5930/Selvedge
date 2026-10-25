From Stdlib Require Import List Bool NArith Lia.
From Selvedge.Kernel Require Import Domain State Tasks WorldInvariant
 ForkConstructionProofs ForkLineageProofs ForkPreservation.
Import ListNotations.

Lemma root_creation_keeps_existing_descendant_counts : forall child before owner,
 task_lineage child = [] ->
 Tasks.descendant_count owner (world_tasks (append_task child before)) =
 Tasks.descendant_count owner (world_tasks before).
Proof.
 intros child before owner Root.
 change (Tasks.descendant_count owner (world_tasks before ++ [child]) =
   Tasks.descendant_count owner (world_tasks before)).
 rewrite descendant_count_app.
 unfold Tasks.descendant_count at 2; cbn; rewrite Root; cbn; lia.
Qed.

Lemma root_creation_keeps_existing_task_requirements : forall child before owner old,
 task_lineage child = [] -> find_task owner before = Some old ->
 WorldInvariant.task_valid owner old before = true ->
 WorldInvariant.task_valid owner old (append_task child before) = true.
Proof.
 intros child before owner old Root Found Valid.
 pose proof (a_valid_task_has_its_progress_requirements owner old before Valid)
   as [Context [Phase [Checked Operations]]].
 eapply retained_task_requirements_lift with (before:=before) (old:=old).
 - apply fork_retains_task_reflexive.
 - reflexivity.
 - eapply existing_lineage_survives_a_fork with (old:=old) (before:=before).
   + apply fork_retains_task_reflexive.
   + intros ancestor original Present; exists original; split.
     * apply append_task_preserves_existing; exact Present.
     * apply fork_retains_task_reflexive.
   + unfold WorldInvariant.task_valid in Valid; repeat rewrite andb_true_iff in Valid; tauto.
 - rewrite root_creation_keeps_existing_descendant_counts by exact Root.
   apply N.leb_le.
   unfold WorldInvariant.task_valid in Valid; repeat rewrite andb_true_iff in Valid; tauto.
 - exact Context.
 - exact Phase.
 - exact Checked.
 - exact Operations.
 - exact Valid.
Qed.

(* Birth adds a root without modifying existing task identities or ticket
   ownership. The new task's own requirements remain an explicit obligation;
   they are not inferred from the commit-time world checker. *)
Theorem root_birth_preserves_every_world_requirement : forall child before,
 WorldInvariant.well_formed before -> task_lineage child = [] ->
 WorldInvariant.task_tickets child = [] ->
 WorldInvariant.task_valid (next_task before) child (append_task child before) = true ->
 WorldInvariant.well_formed (append_task child before).
Proof.
 intros child before Valid Root Tickets Child.
 constructor.
 - exact (WorldInvariant.environment_requirement before Valid).
 - exact (WorldInvariant.projects_requirement before Valid).
 - rewrite task_registry_requirements_ignore_the_journal_cursor.
   change (WorldInvariant.tasks_valid 0 (world_tasks before ++ [child]) (append_task child before) = true).
   rewrite task_registry_requirements_append.
   apply andb_true_iff; split.
   + apply task_registry_requirement_from_every_lookup; intros owner old Found.
     eapply root_creation_keeps_existing_task_requirements; [exact Root|exact Found|].
     eapply lookup_task_requirements; eassumption.
   + rewrite N.add_0_l.
     change (WorldInvariant.task_valid (next_task before) child (append_task child before) && true = true).
     rewrite Child; reflexivity.
 - change (WorldInvariant.tickets_valid (append_task child before) = true).
   unfold WorldInvariant.tickets_valid.
   change (WorldInvariant.unique_tickets
     (flat_map WorldInvariant.task_tickets (world_tasks before ++ [child]) ++
       WorldInvariant.feature_tickets (world_features before)) &&
     forallb (fun ticket => (ticket <? world_next_ticket before)%N)
       (flat_map WorldInvariant.task_tickets (world_tasks before ++ [child]) ++
         WorldInvariant.feature_tickets (world_features before)) = true).
   rewrite flat_map_app; cbn; rewrite Tickets, app_nil_r.
   exact (WorldInvariant.tickets_requirement before Valid).
 - eapply feature_requirements_survive_a_fork with (before:=WorldInvariant.world_structure before).
   + reflexivity.
   + reflexivity.
   + change (world_next_ticket before <= world_next_ticket before)%N; lia.
   + intros owner old Found; exists old; split.
     * apply append_task_preserves_existing; exact Found.
     * apply fork_retains_task_reflexive.
   + exact (WorldInvariant.features_requirement before Valid).
Qed.

Corollary prepared_root_birth_preserves_every_world_requirement : forall child before,
 WorldInvariant.well_formed before -> task_lineage child = [] ->
 WorldInvariant.task_tickets child = [] ->
 WorldInvariant.task_valid (next_task before) child
   (Tasks.birth_world (Tasks.birth_prepared child before)) = true ->
 WorldInvariant.well_formed (Tasks.birth_world (Tasks.birth_prepared child before)).
Proof. intros; apply root_birth_preserves_every_world_requirement; assumption. Qed.
