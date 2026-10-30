From Selvedge.Foundation Require Import KeyedListProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain State FeatureAdmissionProofs.
From Selvedge.Features Require Import Domain State TitleRuntime.
Import ListNotations.
Open Scope list_scope.
Module F:=Selvedge.Features.Domain.

Definition execution_core (value : world) :=
 (world_sequence value, world_tasks value, world_next_ticket value,
  world_environment value, world_projects value).
(** A delayed completion does not rename the current request. *)
Theorem stale_title_is_ignored : forall value id ticket expected selected prompt ok text,
 TitleRuntime.entry id value = Some (F.TitleEntry id (F.TitlePending (RequestEnvelope.Envelope expected (selected, prompt)))) ->
 ticket <> expected ->
 decision_world (TitleRuntime.complete id ticket ok text value) = value /\
 decision_effects (TitleRuntime.complete id ticket ok text value) = [].
Proof.
 intros value id ticket expected selected prompt ok text found different.
 unfold TitleRuntime.complete. rewrite found. simpl.
 apply N.eqb_neq in different. rewrite different. split;reflexivity.
Qed.
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
 let prompt := TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features before)))
   (TitleRuntime.first_request (task_history task)) in
 TitleRuntime.start id result =
 Decision (TitleRuntime.store id (F.TitlePending (RequestEnvelope.Envelope (world_next_ticket before) (selected, prompt)))
   (with_ticket (N.succ (world_next_ticket before)) before))
   (decision_reply result) (decision_effects result ++ [RequestFeature (RequestTypes.Packet (TicketedRequest.Scoped.title_protocol id) (RequestEnvelope.Envelope (world_next_ticket before) (selected, prompt)))]).
Proof.
 intros id task result selected Found Absent Accepts Nonblank Chosen.
 destruct (admitted_title_resolves_without_rechecking id task (decision_world result) selected
   Found Absent Accepts Nonblank Chosen) as [request [Resolved [Owner [Current Selected]]]].
 cbv zeta; unfold TitleRuntime.start; rewrite Resolved.
 change (Decision
   (TitleRuntime.store (TaskScope.owner (FeatureRequestAdmission.title_reference request))
     (F.TitlePending (RequestEnvelope.Envelope (world_next_ticket (decision_world result)) ((FeatureRequestAdmission.title_profile request), (FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) (decision_world result)))))
     (with_ticket (N.succ (world_next_ticket (decision_world result))) (decision_world result)))
   (decision_reply result)
   (decision_effects result ++ [RequestFeature (RequestTypes.Packet (TicketedRequest.Scoped.title_protocol (TaskScope.owner (FeatureRequestAdmission.title_reference request))) (RequestEnvelope.Envelope (world_next_ticket (decision_world result)) ((FeatureRequestAdmission.title_profile request), (FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) (decision_world result)))))]) =
   Decision (TitleRuntime.store id
     (F.TitlePending (RequestEnvelope.Envelope (world_next_ticket (decision_world result)) (selected, (FeatureRequestAdmission.title_prompt task (decision_world result)))))
     (with_ticket (N.succ (world_next_ticket (decision_world result))) (decision_world result)))
   (decision_reply result) (decision_effects result ++ [RequestFeature (RequestTypes.Packet (TicketedRequest.Scoped.title_protocol id) (RequestEnvelope.Envelope (world_next_ticket (decision_world result)) (selected, (FeatureRequestAdmission.title_prompt task (decision_world result)))))])).
 rewrite Owner,Current,Selected; reflexivity.
Qed.

Lemma stored_title_is_observed : forall id state value,
 TitleRuntime.entry id (TitleRuntime.store id state value)=Some (F.TitleEntry id state).
Proof.
 intros id state [seq tasks ticket env projects features]. destruct features.
 unfold TitleRuntime.entry,FeatureRequestAdmission.title_entry,TitleRuntime.store. cbn. now rewrite N.eqb_refl.
Qed.



Theorem storing_title_keeps_other_generations : forall owner id state value,
 owner <> id ->
 TitleRuntime.entry owner (TitleRuntime.store id state value) = TitleRuntime.entry owner value.
Proof.
 intros owner id state [seq tasks ticket env projects features] Different. destruct features.
 unfold TitleRuntime.entry, FeatureRequestAdmission.title_entry, TitleRuntime.store. cbn.
 apply N.eqb_neq in Different. rewrite Different.
 apply filtering_another_key_preserves_lookup.
 - intros; now apply N.eqb_eq.
 - now apply N.eqb_neq.
Qed.

Theorem current_title_completion_commits_normalized_name : forall value id ticket selected prompt text,
 TitleRuntime.entry id value=Some (F.TitleEntry id (F.TitlePending (RequestEnvelope.Envelope ticket (selected, prompt)))) ->
 Selvedge.Features.Titles.normalize text<>""%string ->
 TitleRuntime.entry id (decision_world (TitleRuntime.complete id ticket true text value))=
   Some (F.TitleEntry id (F.Named (Selvedge.Features.Titles.normalize text))).
Proof.
 intros value id ticket selected prompt text pending nonempty.
 unfold TitleRuntime.complete. rewrite pending. cbn. rewrite N.eqb_refl.
 apply String.eqb_neq in nonempty. rewrite nonempty. apply stored_title_is_observed.
