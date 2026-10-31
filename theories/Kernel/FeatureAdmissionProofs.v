From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskScope.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Programming Require Import OptionObservationProofs.
From Selvedge.Kernel Require Import Domain State FeatureRequestAdmission ChatgptArguments.
From Selvedge.Programming Require CommandResult.
Import ListNotations.

Definition observe_present := @OptionObservationProofs.observe_present.
Definition observe_absent := @OptionObservationProofs.observe_absent.
Definition observe_cases := @OptionObservationProofs.observe_cases.
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

Theorem admitted_connection_resolves_without_rechecking : forall identity project request arguments grant target before,
 connection_authority identity project (sharing_registry before) = Some grant ->
 connection_project project before = Some target -> connection_has_primary target = true ->
 connection_retry identity (ChatgptArguments.request_text request) (sharing_registry before) = None ->
 connection_workspace target before = true -> connection_capacity before = true ->
 exists resolved,
 resolve_connection identity project request arguments before = CommandResult.Accepted (NewConnection resolved) /\
 resolved_job resolved = connection_job identity project (ChatgptArguments.request_text request) arguments grant target.
Proof.
 intros identity project request arguments grant target before Authority Project Primary Retry Workspace Capacity.
 unfold resolve_connection.
 eapply observe_present; [exact Authority|]; intros Granted.
 eapply observe_present; [exact Project|]; intros Existing.
 apply CommandResult.require_satisfied; [exact Primary|]; intros HasPrimary.
 eapply observe_absent; [exact Retry|]; intros Fresh.
 apply CommandResult.require_satisfied; [exact Workspace|]; intros Ready.
 apply CommandResult.require_satisfied; [exact Capacity|]; intros Room.
 eexists; split; reflexivity.
Qed.
