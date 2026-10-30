From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs OptionListProofs ReceiverProofs.
From Selvedge.Kernel Require Import Domain State TicketedRequest TaskScopeProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.

(** The common contract follows the receiver constructor, independently of
    which protocol declares it. A new protocol adds no preservation case. *)
Theorem every_feature_request_has_its_installed_receiver : forall before (request : S.feature_plan before),
 match decision_effects (S.feature_issue request) with
 | [RequestFeature sent] =>
   Receiver.lookup (RequestTypes.receiver (RequestTypes.definition sent))
     (world_features (decision_world (S.feature_issue request))) = Some (RequestTypes.request sent)
 | _ => False end.
Proof.
 intros before request.
 unfold S.feature_issue,S.feature_issue_change,CommandResult.accept,allocate_identity,
   S.feature_request,RequestTypes.install; cbn -[Receiver.lookup Receiver.install S.feature_envelope].
 apply ReceiverProofs.installed; exact (S.feature_available request).
Qed.

Theorem feature_requests_preserve_execution_frame : forall before (request : S.feature_plan before),
 let after:=decision_world (S.feature_issue request) in
 world_tasks after=world_tasks before /\ world_projects after=world_projects before /\
 world_environment after=world_environment before /\ world_sequence after=world_sequence before.
Proof.
 intros before request; cbn zeta.
 unfold S.feature_issue,S.feature_issue_change,CommandResult.accept,S.install_feature,allocate_identity.
 destruct (S.channel_space (S.feature_protocol request)); repeat split; reflexivity.
Qed.

Lemma admitted_maintenance_has_a_selected_plan : forall before owner request current
 (Found : find_task owner before = Some current),
 S.maintenance_admission owner request before = true ->
 exists reference, S.maintenance_selected owner request before current Found = Some reference.
Proof.
 intros before owner request current Found Ready.
 unfold S.maintenance_admission,S.maintenance_ready in Ready; rewrite Found in Ready.
 unfold S.maintenance_selected.
 eapply observe_cases; [intros entry Stored|intro Missing].
 - rewrite Stored in Ready; unfold S.maintenance_observed,S.boolean_admission.
   destruct (Bool.bool_dec _ true) as [Eligible|Refused]; [eexists; reflexivity|contradiction].
 - rewrite Missing in Ready; discriminate.
Qed.

(** The provider continuation retains the context observation actually read
    from the registry, rather than accepting one supplied in a new request. *)
Lemma resolved_maintenance_installs_its_exact_receiver : forall before owner request
 (reference : S.maintenance_reference before owner request),
 let issued:=S.maintenance_issue reference in
 let built:=S.maintenance_build owner (world_next_ticket before) request in
 find (fun item => N.eqb owner (fst item))
  (C.maintenance_entries (F.feature_compaction (world_features (decision_world issued)))) =
  Some (owner,set C.entry_observation (fun _ => match S.compaction_entry owner before with
    | Some current => C.entry_observation current | None => None end) (fst built)) /\
 decision_effects issued=[MaintainContext (snd built)].
Proof.
 intros before owner request reference; cbn zeta.
 rewrite (S.maintenance_previous_found reference).
 unfold S.maintenance_issue.
 cbn [allocate_identity next_identity].
 destruct (S.maintenance_build owner (world_next_ticket before) request) as [pending emitted].
 split; [|reflexivity].
 unfold S.put_compaction,S.install_feature,S.compaction_slot,S.compaction_entries,
   Receiver.field,Receiver.inject,Receiver.keyed,Receiver.install,with_features,set; cbn.
 now rewrite N.eqb_refl.
Qed.

Theorem maintenance_context_installs_the_exact_shared_ticket :
 forall before (request : S.maintenance_context_plan before),
 let target := S.maintenance_context_target request in
 let current := TaskScope.selected target in
 let owner := TaskScope.owner target in
 let ticket := world_next_ticket before in
 let issued := S.maintenance_observe request in
 find_task owner (decision_world issued) =
   Some (with_activity (ObservingContext ticket (List.length (task_history current))) current) /\
 (exists entry, S.compaction_entry owner (decision_world issued) = Some entry /\
   C.entry_job entry = C.AwaitingContext ticket (S.maintenance_context_purpose request)
     (match task_activity current with ReadyForModel => true | _ => false end)) /\
 decision_effects issued = [ObserveContext owner ticket current].
Proof.
 intros before request; cbn zeta.
 unfold S.maintenance_observe. cbn [allocate_identity next_identity decision_world decision_effects accept].
 split.
 - change (find_task (TaskScope.owner (S.maintenance_context_target request))
     (put_task (TaskScope.owner (S.maintenance_context_target request))
      (with_activity (ObservingContext (world_next_ticket before)
        (List.length (task_history (TaskScope.selected (S.maintenance_context_target request)))))
         (TaskScope.selected (S.maintenance_context_target request)))
      (with_ticket (N.succ (world_next_ticket before)) before)) =
     Some (with_activity (ObservingContext (world_next_ticket before)
        (List.length (task_history (TaskScope.selected (S.maintenance_context_target request)))))
         (TaskScope.selected (S.maintenance_context_target request)))).
   unfold find_task, put_task, with_tasks; cbn.
   eapply registry_replace_selected. exact (TaskScope.observed (S.maintenance_context_target request)).
 - split; [|reflexivity].
   unfold S.compaction_entry,S.put_compaction,S.install_feature,S.compaction_slot,S.compaction_entries,
     Receiver.field,Receiver.inject,Receiver.keyed,Receiver.install,with_features,set; cbn.
   rewrite N.eqb_refl. eexists; split; reflexivity.
Qed.

Theorem maintenance_observation_uses_the_current_task : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = true ->
 S.maintenance_prefix_ready purpose (task_history (TaskScope.selected reference)) = true ->
 exists request, S.maintenance_context_selected reference purpose entry = Some request /\
   decision_effects (S.maintenance_observe request) =
     [ObserveContext (TaskScope.owner reference) (world_next_ticket before) (TaskScope.selected reference)].
Proof.
 intros before reference purpose entry Allowed Closed.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused].
 - eexists; split; reflexivity.
 - unfold S.maintenance_context_ready in Refused; rewrite Allowed,Closed in Refused; contradiction.
Qed.

Theorem unavailable_maintenance_observation_has_no_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = false ->
 S.maintenance_context_selected reference purpose entry = None.
Proof.
 intros before reference purpose entry Unavailable.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready in Admitted; rewrite Unavailable in Admitted; discriminate.
Qed.

Theorem an_open_summary_prefix_has_no_context_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 ContextSelection.closed_prefix (task_history (TaskScope.selected reference)) = false ->
 S.maintenance_context_selected reference (Some purpose) entry = None.
Proof.
 intros before reference purpose entry Open.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready (Some purpose) (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready,S.maintenance_prefix_ready in Admitted.
 rewrite Open,andb_false_r in Admitted; discriminate.
Qed.
