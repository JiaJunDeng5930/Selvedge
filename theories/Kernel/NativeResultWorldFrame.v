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

Local Lemma an_existing_task_remains_present : forall owner,
 WorldInvariant.present (find_task owner before) = true ->
 WorldInvariant.present (find_task owner after) = true.
Proof.
 intros owner Present; destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
 destruct (Retained owner old Found) as [next [After Frame]]. rewrite After; reflexivity.
Qed.

Local Lemma fork_retains_lineage : forall old next,
 native_result_retains_task old next -> task_lineage old = task_lineage next.
Proof.
 intros old next Frame; eapply observing_a_native_result_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Local Lemma title_survives_a_fork : forall entry,
 WorldInvariant.title_valid entry before = true -> WorldInvariant.title_valid entry after = true.
Proof.
 intros entry Valid; unfold WorldInvariant.title_valid in *.
 apply andb_true_iff in Valid as [Present Valid].
 apply andb_true_iff; split; [apply an_existing_task_remains_present; exact Present|].
 destruct (Selvedge.Features.Domain.title_value entry); try exact Valid.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Ticket Profile] Capable] Budget].
 repeat split; try assumption; apply N.ltb_lt; apply N.ltb_lt in Ticket; lia.
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

Local Lemma card_survives_a_fork : forall card,
 WorldInvariant.card_valid card before = true -> WorldInvariant.card_valid card after = true.
Proof.
 intros card Valid; unfold WorldInvariant.card_valid in *.
 assert (Draft : Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) before =
   Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) after).
 { unfold Selvedge.Features.Board.valid_draft, BoardFacts.valid_draft,
     BoardFacts.lookup_agent, BoardFacts.registry;
   rewrite SameProjects, SameFeatures; reflexivity. }
 apply andb_true_iff in Valid as [Static Enrichment].
 apply andb_true_iff; split.
 - apply andb_true_iff in Static as [Fixed Linked]; apply andb_true_iff; split.
   + rewrite <- Draft; exact Fixed.
   + destruct (Selvedge.Features.Domain.card_task card); [apply an_existing_task_remains_present; exact Linked|reflexivity].
 - destruct (Selvedge.Features.Domain.card_enrichment card); try exact Enrichment.
   repeat rewrite andb_true_iff in Enrichment |- *.
   destruct Enrichment as [[Ticket Revision] Active]; repeat split; try assumption.
   apply N.ltb_lt; apply N.ltb_lt in Ticket; lia.
Qed.

Local Lemma work_owner_survives_a_fork : forall owner old next,
 find_task owner before = Some old -> find_task owner after = Some next ->
 native_result_retains_task old next ->
 Selvedge.Features.Work.task_owner owner before = Selvedge.Features.Work.task_owner owner after.
Proof.
 intros owner old next Found After Frame; unfold Selvedge.Features.Work.task_owner.
 rewrite Found, After, <- SameFeatures, (fork_retains_lineage old next Frame); reflexivity.
Qed.

Local Lemma graph_survives_a_fork : forall owner graph,
 WorldInvariant.graph_valid owner graph before = true -> WorldInvariant.graph_valid owner graph after = true.
Proof.
 intros owner graph Valid; unfold WorldInvariant.graph_valid in *; rewrite <- SameFeatures.
 apply andb_true_iff in Valid as [Static Nodes]; apply andb_true_iff; split; [exact Static|].
 rewrite forallb_forall in Nodes |- *; intros node Member; specialize (Nodes node Member).
 apply andb_true_iff in Nodes as [Present InWork]; apply andb_true_iff; split.
 - apply an_existing_task_remains_present; exact Present.
 - destruct (find_task (Selvedge.Features.Domain.node_task node) before) as [old|] eqn:Found; [|discriminate].
   destruct (Retained _ old Found) as [next [After Frame]].
   unfold Selvedge.Features.TaskGraph.task_in_work in *.
   destruct (Selvedge.Features.Domain.association owner
     (Selvedge.Features.Domain.feature_graph_owners (world_features before))); [|exact InWork].
   rewrite <- (work_owner_survives_a_fork _ old next Found After Frame); exact InWork.
Qed.

