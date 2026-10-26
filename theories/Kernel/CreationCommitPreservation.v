From Selvedge.Kernel Require CommandResult.
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
 unfold Worktree.handle_create, Worktree.handle_create_result, CommandExecution.content_result.
 destruct (CommandExecution.user_content (Commands.create_message request) (Commands.create_images request))
   as [contents|] eqn:Parsed; [|exact Valid].
 cbn [CommandResult.bind]. unfold Worktree.create_selected_result,
   Worktree.create_intent_result, Worktree.resolve_start_birth.
 destruct (CommandExecution.resolve_context_start
   (Worktree.creation_entry Worktree.ImplicitCreation None)
   (Commands.create_profile request) (Commands.create_reasoning request) contents
   (Commands.create_settings request) false None before) as [cause|start] eqn:Resolved.
 - exact Valid.
 - cbn [Worktree.start_allowed CommandExecution.creation_allowed].
   unfold Worktree.prepare_selected_birth,Worktree.prepare_scoped.
   destruct (Worktree.prepare_resolved Worktree.ImplicitCreation None None start before)
     as [plan|reply] eqn:Prepared.
   + cbn [Worktree.final_authority].
     change (well_formed (decision_world (Worktree.consume_planned_start plan before))).
     eapply a_resolved_public_resource_creation_preserves_every_world_requirement; eassumption.
   + exact Valid.
Qed.

Theorem public_creation_candidates_preserve_every_world_requirement : forall request before,
 well_formed before -> well_formed (decision_world (CreationCommit.candidate request before)).
Proof.
 intros request before Valid; unfold CreationCommit.candidate.
 rewrite CommandResult.appending_effects_keeps_the_committed_world.
 apply the_public_creation_handler_preserves_every_world_requirement; exact Valid.
Qed.

Theorem public_creation_packets_preserve_world_requirements : forall request before,
 world_valid before = true -> world_valid (fst (CreationCommit.packet request before)) = true.
Proof.
 intros request before Valid; unfold CreationCommit.packet.
 apply CommitPacket.finalize_preserves.
 - intros; now rewrite a_journal_cursor_does_not_change_domain_validity.
 - unfold CreationCommit.select,CommitPacket.choose,Delivery.deliver_with_status.
   destruct (Delivery.fits true (CreationCommit.candidate request before)); cbn [snd CommitPacket.selected_decision decision_world]; [|exact Valid].
   apply well_formed_worlds_pass_the_checker,public_creation_candidates_preserve_every_world_requirement.
   apply the_world_checker_establishes_all_requirements; exact Valid.
Qed.
