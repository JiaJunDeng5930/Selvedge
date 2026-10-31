From Selvedge.Kernel Require Import FeatureAdmissionProofs.
From Selvedge.Kernel Require CommandResult FeatureRequestAdmission.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import JsonProofs KeyedListProofs.
From Selvedge.Kernel Require Import Domain State Numbers Codec ChatgptArguments.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Chatgpt.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.

Lemma sharing_registry_store : forall sharing value,
 Chatgpt.registry (Chatgpt.store sharing value) = sharing.
Proof. intros sharing [seq tasks ticket env projects features]. destruct features; reflexivity. Qed.

Lemma lookup_replaced_job : forall id job state,
 Chatgpt.find_job id (Chatgpt.replace_job id job state) = Some job.
Proof. intros id job [grants jobs next]. unfold Chatgpt.find_job,Chatgpt.replace_job; cbn. now rewrite N.eqb_refl. Qed.
Lemma authority_replaced_job : forall connection project id job state,
 Chatgpt.authority connection project (Chatgpt.replace_job id job state)=Chatgpt.authority connection project state.
Proof. intros connection project id job [grants jobs next]. reflexivity. Qed.

Lemma outcome_preserves_ownership : forall connection project outcome job,
 Chatgpt.owned connection project (Chatgpt.with_outcome outcome job)=Chatgpt.owned connection project job.
Proof. intros connection project outcome []; reflexivity. Qed.
Lemma interrupted_is_not_pending : forall reason job,
 Chatgpt.pending (Chatgpt.with_outcome (F.JobInterrupted reason) job)=false.
Proof. intros reason []; reflexivity. Qed.

Theorem connection_without_project_grant_cannot_execute : forall connection project request arguments value,
 Chatgpt.authority connection project (Chatgpt.registry value) = None ->
 decision_world (Chatgpt.run connection project request arguments value) = value /\
 decision_effects (Chatgpt.run connection project request arguments value) = [].
Proof.
 intros connection project request arguments value Missing.
 unfold Chatgpt.run,Chatgpt.run_result.
 destruct (FeatureRequestAdmission.resolve_connection connection project request arguments value)
   as [[identity job|resolved]|reason];
   cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
     Chatgpt.resolved_connection_change CommandResult.accept CommandResult.reject];
   try (split; reflexivity).
 pose proof (FeatureRequestAdmission.resolved_authority resolved) as Authority.
 unfold Chatgpt.authority,Chatgpt.registry in Missing. rewrite Missing in Authority; discriminate.
Qed.

Theorem query_cannot_reveal_foreign_operation : forall (payload : G.chatgpt_operation_payload) value,
 Chatgpt.authority (G.chatgpt_operation_connection_id payload)
   (G.chatgpt_operation_project_id payload) (Chatgpt.registry value) = None ->
 Chatgpt.handle_chatgpt_operation payload None value = Chatgpt.forbidden.
Proof.
 intros payload value Missing. unfold Chatgpt.handle_chatgpt_operation, Chatgpt.read_job.
 now rewrite Missing.
Qed.

Theorem recovery_never_replays_running_job : forall connection project request arguments workspace resource sandbox,
 F.job_state (Chatgpt.recover_job (F.ConnectionJob connection project request arguments workspace resource sandbox F.JobRunning)) =
 F.JobInterrupted "Service restarted; execution may have happened and will not be replayed".
Proof. reflexivity. Qed.

(** Forgetting ends retention without returning the identifier to the supply. *)
Theorem public_forget_removes_settled_receipt : forall (payload : G.chatgpt_forget_payload) value job granted caller,
 let connection := G.chatgpt_forget_connection_id payload in
 let project := G.chatgpt_forget_project_id payload in
 let id := G.chatgpt_forget_operation_id payload in
 Chatgpt.authority connection project (Chatgpt.registry value) = Some granted ->
 Chatgpt.find_job id (Chatgpt.registry value) = Some job ->
 Chatgpt.owned connection project job = true ->
 Chatgpt.pending job = false ->
 exists decision,
 Chatgpt.handle_chatgpt_forget payload caller value = decision /\
 Chatgpt.find_job id (Chatgpt.registry (decision_world decision)) = None /\
 F.sharing_next (Chatgpt.registry (decision_world decision)) = F.sharing_next (Chatgpt.registry value) /\
 decision_effects decision = [].
Proof.
 intros payload value job granted caller connection project id authority found owner settled.
 change (Chatgpt.handle_chatgpt_forget payload caller value)
   with (Chatgpt.edit true connection project id value).
 unfold Chatgpt.edit. rewrite authority,found,owner,settled. cbn.
 eexists. split; [reflexivity|].
 cbn beta iota zeta delta [decision_world decision_effects accept].
 rewrite sharing_registry_store. destruct (Chatgpt.registry value) as [grants jobs next].
 cbn. unfold Chatgpt.find_job. cbn. rewrite removing_a_key_clears_its_lookup.
 repeat split; reflexivity.
Qed.

(** Repeating an accepted cancellation cannot request a second physical stop. *)
Theorem repeated_cancellation_is_idempotent : forall connection project id value,
 let first:=Chatgpt.edit false connection project id value in
 let second:=Chatgpt.edit false connection project id (decision_world first) in
 decision_world second=decision_world first /\ decision_effects second=[].
