From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Host Require Import Process.
From Selvedge.Adapters Require Common HostProcess.
Import ListNotations.

Theorem completion_closes_stdin current :
  stdin_open (observe current Finished) = false.
Proof. reflexivity. Qed.

Theorem closed_input_rejects_write current terminal eof resize :
  exists reason,
  admit_write (observe current InputClosed) terminal eof resize =
    Some reason.
Proof. destruct current as [[] input busy reason]; eexists; reflexivity. Qed.

Theorem reserved_write_is_exclusive current next :
  reserve_write current = inr next ->
  exists reason, reserve_write next = inl reason.
Proof.
  destruct current as [phase input busy reason]; destruct busy;
    cbn; intros; inversion H; eexists; reflexivity.
Qed.

Theorem first_reason_survives current first later :
  process_reason current = Some first ->
  process_reason (with_reason current later) = Some first.
Proof. unfold with_reason; intros H; rewrite H; reflexivity. Qed.

Theorem append_tail_is_bounded capacity current added :
  retained (append_tail capacity current added) <= capacity.
Proof.
  unfold append_tail, keep_old, keep_new; cbn.
  pose proof (Nat.le_min_l capacity added).
  pose proof (Nat.le_min_r (retained current) (capacity - Nat.min capacity added)).
  lia.
Qed.

Theorem append_tail_preserves_absolute_cursor capacity current added :
  total (append_tail capacity current added) =
    (total current + N.of_nat added)%N.
Proof. reflexivity. Qed.

Theorem append_plan_keeps_exact_buffer capacity current added :
  retained current - drop_old capacity current added + (added - drop_new capacity added) =
    retained (append_tail capacity current added).
Proof.
  unfold append_tail, drop_old, drop_new, keep_old, keep_new; cbn.
  pose proof (Nat.le_min_l (retained current) (capacity - Nat.min capacity added)).
  pose proof (Nat.le_min_r capacity added).
  lia.
Qed.

Theorem read_cursor_never_exceeds_total current cursor :
  (read_start current cursor <= total current)%N.
Proof. unfold read_start, tail_start; apply N.max_lub; lia. Qed.

Theorem completed_retention_is_bounded current key :
  List.length (completed (complete current key)) <= 64.
Proof. unfold complete; cbn; rewrite length_skipn; lia. Qed.

Theorem completion_retains_exactly_unexpired_entries current key entry :
  In entry (entries (complete current key)) <->
  In entry (entries current) /\
  ~ In (entry_key entry)
    (firstn (List.length (completed current ++ [key]) - 64)
      (completed current ++ [key])).
Proof.
  unfold complete, retired, completion_queue; cbn [entries].
  rewrite filter_In, Bool.negb_true_iff.
  assert (Absent : forall keys,
    existsb (String.eqb (entry_key entry)) keys = false <->
    ~ In (entry_key entry) keys).
  { intros keys; split.
    - intros Missing Present.
      assert (Found : existsb (String.eqb (entry_key entry)) keys = true).
      { apply existsb_exists. exists (entry_key entry).
        split; [exact Present|apply String.eqb_refl]. }
      congruence.
    - intros Missing. destruct (existsb (String.eqb (entry_key entry)) keys) eqn:Found;
        [|reflexivity].
      apply existsb_exists in Found as [name [Present Equal]].
      apply String.eqb_eq in Equal. subst name. contradiction. }
  now rewrite Absent.
Qed.

Theorem artifact_metadata_requires_complete_published_capture source :
  Common.boolean_field (HostProcess.artifact_metadata source) "persisted" = true ->
  Common.boolean_field source "capture_complete" = true /\
  Common.boolean_field source "paths_published" = true.
Proof.
  change (artifact_persisted (Common.boolean_field source "capture_complete")
    (Common.boolean_field source "paths_published") = true ->
    Common.boolean_field source "capture_complete" = true /\
    Common.boolean_field source "paths_published" = true).
  unfold artifact_persisted; apply andb_true_iff.
Qed.

Theorem byte_ring_is_bounded capacity current added :
  ring_length (append_ring capacity current added) <= capacity.
Proof. unfold append_ring; cbn; apply Nat.le_min_l. Qed.

Theorem byte_ring_position_is_bounded capacity current added :
  0 < capacity -> ring_position (append_ring capacity current added) < capacity.
Proof.
  intros positive; unfold append_ring; cbn.
  destruct (Nat.leb capacity added); [lia|].
  apply Nat.mod_upper_bound; lia.
Qed.

Theorem byte_ring_preserves_total capacity current added :
  ring_total (append_ring capacity current added) = (ring_total current + N.of_nat added)%N.
Proof. reflexivity. Qed.

Theorem byte_ring_rotation_preserves_length capacity current :
  ring_position current <= ring_length current ->
  fold_right (fun slice count => slice_count slice + count) 0 (ring_slices capacity current) = ring_length current.
Proof.
  intros bounded; unfold ring_slices.
  destruct (Nat.eqb (ring_length current) capacity); cbn; lia.
Qed.
