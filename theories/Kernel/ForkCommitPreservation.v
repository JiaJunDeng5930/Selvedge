From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain Codec State CommandHandlers CommandExecution
 ForkCommit ForkCommitProofs ForkPreservation WorldInvariant WorldInvariantProofs Delivery.
From Selvedge.Generated Require Import Commands.
From Selvedge.Foundation Require Import Json.

Theorem the_actual_manual_fork_handler_preserves_world_requirements : forall request before,
 well_formed before ->
 well_formed (decision_world (CommandHandlers.execute (Commands.Cmd_fork request) None before)).
Proof.
 intros request before Valid.
 destruct (traverse Images.parse_content (message_sources request)) as [messages|] eqn:Parsed.
 - rewrite (a_manual_fork_uses_the_actual_domain_constructor request messages before Parsed).
   apply every_manual_fork_preserves_every_world_requirement; exact Valid.
 - rewrite the_actual_manual_fork_handler_interprets_its_message_admission, Parsed.
   exact Valid.
Qed.

Lemma the_manual_fork_proposal_preserves_world_requirements : forall request before,
 well_formed before -> well_formed (decision_world (ForkCommit.propose request before)).
Proof.
 intros; unfold ForkCommit.propose, ForkCommit.propose_result.
 destruct (Worktree.execution_allowed _ _).
 - apply the_actual_manual_fork_handler_preserves_world_requirements; assumption.
 - assumption.
Qed.

Theorem a_manual_fork_transaction_preserves_world_requirements : forall request before,
 well_formed before -> well_formed (decision_world (ForkCommit.candidate request before)).
Proof.
 intros request before Valid; rewrite the_fork_transaction_keeps_the_admitted_world.
 destruct (workspace_admission_keeps_the_constructor_or_the_before_world before
   (ForkCommit.propose_result request before)) as [Constructed|Refused].
 - rewrite Constructed; apply the_manual_fork_proposal_preserves_world_requirements; exact Valid.
 - rewrite Refused; exact Valid.
Qed.

Theorem manual_fork_packets_preserve_world_requirements : forall request before,
 world_valid before = true -> world_valid (fst (ForkCommit.packet request before)) = true.
Proof.
 intros request before Valid; unfold ForkCommit.packet.
 apply CommitPacket.finalize_preserves.
 - intros; now rewrite a_journal_cursor_does_not_change_domain_validity.
 - unfold ForkCommit.select,CommitPacket.choose,Delivery.deliver_with_status.
   destruct (Delivery.fits true (ForkCommit.candidate request before)); cbn [snd CommitPacket.selected_decision decision_world]; [|exact Valid].
   apply well_formed_worlds_pass_the_checker,a_manual_fork_transaction_preserves_world_requirements.
   apply the_world_checker_establishes_all_requirements; exact Valid.
Qed.
