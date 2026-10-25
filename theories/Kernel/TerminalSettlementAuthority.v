From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Callbacks History ContextSelection
 TerminalSettlement TerminalSettlementProofs ForkPreservation WorldInvariant CommitAdmission
 AfterHookAuthorizationProofs ArchivedRuntimeFrameProofs.
Import ListNotations.
Open Scope list_scope.

Lemma terminal_receipts_have_the_owned_archived_authority :
 forall owner operations original plugin outcome result error,
 find (fun pending => N.eqb (operation_id original) (operation_id pending)) operations = Some original ->
 CommitAdmission.operation_nonexecuting original = true ->
 forallb (CommitAdmission.archived_message owner operations)
   (terminal_suffix owner original plugin outcome result error) = true.
Proof.
 intros owner operations original plugin outcome result error Owned Nonexecuting.
 pose proof Owned as Member; apply find_some in Member as [Member _].
 unfold terminal_suffix, History.operation_result; destruct (operation_announced original).
 - cbn [forallb CommitAdmission.archived_message].
   rewrite N.eqb_refl, Owned, Nonexecuting, String.eqb_refl; reflexivity.
 - cbn [forallb CommitAdmission.archived_message].
   rewrite N.eqb_refl, Owned, Nonexecuting; cbn [andb].
   rewrite andb_true_r; apply existsb_exists; exists original; split; [exact Member|].
   rewrite String.eqb_refl, Nonexecuting; reflexivity.
Qed.

Theorem terminal_settlement_retains_the_owner_authority :
 forall source raw before features owner current operations original plugin previous failed outcome,
 task_lifecycle current = Archived operations ->
 find (fun pending => N.eqb (operation_id original) (operation_id pending)) operations = Some original ->
 CommitAdmission.operation_nonexecuting original = true ->
 CommitAdmission.retained_task source raw before owner features features current
   (settled_task owner original plugin previous failed outcome current) = true.
Proof.
 intros source raw before features owner current operations original plugin previous failed outcome
 ArchivedTask Owned Nonexecuting.
 set (settled := settled_task owner original plugin previous failed outcome current).
 pose proof (settlement_preserves_the_archived_frame owner original plugin previous failed outcome current operations ArchivedTask)
   as Frame.
 fold settled in Frame.
 assert (History : task_history settled = task_history current ++ terminal_suffix owner original plugin outcome
   (fst (result_value previous failed outcome)) (snd (result_value previous failed outcome)))
   by (unfold settled; apply terminal_settlement_keeps_its_history_suffix).
 assert (Lifecycle : task_lifecycle settled = Archived (Callbacks.remove_operation (operation_id original) operations))
   by (unfold settled; eapply terminal_settlement_keeps_its_archived_lifecycle; exact ArchivedTask).
 assert (Queued : task_queued settled = task_queued current).
 { unfold settled, settled_task; destruct (result_value previous failed outcome).
   destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
   destruct lifecycle; reflexivity. }
 assert (Prefix : ContextSelection.history_extends (task_history current) (task_history settled) = true).
 { rewrite History; apply appended_history_preserves_captured_prefix, the_same_history_retains_its_captured_prefix. }
 unfold CommitAdmission.retained_task.
 rewrite <- (task_frame_preserves_lineage _ _ Frame), <- (task_frame_preserves_contract _ _ Frame),
  <- (task_frame_preserves_profile _ _ Frame), <- (task_frame_preserves_settings _ _ Frame).
 rewrite the_same_lineage_has_the_same_ancestors, the_same_creation_contract_has_the_same_configuration,
  the_same_profile_has_the_same_configuration, the_same_settings_have_the_same_configuration, Prefix.
 cbn [andb orb].
 unfold CommitAdmission.same_archived_task; rewrite ArchivedTask, Lifecycle, Prefix, Queued,
  the_same_queued_content_is_retained; cbn [andb].
 unfold CommitAdmission.archived_suffix_valid; rewrite History.
 rewrite skipn_app, skipn_all, Nat.sub_diag; cbn [app skipn].
 rewrite andb_true_r. unfold task_operations; rewrite ArchivedTask.
 eapply terminal_receipts_have_the_owned_archived_authority; eauto.
Qed.

Lemma unchanged_task_registry_has_authority : forall source raw before features first entries,
 CommitAdmission.retained_tasks_from source raw before first features features entries entries = true.
Proof.
 intros source raw before features first entries; revert first.
 induction entries; intro first; [reflexivity|].
 cbn [CommitAdmission.retained_tasks_from].
 rewrite retained_task_allows_operation_progress by reflexivity.
 rewrite IHentries; reflexivity.
Qed.

Lemma replacing_one_task_lifts_its_authority : forall source raw before features entries first selected old next,
 registry_at selected entries = Some old ->
 CommitAdmission.retained_task source raw before (first + selected)%N features features old next = true ->
 CommitAdmission.retained_tasks_from source raw before first features features entries (replace selected next entries) = true.
Proof.
 intros source raw before features entries; induction entries as [|head tail IH];
 intros first selected old next Found Target; [discriminate|].
 cbn in Found; cbn [replace]; destruct (N.eqb selected 0) eqn:AtHead.
 - apply N.eqb_eq in AtHead; subst selected; rewrite N.add_0_r in Target.
   inversion Found; subst old. cbn [CommitAdmission.retained_tasks_from]; rewrite Target,
     unchanged_task_registry_has_authority; reflexivity.
 - cbn [CommitAdmission.retained_tasks_from].
   rewrite retained_task_allows_operation_progress by reflexivity; cbn [andb].
   eapply IH; [exact Found|].
   replace (N.succ first + N.pred selected)%N with (first + selected)%N by (apply N.eqb_neq in AtHead; lia).
   exact Target.
Qed.

Theorem terminal_settlement_has_global_transition_authority :
 forall source raw before owner current operations original plugin previous failed outcome reply,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 task_lifecycle current = Archived operations ->
 find (fun pending => N.eqb (operation_id original) (operation_id pending)) operations = Some original ->
 CommitAdmission.operation_nonexecuting original = true ->
 CommitAdmission.transition_authorized true source raw before
   (Decision (put_task owner (settled_task owner original plugin previous failed outcome current) before)
     reply [ContinueScheduling]) = true.
Proof.
 intros source raw before owner current operations original plugin previous failed outcome reply
 Valid Found ArchivedTask Owned Nonexecuting.
 set (settled := settled_task owner original plugin previous failed outcome current).
 set (after := put_task owner settled before).
 assert (Fields : world_features after = world_features before /\ world_projects after = world_projects before /\
   world_next_ticket after = world_next_ticket before).
 { unfold after, put_task; destruct before; repeat split; reflexivity. }
 destruct Fields as [Features [Projects Tickets]].
 unfold CommitAdmission.transition_authorized; cbn [decision_world decision_effects].
 fold settled after.
 repeat rewrite andb_true_iff; repeat split.
 - unfold CommitAdmission.world_evolution.
   rewrite Features, Projects, Tickets, !N.leb_refl, !andb_true_r; cbn [andb].
   apply andb_true_iff; split.
   + unfold CommitAdmission.retained_tasks; rewrite Features.
     unfold after, put_task; rewrite writing_tasks_installs_the_registry.
     eapply replacing_one_task_lifts_its_authority; [exact Found|].
     change (CommitAdmission.retained_task source raw before owner (world_features before) (world_features before) current settled = true).
     unfold settled; eapply terminal_settlement_retains_the_owner_authority; eauto.
   + exact (well_formed_features_admit_their_unchanged_configuration
       (WorldInvariant.world_structure before) (WorldInvariant.features_requirement before Valid)).
Qed.
