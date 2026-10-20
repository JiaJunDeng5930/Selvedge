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