Local Lemma graphs_survive_a_fork : forall owner entries,
 WorldInvariant.graphs_valid owner entries before = true ->
 WorldInvariant.graphs_valid owner entries after = true.
Proof.
 intros owner entries; revert owner; induction entries as [|graph rest IH]; intros owner Valid; [reflexivity|].
 cbn [WorldInvariant.graphs_valid] in *; apply andb_true_iff in Valid as [Head Tail].
 apply andb_true_iff; split; [|apply IH; exact Tail].
 destruct graph; [apply graph_survives_a_fork; exact Head|reflexivity].
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
 intro Valid; unfold WorldInvariant.features_valid in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works] Maintenance].
 repeat split.
 - unfold WorldInvariant.titles_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Titles |- *; destruct Titles as [[[TaskPrompt AgentPrompt] Unique] Entries].
   repeat split; try assumption. apply forallb_forall; intros entry Member.
   apply title_survives_a_fork; apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.remote_valid in *; rewrite <- SameFeatures; exact Remote.
 - unfold WorldInvariant.worktrees_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Trees as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply tree_survives_a_fork.
   apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.board_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Board |- *.
   destruct Board as [[[[[[[Cards Agents] CardBound] AgentBound] Entries] Unique] AgentEntries] Draft].
   repeat split; try assumption. apply forallb_forall; intros card Member.
   apply card_survives_a_fork; apply forallb_forall with (x:=card) in Entries; assumption.
 - unfold WorldInvariant.sharing_valid in *;
     unfold Selvedge.Features.WorkspaceBinding.resource_ready, Selvedge.Features.WorkspaceBinding.owned in *.
   rewrite <- SameFeatures, <- SameProjects; exact Sharing.
 - unfold WorldInvariant.graph_registry_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Graphs as [Count Entries]; apply andb_true_iff; split; [exact Count|].
   apply graphs_survive_a_fork; exact Entries.
 - unfold WorldInvariant.works_valid, WorldInvariant.work_owners_valid, Selvedge.Features.Work.lookup in *;
     rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Works |- *.
   destruct Works as [[[[[Bound Entries] [TaskUnique TaskEntries]] [GraphUnique GraphEntries]] Roots] GraphRoots].
   repeat split; try assumption.
   apply forallb_forall; intros [owner work] Member.
   apply forallb_forall with (x:=(owner,work)) in Roots; [|exact Member].
   cbn in Roots |- *.
   destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
   destruct (Retained _ old Found) as [next [After Frame]]. rewrite After.
   rewrite <- (fork_retains_lineage old next Frame); exact Roots.
 - unfold WorldInvariant.compaction_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Maintenance as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply maintenance_survives_a_fork.
   apply forallb_forall with (x:=entry) in Entries; assumption.
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

Lemma native_result_lineage_requirement : forall id old next before after,
 native_result_retains_task old next ->
 (forall owner original, find_task owner before = Some original ->
   exists current, find_task owner after = Some current /\ native_result_retains_task original current) ->
 WorldInvariant.lineage_valid id old before = true ->
 WorldInvariant.lineage_valid id next after = true.
