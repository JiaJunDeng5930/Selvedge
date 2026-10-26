From Stdlib Require Import List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant TicketSupplyProofs.

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

Lemma graph_entries_requirements_follow_entry_observations : forall entries first before after,
 (forall owner graph, graph_valid owner graph after = graph_valid owner graph before) ->
 graphs_valid first entries after = graphs_valid first entries before.
Proof.
 induction entries as [|graph rest IH]; intros first before after Entry; [reflexivity|].
 cbn [graphs_valid]; rewrite IH with (before:=before) by exact Entry.
 destruct graph; [rewrite Entry|]; reflexivity.
Qed.

Lemma graph_registry_requirements_follow_entry_observations : forall before after,
 Selvedge.Features.Domain.feature_graphs (world_features after) =
   Selvedge.Features.Domain.feature_graphs (world_features before) ->
 (forall owner graph, graph_valid owner graph after = graph_valid owner graph before) ->
 graph_registry_valid after = graph_registry_valid before.
Proof.
 intros before after Registry Entry; unfold graph_registry_valid; rewrite Registry.
 f_equal; now apply graph_entries_requirements_follow_entry_observations.
Qed.

Lemma graph_registry_requirements_ignore_journal_cursor : forall entries first sequence before,
 graphs_valid first entries (with_sequence sequence before) = graphs_valid first entries before.
Proof. intros; apply graph_entries_requirements_follow_entry_observations; reflexivity. Qed.

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

Theorem unchanged_registries_preserve_other_world_requirements : forall before after,
 world_environment after = world_environment before ->
 world_projects after = world_projects before ->
 world_tasks after = world_tasks before ->
 well_formed before -> tickets_valid after = true -> features_valid after = true ->
 well_formed after.
Proof.
 intros before after Environment Projects Tasks Valid Tickets Features; constructor.
 - change (environment_valid (world_environment after) = true).
   rewrite Environment; exact (environment_requirement before Valid).
 - change (projects_valid after = true). unfold projects_valid; rewrite Projects.
   exact (projects_requirement before Valid).
 - change (tasks_valid 0 (world_tasks after) (world_structure after) = true).
   rewrite (registry_requirements_read_only_the_task_and_project_registries
     (world_tasks after) 0 (world_structure before) (world_structure after))
     by assumption.
   rewrite Tasks; exact (tasks_requirement before Valid).
 - exact Tickets.
 - unfold world_structure; rewrite feature_requirements_ignore_journal_cursor; exact Features.
Qed.

Definition distinct_ticket_list_passes_checker := distinct_tickets_pass_the_uniqueness_checker.
Definition an_observed_registry_entry_is_a_member := @RegistryProofs.registry_lookup_is_member.

(* Feature requirements depend on task identity, lineage and the observations
   made by worktrees. Operations provide those observations once; the common
   lift owns the combination of all unchanged feature components. *)
Definition feature_core_valid (value : world) :=
 titles_valid value && remote_valid (Selvedge.Features.Domain.feature_remote (world_features value)) &&
 worktrees_valid value && board_valid value && sharing_valid value &&
 graph_registry_valid value && works_valid value.

Lemma equal_registry_maps_retain_tasks : forall (A : Type) (observe : task -> A)
 before after owner old,
 map observe (world_tasks before) = map observe (world_tasks after) ->
 find_task owner before = Some old ->
 exists next, find_task owner after = Some next /\ observe old = observe next.
Proof.
 intros A observe before after owner old Same Found.
 assert (Lookup : option_map observe (find_task owner before) =
   option_map observe (find_task owner after)).
 { unfold find_task; rewrite <- !registry_lookup_commutes_with_mapping, Same; reflexivity. }
 rewrite Found in Lookup. destruct (find_task owner after) as [next|] eqn:After;
   [|discriminate]. exists next; split; [reflexivity|]. now inversion Lookup.
Qed.

Section FeatureTaskFrame.
Variables before after : world.
Hypothesis SameFeatures : world_features before = world_features after.
Hypothesis SameProjects : world_projects before = world_projects after.
Hypothesis LaterTickets : (world_next_ticket before <= world_next_ticket after)%N.
Hypothesis Retained : forall owner old, find_task owner before = Some old ->
 exists next, find_task owner after = Some next /\ task_lineage old = task_lineage next.
Hypothesis TreesPreserved : forall entry,
 tree_owner_valid entry before = true -> tree_owner_valid entry after = true.