Qed.

(** Editing policy affects future generations; already frozen requests and
    saved names remain in the same registry. *)
Theorem title_configuration_preserves_generation_entries : forall value revision task_prompt agent_prompt,
 F.feature_titles (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value)))=
 F.feature_titles (world_features value).
Proof.
 intros. unfold TitleRuntime.configure.
 destruct (negb (Titles.valid_instructions task_prompt && Titles.valid_instructions agent_prompt)); [reflexivity|].
 destruct (negb (N.eqb revision (F.title_revision (F.feature_title_settings (world_features value)))));
 reflexivity.
Qed.

Theorem current_title_configuration_writes_both_instructions :
 forall value revision task_prompt agent_prompt,
 Titles.valid_instructions task_prompt = true ->
 Titles.valid_instructions agent_prompt = true ->
 revision = F.title_revision (F.feature_title_settings (world_features value)) ->
 F.feature_title_settings (world_features
   (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value))) =
 F.TitleSettings (N.succ revision) task_prompt agent_prompt /\
 decision_effects (TitleRuntime.configure revision task_prompt agent_prompt value) = [].
Proof.
 intros value revision task_prompt agent_prompt Task Agent Revision.
 unfold TitleRuntime.configure. rewrite Task, Agent. cbn [andb negb].
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
 destruct (negb (Titles.valid_instructions task_prompt && Titles.valid_instructions agent_prompt));
   [split; reflexivity|].
 apply N.eqb_neq in Different. rewrite Different. split; reflexivity.
Qed.

Theorem title_configuration_keeps_execution_state :
 forall value revision task_prompt agent_prompt,
 execution_core (decision_world (TitleRuntime.configure revision task_prompt agent_prompt value)) =
 execution_core value.
Proof.
 intros. unfold TitleRuntime.configure.
 destruct (negb (Titles.valid_instructions task_prompt && Titles.valid_instructions agent_prompt));
   [reflexivity|].
 destruct (negb (N.eqb revision (F.title_revision (F.feature_title_settings (world_features value)))));
   reflexivity.
Qed.

Theorem terminal_title_completion_is_ignored : forall value id status ticket ok text,
 TitleRuntime.entry id value = Some (F.TitleEntry id status) ->
 (match status with F.TitlePending (RequestEnvelope.Envelope _ (_, _)) => False | _ => True end) ->
 decision_world (TitleRuntime.complete id ticket ok text value) = value /\
 decision_effects (TitleRuntime.complete id ticket ok text value) = [].
Proof.
 intros value id status ticket ok text Found Terminal.
 unfold TitleRuntime.complete. rewrite Found.
 destruct status as [[expected [selected prompt]]|title|reason];
   cbn in Terminal |- *; [contradiction|split; reflexivity|split; reflexivity].
Qed.

Theorem title_completion_keeps_other_generations : forall value owner id ticket ok text,
 owner <> id ->
 TitleRuntime.entry owner (decision_world (TitleRuntime.complete id ticket ok text value)) =
 TitleRuntime.entry owner value.
Proof.
 intros value owner id ticket ok text Different. unfold TitleRuntime.complete.
 destruct (TitleRuntime.entry id value) as [[stored status]|]; [|reflexivity].
 destruct status as [[expected [selected prompt]]|title|reason]; [|reflexivity|reflexivity].
 cbn [F.title_value]. destruct (N.eqb ticket expected); [|reflexivity].
 destruct (ok && negb (String.eqb (Titles.normalize text) ""));
   apply storing_title_keeps_other_generations; exact Different.
Qed.

Theorem title_completion_keeps_execution_state : forall value id ticket ok text,
 execution_core (decision_world (TitleRuntime.complete id ticket ok text value)) = execution_core value.
Proof.
 intros value id ticket ok text. unfold TitleRuntime.complete.
 destruct (TitleRuntime.entry id value) as [[owner status]|]; [|reflexivity].
 destruct status as [[expected [selected prompt]]|title|reason]; [|reflexivity|reflexivity].
 cbn [F.title_value]. destruct (N.eqb ticket expected); [|reflexivity].
 destruct (ok && negb (String.eqb (Titles.normalize text) "")); reflexivity.
Qed.

Theorem title_recovery_keeps_execution_state : forall value,
 execution_core (TitleRuntime.recover value) = execution_core value.
Proof. intros; reflexivity. Qed.

Theorem title_completion_keeps_saved_instructions : forall value id ticket ok text,
 F.feature_title_settings (world_features (decision_world (TitleRuntime.complete id ticket ok text value))) =
 F.feature_title_settings (world_features value).
Proof.
 intros value id ticket ok text. unfold TitleRuntime.complete.
 destruct (TitleRuntime.entry id value) as [[owner status]|]; [|reflexivity].
 destruct status as [[expected [selected prompt]]|title|reason]; [|reflexivity|reflexivity].
 cbn [F.title_value]. destruct (N.eqb ticket expected); [|reflexivity].
 destruct (ok && negb (String.eqb (Titles.normalize text) "")); reflexivity.
Qed.

Theorem title_recovery_keeps_saved_instructions : forall value,
 F.feature_title_settings (world_features (TitleRuntime.recover value)) =
 F.feature_title_settings (world_features value).
Proof. intros; reflexivity. Qed.
