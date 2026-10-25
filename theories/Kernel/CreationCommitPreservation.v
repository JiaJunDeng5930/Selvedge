From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain State Codec Tasks CommandExecution
 CreationCommit CreationResourcesProofs WorldInvariant WorldInvariantProofs Delivery.
From Selvedge.Features Require Import Worktree.
Open Scope string_scope.

Theorem the_public_creation_handler_preserves_every_world_requirement : forall request before,
 well_formed before -> well_formed (decision_world (Worktree.handle_create request None before)).
Proof.
 intros request before Valid.
 unfold Worktree.handle_create, CommandExecution.with_content.
 destruct (CommandExecution.user_content (Commands.create_message request) (Commands.create_images request))
   as [contents|] eqn:Parsed; [|exact Valid].
 unfold Worktree.create_selected, Worktree.create_planned, Worktree.create_intent.
 unfold Worktree.consume_start_resolution.
 destruct (CommandExecution.resolve_context_start
   (Worktree.creation_entry Worktree.ImplicitCreation None)
   (Commands.create_profile request) (Commands.create_reasoning request) contents
   (Commands.create_settings request) false None before) as [cause|start] eqn:Resolved.
 - exact Valid.
 - cbn [Worktree.start_allowed CommandExecution.creation_allowed].
   destruct (Worktree.prepare_resolved Worktree.ImplicitCreation None None start before)
     as [plan|reply] eqn:Prepared.
   + eapply a_resolved_public_resource_creation_preserves_every_world_requirement; eassumption.
   + exact Valid.
Qed.

Theorem public_creation_candidates_preserve_every_world_requirement : forall request before,
 well_formed before -> well_formed (decision_world (CreationCommit.candidate request before)).
Proof.
 intros request before Valid; unfold CreationCommit.candidate.
 destruct (bool_default "ok" (decision_reply (Worktree.handle_create request None before)) false);
 cbn [decision_world]; apply the_public_creation_handler_preserves_every_world_requirement; exact Valid.
Qed.

Theorem public_creation_packets_preserve_world_requirements : forall request before,
 world_valid before = true -> world_valid (fst (CreationCommit.packet request before)) = true.
Proof.
 intros request before Valid; unfold CreationCommit.packet,Delivery.deliver_with_status.
 destruct (Delivery.fits true (CreationCommit.candidate request before)); cbn [fst decision_world];
 rewrite a_journal_cursor_does_not_change_domain_validity.
 - apply well_formed_worlds_pass_the_checker,public_creation_candidates_preserve_every_world_requirement.
   apply the_world_checker_establishes_all_requirements; exact Valid.
 - exact Valid.
Qed.
