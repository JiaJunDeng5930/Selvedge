From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs InputDecoder
 Scheduler SideContext Dispatch Limits Observation Notifications Delivery Packet.
From Selvedge.Kernel Require Import TicketedRequest Capabilities WorldInvariant WorldInvariantProofs
 AfterHookPreservation AfterHookAuthorizationProofs PacketBusinessProofs CommitAdmission ScopedRequestProofs.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.

Lemma a_current_after_operation_uses_the_before_indexed_request :
 forall owner task before original plugin pending result error,
 find_task owner before = Some task ->
 TicketedRequest.Scoped.operation_at (operation_id original) task = Some original ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 Capabilities.hook_available Capabilities.AfterTool plugin
   (environment_plugins (world_environment before)) = true ->
 Scheduler.after_hooks_step owner original task before =
 TicketedRequest.issue owner (TicketedRequest.After original plugin pending result error task) before.
Proof.
 intros owner task before original plugin pending result error Found Owned Stage Available.
 unfold Scheduler.after_hooks_step; rewrite Stage, Available.
 apply after_uses_the_current_operation; assumption.
Qed.

Lemma a_quiet_task_prefix_is_skipped :
 forall execute permitted prefix suffix value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Numbers.indexed (fun owner task => (owner,task)) first prefix) ->
 Scheduler.find_step execute permitted first (prefix ++ suffix) value =
 Scheduler.find_step execute permitted (first + N.of_nat (List.length prefix)) suffix value.
Proof.
 intros execute permitted prefix; induction prefix as [|task rest IH]; intros suffix value first Quiet.
 - cbn; rewrite N.add_0_r; reflexivity.
 - cbn [Numbers.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
   cbn [app Scheduler.find_step]. rewrite Head, IH by exact Tail.
   cbn [List.length]. rewrite Nat2N.inj_succ. f_equal; lia.
Qed.

Lemma a_quiet_task_registry_has_no_step :
 forall execute permitted tasks value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Numbers.indexed (fun owner task => (owner,task)) first tasks) ->
 Scheduler.find_step execute permitted first tasks value = None.
Proof.
 intros execute permitted tasks; induction tasks as [|task rest IH]; intros value first Quiet; [reflexivity|].
 cbn [Numbers.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
 cbn [Scheduler.find_step]; rewrite Head; apply IH; exact Tail.
Qed.

Lemma a_quiet_task_registry_needs_no_continuation : forall permitted tasks value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Numbers.indexed (fun owner task => (owner,task)) first tasks) ->
 existsb (fun entry => let '(owner,task) := entry in
   match Scheduler.next_runnable_step permitted owner task value with Some _ => true | None => false end)
   (Numbers.indexed (fun owner task => (owner,task)) first tasks) = false.
Proof.
 intros permitted tasks; induction tasks as [|task rest IH]; intros value first Quiet; [reflexivity|].
 cbn [Numbers.indexed existsb] in Quiet |- *; inversion Quiet as [|? ? Head Tail]; subst.
 rewrite Head; cbn; apply IH; exact Tail.
Qed.

Lemma scheduling_a_quiet_world_keeps_its_effects : forall fuel execute permitted value effects,
 SideContext.reconcile value = value ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Numbers.indexed (fun owner task => (owner,task)) 0 (world_tasks value)) ->
 Scheduler.schedule fuel execute permitted value effects = (value,effects).
Proof.
 intros fuel execute permitted value effects Reconciled Quiet.
 destruct fuel; cbn [Scheduler.schedule]; rewrite Reconciled.
 - rewrite a_quiet_task_registry_needs_no_continuation by exact Quiet; reflexivity.
 - rewrite a_quiet_task_registry_has_no_step by exact Quiet; reflexivity.
Qed.

Theorem one_settlement_step_reaches_the_scheduled_candidate :
 forall execute permitted before after prefix task suffix issued effects reply,
 world_tasks before = (prefix ++ task :: suffix)%list ->
 SideContext.reconcile before = before ->
 SideContext.reconcile after = after ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task before = None)
   (Numbers.indexed (fun owner task => (owner,task)) 0 prefix) ->
 Scheduler.next_runnable_step permitted (N.of_nat (List.length prefix)) task before =
   Some (Scheduler.SettlementStep issued) ->
 Scheduler.interpret_step execute (N.of_nat (List.length prefix)) task before
   (Scheduler.SettlementStep issued) = Some (Decision after (decision_reply
     (Scheduler.operation_step (N.of_nat (List.length prefix)) issued task before)) effects) ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task after = None)
   (Numbers.indexed (fun owner task => (owner,task)) 0 (world_tasks after)) ->
 Dispatch.prepare after effects = (after,effects) ->
 Scheduler.run execute permitted (Decision before reply []) = Decision after reply effects.
