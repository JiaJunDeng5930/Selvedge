From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Features Require Import Domain State TitleRuntime FeatureScopeProofs.
Import ListNotations.
Open Scope list_scope.
Module F:=Selvedge.Features.Domain.

Definition execution_core (value : world) :=
 (world_sequence value, world_tasks value, world_next_ticket value,
  world_environment value, world_projects value).
(** A delayed completion does not rename the current request. *)
Theorem stale_title_is_ignored : forall value id ticket expected selected prompt ok text,
 TitleRuntime.entry id value = Some (F.TitleEntry id (F.TitlePending expected selected prompt)) ->
 ticket <> expected ->
 decision_world (TitleRuntime.complete id ticket ok text value) = value /\
 decision_effects (TitleRuntime.complete id ticket ok text value) = [].
Proof.
 intros value id ticket expected selected prompt ok text found different.
 unfold TitleRuntime.complete. rewrite found. simpl.
 apply N.eqb_neq in different. rewrite different. split;reflexivity.
Qed.
Theorem pending_request_is_frozen : forall value id task result item,
 decision_world result = value -> TitleRuntime.entry id value = Some item ->
 TitleRuntime.start id task result = result.
Proof. intros. unfold TitleRuntime.start. rewrite H,H0. reflexivity. Qed.

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
 TitleRuntime.start id task result =
 Decision (TitleRuntime.store id (F.TitlePending (world_next_ticket before) selected prompt)
   (with_ticket (N.succ (world_next_ticket before)) before))
   (decision_reply result) (decision_effects result ++ [SuggestTitle id (world_next_ticket before) selected prompt]).
Proof.
 intros id task result selected Found Absent Accepts Nonblank Chosen.
 pose proof (title_scope_from_current_task id task (decision_world result) selected
   Found Absent Accepts Nonblank Chosen) as Scope.
 cbv zeta. unfold TitleRuntime.start. rewrite Absent,Accepts,Nonblank,Chosen.
 unfold TicketedRequest.Scoped.feature_run,TicketedRequest.Scoped.feature_with_reply,TicketedRequest.Scoped.feature.
 destruct (Bool.bool_dec _ true) as [Admitted|Refused]; [reflexivity|].
 exfalso; apply Refused; exact Scope.
Qed.

(** This is the actual emitted request. The selected profile and the single
    computed prompt are frozen in the pending entry by the same transition. *)
Theorem admitted_title_emits_frozen_request : forall id task result selected,
 find_task id (decision_world result)=Some task ->
 TitleRuntime.entry id (decision_world result)=None ->
 TitleRuntime.accepts task=true ->
 Selvedge.Foundation.Utf8.nonblank (TitleRuntime.first_request (task_history task))=true ->
 TitleRuntime.selected_profile task (decision_world result)=Some selected ->
 decision_effects (TitleRuntime.start id task result)=decision_effects result ++
 [SuggestTitle id (world_next_ticket (decision_world result)) selected
   (TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features (decision_world result))))
     (TitleRuntime.first_request (task_history task)))].
Proof. intros. rewrite title_start_with_observed_owner with (selected:=selected) by assumption. reflexivity. Qed.

Lemma stored_title_is_observed : forall id state value,
 TitleRuntime.entry id (TitleRuntime.store id state value)=Some (F.TitleEntry id state).
Proof.
 intros id state [seq tasks ticket env projects features]. destruct features.
 unfold TitleRuntime.entry,TitleRuntime.store. cbn. now rewrite N.eqb_refl.
Qed.

Local Lemma title_lookup_skips_another_owner : forall entries owner removed,
 owner <> removed ->
 find (fun item => N.eqb owner (F.title_task item))
   (filter (fun item => negb (N.eqb removed (F.title_task item))) entries) =
 find (fun item => N.eqb owner (F.title_task item)) entries.
Proof.
 induction entries as [|item rest IH]; intros owner removed Different; [reflexivity|].
 cbn [filter find]. destruct (N.eqb removed (F.title_task item)) eqn:Removed.
 - cbn. assert (N.eqb owner (F.title_task item) = false) as Other.
   { apply N.eqb_neq. apply N.eqb_eq in Removed. congruence. }
   rewrite Other. apply IH; exact Different.
 - cbn [negb find]. destruct (N.eqb owner (F.title_task item)); [reflexivity|].
   apply IH; exact Different.
