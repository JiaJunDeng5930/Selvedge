From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonProofs.
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
 intros connection project request arguments value missing.
 unfold Chatgpt.run.
 destruct (negb (Chatgpt.ids_valid [connection;project] && Chatgpt.bounded_text 128 request));
 [split;reflexivity|].
 destruct (ChatgptArguments.admit_args arguments); [|split;reflexivity].
 rewrite missing. split;reflexivity.
Qed.

Theorem query_cannot_reveal_foreign_operation : forall connection project id value,
 Chatgpt.ids_valid [connection;project;id] = true ->
 Chatgpt.authority connection project (Chatgpt.registry value) = None ->
 Chatgpt.query (G.Cmd_chatgpt_operation (G.Build_chatgpt_operation connection project id)) None value = Some Chatgpt.forbidden.
Proof.
 intros. change (Some (Chatgpt.valid_query [connection;project;id] (Chatgpt.read_job connection project id value))=Some Chatgpt.forbidden).
 unfold Chatgpt.valid_query. rewrite H. unfold Chatgpt.read_job. now rewrite H0.
Qed.

Theorem finished_callback_is_ignored : forall id job result error value,
 Chatgpt.find_job id (Chatgpt.registry value) = Some job ->
 Chatgpt.pending job = false ->
 let '(_,_,decision):=Chatgpt.settle id result error value in
 decision_world decision=value /\ decision_effects decision=[].
Proof. intros. unfold Chatgpt.settle. rewrite H,H0. split;reflexivity. Qed.

Theorem missing_callback_is_ignored : forall id result error value,
 Chatgpt.find_job id (Chatgpt.registry value) = None ->
 let '(_,_,decision):=Chatgpt.settle id result error value in
 decision_world decision=value /\ decision_effects decision=[].
Proof. intros. unfold Chatgpt.settle. rewrite H. split;reflexivity. Qed.

Theorem completion_preserves_execution_context : forall id job result error value,
 Chatgpt.find_job id (Chatgpt.registry value) = Some job -> Chatgpt.pending job=true ->
 let '(_,_,decision):=Chatgpt.settle id result error value in
 exists finished,Chatgpt.find_job id (Chatgpt.registry (decision_world decision))=Some finished /\
 F.job_connection finished=F.job_connection job /\ F.job_project finished=F.job_project job /\
 F.job_request finished=F.job_request job /\ F.job_arguments finished=F.job_arguments job /\
 F.job_workspace finished=F.job_workspace job /\ F.job_resource finished=F.job_resource job /\ F.job_sandbox finished=F.job_sandbox job /\
 F.job_state finished=F.JobFinished result error.
Proof.
 intros. unfold Chatgpt.settle. rewrite H,H0. cbn.
 exists (Chatgpt.with_outcome (F.JobFinished result error) job).
 rewrite sharing_registry_store,lookup_replaced_job.
 destruct job; repeat split;reflexivity.
Qed.

Theorem recovery_never_replays_running_job : forall connection project request arguments workspace resource sandbox,
 F.job_state (Chatgpt.recover_job (F.ConnectionJob connection project request arguments workspace resource sandbox F.JobRunning)) =
 F.JobInterrupted "Service restarted; execution may have happened and will not be replayed".
Proof. reflexivity. Qed.

Lemma removed_job_is_absent : forall id jobs,
 find (fun item : N * F.connection_job => N.eqb id (fst item))
   (filter (fun item => negb (N.eqb id (fst item))) jobs) = None.
Proof.
 intros id jobs. induction jobs as [|[key job] rest IH]; [reflexivity|].
 cbn. destruct (N.eqb id key) eqn:same; [exact IH|].
 cbn. rewrite same. exact IH.
Qed.

(** Forgetting ends retention without returning the identifier to the supply. *)
Theorem public_forget_removes_settled_receipt : forall connection project id value job granted caller,
 Chatgpt.ids_valid [connection;project;id] = true ->
 Chatgpt.authority connection project (Chatgpt.registry value) = Some granted ->
 Chatgpt.find_job id (Chatgpt.registry value) = Some job ->
 Chatgpt.owned connection project job = true ->
 Chatgpt.pending job = false ->
 exists decision,
 Chatgpt.command (G.Cmd_chatgpt_forget (G.Build_chatgpt_forget connection project id)) caller value = Some decision /\
 Chatgpt.find_job id (Chatgpt.registry (decision_world decision)) = None /\
 F.sharing_next (Chatgpt.registry (decision_world decision)) = F.sharing_next (Chatgpt.registry value) /\
 decision_effects decision = [].
