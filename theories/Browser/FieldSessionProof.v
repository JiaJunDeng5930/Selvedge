From Stdlib Require Import String Bool.
From Selvedge.Browser Require Import FieldSession.

Theorem changed_canonical_supersedes_composition : forall identity old value,
  value <> old -> session (updated (step (Synchronize value) (State identity old Composing))) = SupersededComposition.
Proof.
  intros identity old value changed; unfold step; simpl.
  assert (String.eqb value old = false) by (apply String.eqb_neq; assumption).
  rewrite H; reflexivity.
Qed.
Theorem superseded_composition_cannot_restore_old_draft : forall identity value,
  deliver (step CompositionEnded (State identity value SupersededComposition)) = false /\
  replace (step CompositionEnded (State identity value SupersededComposition)) = true.
Proof. split; reflexivity. Qed.
Theorem trailing_input_keeps_new_canonical : forall identity value,
  step InputObserved (State identity value SupersededTail) =
    Decision (State identity value SupersededTail) false true.
Proof. reflexivity. Qed.
Theorem equal_canonical_does_not_interrupt_composition : forall identity value,
  step (Synchronize value) (State identity value Composing) = Decision (State identity value Composing) false false.
Proof. intros; unfold step; simpl; rewrite String.eqb_refl; reflexivity. Qed.