Proof.
 intros execute permitted before after prefix task suffix issued effects reply Registry
   BeforeReconciled AfterReconciled Prefix Selected Interpreted Quiet Prepared.
 assert (First : Scheduler.find_step execute permitted 0 (world_tasks before) before =
   Some (Decision after (decision_reply
     (Scheduler.operation_step (N.of_nat (List.length prefix)) issued task before)) effects)).
 { rewrite Registry, a_quiet_task_prefix_is_skipped by exact Prefix.
   cbn [N.add Scheduler.find_step]. rewrite Selected, Interpreted; reflexivity. }
 unfold Scheduler.run. cbn [decision_world decision_reply decision_effects].
 change ((let '(value,effects) := Scheduler.schedule (S (Nat.pred Limits.schedule_steps)) execute permitted before [] in
   let '(value,effects) := Dispatch.prepare value effects in Decision value reply effects) =
   Decision after reply effects).
 cbn [Scheduler.schedule]; rewrite BeforeReconciled, First; cbn [decision_world decision_effects app].
 rewrite scheduling_a_quiet_world_keeps_its_effects by assumption.
 rewrite Prepared; reflexivity.
Qed.

(* These frames describe one Continue turn with no additional feature or task
   work. Other operations, plugins, feature registries and unready resources
   remain in the world; only their eligibility in this turn is constrained. *)
Theorem an_archived_result_is_dispatched_by_the_exported_packet :
 forall source before owner prefix task suffix operations original plugin pending result error,
 let issued := TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before in
 let after := decision_world issued in
 let candidate := Decision after (State.success JNull) (decision_effects issued) in
 WorldInvariant.well_formed before ->
 InputDecoder.decode source = Some Continue ->
 N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes = true ->
 find_task owner before = Some task ->
 world_tasks before = (prefix ++ task :: suffix)%list ->
 owner = N.of_nat (List.length prefix) ->
 task_lifecycle task = Archived operations ->
 Selvedge.Features.Runtime.can_schedule_task owner before = false ->
 Scheduler.ready_settlement operations = Some original ->
 TicketedRequest.Scoped.operation_at (operation_id original) task = Some original ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 Capabilities.hook_available Capabilities.AfterTool plugin
   (environment_plugins (world_environment before)) = true ->
 Selvedge.Features.Runtime.after_transition before (State.accept JNull before []) = State.accept JNull before [] ->
 SideContext.reconcile before = before ->
 SideContext.reconcile after = after ->
 Forall (fun entry => let '(id,other) := entry in
   Scheduler.next_runnable_step Selvedge.Features.Runtime.can_schedule_task id other before = None)
   (Numbers.indexed (fun id other => (id,other)) 0 prefix) ->
 Forall (fun entry => let '(id,other) := entry in
   Scheduler.next_runnable_step Selvedge.Features.Runtime.can_schedule_task id other after = None)
   (Numbers.indexed (fun id other => (id,other)) 0 (world_tasks after)) ->
 Selvedge.Features.Runtime.finish candidate = candidate ->
 Delivery.fits true candidate = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) after,
   Notifications.envelope true true (Some Continue) before candidate).
Proof.
 intros source before owner prefix task suffix operations original plugin pending result error
   issued after candidate WellFormed Decoded InputBudget Found Registry Owner ArchivedTask
   Blocked Ready Owned Stage Available FeatureFrame Reconciled AfterReconciled Prefix Quiet Finish OutputBudget.
 assert (Member : In original (task_operations task)).
 { unfold TicketedRequest.Scoped.operation_at in Owned; apply find_some in Owned; exact (proj1 Owned). }
 assert (Next : Scheduler.next_runnable_step Selvedge.Features.Runtime.can_schedule_task owner task before =
   Some (Scheduler.SettlementStep original)).
 { unfold Scheduler.next_runnable_step; rewrite Blocked.
   unfold task_operations; rewrite ArchivedTask, Ready; reflexivity. }
 assert (Step : Scheduler.operation_step owner original task before = issued).
 { unfold Scheduler.operation_step; rewrite Stage.
   unfold issued; eapply a_current_after_operation_uses_the_before_indexed_request; eauto. }
 assert (Scheduled : Scheduler.run Packet.execute_command Selvedge.Features.Runtime.can_schedule_task
   (State.accept JNull before []) = candidate).
 { unfold candidate. rewrite Owner in *.
   eapply one_settlement_step_reaches_the_scheduled_candidate
     with (prefix:=prefix) (task:=task) (suffix:=suffix) (issued:=original); eauto.
   - unfold Scheduler.interpret_step. rewrite Step; unfold issued; reflexivity.
 }
 assert (Retained : Dispatch.retain_live_effects candidate = candidate).
 { unfold candidate, Dispatch.retain_live_effects.
   f_equal. change (decision_effects (Dispatch.retain_live_effects issued) = decision_effects issued).
   unfold issued. rewrite an_issued_after_hook_survives_the_final_withdrawal by assumption; reflexivity. }
 assert (Valid : WorldInvariant.world_valid after = true).
 { apply well_formed_worlds_pass_the_checker; unfold after, issued.
   eapply issuing_an_archived_after_hook_preserves_world_requirements; eauto.
   unfold task_operations in Member; rewrite ArchivedTask in Member; exact Member. }
 assert (Authorized : CommitAdmission.transition_authorized true (Some Continue) source before candidate = true).
 { change (CommitAdmission.transition_authorized true (Some Continue) source before issued = true).
   unfold issued; eapply an_archived_after_request_has_transition_authority; eauto. }
 assert (Admitted : Packet.admit_with_status true (Some Continue) source before candidate = (true,candidate)).
 { unfold Packet.admit_with_status; rewrite Retained.
   change (WorldInvariant.world_valid (decision_world candidate) = true) in Valid.
   unfold WorldInvariant.validate_with_status; rewrite Valid.
   unfold CommitAdmission.validate_with_status; rewrite Authorized.
   unfold Delivery.deliver_with_status; rewrite OutputBudget; reflexivity. }
 unfold Packet.packet; rewrite InputBudget; cbv beta zeta; rewrite Decoded.
 cbn [Packet.manual_fork_input Packet.transition_decoded Packet.core_transition].
 rewrite FeatureFrame, Scheduled, Finish, Admitted; reflexivity.
Qed.
