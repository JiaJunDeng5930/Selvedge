From Selvedge.Kernel Require Import FeatureAdmissionProofs.
From Selvedge.Kernel Require CommandResult FeatureRequestAdmission.
From Selvedge.Kernel Require Import FeatureFrameProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State Codec Inputs TicketedRequest
 WorldInvariant WorldInvariantProofs CommitAdmission AfterHookAuthorizationProofs FeatureAuthorityProofs ProtocolProofs ConnectionCommit DeferredCommit ChatgptArgumentsProofs.
From Selvedge.Features Require Import Domain State Chatgpt WorkspaceBinding Board TaskGraph.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module F := Selvedge.Features.Domain.
Module W := Selvedge.Kernel.WorldInvariant.
Module A := Selvedge.Kernel.CommitAdmission.

Lemma sharing_store_preserves_other_requirements : forall replacement before,
 W.world_valid before=true -> W.sharing_valid (Chatgpt.store replacement before)=true ->
 W.world_valid (Chatgpt.store replacement before)=true.
Proof.
 intros replacement before Valid Sharing.
 apply well_formed_worlds_pass_the_checker.
 apply unchanged_registries_preserve_other_world_requirements with before;
   try reflexivity; [now apply the_world_checker_establishes_all_requirements| |].
 - exact (W.tickets_requirement before (the_world_checker_establishes_all_requirements before Valid)).
 - assert (Graphs : W.graph_registry_valid (Chatgpt.store replacement before) = W.graph_registry_valid before).
   { apply graph_registry_requirements_follow_entry_observations; reflexivity. }
   pose proof (well_formed_feature_requirements before
     (the_world_checker_establishes_all_requirements before Valid)) as Features.
   unfold W.features_valid in *; rewrite Graphs.
   repeat rewrite andb_true_iff in *; intuition.
Qed.

Lemma sharing_store_keeps_resource_observation : forall replacement space resource before,
 WorkspaceBinding.resource_ready space resource (Chatgpt.store replacement before)=
 WorkspaceBinding.resource_ready space resource before.
Proof. intros. unfold WorkspaceBinding.resource_ready,WorkspaceBinding.owned,Chatgpt.store,
 with_features,Selvedge.Features.State.with_sharing,set; reflexivity. Qed.

Definition fresh_state before job :=
 let previous:=Chatgpt.registry before in
 F.ConnectionState (F.sharing_grants previous)
  ((F.sharing_next previous,job)::F.sharing_jobs previous) (N.succ (F.sharing_next previous)).

Lemma below_supply_filter_is_identity : forall identity entries,
 forallb (fun entry : N * F.connection_job => (fst entry <? identity)%N) entries=true ->
 filter (fun entry=>negb (N.eqb identity (fst entry))) entries=entries.
Proof.
 intros identity entries; induction entries as [|[id job] rest IH]; intro Bounded; [reflexivity|].
 cbn in Bounded; apply andb_true_iff in Bounded as [Head Tail].
 apply N.ltb_lt in Head.
 assert (Distinct: N.eqb identity id=false) by (apply N.eqb_neq;lia).
 cbn; rewrite Distinct; cbn; rewrite IH by exact Tail; reflexivity.
Qed.

Lemma an_issued_connection_has_the_fresh_state : forall before
 (request : TicketedRequest.Scoped.feature_plan before) job,
 TicketedRequest.Scoped.feature_intent request = TicketedRequest.Scoped.ConnectionRequest job ->
 forallb (fun entry : N * F.connection_job => (fst entry <? F.sharing_next (Chatgpt.registry before))%N)
  (F.sharing_jobs (Chatgpt.registry before))=true ->
 TicketedRequest.Scoped.feature_issue request =
 accept (JObject [("accepted"%string,JBool true)])
  (Chatgpt.store (fresh_state before job) before)
  [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job].
Proof.
 intros before [source Admitted] job Intent Bounded.
 cbn in Intent; subst source.
 unfold TicketedRequest.Scoped.feature_issue,TicketedRequest.Scoped.feature_issue_change,CommandResult.accept,TicketedRequest.Scoped.feature_build,
 TicketedRequest.Scoped.feature_space,TicketedRequest.allocate_identity,TicketedRequest.next_identity,
 TicketedRequest.Scoped.put_connection.
 unfold Chatgpt.store,fresh_state,Chatgpt.registry,FeatureRequestAdmission.sharing_registry,with_features,
 Selvedge.Features.State.with_sharing,set in *; cbn in *.
 rewrite below_supply_filter_is_identity by exact Bounded.
 reflexivity.
