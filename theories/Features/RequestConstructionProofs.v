From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State TicketedRequest FeatureRequestProofs.
From Selvedge.Features Require Import TitleRuntime TitleProofs Board Chatgpt Compaction.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.

Theorem title_start_installs_its_frozen_request : forall id task result selected,
 find_task id (decision_world result)=Some task ->
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
 intros id task result selected Found Absent Eligible Nonblank Selected.
 rewrite title_start_with_observed_owner with (selected:=selected) by assumption.
 cbn [decision_world].
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
 apply every_responded_feature_request_has_its_installed_receiver; exact Member.
Qed.

(* A maintenance operation either has its observed provider input, or first
   installs a task-context observation. Both effects have an exact receiver. *)
Definition maintenance_receiver_installed (emitted : effect) (after : world) :=
 match emitted with
 | ObserveContext owner ticket snapshot =>
   find_task owner after = Some
     (with_activity (ObservingContext ticket (List.length (task_history snapshot))) snapshot) /\
   exists entry purpose,
     S.compaction_entry owner after = Some entry /\
     Selvedge.Features.CompactionTypes.entry_job entry =
       Selvedge.Features.CompactionTypes.AwaitingContext ticket purpose
         (match task_activity snapshot with ReadyForModel => true | _ => false end)
 | _ => receiver_installed emitted after end.

Lemma feature_receivers_are_maintenance_receivers : forall emitted after,
 receiver_installed emitted after -> maintenance_receiver_installed emitted after.
Proof. intros; destruct emitted; cbn in *; try contradiction; assumption. Qed.

Lemma maintenance_observation_installs_its_receiver : forall before
 (request : S.maintenance_context_plan before) emitted,
 In emitted (decision_effects (S.maintenance_observe request)) ->
 maintenance_receiver_installed emitted (decision_world (S.maintenance_observe request)).
Proof.
 intros before request emitted Member.
 destruct (maintenance_context_installs_the_exact_shared_ticket before request)
   as [Task [[entry [Found Job]] Effects]].
 rewrite Effects in Member; destruct Member as [<-|[]].
 cbn [maintenance_receiver_installed]. split; [exact Task|].
 exists entry, (S.maintenance_context_purpose request); split; assumption.
Qed.

Lemma waiting_for_context_installs_every_emitted_receiver : forall id purpose entry before emitted,
 In emitted (decision_effects (Compaction.wait_for_context id purpose entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.wait_for_context id purpose entry before)).
Proof.
 intros id purpose entry before emitted Member; unfold Compaction.wait_for_context in *.
 destruct (find_task id before) as [current|]; [|contradiction].
 destruct (S.maintenance_context id purpose entry before) as [request|]; [|contradiction].
 eapply maintenance_observation_installs_its_receiver; exact Member.
Qed.

Theorem maintenance_requests_install_every_emitted_receiver : forall id request before emitted,
 In emitted (decision_effects (Compaction.run_request id request before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.run_request id request before)).
Proof.
 intros id request before emitted Member; unfold Compaction.run_request in *.
 destruct (S.feature (S.MaintainRequest id request) before) as [admitted|].
 - apply feature_receivers_are_maintenance_receivers.
   eapply every_feature_request_has_its_installed_receiver; exact Member.
 - destruct request; eapply waiting_for_context_installs_every_emitted_receiver; exact Member.
Qed.

Theorem scope_requests_install_their_receiver : forall id input purpose entry before emitted,
 In emitted (decision_effects (Compaction.begin_scope id input purpose entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.begin_scope id input purpose entry before)).
Proof. intros; eapply maintenance_requests_install_every_emitted_receiver; exact H. Qed.

Theorem compact_requests_install_their_receiver : forall id task input purpose target progress scope entry before emitted,
 In emitted (decision_effects (Compaction.dispatch_compact id task input purpose target progress scope entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.dispatch_compact id task input purpose target progress scope entry before)).
Proof.
 intros id task input purpose target progress scope entry before emitted Member.
 unfold Compaction.dispatch_compact in *.
 destruct (CompactionPlan.fit_transport _ _) as [fitted|]; [|contradiction].
 destruct (_ && _)%bool; [|contradiction].
 eapply maintenance_requests_install_every_emitted_receiver; exact Member.
Qed.

Lemma portable_requests_install_their_receiver : forall id task scope entry before emitted,
 In emitted (decision_effects (Compaction.force_portable id task scope entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.force_portable id task scope entry before)).
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

Lemma oversized_candidates_install_every_emitted_receiver :
 forall id task scope candidate entry reason before emitted,
 In emitted (decision_effects (Compaction.oversized_candidate id task scope candidate entry reason before)) ->
 maintenance_receiver_installed emitted
   (decision_world (Compaction.oversized_candidate id task scope candidate entry reason before)).
Proof.
 intros id task scope candidate entry reason before emitted Member.
 unfold Compaction.oversized_candidate in *.
 destruct candidate as [candidate|]; [destruct candidate|]; try contradiction;
   eapply portable_requests_install_their_receiver; exact Member.
Qed.

Theorem measurement_requests_install_their_receiver : forall id task input scope purpose candidate entry before emitted,
 In emitted (decision_effects (Compaction.measured_call id task input scope purpose candidate entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.measured_call id task input scope purpose candidate entry before)).
Proof.
 intros id task input scope purpose candidate entry before emitted Member.
 unfold Compaction.measured_call in *.
 destruct (N.leb _ _).
 - eapply maintenance_requests_install_every_emitted_receiver; exact Member.
 - eapply oversized_candidates_install_every_emitted_receiver; exact Member.
Qed.

Theorem validation_requests_install_their_receiver : forall id task input purpose candidate entry before emitted,
 In emitted (decision_effects (Compaction.begin_validation id task input purpose candidate entry before)) ->
 maintenance_receiver_installed emitted (decision_world (Compaction.begin_validation id task input purpose candidate entry before)).
Proof.
 intros id task input purpose candidate entry before emitted Member.
 unfold Compaction.begin_validation in *.
 destruct (Compaction.relevant input task before); [|contradiction].
 eapply maintenance_requests_install_every_emitted_receiver; exact Member.
Qed.

Theorem validation_completion_requests_install_their_receiver :
 forall id task input purpose candidate preview scope tokens budget entry before emitted,
 In emitted (decision_effects
   (Compaction.finish_validation id task input purpose candidate preview scope tokens budget entry before)) ->
 maintenance_receiver_installed emitted (decision_world
   (Compaction.finish_validation id task input purpose candidate preview scope tokens budget entry before)).
Proof.
 intros id task input purpose candidate preview scope tokens budget entry before emitted Member.
 unfold Compaction.finish_validation in *.
 destruct (Compaction.relevant input task before && ContextSelection.consumes candidate scope)%bool;
   [|contradiction].
 destruct (Compaction.same_history preview
   (ContextSelection.adopt (CompactionTypes.captured_history input) candidate (task_history task))).
 - destruct (_ && _)%bool; [contradiction|].
   eapply oversized_candidates_install_every_emitted_receiver; exact Member.
 - eapply validation_requests_install_their_receiver; exact Member.
Qed.
