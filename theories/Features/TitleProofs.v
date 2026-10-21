From Stdlib Require Import String List NArith.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Features Require Import Domain State TitleRuntime.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
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

(** This is the actual emitted request. The selected profile and the single
    computed prompt are frozen in the pending entry by the same transition. *)
Theorem admitted_title_emits_frozen_request : forall id task result selected,
 TitleRuntime.entry id (decision_world result)=None ->
 TitleRuntime.accepts task=true ->
 Selvedge.Foundation.Utf8.nonblank (TitleRuntime.first_request (task_history task))=true ->
 TitleRuntime.selected_profile task (decision_world result)=Some selected ->
 decision_effects (TitleRuntime.start id task result)=decision_effects result ++
 [SuggestTitle id (world_next_ticket (decision_world result)) selected
   (TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features (decision_world result))))
     (TitleRuntime.first_request (task_history task)))].
Proof. intros. unfold TitleRuntime.start. rewrite H,H0,H1,H2. reflexivity. Qed.

Lemma stored_title_is_observed : forall id state value,
 TitleRuntime.entry id (TitleRuntime.store id state value)=Some (F.TitleEntry id state).
Proof.
 intros id state [seq tasks ticket env projects features]. destruct features.
 unfold TitleRuntime.entry,TitleRuntime.store. cbn. now rewrite N.eqb_refl.
Qed.

(** Admission freezes the same prompt/profile as the external request. Neither
    settings changes nor a later model completion may select a new request. *)
Theorem admitted_title_stores_frozen_request : forall id task result selected,
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
 intros id task result selected absent eligible nonblank chosen.
 cbv zeta. unfold TitleRuntime.start. rewrite absent,eligible,nonblank,chosen.
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