Proof.
 intros connection project id value job granted caller ids authority found owner settled.
 change (Chatgpt.command (G.Cmd_chatgpt_forget (G.Build_chatgpt_forget connection project id)) caller value)
   with (Some (Chatgpt.edit true connection project id value)).
 unfold Chatgpt.edit. rewrite ids,authority,found,owner,settled. cbn.
 eexists. split; [reflexivity|].
 cbn beta iota zeta delta [decision_world decision_effects accept].
 rewrite sharing_registry_store. destruct (Chatgpt.registry value) as [grants jobs next].
 cbn. unfold Chatgpt.find_job. cbn. rewrite removed_job_is_absent.
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
 destruct (negb (Chatgpt.ids_valid [connection;project;id])) eqn:ids.
 - cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite ids. split;reflexivity.
 - destruct (Chatgpt.authority connection project (Chatgpt.registry value)) as [granted|] eqn:authority.
   + destruct (Chatgpt.find_job id (Chatgpt.registry value)) as [job|] eqn:found.
     * destruct (negb (Chatgpt.owned connection project job)) eqn:owner.
       -- cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite ids,authority,found,owner. split;reflexivity.
       -- destruct (Chatgpt.pending job) eqn:running.
          ++ cbn beta iota zeta delta [decision_world decision_effects accept reject].
             unfold Chatgpt.edit. rewrite ids,sharing_registry_store,authority_replaced_job,authority,lookup_replaced_job.
             rewrite outcome_preserves_ownership,owner,interrupted_is_not_pending.
             split;reflexivity.
          ++ cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite ids,authority,found,owner,running. split;reflexivity.
     * cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite ids,authority,found. split;reflexivity.
   + cbn beta iota zeta delta [decision_world decision_effects accept reject]. unfold Chatgpt.edit. rewrite ids,authority. split;reflexivity.
Qed.

(** This conclusion requires actual authority and admission, not an assumed
    successful result. It excludes a dispatcher that silently refuses all jobs. *)
Theorem accepted_public_exec_emits_frozen_job : forall connection project request arguments decoded granted target value caller,
 Chatgpt.ids_valid [connection;project] = true -> Chatgpt.bounded_text 128 request=true ->
 ChatgptArguments.admit_args arguments=Some decoded ->
 Chatgpt.authority connection project (Chatgpt.registry value)=Some granted ->
 Chatgpt.project project value=Some target -> workspace_primary (project_workspace target)<>None ->
 Chatgpt.retry connection request (Chatgpt.registry value)=None ->
 Worktree.workspace_available (project_workspace target) value=true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) value=true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry value))) <? 128) &&
   (F.sharing_next (Chatgpt.registry value) <? ChatgptArguments.identity_maximum))=true ->
 exists decision job,
 Chatgpt.command (G.Cmd_chatgpt_exec (G.Build_chatgpt_exec connection project request arguments)) caller value=Some decision /\
 decision_effects decision=[RunConnectionJob (F.sharing_next (Chatgpt.registry value)) job] /\
 F.job_connection job=connection /\ F.job_project job=project /\ F.job_arguments job=decoded /\
 F.job_workspace job=project_workspace target /\ F.job_resource job=project_resource target /\ F.job_sandbox job=F.connection_sandbox granted /\ F.job_state job=F.JobRunning.
Proof.
 intros connection project request arguments decoded granted target value caller ids bounded admitted authority project_found primary retry available resource capacity.
 change (Chatgpt.command (G.Cmd_chatgpt_exec (G.Build_chatgpt_exec connection project request arguments)) caller value)
   with (Some (Chatgpt.run connection project request arguments value)).
 unfold Chatgpt.run. rewrite ids,bounded,admitted,authority,project_found.
 cbn beta iota zeta delta [andb negb].
 destruct (workspace_primary (project_workspace target)) eqn:found; [|contradiction].
 unfold Chatgpt.start. rewrite retry,available,resource,capacity.
 eexists; eexists; repeat split;reflexivity.
Qed.

(** A retry remains a receipt lookup, but a new physical job cannot enter
    a managed workspace whose resource is unavailable. *)
Theorem unavailable_fresh_job_emits_no_io : forall connection project request arguments granted target value,
 Chatgpt.retry connection request (Chatgpt.registry value)=None ->
 Worktree.workspace_available (project_workspace target) value=false ->
 decision_world (Chatgpt.start connection project request arguments granted target value)=value /\
 decision_effects (Chatgpt.start connection project request arguments granted target value)=[].
Proof. intros. unfold Chatgpt.start. rewrite H,H0. split;reflexivity. Qed.