Qed.

Lemma a_connection_job_has_reflexive_authority : forall job,
 A.same_connection_job job job=true.
Proof.
 intros. unfold A.same_connection_job, Comparison.all, Comparison.on; cbn [fold_left].
 rewrite !N.eqb_refl,!String.eqb_refl,!equal_is_reflexive.
 unfold Workspace.same_resource. destruct (F.job_resource job); rewrite ?N.eqb_refl; cbn.
 all: destruct (F.job_state job); cbn [A.same_connection_state]; rewrite ?equal_is_reflexive,?Bool.eqb_reflx,?String.eqb_refl; reflexivity.
Qed.

Lemma fresh_connection_effect_has_receiver_authority : forall before job,
 A.feature_effect_valid (RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job)
  before (Chatgpt.store (fresh_state before job) before)=true.
Proof.
 intros. unfold A.feature_effect_valid,A.fresh_connection_job,A.connection_job_at,
 fresh_state,Chatgpt.store,Chatgpt.registry,FeatureRequestAdmission.sharing_registry,with_features,Selvedge.Features.State.with_sharing,set.
 cbn. rewrite !N.eqb_refl,N.leb_refl.
 assert (Fresh: (F.sharing_next (F.feature_sharing (world_features before)) <?
  N.succ (F.sharing_next (F.feature_sharing (world_features before))))%N=true) by (apply N.ltb_lt;lia).
 rewrite Fresh. cbn. apply a_connection_job_has_reflexive_authority.
Qed.

Lemma distinct_tickets_are_unique : forall tickets,
 NoDup tickets -> W.unique_tickets tickets=true.
Proof.
 intros tickets Distinct. unfold W.unique_tickets.
 assert (Identity: nodup N.eq_dec tickets=tickets).
 { induction Distinct; cbn; [reflexivity|].
   destruct (in_dec N.eq_dec x l); [contradiction|]. now rewrite IHDistinct. }
 rewrite Identity; apply Nat.eqb_refl.
Qed.

Lemma sharing_jobs_stay_below_their_supply : forall before,
 W.sharing_valid before=true ->
 forallb (fun entry : N * F.connection_job => (fst entry <? F.sharing_next (Chatgpt.registry before))%N)
  (F.sharing_jobs (Chatgpt.registry before))=true.
Proof.
 intros before Valid. unfold W.sharing_valid in Valid.
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[[[[Grants UniqueGrants] GrantFields] Capacity] Supply] UniqueJobs] Fields].
 apply forallb_forall; intros [id job] Member.
 apply forallb_forall with (x:=(id,job)) in Fields; [|exact Member].
 cbn in Fields; repeat rewrite andb_true_iff in Fields; tauto.
Qed.

Lemma fresh_connection_preserves_sharing_requirements : forall before job,
 W.sharing_valid before=true ->
 (N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) < 128)%N ->
 (F.sharing_next (Chatgpt.registry before) < 4294967295)%N ->
 Selvedge.Features.Remote.identifier_valid (F.job_request job)=true ->
 ChatgptArguments.valid_args (F.job_arguments_json job)=true ->
 Workspace.valid_workspace (F.job_workspace job)=true ->
 F.job_state job=F.JobRunning ->
 WorkspaceBinding.resource_ready (F.job_workspace job) (F.job_resource job) before=true ->
 W.sharing_valid (Chatgpt.store (fresh_state before job) before)=true.
