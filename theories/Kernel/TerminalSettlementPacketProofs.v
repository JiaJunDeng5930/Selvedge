From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State TaskScope Inputs HookRules HookCallbacks Callbacks
 TerminalSettlement TerminalSettlementPlanProofs TerminalSettlementProofs TerminalSettlementPreservation TerminalSettlementAuthority
 DeferredCommit DeferredCommitProofs Delivery Notifications Dispatch WorldInvariant WorldInvariantProofs
 CommitAdmission ArchivedRuntimeFrameProofs.
Import ListNotations.
Open Scope list_scope.

Lemma a_terminal_plan_carries_its_exact_owned_operation : forall before (accepted : TerminalSettlement.plan before),
 let payload := TerminalSettlement.request accepted in
 let current := TaskScope.selected (TerminalSettlement.target accepted) in
 exists operations original expected plugin pending previous failed,
 find_task (TerminalSettlement.owner payload) before = Some current /\
 task_lifecycle current = Archived operations /\
 find (fun operation => N.eqb (TerminalSettlement.operation payload) (operation_id operation)) operations = Some original /\
 operation_stage original = AwaitingAfterHook expected plugin pending previous failed /\
 expected = TerminalSettlement.ticket payload /\
 (match HookRules.after_apply previous (TerminalSettlement.outcome payload), pending with
  | HookRules.RefuseResult _ _, _ | _, [] => true | _, _ => false end) = true /\
 TerminalSettlement.update accepted = HookCallbacks.after_result_plan_for
   (TerminalSettlement.owner payload) original plugin pending failed (TerminalSettlement.outcome payload)
   (HookRules.after_apply previous (TerminalSettlement.outcome payload)).
Proof.
 intros before accepted payload current.
 pose proof (TerminalSettlement.observed_update accepted) as Final.
 change (TerminalSettlement.resolved_update payload current = Some (TerminalSettlement.update accepted)) in Final.
 unfold TerminalSettlement.resolved_update in Final.
 destruct (task_lifecycle current) as [phase operations|phase operations|phase operations|operations] eqn:ArchivedTask;
 try discriminate.
 unfold RequestReceiver.pending_after,RequestReceiver.operation_at,task_operations in Final; rewrite ArchivedTask in Final.
 destruct (find (fun pending => N.eqb (TerminalSettlement.operation payload) (operation_id pending)) operations)
   as [original|] eqn:Owned; [|discriminate].
 unfold RequestReceiver.operation_receiver in Final.
 destruct (operation_stage original) as [ticket|ticket reviewer|reviewer|ticket reviewer|pending result failed|
    expected plugin pending previous failed] eqn:Stage; try discriminate.
 destruct (N.eqb expected (TerminalSettlement.ticket payload)) eqn:Matched; [|discriminate].
 destruct (TerminalSettlement.final_action (HookRules.after_apply previous (TerminalSettlement.outcome payload)) pending) eqn:Terminal;
   [|discriminate].
 injection Final as Update; symmetry in Update.
 apply N.eqb_eq in Matched; unfold TerminalSettlement.final_action in Terminal.
 exists operations, original, expected, plugin, pending, previous, failed; repeat split; try assumption.
 unfold payload, current. rewrite <- (TerminalSettlement.owns_request accepted).
 exact (TaskScope.observed (TerminalSettlement.target accepted)).
Qed.

Theorem every_terminal_plan_constructs_its_exact_successful_settlement :
 forall before (accepted : TerminalSettlement.plan before),
 exists operations original plugin previous failed,
 let payload := TerminalSettlement.request accepted in
 let current := TaskScope.selected (TerminalSettlement.target accepted) in
 let settled := settled_task (TerminalSettlement.owner payload) original plugin previous failed
   (TerminalSettlement.outcome payload) current in
 find_task (TerminalSettlement.owner payload) before = Some current /\
 task_lifecycle current = Archived operations /\
 find (fun operation => N.eqb (operation_id original) (operation_id operation)) operations = Some original /\
 CommitAdmission.operation_nonexecuting original = true /\
 TerminalSettlement.candidate accepted = Decision (put_task (TerminalSettlement.owner payload) settled before)
   (State.success (JObject [("accepted"%string,JBool true)])) [ContinueScheduling].
