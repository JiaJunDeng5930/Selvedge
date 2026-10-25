From Stdlib Require Import List Relations Relation_Operators PeanoNat NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet PacketProofs Journal
 WorldInvariant WorldInvariantProofs CommitAdmission ForkCommit ForkCommitAuthorization.
From Selvedge.Kernel Require Scheduler CreationCommit CreationCommitAuthorization DeferredCommitProofs.
From Selvedge.Features Require Import Runtime.
Import ListNotations.

Lemma domain_relation_ignores_journal_sequence : forall source raw_source before after sequence,
 CommitAdmission.world_evolution source raw_source before (with_sequence sequence after) =
 CommitAdmission.world_evolution source raw_source before after.
Proof.
 intros source raw_source before after sequence; destruct after.
 cbn [with_sequence set CommitAdmission.world_evolution CommitAdmission.retained_tasks
   CommitAdmission.retained_tasks_from]; reflexivity.
Qed.

Lemma domain_projection_erases_journal_sequence : forall state sequence,
 WorldInvariant.world_structure (with_sequence sequence state) = WorldInvariant.world_structure state.
Proof.
 intros state sequence; destruct state.
 cbn [WorldInvariant.world_structure with_sequence set]; reflexivity.
Qed.

Theorem every_actual_packet_preserves_global_state_relation_or_rolls_back : forall source before,
 well_formed before ->
 let '(after, receipt) := Packet.packet source before in
 WorldInvariant.world_structure after = WorldInvariant.world_structure before \/
 exists input, CommitAdmission.world_evolution input source before after = true.
Proof.
 intros source before Valid; unfold Packet.packet; cbv beta zeta;
 fold (Packet.manual_fork source) (Packet.transition source before).
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes).
 - destruct (Packet.manual_fork source) as [request|].
   { unfold ForkCommit.packet.
     destruct (Delivery.deliver_with_status true (ForkCommit.candidate request before) before)
       as [fits delivered] eqn:Outcome.
     pose proof (a_delivered_fork_retains_or_constructs_its_cross_state_authority
       (Some (UserCommand (Selvedge.Generated.Commands.Cmd_fork request))) source request before Valid) as Authority.
     rewrite Outcome in Authority; cbn [snd] in Authority; cbn.
     destruct Authority as [Retained|Evolved].
     - left; rewrite domain_projection_erases_journal_sequence; exact Retained.
     - right; exists (Some (UserCommand (Selvedge.Generated.Commands.Cmd_fork request))).
       rewrite domain_relation_ignores_journal_sequence; exact Evolved. }
   destruct (CreationCommit.input (InputDecoder.decode source)) as [request|].
   { unfold CreationCommit.packet, Delivery.deliver_with_status.
     destruct (Delivery.fits true (CreationCommit.candidate request before)); cbn [fst decision_world].
     - right; exists (Some (UserCommand (Selvedge.Generated.Commands.Cmd_create request))).
       rewrite domain_relation_ignores_journal_sequence.
       apply CreationCommitAuthorization.every_creation_candidate_preserves_retained_execution_authority; exact Valid.
     - left; apply domain_projection_erases_journal_sequence. }
   destruct (Packet.deferred_candidate (InputDecoder.decode source) before) as [[input candidate]|].
   { pose proof (DeferredCommitProofs.packet_preserves_global_state_relation_or_rolls_back (Some input) source before candidate) as Authority.
     destruct (DeferredCommit.packet (Some input) source before candidate) as [after envelope] eqn:Committed.
     cbn [fst] in Authority |- *.
     destruct Authority as [Retained|Evolved].
     - left; exact Retained.
     - right; exists (Some input); exact Evolved. }
   destruct (Packet.transition source before) as [[[durable schedules] input] candidate] eqn:Transition.
   set (prepared := if schedules then Runtime.finish
     (Scheduler.run Packet.execute_command Runtime.can_schedule_task candidate) else candidate).
   destruct (Packet.admit_with_status durable input source before prepared) as [accepted admitted] eqn:Outcome.
   pose proof (PacketProofs.actual_commit_admission_satisfies_global_transition_or_rollback
     durable input source before prepared) as Admission.
   rewrite (PacketProofs.admit_result_is_the_selected_outcome durable input source before prepared accepted admitted Outcome) in Admission.
   destruct Admission as [[RolledBack _] | [Evolution _]].
   + left; destruct durable; cbn [fst].
     * rewrite RolledBack; reflexivity.
     * rewrite RolledBack; exact (domain_projection_erases_journal_sequence before
         (N.succ (world_sequence before))).
   + right; destruct durable; cbn [fst].
     * exists input; exact Evolution.
     * exists input; exact Evolution.
 - left; reflexivity.