Proof.
 intros connection project id value.
 unfold Chatgpt.edit at 1.
 destruct (Chatgpt.authority connection project (Chatgpt.registry value)) as [granted|] eqn:authority.
 - destruct (Chatgpt.find_job id (Chatgpt.registry value)) as [job|] eqn:found.
   + destruct (negb (Chatgpt.owned connection project job)) eqn:owner.
     * cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite authority,found,owner. split;reflexivity.
     * destruct (Chatgpt.pending job) eqn:running.
       -- cbn beta iota zeta delta [decision_world decision_effects accept reject].
          unfold Chatgpt.edit. rewrite sharing_registry_store,authority_replaced_job,authority,lookup_replaced_job.
          rewrite outcome_preserves_ownership,owner,interrupted_is_not_pending.
          split;reflexivity.
       -- cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite authority,found,owner,running. split;reflexivity.
   + cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite authority,found. split;reflexivity.
 - cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite authority. split;reflexivity.
Qed.

(** This conclusion requires actual authority and admission, not an assumed
    successful result. It excludes a dispatcher that silently refuses all jobs. *)
Theorem accepted_public_exec_emits_frozen_job : forall (payload : G.chatgpt_exec_payload) granted target value caller,
 let connection := G.chatgpt_exec_connection_id payload in
 let project := G.chatgpt_exec_project_id payload in
 let request := G.chatgpt_exec_request_id_admitted payload in
 let arguments := G.chatgpt_exec_arguments_admitted payload in
 Chatgpt.authority connection project (Chatgpt.registry value)=Some granted ->
 Chatgpt.project project value=Some target -> workspace_primary (project_workspace target)<>None ->
 Chatgpt.retry connection (ChatgptArguments.request_text request) (Chatgpt.registry value)=None ->
 Worktree.workspace_available (project_workspace target) value=true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) value=true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry value))) <? 128) &&
   (F.sharing_next (Chatgpt.registry value) <? ChatgptArguments.identity_maximum))=true ->
 exists decision job,
 Chatgpt.handle_chatgpt_exec payload caller value=decision /\
 decision_effects decision=[RequestFeature (RequestTypes.Packet (RequestTypes.release (Chatgpt.protocol (world_features value)))
   (RequestEnvelope.Envelope (F.sharing_next (Chatgpt.registry value)) job))] /\
 F.job_connection job=connection /\ F.job_project job=project /\ F.job_arguments job=arguments /\
 F.job_workspace job=project_workspace target /\ F.job_resource job=project_resource target /\ F.job_sandbox job=F.connection_sandbox granted /\ F.job_state job=F.JobRunning.
Proof.
 intros payload granted target value caller connection project request arguments authority project_found primary retry available resource capacity.
 assert (Primary : FeatureRequestAdmission.connection_has_primary target = true).
 { unfold FeatureRequestAdmission.connection_has_primary; destruct (workspace_primary (project_workspace target));
   [reflexivity|contradiction]. }
 assert (Ready : FeatureRequestAdmission.connection_workspace target value = true).
 { unfold FeatureRequestAdmission.connection_workspace. change (WorkspaceBinding.workspace_available (project_workspace target) value = true) in available. now rewrite available,resource. }
 destruct (admitted_connection_resolves_without_rechecking connection project request arguments granted target value
   authority project_found Primary retry Ready capacity) as [resolved [Resolved Job]].
 unfold Chatgpt.handle_chatgpt_exec,Chatgpt.handle_chatgpt_exec_result,Chatgpt.run_result.
 fold connection project request arguments.
 rewrite Resolved.
 cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
   Chatgpt.resolved_connection_change Chatgpt.plan
   TicketedRequest.Scoped.feature_issue_change TicketedRequest.Scoped.feature_input TicketedRequest.Scoped.feature_selected
   TicketedRequest.Scoped.feature_request TicketedRequest.Scoped.feature_envelope TicketedRequest.Scoped.feature_protocol
   TicketedRequest.Scoped.channel_protocol TicketedRequest.Scoped.channel_space
   Chatgpt.channel TicketedRequest.Scoped.channel_input TicketedRequest.allocate_identity TicketedRequest.next_identity].
 assert (Input : TicketedRequest.Scoped.feature_input (Chatgpt.plan resolved) =
   FeatureRequestAdmission.connection_job connection project (ChatgptArguments.request_text request) arguments granted target) by exact Job.
 rewrite Job. eexists; eexists; repeat split; try reflexivity; rewrite Input; reflexivity.
Qed.

(** A retry remains a receipt lookup, but a new physical job cannot enter
    a managed workspace whose resource is unavailable. *)
Theorem unavailable_fresh_job_emits_no_io : forall connection project request arguments target value,
 Chatgpt.project project value=Some target ->
 Worktree.workspace_available (project_workspace target) value=false ->
 decision_world (Chatgpt.run connection project request arguments value)=value /\
 decision_effects (Chatgpt.run connection project request arguments value)=[].
Proof.
 intros connection project request arguments target value Project Unavailable.
 unfold Chatgpt.run,Chatgpt.run_result.
 destruct (FeatureRequestAdmission.resolve_connection connection project request arguments value)
   as [[identity job|resolved]|reason];
   cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
     Chatgpt.resolved_connection_change CommandResult.accept CommandResult.reject];
   try (split; reflexivity).
 pose proof (FeatureRequestAdmission.resolved_target_found resolved) as Found.
 change (FeatureRequestAdmission.connection_project project value = Some target) in Project.
 rewrite Project in Found; injection Found as Target.
 pose proof (FeatureRequestAdmission.resolved_workspace resolved) as Ready.
 unfold FeatureRequestAdmission.connection_workspace in Ready; rewrite <- Target in Ready.
 change (WorkspaceBinding.workspace_available (project_workspace target) value = false) in Unavailable.
 rewrite Unavailable in Ready; discriminate.
Qed.