Proof.
 intros before job Valid Capacity Supply Request Arguments Workspace Running Resource.
 pose proof (sharing_jobs_stay_below_their_supply before Valid) as Bounded.
 unfold W.sharing_valid in Valid |- *.
 unfold fresh_state,Chatgpt.store,Chatgpt.registry,FeatureRequestAdmission.sharing_registry,with_features,Selvedge.Features.State.with_sharing,set in *.
 cbn -[forallb W.unique_tickets W.within_u32 ChatgptArguments.valid_args Workspace.valid_workspace WorkspaceBinding.resource_ready Selvedge.Features.Remote.identifier_valid] in *.
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[[[[Grants UniqueGrants] GrantFields] OldCapacity] OldSupply] UniqueJobs] Fields].
 repeat rewrite andb_true_iff; repeat split; try assumption.
 - apply Nat.leb_le; lia.
 - unfold W.within_u32. apply N.leb_le;lia.
 - apply distinct_tickets_are_unique. cbn.
   constructor.
   + intro Member. apply in_map_iff in Member as [[id old] [Equal Member]]. cbn in Equal;subst id.
     apply forallb_forall with (x:=(F.sharing_next (F.feature_sharing (world_features before)),old)) in Bounded;
      [|exact Member]. cbn in Bounded. rewrite N.ltb_irrefl in Bounded;discriminate.
   + apply unique_tickets_denotes_distinct_correlation_owners;exact UniqueJobs.
 - apply forallb_forall; intros [id current] [New|Member].
   + inversion New;subst id current. cbn -[Selvedge.Features.Remote.identifier_valid ChatgptArguments.valid_args Workspace.valid_workspace WorkspaceBinding.resource_ready]. rewrite Request,Arguments,Workspace,Running.
     assert (Less: (F.sharing_next (F.feature_sharing (world_features before)) <?
       N.succ (F.sharing_next (F.feature_sharing (world_features before))))%N=true)
       by (apply N.ltb_lt;lia).
     rewrite Less. cbn. exact Resource.
   + apply forallb_forall with (x:=(id,current)) in Fields; [|exact Member].
     cbn -[Selvedge.Features.Remote.identifier_valid ChatgptArguments.valid_args Workspace.valid_workspace WorkspaceBinding.resource_ready] in Fields. repeat rewrite andb_true_iff in Fields.
     destruct Fields as [[[[OldBound OldRequest] OldArguments] OldWorkspace] OldResource].
     repeat rewrite andb_true_iff; repeat split; try assumption. apply N.ltb_lt;apply N.ltb_lt in OldBound;lia.
Qed.

Lemma fresh_connection_preserves_feature_evolution : forall before job,
 W.features_valid before=true ->
 A.features_evolution (world_features before)
  (world_features (Chatgpt.store (fresh_state before job) before))=true.
Proof.
 intros before job Valid.
 pose proof (well_formed_features_admit_their_unchanged_configuration before Valid) as Original.
 unfold A.features_evolution,A.titles_evolution,A.same_title_prompts in Original |- *.
 unfold Chatgpt.store,fresh_state,Chatgpt.registry,FeatureRequestAdmission.sharing_registry,with_features,Selvedge.Features.State.with_sharing,set.
 cbn -[A.board_evolution A.compaction_evolution] in *.
 assert (Supply: (F.sharing_next (F.feature_sharing (world_features before)) <=?
 N.succ (F.sharing_next (F.feature_sharing (world_features before))))%N=true)
  by (apply N.leb_le;lia).
 rewrite Supply. repeat rewrite andb_true_iff in *;tauto.
Qed.

Theorem fresh_connection_has_complete_commit_authority : forall source raw before job reply,
 W.features_valid before=true ->
 A.transition_authorized true source raw before
  (Decision (Chatgpt.store (fresh_state before job) before) reply
    [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job;ContinueScheduling])=true.
Proof.
 intros source raw before job reply Features.
 unfold A.transition_authorized,A.world_evolution,A.retained_tasks.
 cbn [decision_world decision_effects].
 rewrite unchanged_tasks_keep_authority_across_other_features.
 change (true && (world_next_ticket before <=? world_next_ticket before)%N &&
 (N.of_nat (List.length (world_projects before)) <=? N.of_nat (List.length (world_projects before)))%N &&
 A.features_evolution (world_features before) (world_features (Chatgpt.store (fresh_state before job) before)) &&
 A.effect_tickets_fresh (world_next_ticket before) (world_next_ticket before)
 [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job;ContinueScheduling] &&
 A.effects_authorized source raw before (Chatgpt.store (fresh_state before job) before)
 [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job;ContinueScheduling]=true).
 rewrite !N.leb_refl,fresh_connection_preserves_feature_evolution by exact Features.
 cbn [A.effect_tickets_fresh A.unique_effect_tickets A.effect_ticket A.effects_authorized A.effect_authorized].
 rewrite fresh_connection_effect_has_receiver_authority. reflexivity.
