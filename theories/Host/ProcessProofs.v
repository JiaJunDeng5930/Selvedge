From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Host Require Import Process.
Import ListNotations.

Theorem finished_requires_exit_and_drain current :
  process_phase current <> Completed ->
  process_phase (observe current Finished) = Completed ->
  process_phase current = Draining /\ output_drained current = true.
Proof.
  destruct current as [phase input busy drained reason].
  destruct phase, drained; cbn; intros; intuition discriminate.
Qed.

Theorem completion_closes_stdin current :
  stdin_open (observe current Failed) = false.
Proof. reflexivity. Qed.

Theorem exit_rejects_write current terminal eof cols rows :
  process_phase current = Running ->
  admit_write (observe current ShellExited) terminal eof cols rows =
    Some (Failure "process_stdin_closed" "The process input is closed").
Proof. destruct current; cbn; intros; subst; reflexivity. Qed.

Theorem reserved_write_is_exclusive current next :
  reserve_write current = inr next ->
  reserve_write next = inl (Failure "process_input_busy" "Another input write is still pending for this process").
Proof.
  destruct current as [phase input busy drained reason]; destruct busy;
    cbn; intros; inversion H; reflexivity.
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
