From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State TicketedRequest FeatureRequestProofs.
From Selvedge.Features Require Import TitleRuntime Board Chatgpt Compaction.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.

Theorem title_start_installs_its_frozen_request : forall id task result selected,
 TitleRuntime.entry id (decision_world result)=None ->
 TitleRuntime.accepts task=true ->
 Selvedge.Foundation.Utf8.nonblank (TitleRuntime.first_request (task_history task))=true ->
 TitleRuntime.selected_profile task (decision_world result)=Some selected ->
 receiver_installed
  (SuggestTitle id (world_next_ticket (decision_world result)) selected
   (TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features (decision_world result))))
    (TitleRuntime.first_request (task_history task))))
  (decision_world (TitleRuntime.start id task result)).
Proof.
 intros id task result selected Absent Eligible Nonblank Selected.
 unfold TitleRuntime.start. rewrite Absent,Eligible,Nonblank,Selected.
 apply put_title_installs.
Qed.

Theorem board_requests_install_their_receiver : forall id card profile retitle before emitted,
 In emitted (decision_effects (Board.request_text id card profile retitle before)) ->
 receiver_installed emitted (decision_world (Board.request_text id card profile retitle before)).
Proof.
 intros id card profile retitle before emitted Member. unfold Board.request_text in *.
 destruct (Tasks.find_profile _ _) as [selected|]; [|contradiction].
 destruct (negb (TitleRuntime.ordinary selected)); [contradiction|].
 apply every_responded_feature_request_has_its_installed_receiver; exact Member.
Qed.

Theorem connection_requests_install_their_receiver : forall connection project request arguments granted target before emitted,
 In emitted (decision_effects (Chatgpt.start connection project request arguments granted target before)) ->
 receiver_installed emitted (decision_world (Chatgpt.start connection project request arguments granted target before)).
Proof.
 intros connection project request arguments granted target before emitted Member.
 unfold Chatgpt.start in *.
 destruct (Chatgpt.retry _ _ _) as [[identity job]|];
 repeat match goal with
 | H : context [if ?condition then _ else _] |- _ => destruct condition eqn:? end;
 try contradiction.
 apply every_resolved_feature_request_has_its_installed_receiver; exact Member.
Qed.

Theorem scope_requests_install_their_receiver : forall id input purpose entry before emitted,
 In emitted (decision_effects (Compaction.begin_scope id input purpose entry before)) ->
 receiver_installed emitted (decision_world (Compaction.begin_scope id input purpose entry before)).
Proof. intros; apply every_resolved_feature_request_has_its_installed_receiver; exact H. Qed.

Theorem compact_requests_install_their_receiver : forall id task input purpose target progress scope entry before emitted,
 In emitted (decision_effects (Compaction.dispatch_compact id task input purpose target progress scope entry before)) ->
 receiver_installed emitted (decision_world (Compaction.dispatch_compact id task input purpose target progress scope entry before)).
Proof.
 intros id task input purpose target progress scope entry before emitted Member.
 unfold Compaction.dispatch_compact in *.
 destruct (CompactionPlan.fit_transport _ _) as [fitted|]; [|contradiction].
 destruct (_ && _)%bool; [|contradiction].
 apply every_resolved_feature_request_has_its_installed_receiver; exact Member.
Qed.

Lemma portable_requests_install_their_receiver : forall id task scope entry before emitted,
 In emitted (decision_effects (Compaction.force_portable id task scope entry before)) ->
 receiver_installed emitted (decision_world (Compaction.force_portable id task scope entry before)).
Proof.
 intros id task scope entry before emitted Member. unfold Compaction.force_portable in *.
 destruct (Compaction.configured_target _ _) as [target|]; [|contradiction].
 unfold Compaction.with_measurement in *; unfold set in *; cbn in *.
 destruct (Selvedge.Features.CompactionTypes.entry_job entry);
 try contradiction;
 repeat match goal with
 | H : context [if ?condition then _ else _] |- _ => destruct condition eqn:? end;
 try contradiction;
 unfold Compaction.start in *;
 destruct (CompactionPlan.start_with_images _ _ _ _ _ _ _ _) as [progress|]; try contradiction;
 eapply compact_requests_install_their_receiver; exact Member.
Qed.

Theorem measurement_requests_install_their_receiver : forall id task input scope purpose candidate entry before emitted,
 In emitted (decision_effects (Compaction.measured_call id task input scope purpose candidate entry before)) ->
 receiver_installed emitted (decision_world (Compaction.measured_call id task input scope purpose candidate entry before)).
Proof.
 intros id task input scope purpose candidate entry before emitted Member.
 unfold Compaction.measured_call in *.
 destruct (N.leb _ _).
 - apply every_resolved_feature_request_has_its_installed_receiver; exact Member.
 - eapply portable_requests_install_their_receiver; exact Member.
Qed.