Qed.

Theorem batches_preserve_input_and_receipt_order : forall first second state,
 run (first ++ second) state = run second (run first state).
Proof. intros; unfold run; apply fold_left_app. Qed.

Theorem every_trace_is_reachable_by_actual_inputs : forall events state,
 reachable state (run events state).
Proof.
 induction events as [|source rest IH]; intros state; cbn [run].
 - apply rt_refl.
 - eapply rt_trans; [apply rt_step; exists source; reflexivity|apply IH].
Qed.

Theorem replay_projects_the_actual_trace : forall events state,
 trace_world (run events state) = replay events (trace_world state).
Proof.
 induction events as [|source rest IH]; intros state; [reflexivity|].
 change (trace_world (run rest (advance source state)) =
  replay rest (fst (Packet.packet source (trace_world state)))).
 rewrite IH. unfold advance.
 destruct (Packet.packet source (trace_world state)); reflexivity.
Qed.

Theorem every_input_retains_one_complete_receipt : forall events state,
 List.length (trace_receipts (run events state)) =
 (List.length events + List.length (trace_receipts state))%nat.
Proof.
 induction events as [|source rest IH]; intros state; [reflexivity|].
 change (List.length (trace_receipts (run rest (advance source state))) =
  S (List.length rest + List.length (trace_receipts state))%nat).
 rewrite IH. unfold advance.
 destruct (Packet.packet source (trace_world state)); cbn; apply Nat.add_succ_r.
Qed.

Theorem extending_a_trace_never_rewrites_prior_receipts : forall events state,
 exists generated, trace_receipts (run events state) = generated ++ trace_receipts state.
Proof.
 induction events as [|source rest IH]; intros state.
 - exists []; reflexivity.
 - change (exists generated, trace_receipts (run rest (advance source state)) = generated ++ trace_receipts state).
   destruct (IH (advance source state)) as [generated Kept].
   rewrite Kept. unfold advance.
   destruct (Packet.packet source (trace_world state)) as [next receipt].
   exists (generated ++ [receipt]); cbn. rewrite <- app_assoc; reflexivity.
Qed.

(* This premise identifies a decoded public read-only command. It does not
   assume the unchanged-world conclusion or any fact about later inputs. *)
Theorem an_actual_query_does_not_change_later_replay : forall first second state source command reply,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None (replay first state) = Some reply ->
 replay (first ++ source :: second) state = replay (first ++ second) state.
Proof.
 intros first second state source command reply Decoded Query.
 unfold replay; rewrite !fold_left_app; cbn.
 destruct (actual_query_preserves_world_and_emits_no_effect
  source command reply (replay first state) Decoded Query) as [Unchanged _].
 unfold replay in Unchanged; rewrite Unchanged; reflexivity.
Qed.


Theorem every_actual_history_step_preserves_world_requirements : forall source state,
 world_valid (trace_world state) = true -> world_valid (trace_world (advance source state)) = true.
Proof.
 intros source state Before; unfold advance.
 pose proof (every_actual_packet_preserves_world_requirements source (trace_world state) Before) as Safe.
 destruct (Packet.packet source (trace_world state)); exact Safe.
Qed.
Theorem every_actual_history_preserves_world_requirements : forall events state,
 world_valid (trace_world state) = true -> world_valid (trace_world (run events state)) = true.
Proof.
 induction events as [|source rest IH]; intros state Before; [exact Before|].
 change (world_valid (trace_world (run rest (advance source state))) = true).
 apply IH, every_actual_history_step_preserves_world_requirements; exact Before.
Qed.
Theorem actual_reachability_preserves_world_requirements : forall before after,
 reachable before after -> world_valid (trace_world before) = true -> world_valid (trace_world after) = true.
Proof.
 intros before after Path; induction Path; intros Valid.
 - destruct H as [source Step]; subst y.
   apply every_actual_history_step_preserves_world_requirements; exact Valid.
 - exact Valid.
 - apply IHPath2, IHPath1; exact Valid.
Qed.
Theorem every_actual_replay_preserves_world_requirements : forall events before,
 world_valid before = true -> world_valid (replay events before) = true.
Proof.
 induction events as [|source rest IH]; intros before Valid; [exact Valid|].
 change (world_valid (replay rest (fst (Packet.packet source before))) = true).
 apply IH, every_actual_packet_preserves_world_requirements; exact Valid.
Qed.
Theorem replay_from_initial_establishes_every_named_world_requirement : forall events,
 well_formed (replay events State.initial).
Proof.
 intros events; apply the_world_checker_establishes_all_requirements.
 apply every_actual_replay_preserves_world_requirements, the_initial_world_is_well_formed.
Qed.