Proof.
 intros id old next before after Frame Retained Valid.
 unfold WorldInvariant.lineage_valid in *.
 rewrite <- (fork_retains_lineage _ _ Frame), <- (native_result_frame_contract _ _ Frame).
 destruct (task_lineage old) as [|ancestor tail]; [reflexivity|].
 destruct (find_task ancestor before) as [original|] eqn:Found; [|discriminate].
 destruct (Retained ancestor original Found) as [current [After ParentFrame]]. rewrite After.
 rewrite <- (fork_retains_lineage _ _ ParentFrame), <- (native_result_frame_contract _ _ ParentFrame).
 exact Valid.
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
 set (after := put_task owner next (with_ticket ticket before)).
 assert (Projects : world_projects before = world_projects after) by reflexivity.
 assert (Features : world_features before = world_features after) by reflexivity.
 assert (Retained : forall queried original, find_task queried before = Some original ->
   exists current, find_task queried after = Some current /\ native_result_retains_task original current).
 { intros queried original Lookup; destruct (N.eq_dec queried owner) as [Same|Other].
   - subst queried; rewrite Found in Lookup; inversion Lookup; subst original.
     exists next; split; [|exact Frame].
     unfold after; eapply LifecycleProofs.find_put_task; exact Found.
   - exists original; split.
     + unfold after, find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn.
       rewrite RegistryProofs.registry_replace_other by congruence; exact Lookup.
     + apply native_result_retains_task_reflexive. }
 assert (Lineages : map task_lineage (world_tasks after) = map task_lineage (world_tasks before)).
 { unfold after, put_task, with_tasks, with_ticket; cbv [set]; cbn.
   eapply replacing_equal_projection_keeps_registry_observations; [exact Found|].
   apply fork_retains_lineage; exact Frame. }
 assert (Tasks : WorldInvariant.tasks_valid 0 (world_tasks after) after = true).
 { apply task_registry_requirement_from_every_lookup; intros queried current Lookup.
   rewrite N.add_0_l.
   change (find_task queried after = Some current) in Lookup.
   assert (Original : exists original, find_task queried before = Some original /\
     native_result_retains_task original current /\ task_progress_requirements queried current).
   { destruct (N.eq_dec queried owner) as [Same|Other].
     - subst queried.
       assert (Installed : find_task owner after = Some next).
       { unfold after; eapply LifecycleProofs.find_put_task; exact Found. }
       rewrite Installed in Lookup; inversion Lookup; subst current.
       exists old; split; [exact Found|]; split; [exact Frame|].
       unfold task_progress_requirements; repeat split; assumption.
     - assert (Before : find_task queried before = Some current).
       { unfold after, find_task, put_task, with_tasks, with_ticket in Lookup; cbv [set] in Lookup; cbn in Lookup.
         rewrite RegistryProofs.registry_replace_other in Lookup by congruence; exact Lookup. }
       exists current; split; [exact Before|]; split.
       + apply native_result_retains_task_reflexive.
       + apply a_valid_task_has_its_progress_requirements with (before:=before).
         rewrite <- task_requirements_ignore_the_journal_cursor.
         eapply ForkLineageProofs.lookup_task_requirements; eauto. }
   destruct Original as [original [Before [Retains [CurrentContext [CurrentPhase [CurrentChecked CurrentOperations]]]]]].
   pose proof (ForkLineageProofs.lookup_task_requirements before queried original Valid Before) as OldValid.
   rewrite task_requirements_ignore_the_journal_cursor in OldValid.
   unfold WorldInvariant.task_valid in OldValid |- *; repeat rewrite andb_true_iff in OldValid |- *.
   destruct OldValid as [[[[[[[[[[Contract Profile] Settings] OldContext] ContractProject] CurrentProject]
     OldLineage] Capacity] OldPhase] OldChecked] OldOperations].
   repeat split; try assumption.
   - rewrite <- (native_result_frame_contract _ _ Retains); exact Contract.
   - rewrite <- (native_result_frame_profile _ _ Retains); exact Profile.
   - rewrite <- (native_result_frame_settings _ _ Retains); exact Settings.
   - unfold WorldInvariant.project_binding in *; rewrite <- (native_result_frame_contract _ _ Retains), <- Projects; exact ContractProject.
   - unfold WorldInvariant.project_binding in *; rewrite <- (native_result_frame_settings _ _ Retains), <- Projects; exact CurrentProject.
   - eapply native_result_lineage_requirement; eauto.
   - rewrite <- (native_result_frame_contract _ _ Retains).
     rewrite (ForkLineageProofs.descendant_count_depends_only_on_lineages queried _ _ Lineages); exact Capacity. }
 constructor.
 - change (WorldInvariant.environment_valid (world_environment before) = true).
   exact (WorldInvariant.environment_requirement before Valid).
 - change (WorldInvariant.projects_valid before = true).
   exact (WorldInvariant.projects_requirement before Valid).
 - rewrite task_registry_requirements_ignore_the_journal_cursor; exact Tasks.
 - exact Tickets.
 - eapply native_result_feature_requirements with (before:=WorldInvariant.world_structure before);
     [exact Features|exact Projects|exact Later|exact Retained|].
   exact (WorldInvariant.features_requirement before Valid).
Qed.
