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
 CommandHandlers.execute (G.Cmd_fork request)
   (Some (Tasks.NativeCall (G.fork_task_id request) invocation remaining)) before =
 accept (fork_reply (G.fork_child_count request) before)
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining)
     (G.fork_task_id request) (G.fork_child_count request) messages parent selected before) [].
Proof.
 intros request invocation remaining messages before parent selected Parsed Admissible.
 change ((match Codec.traverse Images.parse_content (message_sources request) with
 | Some parsed => Tasks.fork_with_caller
   (if N.eqb (G.fork_task_id request) (G.fork_task_id request)
    then Tasks.AcceptedNativeFork invocation remaining else Tasks.ManualFork)
   (settings_origin request) (G.fork_task_id request) (G.fork_child_count request)
   parsed (G.fork_settings request) before
 | None => reject "invalid_message" "Child messages contain invalid content parts" before end) =
 accept (fork_reply (G.fork_child_count request) before)
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining)
     (G.fork_task_id request) (G.fork_child_count request) messages parent selected before) []).
 rewrite Parsed, N.eqb_refl.
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
   (accept (fork_reply count before)
     (fork_candidate (Tasks.AcceptedNativeFork invocation remaining) owner count messages parent selected before) []) =
 accept (fork_reply count before)
   (fork_candidate (Tasks.AcceptedNativeFork invocation remaining) owner count messages parent selected before) [].
Proof.
 intros invocation remaining origin owner count messages raw before parent selected Admissible Available.
 assert (Positive : (0 < count)%N).
 { destruct Admissible as (_ & _ & Count & _).
   unfold TaskConstraints.fork_count_valid in Count.
   apply andb_true_iff in Count as [Positive _]; now apply N.ltb_lt in Positive. }
 unfold ForkCommit.admit_workspace; cbn [accept decision_world].
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
