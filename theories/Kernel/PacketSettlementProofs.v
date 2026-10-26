From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs InputDecoder
 Scheduler SideContext Dispatch Limits Observation Notifications Delivery Packet.
From Selvedge.Kernel Require Import TicketedRequest Capabilities WorldInvariant WorldInvariantProofs
 AfterHookPreservation AfterHookAuthorizationProofs PacketBusinessProofs CommitAdmission ScopedRequestProofs
 TerminalSettlement TerminalSettlementPacketProofs.
From Selvedge.Kernel Require CreationCommit NativeForkCommit BoardCommit ConnectionCommit TitleCommit.
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
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first prefix) ->
 Scheduler.find_step execute permitted first (prefix ++ suffix) value =
 Scheduler.find_step execute permitted (first + N.of_nat (List.length prefix)) suffix value.
Proof.
 intros execute permitted prefix; induction prefix as [|task rest IH]; intros suffix value first Quiet.
 - cbn; rewrite N.add_0_r; reflexivity.
 - cbn [Selvedge.Foundation.Registry.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
   cbn [app Scheduler.find_step]. rewrite Head, IH by exact Tail.
   cbn [List.length]. rewrite Nat2N.inj_succ. f_equal; lia.
Qed.

Lemma a_quiet_task_registry_has_no_step :
 forall execute permitted tasks value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first tasks) ->
 Scheduler.find_step execute permitted first tasks value = None.
Proof.
 intros execute permitted tasks; induction tasks as [|task rest IH]; intros value first Quiet; [reflexivity|].
 cbn [Selvedge.Foundation.Registry.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
 cbn [Scheduler.find_step]; rewrite Head; apply IH; exact Tail.
Qed.

Lemma a_quiet_task_registry_has_no_native_fork :
 forall permitted tasks value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first tasks) ->
 Scheduler.first_native_fork permitted first tasks value = None.
Proof.
 intros permitted tasks; induction tasks as [|task rest IH]; intros value first Quiet; [reflexivity|].
 cbn [Selvedge.Foundation.Registry.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
 cbn [Scheduler.first_native_fork]; rewrite Head; apply IH; exact Tail.
Qed.

Lemma a_quiet_native_fork_prefix_is_skipped :
 forall permitted prefix suffix value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first prefix) ->
 Scheduler.first_native_fork permitted first (prefix ++ suffix) value =
 Scheduler.first_native_fork permitted (first + N.of_nat (List.length prefix)) suffix value.
Proof.
 intros permitted prefix; induction prefix as [|task rest IH]; intros suffix value first Quiet.
 - cbn; rewrite N.add_0_r; reflexivity.
 - cbn [Selvedge.Foundation.Registry.indexed] in Quiet; inversion Quiet as [|? ? Head Tail]; subst.
   cbn [app Scheduler.first_native_fork]. rewrite Head, IH by exact Tail.
   cbn [List.length]. rewrite Nat2N.inj_succ. f_equal; lia.
Qed.

Lemma a_quiet_task_registry_needs_no_continuation : forall permitted tasks value first,
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first tasks) ->
 existsb (fun entry => let '(owner,task) := entry in
   match Scheduler.next_runnable_step permitted owner task value with Some _ => true | None => false end)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) first tasks) = false.
Proof.
 intros permitted tasks; induction tasks as [|task rest IH]; intros value first Quiet; [reflexivity|].
 cbn [Selvedge.Foundation.Registry.indexed existsb] in Quiet |- *; inversion Quiet as [|? ? Head Tail]; subst.
 rewrite Head; cbn; apply IH; exact Tail.
Qed.

Lemma scheduling_a_quiet_world_keeps_its_effects : forall fuel execute permitted value effects,
 SideContext.reconcile value = value ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task value = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) 0 (world_tasks value)) ->
 Scheduler.schedule fuel execute permitted value effects = (value,effects).
Proof.
 intros fuel execute permitted value effects Reconciled Quiet.
 assert (NoContinuation : Scheduler.continue_runnable permitted value effects = effects).
 { unfold Scheduler.continue_runnable, Scheduler.has_runnable_work.
   rewrite a_quiet_task_registry_needs_no_continuation by exact Quiet; reflexivity. }
 destruct fuel; cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted];
   destruct (existsb Scheduler.effect_requires_commit effects); try (now rewrite NoContinuation);
   rewrite Reconciled.
 - rewrite NoContinuation; reflexivity.
 - rewrite a_quiet_task_registry_has_no_native_fork by exact Quiet.
   rewrite a_quiet_task_registry_has_no_step by exact Quiet; reflexivity.
Qed.

