From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State CommitAdmission AfterHookAuthorizationProofs.
Module A := CommitAdmission.

Lemma a_task_keeps_authority_across_other_features : forall source raw before owner old_features next_features current,
 A.retained_task source raw before owner old_features next_features current current=true.
Proof.
 intros. unfold A.retained_task,A.same_archived_task,A.archived_suffix_valid.
 rewrite the_same_lineage_has_the_same_ancestors,
 the_same_creation_contract_has_the_same_configuration,
 the_same_profile_has_the_same_configuration,
 the_same_settings_have_the_same_configuration,
 the_same_history_retains_its_captured_prefix.
 cbn -[A.same_content_lists]. destruct (task_lifecycle current); cbn -[A.same_content_lists];
 rewrite ?the_same_history_retains_its_captured_prefix,?skipn_all,?the_same_queued_content_is_retained; reflexivity.
Qed.

Lemma unchanged_tasks_keep_authority_across_other_features : forall source raw before owner old_features next_features entries,
 A.retained_tasks_from source raw before owner old_features next_features entries entries=true.
Proof. intros source raw before owner old_features next_features entries; revert owner;
 induction entries; intros; cbn [A.retained_tasks_from];
 rewrite ?a_task_keeps_authority_across_other_features,?IHentries; reflexivity. Qed.


Lemma replacing_one_task_keeps_authority_across_other_features :
 forall source raw before first old_features next_features values owner current replacement,
 registry_at owner values = Some current ->
 (forall actual, A.retained_task source raw before actual old_features next_features current replacement = true) ->
 A.retained_tasks_from source raw before first old_features next_features values (replace owner replacement values) = true.
Proof.
 intros source raw before first old_features next_features values; revert first.
 induction values as [|head rest IH]; intros first owner current replacement Found Authority; [discriminate|].
 cbn [registry_at] in Found; cbn [replace]; destruct (N.eqb owner 0).
 - inversion Found; subst head; cbn [A.retained_tasks_from].
   rewrite Authority, unchanged_tasks_keep_authority_across_other_features; reflexivity.
 - cbn [A.retained_tasks_from]. rewrite a_task_keeps_authority_across_other_features; cbn.
   eapply IH; eassumption.
Qed.
