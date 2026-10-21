From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Tasks.
From Selvedge.Features Require Import Domain Board Titles TitleRuntime.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Theorem stale_card_is_atomic : forall id expected value card run,
 Board.lookup id value = Some card -> expected <> F.card_revision card ->
 Board.with_card id expected value run =
 reject "card_conflict"%string "The card changed in another view or during execution. Refresh its current values before applying this edit."%string value.
Proof.
 intros id expected value card run found different.
 unfold Board.with_card. rewrite found. apply N.eqb_neq in different. rewrite different. reflexivity.
Qed.

(** Wiring to the shared drafting policy does not depend on linkage. Profile
    admission and the actual positive request are established separately. *)
Lemma idle_regeneration_uses_drafting_policy : forall id value card profile now observed,
 Board.lookup id value=Some card ->
 Board.clock observed=Some now -> Board.mutable card value=true ->
 Board.regenerate id (F.card_revision card) observed profile value=
   Board.request_text id card profile true value.
Proof.
 intros id value card profile now observed found clock idle.
 unfold Board.regenerate,Board.at_clock. rewrite clock.
 unfold Board.with_card. rewrite found,N.eqb_refl,idle. reflexivity.
Qed.

(** An existing ordinary endpoint and a current editable card suffice to emit
    the real request. The effect freezes identity, lease, profile, prompt and
    draft; model success or request acceptance is not assumed. *)
Theorem admitted_regeneration_emits_frozen_request : forall id revision value card profile_name selected now observed,
 Board.lookup id value=Some card -> revision=F.card_revision card ->
 Board.clock observed=Some now -> BoardFacts.mutable card value=true ->
 Tasks.find_profile
   (if String.eqb profile_name "" then F.board_draft_profile (Board.registry value) else profile_name)
   (environment_profiles (world_environment value))=Some selected ->
 TitleRuntime.ordinary selected=true ->
 decision_effects (Board.regenerate id revision observed profile_name value)=
 [SuggestCard id (world_next_ticket value) (F.card_revision card) selected
   (Titles.board_prompt (F.title_task_prompt (F.feature_title_settings (world_features value)))
     (F.draft_title (F.card_contents card)) (F.draft_description (F.card_contents card)) true)
   (F.card_contents card) true].
Proof.
 intros id revision value card profile_name selected now observed found current clock editable available ordinary.
 subst revision. rewrite idle_regeneration_uses_drafting_policy with (card:=card) (now:=now);
 [|exact found|exact clock|exact editable].
 unfold Board.request_text. rewrite available,ordinary. reflexivity.
Qed.

(** A title result retains the linked Task identifier in the saved card. *)
Theorem card_title_result_preserves_conversation : forall value card ok title description reason,
 F.card_task (Board.suggestion ok true title description reason card value)=F.card_task card.
Proof. reflexivity. Qed.

(** The same card store used by completion cannot overwrite conversations or
    their independent generated-name registry. *)
Theorem saving_card_preserves_conversations_and_their_titles : forall id card value,
 world_tasks (Board.put id card value)=world_tasks value /\
 F.feature_titles (world_features (Board.put id card value))=F.feature_titles (world_features value).
Proof. intros. split; reflexivity. Qed.
(** Once linked, edits cannot change the execution request, even when idle. *)
Theorem linked_execution_inputs_are_immutable : forall id expected value card target observed input,
 Board.lookup id value = Some card -> F.card_task card = Some target ->
 Board.changes_execution input = true ->
 decision_world (Board.update_card id expected observed input value) = value.
Proof.
 intros id expected value card target observed input found linked changed.
 unfold Board.update_card, Board.at_clock. destruct (Board.clock observed); [|reflexivity].
 unfold Board.with_card. rewrite found. destruct (N.eqb expected (F.card_revision card)); [|reflexivity].
 destruct (Board.parse_patch input (F.card_contents card)); [|reflexivity].
 unfold Board.unlinked, BoardFacts.unlinked. rewrite linked, changed. simpl.
 rewrite Bool.andb_false_r. reflexivity.
Qed.

(** Stopping suppresses the next model turn; committed asynchronous work
    still owns its Board concurrency slot until its callbacks settle. *)
Theorem stopped_operation_keeps_card_locked : forall card value task phase first rest,
 BoardFacts.linked_task card value=Some task ->
 Selvedge.Kernel.Domain.task_lifecycle task=Selvedge.Kernel.Domain.Stopped phase (first::rest) ->
 BoardFacts.mutable card value=false /\ BoardFacts.runnable card value=false.
Proof.
 intros card value task phase first rest linked stopped.
 assert (busy:BoardFacts.busy card value=true).
 { unfold BoardFacts.busy. rewrite linked. unfold BoardFacts.busy_task, Selvedge.Kernel.Domain.task_busy, Selvedge.Kernel.Domain.task_activity, Selvedge.Kernel.Domain.task_operations. rewrite stopped. apply Bool.orb_true_r. }
 assert (locked:BoardFacts.mutable card value=false).
 { unfold BoardFacts.mutable. rewrite busy. repeat rewrite Bool.orb_true_r. reflexivity. }
 split; [exact locked|]. unfold BoardFacts.runnable. now rewrite locked.
Qed.
