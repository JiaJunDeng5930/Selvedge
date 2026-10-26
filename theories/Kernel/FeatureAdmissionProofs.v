From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Registry OptionListProofs.
From Selvedge.Kernel Require Import Domain State FeatureRequestAdmission ChatgptArguments.
From Selvedge.Kernel Require CommandResult.
Import ListNotations.

Lemma require_satisfied : forall A condition accepted code message (P : CommandResult.result A -> Prop),
 condition = true -> (forall evidence, P (accepted evidence)) ->
 P (require condition accepted code message).
Proof. intros A [] accepted code message P Enabled Satisfied; [apply Satisfied|discriminate]. Qed.
Definition observe_present := @OptionListProofs.observe_present.
Definition observe_absent := @OptionListProofs.observe_absent.
Definition observe_cases := @OptionListProofs.observe_cases.
Lemma require_cases : forall A condition accepted code message (P : CommandResult.result A -> Prop),
 (forall evidence, P (accepted evidence)) -> P (CommandResult.refuse code message) ->
 P (require condition accepted code message).
Proof. intros A [] accepted code message P Accepted Rejected; [apply Accepted|exact Rejected]. Qed.

Theorem admitted_title_resolves_without_rechecking : forall owner current before selected,
 find_task owner before = Some current -> title_entry owner before = None ->
 title_accepts current = true ->
 Selvedge.Foundation.Utf8.nonblank (Selvedge.Features.Observation.first_request (task_history current)) = true ->
 selected_title_profile current before = Some selected ->
 exists request,
 resolve_title owner before = Some request /\
 TaskScope.owner (title_reference request) = owner /\
 TaskScope.selected (title_reference request) = current /\ title_profile request = selected.
Proof.
 intros owner current before selected Found Absent Live Nonblank Chosen.
 unfold resolve_title.
 eapply observe_absent; [exact Absent|]; intros Missing.
 eapply observe_present; [exact Found|]; intros Observed.
 destruct (Bool.bool_dec _ true) as [Eligible|Ineligible].
 - eapply observe_present; [exact Chosen|]; intros Selected.
   eexists; repeat split; reflexivity.
 - exfalso; apply Ineligible; now rewrite Live,Nonblank.
Qed.

Theorem a_pending_title_is_not_resolved_again : forall owner before entry,
 title_entry owner before = Some entry -> resolve_title owner before = None.
Proof.
 intros owner before entry Found; unfold resolve_title.
 eapply observe_present; [exact Found|]; reflexivity.
Qed.

Theorem admitted_connection_resolves_without_rechecking : forall identity project request raw arguments grant target before,
 ids_valid [identity;project] = true -> bounded_text 128 request = true ->
 admit_args raw = Some arguments ->
 connection_authority identity project (sharing_registry before) = Some grant ->
 connection_project project before = Some target -> connection_has_primary target = true ->
 connection_retry identity request (sharing_registry before) = None ->
 connection_workspace target before = true -> connection_capacity before = true ->
 exists resolved,
 resolve_connection identity project request raw before = CommandResult.Accepted (NewConnection resolved) /\
 resolved_job resolved = connection_job identity project request arguments grant target.
Proof.
 intros identity project request raw arguments grant target before Ids Bounded Arguments Authority Project Primary Retry Workspace Capacity.
 unfold resolve_connection.
 apply require_satisfied; [now rewrite Ids,Bounded|]; intros Input.
 rewrite <- admit_arguments_erases in Arguments.
 destruct (admit_arguments raw) as [[decoded Valid]|] eqn:Decoded; cbn in Arguments.
 - inversion Arguments; subst decoded.
   eapply observe_present; [exact Authority|]; intros Granted.
   eapply observe_present; [exact Project|]; intros Existing.
   apply require_satisfied; [exact Primary|]; intros HasPrimary.
   eapply observe_absent; [exact Retry|]; intros Fresh.
   apply require_satisfied; [exact Workspace|]; intros Ready.
   apply require_satisfied; [exact Capacity|]; intros Room.
   eexists; split; reflexivity.
 - discriminate.
Qed.

Theorem resolved_connection_has_authority : forall before identity project request (resolved : resolved_connection before identity project request),
 exists grant, connection_authority (Selvedge.Features.Domain.job_connection (resolved_job resolved))
   (Selvedge.Features.Domain.job_project (resolved_job resolved)) (sharing_registry before) = Some grant.
Proof.
 intros before identity project request [job Owner Project Request Running Admitted]; cbn in *.
 unfold connection in Admitted. fold (sharing_registry before) in Admitted.
 destruct (find _ _) as [grant|] eqn:Grant; [|discriminate].
 destruct (registry_at _ _) as [target|]; [|discriminate].
 repeat rewrite andb_true_iff in Admitted.
 exists grant; unfold connection_authority,connection_grant; rewrite Grant.
 destruct (existsb _ _) eqn:Member; [reflexivity|]. intuition discriminate.
Qed.

Theorem resolved_connection_has_fresh_request : forall before identity project request (resolved : resolved_connection before identity project request),
 connection_retry (Selvedge.Features.Domain.job_connection (resolved_job resolved))
   (Selvedge.Features.Domain.job_request (resolved_job resolved)) (sharing_registry before) = None.
Proof.
 intros before identity project request [job Owner Project Request Running Admitted]; cbn in *.
 unfold connection in Admitted. fold (sharing_registry before) in Admitted.
 destruct (find _ _); [|discriminate]. destruct (registry_at _ _); [|discriminate].
 repeat rewrite andb_true_iff in Admitted.
 assert (NoMatch : existsb (fun entry => N.eqb (Selvedge.Features.Domain.job_connection job)
   (Selvedge.Features.Domain.job_connection (snd entry)) &&
   String.eqb (Selvedge.Features.Domain.job_request job) (Selvedge.Features.Domain.job_request (snd entry)))
   (Selvedge.Features.Domain.sharing_jobs (sharing_registry before)) = false).
 { apply negb_true_iff; tauto. }
 unfold connection_retry.
 destruct (find _ _) as [existing|] eqn:Found; [|reflexivity].
 apply find_some in Found as [Member Matches].
 assert (HasMatch : existsb (fun entry => N.eqb (Selvedge.Features.Domain.job_connection job)
   (Selvedge.Features.Domain.job_connection (snd entry)) &&
   String.eqb (Selvedge.Features.Domain.job_request job) (Selvedge.Features.Domain.job_request (snd entry)))
   (Selvedge.Features.Domain.sharing_jobs (sharing_registry before)) = true).
 { apply existsb_exists; exists existing; auto. }
 rewrite NoMatch in HasMatch; discriminate.
Qed.