Proof.
 intros before accepted.
 destruct (a_terminal_plan_carries_its_exact_owned_operation before accepted)
   as [operations [original [expected [plugin [pending [previous [failed [Found [ArchivedTask [Owned [Stage [Matched [Terminal Update]]]]]]]]]]]]].
 pose proof Owned as Identified; apply find_some in Identified as [Member Identity]; apply N.eqb_eq in Identity.
 exists operations, original, plugin, previous, failed; cbn beta zeta; repeat split; try assumption.
 - rewrite <- Identity; exact Owned.
 - unfold CommitAdmission.operation_nonexecuting; rewrite Stage; reflexivity.
 - change (Decision (Tasks.interpret_result (TerminalSettlement.target accepted) (TerminalSettlement.update accepted))
     (State.success (JObject [("accepted"%string,JBool true)])) [ContinueScheduling] =
     Decision (put_task (TerminalSettlement.owner (TerminalSettlement.request accepted))
       (settled_task (TerminalSettlement.owner (TerminalSettlement.request accepted)) original plugin previous failed
         (TerminalSettlement.outcome (TerminalSettlement.request accepted)) (TaskScope.selected (TerminalSettlement.target accepted))) before)
       (State.success (JObject [("accepted"%string,JBool true)])) [ContinueScheduling]).
   f_equal; unfold Tasks.interpret_result; rewrite Update, (TerminalSettlement.owns_request accepted).
   eapply a_final_update_constructs_the_exact_settlement; eassumption.
Qed.

Theorem every_terminal_plan_preserves_the_world_requirements :
 forall before (accepted : TerminalSettlement.plan before),
 WorldInvariant.well_formed before ->
 WorldInvariant.well_formed (decision_world (TerminalSettlement.candidate accepted)).
Proof.
 intros before accepted Valid.
 destruct (every_terminal_plan_constructs_its_exact_successful_settlement before accepted)
  as [operations [original [plugin [previous [failed [Found [ArchivedTask [Owned [Nonexecuting Candidate]]]]]]]]].
 rewrite Candidate; cbn [decision_world].
 eapply terminal_after_settlement_preserves_every_world_requirement; eauto.
 apply find_some in Owned; exact (proj1 Owned).
Qed.

Theorem every_terminal_plan_has_transition_authority :
 forall before (accepted : TerminalSettlement.plan before) raw,
 WorldInvariant.well_formed before ->
 CommitAdmission.transition_authorized true (Some (TerminalSettlement.source accepted)) raw before
   (TerminalSettlement.candidate accepted) = true.
Proof.
 intros before accepted raw Valid.
 destruct (every_terminal_plan_constructs_its_exact_successful_settlement before accepted)
  as [operations [original [plugin [previous [failed [Found [ArchivedTask [Owned [Nonexecuting Candidate]]]]]]]]].
 rewrite Candidate; eapply terminal_settlement_has_global_transition_authority; eauto.
Qed.

Theorem terminal_commit_admission_keeps_the_constructed_settlement :
 forall before (accepted : TerminalSettlement.plan before) raw,
 WorldInvariant.well_formed before -> Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
 DeferredCommit.admit_with_status true (Some (TerminalSettlement.source accepted)) raw before
  (TerminalSettlement.candidate accepted) = (true,TerminalSettlement.candidate accepted).
