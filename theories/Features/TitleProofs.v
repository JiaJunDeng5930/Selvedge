From Selvedge.Programming Require RequestTypes.
From Selvedge.Programming Require TaskScope.
From Selvedge.Programming Require Import CompletionProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain State FeatureAdmissionProofs.
From Selvedge.Features Require Import Domain State TitleRuntime.
Import ListNotations.
Open Scope list_scope.
Module F:=Selvedge.Features.Domain.

Definition execution_core (value : world) :=
 (world_sequence value, world_tasks value, world_next_ticket value,
  world_environment value, world_projects value).
(** Admission supplies the actual observed owner; the production issuer freezes
    that owner's selected profile and title prompt in its emitted request. *)
Theorem admitted_title_issues_observed_request : forall id task before selected,
 find_task id before = Some task ->
 FeatureRequestAdmission.title_entry id before = None ->
 FeatureRequestAdmission.title_accepts task = true ->
 Selvedge.Foundation.Utf8.nonblank (Observation.first_request (task_history task)) = true ->
 FeatureRequestAdmission.selected_title_profile task before = Some selected ->
 exists request : FeatureRequestAdmission.resolved_title before,
 FeatureRequestAdmission.resolve_title id before = Some request /\
 CommandResult.change_effects (TitleRuntime.issue request) =
   [RequestFeature (RequestTypes.Packet
     (RequestTypes.release (TitleRuntime.protocol (world_features before) id))
     (RequestEnvelope.Envelope (world_next_ticket before)
       (selected,FeatureRequestAdmission.title_prompt task before)))].
Proof.
 intros id task before selected Found Absent Accepts Nonblank Chosen.
 destruct (admitted_title_resolves_without_rechecking id task before selected
   Found Absent Accepts Nonblank Chosen) as [request [Resolved [Owner [Current Selected]]]].
 exists request; split; [exact Resolved|].
 change ([RequestFeature (RequestTypes.Packet
   (RequestTypes.release (TitleRuntime.protocol (world_features before)
     (TaskScope.owner (FeatureRequestAdmission.title_reference request))))
   (RequestEnvelope.Envelope (world_next_ticket before)
     (FeatureRequestAdmission.title_profile request,
      FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) before)))] =
   [RequestFeature (RequestTypes.Packet
     (RequestTypes.release (TitleRuntime.protocol (world_features before) id))
     (RequestEnvelope.Envelope (world_next_ticket before)
       (selected,FeatureRequestAdmission.title_prompt task before)))]).
 rewrite Owner,Current,Selected; reflexivity.
Qed.

(** An explicit title model remains bound to its saved identity even when the
    Task profile or connection registry changes. *)
Theorem explicit_title_profile_uses_only_saved_key : forall task before key selected,
 F.title_agent_profile (F.feature_title_settings (world_features before)) = Some key ->
 FeatureRequestAdmission.selected_title_profile task before = Some selected ->
 profile_key selected = key /\ FeatureRequestAdmission.ordinary_profile selected = true.
Proof.
 intros task before key selected Config Chosen.
 unfold FeatureRequestAdmission.selected_title_profile in Chosen.
 rewrite Config in Chosen.
 remember (environment_profiles (world_environment before)) as configured eqn:Configured.
 clear Configured.
 induction configured as [|candidate rest IH]; simpl in Chosen; [discriminate|].
 destruct (String.eqb key (profile_key candidate) &&
   FeatureRequestAdmission.ordinary_profile candidate) eqn:Admits.
 - inversion Chosen; subst selected.
   apply andb_true_iff in Admits as [Key Ordinary].
   apply String.eqb_eq in Key. split; [symmetry; exact Key|exact Ordinary].
 - exact (IH Chosen).
Qed.

(** Normalization is title-specific; correlation and once-only settlement are
    properties of the shared completion interpreter. *)
Theorem completed_title_is_normalized : forall text,
 Selvedge.Features.Titles.normalize text<>""%string ->
 Completion.outcome (TitleRuntime.completed_name true text) =
 F.Named (Selvedge.Features.Titles.normalize text).
Proof.
 intros text Nonempty. unfold TitleRuntime.completed_name.
 apply String.eqb_neq in Nonempty. rewrite Nonempty. reflexivity.
Qed.

(** Editing policy affects future generations; already frozen requests and
    saved names remain in the same registry. *)
Theorem title_configuration_preserves_generation_entries : forall value revision task_prompt agent_prompt agent_profile,
 F.feature_titles (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value)))=
 F.feature_titles (world_features value).
Proof.
 intros. unfold TitleRuntime.configure.
 destruct (negb (N.eqb revision (F.title_revision (F.feature_title_settings (world_features value)))));
 reflexivity.
Qed.

Theorem current_title_configuration_writes_settings :
 forall value revision task_prompt agent_prompt agent_profile,
 revision = F.title_revision (F.feature_title_settings (world_features value)) ->
 exists updated_revision,
 F.feature_title_settings (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value))) =
 F.TitleSettings updated_revision task_prompt agent_prompt agent_profile /\
 updated_revision <> revision /\
 decision_effects (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value) = [].
Proof.
 intros value revision task_prompt agent_prompt agent_profile Revision.
 unfold TitleRuntime.configure.
 rewrite Revision, N.eqb_refl.
 eexists. repeat split; try reflexivity. apply N.neq_succ_diag_l.
Qed.

Theorem conflicting_title_configuration_keeps_the_complete_world :
 forall value revision task_prompt agent_prompt agent_profile,
 revision <> F.title_revision (F.feature_title_settings (world_features value)) ->
 decision_world (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value) = value /\
 decision_effects (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value) = [].
Proof.
 intros value revision task_prompt agent_prompt agent_profile Different.
 unfold TitleRuntime.configure.
 apply N.eqb_neq in Different. rewrite Different. split; reflexivity.
Qed.

Theorem title_configuration_keeps_execution_state :
 forall value revision task_prompt agent_prompt agent_profile,
 execution_core (decision_world (TitleRuntime.configure revision task_prompt agent_prompt agent_profile value)) =
 execution_core value.
Proof.
 intros. unfold TitleRuntime.configure.
 destruct (negb (N.eqb revision (F.title_revision (F.feature_title_settings (world_features value)))));
   reflexivity.
Qed.

Theorem title_recovery_keeps_execution_state : forall value,
 execution_core (TitleRuntime.recover value) = execution_core value.
Proof. intros; reflexivity. Qed.

Theorem title_recovery_keeps_saved_instructions : forall value,
 F.feature_title_settings (world_features (TitleRuntime.recover value)) =
 F.feature_title_settings (world_features value).
Proof. intros; reflexivity. Qed.
