From Stdlib Require Import String Bool Arith Lia.
From Selvedge.Interaction Require Import SkillMention.

Theorem mention_ignored_during_composition : forall text start finish,
  detect text start finish true = None.
Proof. reflexivity. Qed.

Theorem mention_requires_a_caret : forall text start finish composing,
  start <> finish -> detect text start finish composing = None.
Proof.
  intros text start finish composing different; unfold detect.
  assert (Nat.eqb start finish = false) by (apply Nat.eqb_neq; assumption).
  rewrite H; destruct composing; reflexivity.
Qed.

Theorem mention_requires_a_buffer_position : forall text start composing,
  String.length text < start -> detect text start start composing = None.
Proof.
  intros text start composing outside; unfold detect.
  assert (Nat.leb start (String.length text) = false) by (apply Nat.leb_gt; assumption).
  rewrite H; destruct composing; rewrite Bool.orb_true_r; reflexivity.
Qed.

Theorem moved_selection_is_a_candidate : forall backwards selected count,
  0 < count -> move_index backwards selected count < count.
Proof.
  intros backwards selected count positive; unfold move_index.
  destruct count; [lia|].
  pose proof (Nat.mod_upper_bound selected (S count) ltac:(lia)) as bounded.
  destruct backwards.
  - destruct (Nat.eqb (selected mod S count) 0); lia.
  - destruct (Nat.ltb (S (selected mod S count)) (S count)) eqn:next;
      [apply Nat.ltb_lt in next; lia | lia].
Qed.
