From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs Images
 CommandHandlers CommandExecution ForkCommitProofs ForkPreservation.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

(* Native dispatch accepts the parsed call before entering the shared command
   handler. Its positive result follows from fork permissions and resources,
   rather than an assumed successful command-executor return. *)
Theorem every_admissible_native_fork_handler_constructs_its_business_result :
 forall request invocation remaining messages before parent selected,
 Codec.traverse Images.parse_content (message_sources request) = Some messages ->
 fork_admissible (Tasks.AcceptedNativeFork invocation remaining) (settings_origin request)
   (G.fork_task_id request) (G.fork_child_count request) messages (G.fork_settings request)
   before parent selected ->
 CommandExecution.handle_fork_result request
   (Some (Tasks.NativeCall (G.fork_task_id request) invocation remaining)) before =
 CommandResult.Accepted (CommandResult.Change (fork_reply (G.fork_child_count request) before)
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining)
     (G.fork_task_id request) (G.fork_child_count request) messages parent selected before) []).
Proof.
 intros request invocation remaining messages before parent selected Parsed Admissible.
 unfold CommandExecution.handle_fork_result.
 match goal with |- match ?parsed with Some _ => _ | None => _ end = _ =>
   change (parsed = Some messages) in Parsed end; rewrite Parsed.
 cbn [Tasks.native_owner Tasks.native_invocation Tasks.native_remaining].
 rewrite N.eqb_refl.
 apply CommandResult.a_successful_decision_identifies_its_typed_change with (before:=before).
 apply every_admissible_fork_constructs_its_positive_business_result; exact Admissible.
Qed.

From Selvedge.Kernel Require Import ForkCommit TaskConstraints.
From Selvedge.Features Require Import Worktree.
Open Scope list_scope.

Lemma a_positive_native_fork_admits_its_observed_workspace :
 forall invocation remaining origin owner count messages raw before parent selected,
 fork_admissible (Tasks.AcceptedNativeFork invocation remaining) origin owner count messages raw before parent selected ->
 Worktree.workspace_available (settings_workspace selected) before &&
 Worktree.binding_available selected
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining) owner count messages parent selected before) = true ->
 ForkCommit.admit_workspace before
   (CommandResult.Accepted (CommandResult.Change (fork_reply count before)
     (fork_candidate (Tasks.AcceptedNativeFork invocation remaining) owner count messages parent selected before) [])) =
 CommandResult.Accepted (CommandResult.Change (fork_reply count before)
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining) owner count messages parent selected before) []).
Proof.
 intros invocation remaining origin owner count messages raw before parent selected Admissible Available.
 assert (Positive : (0 < count)%N).
 { destruct Admissible as (_ & _ & Count & _).
   unfold TaskConstraints.fork_count_valid in Count.
   apply andb_true_iff in Count as [Positive _]; now apply N.ltb_lt in Positive. }
 unfold ForkCommit.admit_workspace,ForkCommit.workspace_error;
 cbn [CommandResult.bind CommandResult.change_world].
 rewrite fork_candidate_registry.
 cbn [fork_retained fork_snapshot_parent fork_invocation].
 rewrite skipn_app,skipn_all,Nat.sub_diag; cbn.
 destruct (N.to_nat count) as [|rest] eqn:Count.
 - apply (f_equal N.of_nat) in Count; rewrite N2Nat.id in Count; cbn in Count; lia.
 - pose proof (every_constructed_child_has_its_inherited_execution_frame (S rest)
     owner parent messages selected (Tasks.AcceptedNativeFork invocation remaining)
     (next_task before) (next_task before) invocation) as Frames.
   cbn [constructed_children] in Frames |- *.
   inversion Frames as [|child children Frame Tail]; subst.
   unfold child_execution_frame in Frame; destruct Frame as [_ [Settings _]].
   rewrite Settings,Available; reflexivity.
Qed.