Qed.

Definition bash_arguments := ChatgptArgumentsProofs.argument_values.
Definition bounded_bash_arguments_have_a_valid_canonical_wire :=
 ChatgptArgumentsProofs.bounded_arguments_have_a_valid_canonical_wire.

Lemma sequence_keeps_graph_requirements : forall sequence before owner entries,
 W.graphs_valid owner entries (with_sequence sequence before)=W.graphs_valid owner entries before.
Proof.
 intros sequence before owner entries;revert owner;induction entries as [|entry rest IH];intros;
 cbn [W.graphs_valid];[reflexivity|]. rewrite IH.
 destruct entry;[|reflexivity].
 unfold W.graph_valid,TaskGraph.task_in_work,find_task,with_sequence,set;reflexivity.
Qed.

Lemma sequence_keeps_feature_requirements : forall sequence before,
 W.features_valid (with_sequence sequence before)=W.features_valid before.
Proof.
 intros. unfold W.features_valid,W.graph_registry_valid.
 change (W.titles_valid (with_sequence sequence before) &&
 W.remote_valid (F.feature_remote (world_features before)) &&
 W.worktrees_valid (with_sequence sequence before) && W.board_valid (with_sequence sequence before) &&
 W.sharing_valid (with_sequence sequence before) &&
 (Nat.leb (List.length (filter W.present (F.feature_graphs (world_features before)))) 32 &&
  W.graphs_valid 0 (F.feature_graphs (world_features before)) (with_sequence sequence before)) &&
 W.works_valid (with_sequence sequence before) && W.compaction_valid (with_sequence sequence before) = W.features_valid before).
 rewrite sequence_keeps_graph_requirements.
 unfold W.titles_valid,W.title_valid,W.worktrees_valid,W.tree_owner_valid,
 W.board_valid,W.card_valid,Board.valid_draft,Board.lookup_agent,W.sharing_valid,
 W.works_valid,W.work_owners_valid,Selvedge.Features.Work.lookup,W.compaction_valid,W.maintenance_entry_valid,
 WorkspaceBinding.resource_ready,WorkspaceBinding.owned,find_task,with_sequence,set; reflexivity.
Qed.

Lemma a_valid_world_supplies_connection_requirements : forall before,
 W.world_valid before=true ->
 W.features_valid before=true /\ W.sharing_valid before=true.
Proof.
 intros before Valid. unfold W.world_valid,W.world_structure in Valid.
 apply andb_true_iff in Valid as [_ Features].
 rewrite sequence_keeps_feature_requirements in Features.
 split;[exact Features|]. unfold W.features_valid in Features;repeat rewrite andb_true_iff in Features;tauto.
Qed.

Definition admitted_job connection project request decoded granted target :=
 F.ConnectionJob connection project request decoded (project_workspace target) (project_resource target)
  (F.connection_sandbox granted) F.JobRunning.
Definition accepted_decision before job :=
 Decision (Chatgpt.store (fresh_state before job) before)
  (success (Chatgpt.receipt (F.sharing_next (Chatgpt.registry before)) job))
  [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job;ContinueScheduling].

Theorem admissible_connection_command_constructs_its_exact_result :
 forall connection project request arguments decoded granted target before,
 W.sharing_valid before=true ->
 Chatgpt.ids_valid [connection;project]=true -> Chatgpt.bounded_text 128 request=true ->
 ChatgptArguments.admit_args arguments=Some decoded ->
 Chatgpt.authority connection project (Chatgpt.registry before)=Some granted ->
 Chatgpt.project project before=Some target -> workspace_primary (project_workspace target)<>None ->
 Chatgpt.retry connection request (Chatgpt.registry before)=None ->
 Selvedge.Features.Worktree.workspace_available (project_workspace target) before=true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) before=true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) <? 128) &&
 (F.sharing_next (Chatgpt.registry before) <? ChatgptArguments.identity_maximum))%N=true ->
 ConnectionCommit.candidate (Selvedge.Generated.Commands.Build_chatgpt_exec connection project request arguments) before =
 accepted_decision before (admitted_job connection project request decoded granted target).
