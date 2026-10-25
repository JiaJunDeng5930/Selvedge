From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain Codec State Inputs CommandHandlers CommandExecution
 ForkCommit ForkCommitProofs ForkAuthorizationProofs WorldInvariant CommitAdmission Delivery.
From Selvedge.Generated Require Import Commands.
From Selvedge.Foundation Require Import Json.

Lemma the_manual_fork_handler_retains_or_constructs_its_cross_state_authority :
 forall source raw request before, well_formed before ->
 world_structure (decision_world (CommandHandlers.execute (Commands.Cmd_fork request) None before)) = world_structure before \/
 CommitAdmission.world_evolution source raw before
   (decision_world (CommandHandlers.execute (Commands.Cmd_fork request) None before)) = true.
Proof.
 intros source raw request before Valid.
 destruct (traverse Images.parse_content (message_sources request)) as [messages|] eqn:Parsed.
 - rewrite (a_manual_fork_uses_the_actual_domain_constructor request messages before Parsed).
   apply every_actual_fork_retains_or_constructs_its_cross_state_authority; exact Valid.
 - rewrite the_actual_manual_fork_handler_interprets_its_message_admission, Parsed.
   left; reflexivity.
Qed.

Theorem a_manual_fork_transaction_retains_or_constructs_its_cross_state_authority :
 forall source raw request before, well_formed before ->
 world_structure (decision_world (ForkCommit.candidate request before)) = world_structure before \/
 CommitAdmission.world_evolution source raw before (decision_world (ForkCommit.candidate request before)) = true.
Proof.
 intros source raw request before Valid; rewrite the_fork_transaction_keeps_the_admitted_world.
 destruct (workspace_admission_keeps_the_constructor_or_the_before_world before
   (ForkCommit.propose request before)) as [Constructed|Refused].
 - rewrite Constructed; unfold ForkCommit.propose, Worktree.execution_guard.
   destruct (Worktree.execution_allowed _ _).
   + apply the_manual_fork_handler_retains_or_constructs_its_cross_state_authority; exact Valid.
   + left; reflexivity.
 - rewrite Refused; left; reflexivity.
Qed.

Theorem a_delivered_fork_retains_or_constructs_its_cross_state_authority :
 forall source raw request before, well_formed before ->
 let delivered := snd (Delivery.deliver_with_status true (ForkCommit.candidate request before) before) in
 world_structure (decision_world delivered) = world_structure before \/
 CommitAdmission.world_evolution source raw before (decision_world delivered) = true.
Proof.
 intros source raw request before Valid; cbv zeta; unfold Delivery.deliver_with_status.
 destruct (Delivery.fits true (ForkCommit.candidate request before)); cbn [snd].
 - apply a_manual_fork_transaction_retains_or_constructs_its_cross_state_authority; exact Valid.
 - left; reflexivity.
Qed.