Local Lemma an_existing_task_remains_present : forall owner,
 WorldInvariant.present (find_task owner before) = true ->
 WorldInvariant.present (find_task owner after) = true.
Proof.
 intros owner Present; destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
 destruct (Retained owner old Found) as [next [After Frame]]. rewrite After; reflexivity.
Qed.

Lemma title_survives_the_task_frame : forall entry,
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

Local Lemma card_survives_the_task_frame : forall card,
 WorldInvariant.card_valid card before = true -> WorldInvariant.card_valid card after = true.
Proof.
 intros card Valid; unfold WorldInvariant.card_valid in *.
 assert (Draft : Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) before =
   Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) after).
 { unfold Selvedge.Features.Board.valid_draft, Selvedge.Features.BoardFacts.valid_draft,
     Selvedge.Features.BoardFacts.lookup_agent, Selvedge.Features.BoardFacts.registry;
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

Local Lemma work_owner_survives_the_task_frame : forall owner old next,
 find_task owner before = Some old -> find_task owner after = Some next ->
 task_lineage old = task_lineage next ->
 Selvedge.Features.Work.task_owner owner before = Selvedge.Features.Work.task_owner owner after.
Proof.
 intros owner old next Found After Frame; unfold Selvedge.Features.Work.task_owner.
 rewrite Found, After, <- SameFeatures, Frame; reflexivity.
Qed.

Local Lemma graph_survives_the_task_frame : forall owner graph,
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
   rewrite <- (work_owner_survives_the_task_frame _ old next Found After Frame); exact InWork.
Qed.

Local Lemma graphs_survive_the_task_frame : forall owner entries,
 WorldInvariant.graphs_valid owner entries before = true ->
 WorldInvariant.graphs_valid owner entries after = true.
Proof.
 intros owner entries; revert owner; induction entries as [|graph rest IH]; intros owner Valid; [reflexivity|].
 cbn [WorldInvariant.graphs_valid] in *; apply andb_true_iff in Valid as [Head Tail].
 apply andb_true_iff; split; [|apply IH; exact Tail].
 destruct graph; [apply graph_survives_the_task_frame; exact Head|reflexivity].
Qed.

Theorem feature_core_requirements_follow_task_observations :
 feature_core_valid before = true -> feature_core_valid after = true.
Proof.
 intro Valid; unfold feature_core_valid in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works].
 repeat split.
 - unfold WorldInvariant.titles_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Titles |- *; destruct Titles as [[[TaskPrompt AgentPrompt] Unique] Entries].
   repeat split; try assumption. apply forallb_forall; intros entry Member.
   apply title_survives_the_task_frame; apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.remote_valid in *; rewrite <- SameFeatures; exact Remote.
 - unfold WorldInvariant.worktrees_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Trees as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply TreesPreserved.
   apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.board_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Board |- *.
   destruct Board as [[[[[[[Cards Agents] CardBound] AgentBound] Entries] Unique] AgentEntries] Draft].
   repeat split; try assumption. apply forallb_forall; intros card Member.
   apply card_survives_the_task_frame; apply forallb_forall with (x:=card) in Entries; assumption.
 - unfold WorldInvariant.sharing_valid in *;
     unfold Selvedge.Features.WorkspaceBinding.resource_ready, Selvedge.Features.WorkspaceBinding.owned in *.
   rewrite <- SameFeatures, <- SameProjects; exact Sharing.
 - unfold WorldInvariant.graph_registry_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Graphs as [Count Entries]; apply andb_true_iff; split; [exact Count|].
   apply graphs_survive_the_task_frame; exact Entries.
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
   rewrite <- Frame; exact Roots.
Qed.

Theorem feature_requirements_follow_task_observations :
 (forall entry, maintenance_entry_valid entry before = true ->
   maintenance_entry_valid entry after = true) ->
 features_valid before = true -> features_valid after = true.
Proof.
 intros MaintenancePreserved Valid.
 change (feature_core_valid before && compaction_valid before = true) in Valid.
 change (feature_core_valid after && compaction_valid after = true).
 apply andb_true_iff in Valid as [Core Maintenance]; apply andb_true_iff; split.
 - apply feature_core_requirements_follow_task_observations; exact Core.
 - unfold compaction_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Maintenance as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply MaintenancePreserved.
   apply forallb_forall with (x:=entry) in Entries; assumption.
Qed.
End FeatureTaskFrame.
