From Selvedge.Kernel Require Import FeatureFrameProofs.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Features Require Import BoardFacts.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers ContextTypes Domain Codec State Tasks
 ForkConstructionProofs ForkIdentityProofs WorldInvariant ForkSettingsProofs ForkLineageProofs ForkNativeHistoryProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

From Selvedge.Kernel Require Import ForkPreservation.

(* Native settlement can append an operation as well as history. Feature
   observations retain identity and execution settings, but do not observe the
   running operation registry. *)
Definition native_result_task_frame (value : task) := match task_lifecycle value with
 | Running _ _ => with_lifecycle (Running Idle []) (with_history [] value)
 | Stopped _ _ => with_lifecycle (Stopped Idle []) (with_history [] value)
 | _ => with_history [] value end.
Definition native_result_retains_task (old next : task) :=
 native_result_task_frame old = native_result_task_frame next /\
 (exists suffix, task_history next = task_history old ++ suffix) /\
 (* A stopped idle task with no operations is observable by a failed worktree
    creation. Pending native calls cannot inhabit that worktree state. *)
 match task_lifecycle old with
 | Stopped phase operations => phase = Idle -> task_activity next = Idle /\
   (operations = [] -> task_operations next = [])
 | _ => True end.

Lemma native_result_retains_task_reflexive : forall value,
 native_result_retains_task value value.
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed].
 split; [reflexivity|]; split; [exists []; now rewrite app_nil_r|].
 destruct lifecycle; cbn; auto.
Qed.
Lemma observing_a_native_result_task : forall (A : Type) (observe : task -> A) old next,
 (forall value, observe (native_result_task_frame value) = observe value) ->
 native_result_retains_task old next -> observe old = observe next.
Proof.
 intros A observe old next Stable [Same _].
 rewrite <- (Stable old), <- (Stable next), Same; reflexivity.
Qed.
Section NativeResultFeatureFrame.
Variables before after : world.
Hypothesis SameFeatures : world_features before = world_features after.
Hypothesis SameProjects : world_projects before = world_projects after.
Hypothesis LaterTickets : (world_next_ticket before <= world_next_ticket after)%N.
Hypothesis Retained : forall owner old, find_task owner before = Some old ->
 exists next, find_task owner after = Some next /\ native_result_retains_task old next.

Local Lemma fork_retains_lineage : forall old next,
 native_result_retains_task old next -> task_lineage old = task_lineage next.
Proof.
 intros old next Frame; eapply observing_a_native_result_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Local Lemma tree_survives_a_fork : forall entry,
 WorldInvariant.tree_owner_valid entry before = true -> WorldInvariant.tree_owner_valid entry after = true.
Proof.
 intros entry Valid; unfold WorldInvariant.tree_owner_valid in *.
 destruct (find_task (Selvedge.Features.Domain.worktree_task entry) before) as [old|] eqn:Found;
   [|repeat rewrite andb_false_r in Valid; discriminate].
 destruct (Retained _ old Found) as [next [After [Frame [History Stopped]]]]. rewrite After.
 destruct old as [oc op os ol oh oq oa osp osc omc].
 destruct next as [nc np ns nl nh nq na nsp nsc nmc].
 destruct ol; destruct nl; cbn [native_result_task_frame with_activity with_history with_lifecycle] in Frame;
   inversion Frame; subst; try exact Valid.
 cbn [task_lifecycle task_activity task_operations] in Stopped.
 destruct (Selvedge.Features.Domain.worktree_phase entry); try exact Valid.
 destruct phase; cbn in Valid |- *; try exact Valid;
   try (rewrite andb_false_r in Valid; discriminate).
 destruct (Stopped eq_refl) as [SamePhase Empty]; subst.
 destruct operations; cbn in Valid |- *;
   [|rewrite andb_false_r in Valid; discriminate].
 specialize (Empty eq_refl); subst; exact Valid.
Qed.

Local Lemma maintenance_survives_a_fork : forall entry,
 WorldInvariant.maintenance_entry_valid entry before = true ->
 WorldInvariant.maintenance_entry_valid entry after = true.
Proof.
 intros [owner entry] Valid; unfold WorldInvariant.maintenance_entry_valid in *.
 destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
 destruct (Retained _ old Found) as [next [After [Frame [[suffix History] Stopped]]]]. rewrite After, History.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Maintained Attempted] Useful] Job]; repeat split; try assumption.
 - apply N.leb_le; apply N.leb_le in Attempted.
   pose proof (appended_history_never_reduces_useful_input (task_history old) suffix); lia.
 - apply N.leb_le; apply N.leb_le in Useful.
   pose proof (appended_history_never_reduces_useful_input (task_history old) suffix); lia.
 - unfold WorldInvariant.job_history_valid in *.
   destruct (Selvedge.Features.CompactionTypes.entry_job entry); try exact Job;
     apply appended_history_preserves_captured_prefix; exact Job.
Qed.

Theorem native_result_feature_requirements :
 WorldInvariant.features_valid before = true -> WorldInvariant.features_valid after = true.
Proof.
 apply feature_requirements_follow_task_observations; try assumption.
 - intros owner old Found. destruct (Retained owner old Found) as [next [After Frame]].
   exists next; split; [exact After|apply fork_retains_lineage; exact Frame].
 - apply tree_survives_a_fork.
 - apply maintenance_survives_a_fork.
Qed.
End NativeResultFeatureFrame.

Lemma native_result_frame_contract : forall old next,
 native_result_retains_task old next -> task_contract old = task_contract next.
Proof.
 intros old next Frame; eapply observing_a_native_result_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma native_result_frame_profile : forall old next,
 native_result_retains_task old next -> task_current_profile old = task_current_profile next.
Proof.
 intros old next Frame; eapply observing_a_native_result_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma native_result_frame_settings : forall old next,
 native_result_retains_task old next -> task_current_settings old = task_current_settings next.
Proof.
 intros old next Frame; eapply observing_a_native_result_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.

Theorem native_result_replacement_preserves_every_world_requirement :
 forall before owner old next ticket,
 WorldInvariant.well_formed before -> find_task owner before = Some old ->
 native_result_retains_task old next ->
 (world_next_ticket before <= ticket)%N ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true ->
 WorldInvariant.phase_valid next = true -> WorldInvariant.checked_phase owner next = true ->
 WorldInvariant.operations_valid owner next = true ->
 WorldInvariant.tickets_valid (put_task owner next (with_ticket ticket before)) = true ->
 WorldInvariant.well_formed (put_task owner next (with_ticket ticket before)).
Proof.
 intros before owner old next ticket Valid Found Frame Later Context Phase Checked Operations Tickets.
 eapply task_replacement_preserves_every_world_requirement with (relation:=native_result_retains_task);
   try eassumption.
 - apply native_result_retains_task_reflexive.
 - intros previous current Related; constructor.
   + now apply native_result_frame_contract.
   + now apply native_result_frame_profile.
   + now apply native_result_frame_settings.
   + now apply fork_retains_lineage.
 - apply native_result_feature_requirements.
Qed.