Proof.
 intros connection project request arguments decoded granted target before Valid Ids Bounded Arguments Authority
 Project Primary Retry Available Resource Capacity.
 assert (Root : FeatureRequestAdmission.connection_has_primary target = true).
 { unfold FeatureRequestAdmission.connection_has_primary; destruct (workspace_primary (project_workspace target));
   [reflexivity|contradiction]. }
 assert (Ready : FeatureRequestAdmission.connection_workspace target before = true).
 { unfold FeatureRequestAdmission.connection_workspace. change (WorkspaceBinding.workspace_available (project_workspace target) before = true) in Available. now rewrite Available,Resource. }
 destruct (admitted_connection_resolves_without_rechecking connection project request arguments decoded granted target before
   Ids Bounded Arguments Authority Project Root Retry Ready Capacity) as [resolved [Resolved Job]].
 unfold ConnectionCommit.candidate,Chatgpt.handle_chatgpt_exec_result,Chatgpt.run_result.
 cbn [Selvedge.Generated.Commands.chatgpt_exec_connection_id Selvedge.Generated.Commands.chatgpt_exec_project_id
   Selvedge.Generated.Commands.chatgpt_exec_request_id Selvedge.Generated.Commands.chatgpt_exec_arguments].
 rewrite Resolved.
 unfold DeferredCommit.continue_result,CommandResult.commit,CommandResult.map,CommandResult.bind,
   CommandResult.decide,CommandResult.resolve.
 cbn [Chatgpt.resolved_connection_change CommandResult.append_effects CommandResult.accept].
 change (Decision
   (decision_world (TicketedRequest.Scoped.feature_issue (TicketedRequest.Scoped.connection_plan resolved)))
   (success (Chatgpt.receipt (TicketedRequest.next_identity TicketedRequest.ConnectionIdentity before)
     (FeatureRequestAdmission.resolved_job resolved)))
   (decision_effects (TicketedRequest.Scoped.feature_issue (TicketedRequest.Scoped.connection_plan resolved)) ++ [ContinueScheduling])
   = accepted_decision before (admitted_job connection project request decoded granted target)).
 rewrite an_issued_connection_has_the_fresh_state with (job := FeatureRequestAdmission.resolved_job resolved).
 - rewrite Job; reflexivity.
 - reflexivity.
 - apply sharing_jobs_stay_below_their_supply; exact Valid.
Qed.

Theorem admissible_connection_request_passes_every_commit_requirement :
 forall before job reply source raw,
 W.world_valid before=true ->
 (N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) < 128)%N ->
 (F.sharing_next (Chatgpt.registry before) < 4294967295)%N ->
 Selvedge.Features.Remote.identifier_valid (F.job_request job)=true ->
 ChatgptArguments.valid_args (F.job_arguments_json job)=true ->
 Workspace.valid_workspace (F.job_workspace job)=true ->
 F.job_state job=F.JobRunning ->
 WorkspaceBinding.resource_ready (F.job_workspace job) (F.job_resource job) before=true ->
 let candidate:=Decision (Chatgpt.store (fresh_state before job) before) reply
  [RunConnectionJob (F.sharing_next (Chatgpt.registry before)) job;ContinueScheduling] in
 Delivery.fits true candidate=true ->
 DeferredCommit.admit_with_status true source raw before candidate=(true,candidate).
Proof.
 intros before job reply source raw World Capacity Supply Request Arguments Workspace Running Resource candidate Fits.
 destruct (a_valid_world_supplies_connection_requirements before World) as [Features Sharing].
 assert (WorldAfter: W.world_valid (Chatgpt.store (fresh_state before job) before)=true).
 { apply sharing_store_preserves_other_requirements;[exact World|].
   apply fresh_connection_preserves_sharing_requirements;assumption. }
 assert (Authorized: A.transition_authorized true source raw before candidate=true).
 { apply fresh_connection_has_complete_commit_authority;exact Features. }
 assert (Live : Dispatch.retain_live_effects candidate = candidate) by reflexivity.
 unfold DeferredCommit.admit_with_status. rewrite Live.

 unfold W.validate_with_status. change (W.world_valid (decision_world candidate)) with
  (W.world_valid (Chatgpt.store (fresh_state before job) before)).
 rewrite WorldAfter. unfold A.validate_with_status;rewrite Authorized.
 unfold Delivery.deliver_with_status;rewrite Fits;reflexivity.