Qed.

Theorem storing_title_keeps_other_generations : forall owner id state value,
 owner <> id ->
 TitleRuntime.entry owner (TitleRuntime.store id state value) = TitleRuntime.entry owner value.
Proof.
 intros owner id state [seq tasks ticket env projects features] Different. destruct features.
 unfold TitleRuntime.entry, TitleRuntime.store. cbn.
 apply N.eqb_neq in Different. rewrite Different.
 apply title_lookup_skips_another_owner. now apply N.eqb_neq.
Qed.

(** Admission freezes the same prompt/profile as the external request. Neither
    settings changes nor a later model completion may select a new request. *)
Theorem admitted_title_stores_frozen_request : forall id task result selected,
 find_task id (decision_world result)=Some task ->
 TitleRuntime.entry id (decision_world result)=None ->
 TitleRuntime.accepts task=true ->
 Selvedge.Foundation.Utf8.nonblank (TitleRuntime.first_request (task_history task))=true ->
 TitleRuntime.selected_profile task (decision_world result)=Some selected ->
 let original:=decision_world result in
 let updated:=decision_world (TitleRuntime.start id task result) in
 TitleRuntime.entry id updated=Some (F.TitleEntry id
   (F.TitlePending (world_next_ticket original) selected
     (TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features original)))
       (TitleRuntime.first_request (task_history task))))) /\
 world_next_ticket updated=N.succ (world_next_ticket original) /\
 world_tasks updated=world_tasks original.
Proof.
 intros id task result selected Found absent eligible nonblank chosen.
 cbv zeta. rewrite title_start_with_observed_owner with (selected:=selected) by assumption.
 cbn [decision_world].
 split; [apply stored_title_is_observed|]. split; reflexivity.
Qed.

Theorem current_title_completion_commits_normalized_name : forall value id ticket selected prompt text,
 TitleRuntime.entry id value=Some (F.TitleEntry id (F.TitlePending ticket selected prompt)) ->
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
 (match status with F.TitlePending _ _ _ => False | _ => True end) ->
 decision_world (TitleRuntime.complete id ticket ok text value) = value /\
 decision_effects (TitleRuntime.complete id ticket ok text value) = [].
Proof.
 intros value id status ticket ok text Found Terminal.
 unfold TitleRuntime.complete. rewrite Found.
 destruct status; cbn in Terminal |- *; [contradiction|split; reflexivity|split; reflexivity].
Qed.

Theorem title_completion_keeps_other_generations : forall value owner id ticket ok text,
 owner <> id ->
 TitleRuntime.entry owner (decision_world (TitleRuntime.complete id ticket ok text value)) =
 TitleRuntime.entry owner value.
Proof.
 intros value owner id ticket ok text Different. unfold TitleRuntime.complete.
 destruct (TitleRuntime.entry id value) as [[stored status]|]; [|reflexivity].
 destruct status as [expected selected prompt|title|reason]; [|reflexivity|reflexivity].
 cbn [F.title_value]. destruct (N.eqb ticket expected); [|reflexivity].
 destruct (ok && negb (String.eqb (Titles.normalize text) ""));
   apply storing_title_keeps_other_generations; exact Different.
Qed.

Theorem title_completion_keeps_execution_state : forall value id ticket ok text,
 execution_core (decision_world (TitleRuntime.complete id ticket ok text value)) = execution_core value.
Proof.
 intros value id ticket ok text. unfold TitleRuntime.complete.
 destruct (TitleRuntime.entry id value) as [[owner status]|]; [|reflexivity].
 destruct status as [expected selected prompt|title|reason]; [|reflexivity|reflexivity].
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
 destruct status as [expected selected prompt|title|reason]; [|reflexivity|reflexivity].
 cbn [F.title_value]. destruct (N.eqb ticket expected); [|reflexivity].
 destruct (ok && negb (String.eqb (Titles.normalize text) "")); reflexivity.
Qed.

Theorem title_recovery_keeps_saved_instructions : forall value,
 F.feature_title_settings (world_features (TitleRuntime.recover value)) =
 F.feature_title_settings (world_features value).
Proof. intros; reflexivity. Qed.