Theorem one_settlement_step_reaches_the_scheduled_candidate :
 forall execute permitted before after prefix task suffix issued effects reply,
 world_tasks before = (prefix ++ task :: suffix)%list ->
 SideContext.reconcile before = before ->
 SideContext.reconcile after = after ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task before = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) 0 prefix) ->
 Scheduler.next_runnable_step permitted (N.of_nat (List.length prefix)) task before =
   Some (Scheduler.SettlementStep issued) ->
 Scheduler.interpret_step execute (N.of_nat (List.length prefix)) task before
   (Scheduler.SettlementStep issued) = Some (Decision after (decision_reply
     (Scheduler.operation_step (N.of_nat (List.length prefix)) issued task before)) effects) ->
 Forall (fun entry => let '(owner,task) := entry in
   Scheduler.next_runnable_step permitted owner task after = None)
   (Selvedge.Foundation.Registry.indexed (fun owner task => (owner,task)) 0 (world_tasks after)) ->
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
 unfold Scheduler.run, Scheduler.run_with. cbn [decision_world decision_reply decision_effects].
 change ((let '(value,effects) := Scheduler.schedule (S (Nat.pred Limits.schedule_steps)) execute permitted before [] in
   let '(value,effects) := Dispatch.prepare value effects in Decision value reply effects) =
   Decision after reply effects).
 assert (NoFork : Scheduler.first_native_fork permitted 0 (world_tasks before) before = None).
 { rewrite Registry, a_quiet_native_fork_prefix_is_skipped by exact Prefix.
   cbn [N.add Scheduler.first_native_fork]. rewrite Selected; reflexivity. }
 cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted]; rewrite BeforeReconciled, NoFork, First; cbn [decision_world decision_effects app].
 rewrite scheduling_a_quiet_world_keeps_its_effects by assumption.
 cbn [existsb].
 rewrite Prepared; reflexivity.
Qed.

(* Final archived callbacks commit their owned result before unrelated runtime
   work. The finite request constructor proves its exact local writes; the
   continuation retains normal task and feature progress after that commit. *)
Theorem an_archived_result_is_committed_by_the_exported_packet :
 forall raw before (accepted : TerminalSettlement.plan before),
 InputDecoder.decode raw = Some (TerminalSettlement.source accepted) ->
 TerminalSettlement.resolve (TerminalSettlement.source accepted) before = Some accepted ->
 N.leb (N.of_nat (String.length (TextJson.render_json raw))) Limits.frame_bytes = true ->
 WorldInvariant.well_formed before ->
 Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TerminalSettlement.candidate accepted)),
  Notifications.envelope true true (Some (TerminalSettlement.source accepted)) before
    (TerminalSettlement.candidate accepted)).
Proof.
 intros raw before accepted Decoded Resolved InputBudget Valid OutputBudget.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result.
 rewrite InputBudget; cbv beta zeta; rewrite Decoded.
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input
  ConnectionCommit.input TitleCommit.input Packet.native_fork_input
  NativeForkCommit.resolve Packet.terminal_settlement_input TerminalSettlement.source].
 rewrite Resolved.
 apply a_terminal_settlement_commits_before_independent_runtime_work; assumption.
Qed.

(* The public result follows from the real callback ownership and the output
   budget. Neither the constructor, the executor nor an admission bit is an
   assumed successful result. Other tasks and feature registries are arbitrary. *)
Theorem every_owned_terminal_callback_commits_at_the_public_packet :
 forall raw before payload current,
 let input := AfterCompleted (TerminalSettlement.owner payload) (TerminalSettlement.operation payload)
   (TerminalSettlement.ticket payload) (TerminalSettlement.outcome payload) in
 let result := DeferredCommit.continue (HookCallbacks.after_completed
   (TerminalSettlement.owner payload) (TerminalSettlement.operation payload)
   (TerminalSettlement.ticket payload) (TerminalSettlement.outcome payload) before) in
 InputDecoder.decode raw = Some input ->
 find_task (TerminalSettlement.owner payload) before = Some current ->
 TerminalSettlement.eligible payload current = true ->
 N.leb (N.of_nat (String.length (TextJson.render_json raw))) Limits.frame_bytes = true ->
 WorldInvariant.well_formed before -> Delivery.fits true result = true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (decision_world result),
  Notifications.envelope true true (Some input) before result) /\
 decision_reply result = State.success (JObject [("accepted",JBool true)]) /\
 decision_effects result = [ContinueScheduling].
Proof.
 intros raw before payload current input result Decoded Found Eligible InputBudget Valid OutputBudget.
 destruct (every_owned_terminal_callback_resolves_its_finite_transaction payload before current Found Eligible)
  as [accepted Resolved].
 pose proof (resolution_retains_the_callback_payload payload before accepted Resolved) as Payload.
 assert (Source : TerminalSettlement.source accepted = input).
 { unfold TerminalSettlement.source; rewrite Payload; reflexivity. }
 assert (Candidate : TerminalSettlement.candidate accepted = result).
 { unfold TerminalSettlement.candidate, TerminalSettlement.interpret; rewrite Payload; reflexivity. }
 split.
 - rewrite <- Candidate, <- Source.
   apply an_archived_result_is_committed_by_the_exported_packet; try assumption.
   + rewrite Source; exact Decoded.
   + rewrite Source; unfold input, TerminalSettlement.resolve.
     destruct payload; exact Resolved.
   + rewrite Candidate; exact OutputBudget.
 - destruct (every_terminal_plan_constructs_its_exact_successful_settlement before accepted)
   as [operations [original [plugin [previous [failed [_ [_ [_ [_ Exact]]]]]]]]].
   rewrite <- Candidate, Exact; split; reflexivity.
Qed.
