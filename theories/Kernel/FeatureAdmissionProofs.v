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
 rewrite Arguments.
 eapply observe_present; [exact Authority|]; intros Granted.
 eapply observe_present; [exact Project|]; intros Existing.
 apply require_satisfied; [exact Primary|]; intros HasPrimary.
 eapply observe_absent; [exact Retry|]; intros Fresh.
 apply require_satisfied; [exact Workspace|]; intros Ready.
 apply require_satisfied; [exact Capacity|]; intros Room.
 eexists; split; reflexivity.
Qed.