Proof.
 intros before accepted raw Valid Fits.
 pose proof (well_formed_worlds_pass_the_checker _ (every_terminal_plan_preserves_the_world_requirements before accepted Valid)) as WellFormed.
 pose proof (every_terminal_plan_has_transition_authority before accepted raw Valid) as Authorized.
 assert (Retained : Dispatch.retain_live_effects (TerminalSettlement.candidate accepted) = TerminalSettlement.candidate accepted).
 { destruct (every_terminal_plan_constructs_its_exact_successful_settlement before accepted)
    as [operations [original [plugin [previous [failed [_ [_ [_ [_ Candidate]]]]]]]]].
   rewrite Candidate; reflexivity. }
 unfold DeferredCommit.admit_with_status; rewrite Retained.
 unfold WorldInvariant.validate_with_status; rewrite WellFormed.
 unfold CommitAdmission.validate_with_status; rewrite Authorized.
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.

Theorem a_terminal_settlement_commits_before_independent_runtime_work :
 forall before (accepted : TerminalSettlement.plan before) raw,
 WorldInvariant.well_formed before -> Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
 TerminalSettlement.packet accepted raw =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TerminalSettlement.candidate accepted)),
  Notifications.envelope true true (Some (TerminalSettlement.source accepted)) before (TerminalSettlement.candidate accepted)).
Proof.
 intros; unfold TerminalSettlement.packet, DeferredCommit.packet, DeferredCommit.select.
 rewrite terminal_commit_admission_keeps_the_constructed_settlement by assumption; reflexivity.
Qed.

Theorem terminal_packets_preserve_world_validity : forall before (accepted : TerminalSettlement.plan before) raw,
 WorldInvariant.world_valid before = true ->
 WorldInvariant.world_valid (fst (TerminalSettlement.packet accepted raw)) = true.
Proof. intros; unfold TerminalSettlement.packet; apply DeferredCommitProofs.packet_preserves_world_validity; assumption. Qed.

Theorem terminal_packets_advance_the_journal_sequence : forall before (accepted : TerminalSettlement.plan before) raw,
 world_sequence (fst (TerminalSettlement.packet accepted raw)) = N.succ (world_sequence before).
Proof. intros; unfold TerminalSettlement.packet; apply DeferredCommitProofs.packet_advances_sequence. Qed.





Theorem every_owned_terminal_callback_resolves_its_finite_transaction :
 forall payload before current,
 find_task (TerminalSettlement.owner payload) before = Some current ->
 TerminalSettlement.eligible payload current = true ->
 exists accepted, TerminalSettlement.resolve_request payload before = Some accepted.
Proof.
 intros payload before current Found Eligible.
 pose proof (terminal_resolution_tracks_the_real_eligibility payload before) as Resolution.
 rewrite Found, Eligible in Resolution.
 destruct (TerminalSettlement.resolve_request payload before) as [accepted|] eqn:Resolved;
 [exists accepted; reflexivity|discriminate].
Qed.


Theorem terminal_plans_leave_no_unrouted_assistant_delta :
 forall before (accepted : TerminalSettlement.plan before) queried current,
 find_task queried (decision_world (TerminalSettlement.candidate accepted)) = Some current ->
 Selvedge.Features.TaskGraph.new_outputs before queried current = [].
Proof.
 intros before accepted queried current Lookup.
 destruct (every_terminal_plan_constructs_its_exact_successful_settlement before accepted)
  as [operations [original [plugin [previous [failed [Found [ArchivedTask [Owned [Nonexecuting Candidate]]]]]]]]].
 rewrite Candidate in Lookup; cbn [decision_world] in Lookup.
 destruct (N.eq_dec queried (TerminalSettlement.owner (TerminalSettlement.request accepted))) as [Same|Different].
 - subst queried.
   rewrite LifecycleProofs.find_put_task with (before:=TaskScope.selected (TerminalSettlement.target accepted))
     in Lookup by exact Found.
   inversion Lookup; subst current.
   eapply settlement_does_not_produce_graph_output; eauto.
 - unfold find_task, put_task in Lookup; rewrite writing_tasks_installs_the_registry,
     registry_replace_other in Lookup by congruence.
   change (find_task queried before = Some current) in Lookup.
   unfold Selvedge.Features.TaskGraph.new_outputs; rewrite Lookup, skipn_all; reflexivity.
Qed.
