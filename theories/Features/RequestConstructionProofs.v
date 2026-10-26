From Selvedge.Kernel Require CommandResult FeatureRequestAdmission.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State TicketedRequest FeatureRequestProofs FeatureAdmissionProofs DecisionCompositionProofs.
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
  (decision_world (TitleRuntime.start id result)).
Proof.
 intros id task result selected Found Absent Eligible Nonblank Selected.
 rewrite title_start_with_observed_owner with (task:=task) (selected:=selected) by assumption.
 cbn [decision_world].
 apply put_title_installs.
Qed.

Theorem board_requests_install_their_receiver : forall before
 (target : BoardDrafting.drafting_target before) profile emitted,
 In emitted (decision_effects (Board.request_text target profile)) ->
 receiver_installed emitted (decision_world (Board.request_text target profile)).
Proof.
 intros before target profile emitted. unfold Board.request_text,Board.request_text_result.
 apply observe_cases; [intros selected Registered|intros Missing; cbn; contradiction].
 apply require_cases; [intros Ordinary|cbn; contradiction].
 intros Member. eapply every_feature_request_has_its_installed_receiver; exact Member.
Qed.

Theorem connection_requests_install_their_receiver : forall connection project request arguments before emitted,
 In emitted (decision_effects (Chatgpt.run connection project request arguments before)) ->
 receiver_installed emitted (decision_world (Chatgpt.run connection project request arguments before)).
Proof.
 intros connection project request arguments before emitted Member.
 unfold Chatgpt.run,Chatgpt.run_result in *.
 destruct (FeatureRequestAdmission.resolve_connection connection project request arguments before)
   as [[identity job|resolved]|reason]; cbn [CommandResult.map CommandResult.bind
   CommandResult.decide CommandResult.resolve CommandResult.accept CommandResult.reject
   Chatgpt.resolved_connection_change State.accept State.reject decision_effects decision_world] in *;
   try contradiction.
 change (receiver_installed emitted (decision_world
   (TicketedRequest.Scoped.feature_issue (TicketedRequest.Scoped.connection_plan resolved)))).
 apply every_feature_request_has_its_installed_receiver; exact Member.
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
 (request : S.maintenance_context_plan before),
 emissions_satisfy maintenance_receiver_installed (S.maintenance_observe request).
Proof.
 intros before request emitted Member.
 destruct (maintenance_context_installs_the_exact_shared_ticket before request)
   as [Task [[entry [Found Job]] Effects]].
 rewrite Effects in Member; destruct Member as [<-|[]].
 cbn [maintenance_receiver_installed]. split; [exact Task|].
 exists entry, (S.maintenance_context_purpose request); split; assumption.
Qed.

Lemma issued_features_install_maintenance_receivers : forall before (request : S.feature_plan before),
 emissions_satisfy maintenance_receiver_installed (S.feature_issue request).
Proof.
 intros before request emitted Member; apply feature_receivers_are_maintenance_receivers.
 eapply every_feature_request_has_its_installed_receiver; exact Member.
Qed.
Create HintDb maintenance_receivers.
#[local] Hint Resolve maintenance_observation_installs_its_receiver
 issued_features_install_maintenance_receivers : maintenance_receivers.
Local Ltac derive_maintenance_contract :=
 derive_emission_contract ltac:(eauto 2 with maintenance_receivers).

Lemma waiting_for_context_installs_every_emitted_receiver : forall id purpose entry before,
 emissions_satisfy maintenance_receiver_installed (Compaction.wait_for_context id purpose entry before).
Proof. intros id purpose entry before; unfold Compaction.wait_for_context; derive_maintenance_contract. Qed.
#[local] Hint Resolve waiting_for_context_installs_every_emitted_receiver : maintenance_receivers.

Theorem maintenance_requests_install_every_emitted_receiver : forall id request before,
 emissions_satisfy maintenance_receiver_installed (Compaction.run_request id request before).
Proof. intros id request before; unfold Compaction.run_request; derive_maintenance_contract. Qed.
#[local] Hint Resolve maintenance_requests_install_every_emitted_receiver : maintenance_receivers.

Theorem scope_requests_install_their_receiver : forall id input purpose entry before,
 emissions_satisfy maintenance_receiver_installed (Compaction.begin_scope id input purpose entry before).
Proof. intros id input purpose entry before; apply maintenance_requests_install_every_emitted_receiver. Qed.

Theorem compact_requests_install_their_receiver : forall id task input purpose target progress scope entry before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.dispatch_compact id task input purpose target progress scope entry before).
Proof. intros id task input purpose target progress scope entry before; unfold Compaction.dispatch_compact; derive_maintenance_contract. Qed.
#[local] Hint Resolve compact_requests_install_their_receiver : maintenance_receivers.

Lemma starting_compaction_installs_its_receiver : forall id task input purpose target scope tokens entry before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.start id task input purpose target scope tokens entry before).
Proof. intros id task input purpose target scope tokens entry before; unfold Compaction.start; derive_maintenance_contract. Qed.
#[local] Hint Resolve starting_compaction_installs_its_receiver : maintenance_receivers.

Lemma portable_requests_install_their_receiver : forall id task scope entry before,
 emissions_satisfy maintenance_receiver_installed (Compaction.force_portable id task scope entry before).
Proof. intros id task scope entry before; unfold Compaction.force_portable; derive_maintenance_contract. Qed.
#[local] Hint Resolve portable_requests_install_their_receiver : maintenance_receivers.

Lemma oversized_candidates_install_every_emitted_receiver :
 forall id task scope candidate entry reason before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.oversized_candidate id task scope candidate entry reason before).
Proof. intros id task scope candidate entry reason before; unfold Compaction.oversized_candidate; derive_maintenance_contract. Qed.
#[local] Hint Resolve oversized_candidates_install_every_emitted_receiver : maintenance_receivers.

Theorem measurement_requests_install_their_receiver : forall id task input scope purpose candidate entry before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.measured_call id task input scope purpose candidate entry before).
Proof. intros id task input scope purpose candidate entry before; unfold Compaction.measured_call; derive_maintenance_contract. Qed.

Theorem validation_requests_install_their_receiver : forall id task input purpose candidate entry before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.begin_validation id task input purpose candidate entry before).
Proof. intros id task input purpose candidate entry before; unfold Compaction.begin_validation; derive_maintenance_contract. Qed.
#[local] Hint Resolve validation_requests_install_their_receiver : maintenance_receivers.

Theorem validation_completion_requests_install_their_receiver :
 forall id task input purpose candidate preview scope tokens budget entry before,
 emissions_satisfy maintenance_receiver_installed
   (Compaction.finish_validation id task input purpose candidate preview scope tokens budget entry before).
Proof. intros id task input purpose candidate preview scope tokens budget entry before; unfold Compaction.finish_validation; derive_maintenance_contract. Qed.
