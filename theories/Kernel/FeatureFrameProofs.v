From Stdlib Require Import List Bool NArith PeanoNat.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant.

Lemma task_requirements_read_only_the_task_and_project_registries :
 forall owner task before after,
 world_tasks after = world_tasks before -> world_projects after = world_projects before ->
 task_valid owner task after = task_valid owner task before.
Proof.
 intros owner task before after Tasks Projects.
 unfold task_valid, project_binding, lineage_valid, find_task.
 now rewrite Tasks, Projects.
Qed.

Lemma registry_requirements_read_only_the_task_and_project_registries :
 forall entries owner before after,
 world_tasks after = world_tasks before -> world_projects after = world_projects before ->
 tasks_valid owner entries after = tasks_valid owner entries before.
Proof.
 induction entries as [|task rest IH]; intros owner before after Tasks Projects; cbn [tasks_valid].
 - reflexivity.
 - rewrite (task_requirements_read_only_the_task_and_project_registries owner task before after Tasks Projects).
   now rewrite (IH (N.succ owner) before after Tasks Projects).
Qed.

Lemma graph_registry_requirements_ignore_journal_cursor : forall entries first sequence before,
 graphs_valid first entries (with_sequence sequence before) = graphs_valid first entries before.
Proof.
 induction entries as [|entry rest IH]; intros; cbn [graphs_valid]; [reflexivity|].
 rewrite IH. destruct entry; reflexivity.
Qed.

Lemma feature_requirements_ignore_journal_cursor : forall sequence before,
 features_valid (with_sequence sequence before) = features_valid before.
Proof.
 intros sequence before. unfold features_valid, graph_registry_valid.
 cbn [world_features]. rewrite graph_registry_requirements_ignore_journal_cursor. reflexivity.
Qed.

Lemma well_formed_feature_requirements : forall before,
 well_formed before -> features_valid before = true.
Proof.
 intros before Valid. pose proof (features_requirement before Valid) as Features.
 unfold world_structure in Features. now rewrite feature_requirements_ignore_journal_cursor in Features.
Qed.

Lemma distinct_ticket_list_passes_checker : forall values,
 NoDup values -> unique_tickets values = true.
Proof.
 intros values Unique. unfold unique_tickets.
 assert (Same : nodup N.eq_dec values = values).
 { induction Unique as [|first rest Absent Unique IH]; cbn; [reflexivity|].
   destruct (in_dec N.eq_dec first rest); [contradiction|]. now rewrite IH. }
 rewrite Same. apply Nat.eqb_refl.
Qed.

Lemma an_observed_registry_entry_is_a_member : forall A (values : list A) owner selected,
 registry_at owner values = Some selected -> In selected values.
Proof.
 intros A values; induction values as [|first rest IH]; intros owner selected Found; [discriminate|].
 cbn [registry_at] in Found. destruct (N.eqb owner 0).
 - inversion Found; subst; now left.
 - right; eapply IH; exact Found.
Qed.
