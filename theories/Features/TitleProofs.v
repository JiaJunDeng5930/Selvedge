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
Theorem pending_request_is_frozen : forall value id result item,
 decision_world result = value -> TitleRuntime.entry id value = Some item ->
 TitleRuntime.start id result = result.
Proof.
 intros value id result item World Found; unfold TitleRuntime.start.
 rewrite World, (a_pending_title_is_not_resolved_again id value item Found); reflexivity.
Qed.

(** The public title start is justified by the task actually observed at its
    owner, rather than an unrelated task supplied alongside the identity. *)
Theorem title_start_with_observed_owner : forall id task result selected,
 find_task id (decision_world result) = Some task ->
 TitleRuntime.entry id (decision_world result) = None ->
 TitleRuntime.accepts task = true ->
 Selvedge.Foundation.Utf8.nonblank (TitleRuntime.first_request (task_history task)) = true ->
 TitleRuntime.selected_profile task (decision_world result) = Some selected ->
 let before := decision_world result in
 let prompt := TitleRuntime.prompt (F.title_agent_instructions (F.feature_title_settings (world_features before)))
   (TitleRuntime.first_request (task_history task)) in
 decision_effects (TitleRuntime.start id result) =
   decision_effects result ++ [RequestFeature (RequestTypes.Packet
     (RequestTypes.release (TitleRuntime.protocol (world_features before) id))
     (RequestEnvelope.Envelope (world_next_ticket before) (selected,prompt)))].
Proof.
 intros id task result selected Found Absent Accepts Nonblank Chosen.
 destruct (admitted_title_resolves_without_rechecking id task (decision_world result) selected
   Found Absent Accepts Nonblank Chosen) as [request [Resolved [Owner [Current Selected]]]].
 cbv zeta; unfold TitleRuntime.start; rewrite Resolved.
 change (decision_effects result ++ [RequestFeature (RequestTypes.Packet
   (RequestTypes.release (TitleRuntime.protocol (world_features (decision_world result))
     (TaskScope.owner (FeatureRequestAdmission.title_reference request))))
   (RequestEnvelope.Envelope (world_next_ticket (decision_world result))
     (FeatureRequestAdmission.title_profile request,
      FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) (decision_world result))))] =
   decision_effects result ++ [RequestFeature (RequestTypes.Packet
     (RequestTypes.release (TitleRuntime.protocol (world_features (decision_world result)) id))
     (RequestEnvelope.Envelope (world_next_ticket (decision_world result))
       (selected,FeatureRequestAdmission.title_prompt task (decision_world result))))]).
 rewrite Owner,Current,Selected; reflexivity.
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
Theorem title_configuration_preserves_generation_entries : forall value revision task_prompt agent_prompt,
 F.feature_titles (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value)))=
 F.feature_titles (world_features value).
Proof.
 intros. unfold TitleRuntime.configure.
 destruct (negb (N.eqb revision (F.title_revision (F.feature_title_settings (world_features value)))));
 reflexivity.
Qed.

Theorem current_title_configuration_writes_both_instructions :
 forall value revision task_prompt agent_prompt,
 revision = F.title_revision (F.feature_title_settings (world_features value)) ->
 F.feature_title_settings (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value))) =
 F.TitleSettings (N.succ revision) task_prompt agent_prompt /\
 decision_effects (TitleRuntime.configure revision task_prompt agent_prompt value) = [].
Proof.
 intros value revision task_prompt agent_prompt Revision.
 unfold TitleRuntime.configure.
 rewrite Revision, N.eqb_refl. split; reflexivity.
Qed.

Theorem conflicting_title_configuration_keeps_the_complete_world :
 forall value revision task_prompt agent_prompt,
 revision <> F.title_revision (F.feature_title_settings (world_features value)) ->
 decision_world (TitleRuntime.configure revision task_prompt agent_prompt value) = value /\
 decision_effects (TitleRuntime.configure revision task_prompt agent_prompt value) = [].
Proof.
 intros value revision task_prompt agent_prompt Different.
 unfold TitleRuntime.configure.
 apply N.eqb_neq in Different. rewrite Different. split; reflexivity.
Qed.

Theorem title_configuration_keeps_execution_state :
 forall value revision task_prompt agent_prompt,
 execution_core (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value)) =
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