Qed.

Lemma selected_project_has_a_valid_workspace : forall id before target,
 W.world_valid before=true -> Chatgpt.project id before=Some target ->
 Workspace.valid_workspace (project_workspace target)=true.
Proof.
 intros id before target World Project.
 unfold Chatgpt.project,FeatureRequestAdmission.connection_project in Project.
 destruct (registry_at id (world_projects before)) as [selected|] eqn:Found;[|discriminate].
 destruct (project_deleted selected) eqn:Deleted;[discriminate|]. inversion Project;subst target.
 unfold W.world_valid,W.world_structure in World;repeat rewrite andb_true_iff in World.
 destruct World as [[[[Environment Projects] Tasks] Tickets] Features].
 unfold W.projects_valid in Projects;repeat rewrite andb_true_iff in Projects.
 destruct Projects as [[Registry Count] Valid].
 apply forallb_forall with (x:=selected) in Valid.
 - unfold W.project_valid in Valid;rewrite Deleted in Valid;repeat rewrite andb_true_iff in Valid;tauto.
 - eapply FeatureFrameProofs.an_observed_registry_entry_is_a_member; exact Found.
Qed.

Theorem every_admissible_public_connection_has_its_durable_result :
 forall connection project request arguments command timeout maximum granted target before raw,
 W.world_valid before=true ->
 Chatgpt.ids_valid [connection;project]=true -> Chatgpt.bounded_text 128 request=true ->
 ChatgptArguments.admit_args arguments=Some (bash_arguments command timeout maximum) ->
 negb (String.eqb command ""%string)=true -> Utf8.well_formed command=true ->
 (N.of_nat (String.length command) <= 32768)%N ->
 (100 <= timeout <= 1800000)%N -> (1 <= maximum <= 8192)%N ->
 Chatgpt.authority connection project (Chatgpt.registry before)=Some granted ->
 Chatgpt.project project before=Some target -> workspace_primary (project_workspace target)<>None ->
 Chatgpt.retry connection request (Chatgpt.registry before)=None ->
 Selvedge.Features.Worktree.workspace_available (project_workspace target) before=true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) before=true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) <? 128) &&
 (F.sharing_next (Chatgpt.registry before) <? ChatgptArguments.identity_maximum))%N=true ->
 let job:=admitted_job connection project request (bash_arguments command timeout maximum) granted target in
 Delivery.fits true (accepted_decision before job)=true ->
 ConnectionCommit.packet (Selvedge.Generated.Commands.Build_chatgpt_exec connection project request arguments) raw before =
 (with_sequence (N.succ (world_sequence before)) (Chatgpt.store (fresh_state before job) before),
 Notifications.envelope true true
  (Some (UserCommand (Selvedge.Generated.Commands.Cmd_chatgpt_exec
   (Selvedge.Generated.Commands.Build_chatgpt_exec connection project request arguments))))
  before (accepted_decision before job)).
Proof.
 intros connection project request arguments command timeout maximum granted target before raw World Ids
 Bounded Arguments Nonempty Utf8 Length Timeout Maximum Authority Project Primary Retry Available Resource Capacity job Fits.
 destruct (a_valid_world_supplies_connection_requirements before World) as [Features Sharing].
 unfold ConnectionCommit.packet.
 rewrite admissible_connection_command_constructs_its_exact_result with
  (decoded:=bash_arguments command timeout maximum) (granted:=granted) (target:=target) by assumption.
 fold job. unfold accepted_decision.
 unfold DeferredCommit.packet, DeferredCommit.select, CommitPacket.choose.
 rewrite admissible_connection_request_passes_every_commit_requirement.
 - reflexivity.
 - exact World.
 - apply andb_true_iff in Capacity as [Bound _];apply N.ltb_lt;exact Bound.
 - apply andb_true_iff in Capacity as [_ Bound];apply N.ltb_lt;exact Bound.
 - exact Bounded.
 - unfold job,admitted_job,F.job_arguments_json;cbn [F.job_arguments].
   apply bounded_bash_arguments_have_a_valid_canonical_wire;assumption.
 - apply selected_project_has_a_valid_workspace with (id:=project) (before:=before);assumption.
 - reflexivity.
 - exact Resource.
 - exact Fits.
Qed.
