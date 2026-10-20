From Stdlib Require Import List.
From Selvedge.Foundation Require Import Sequence.
Import ListNotations.

Lemma take_acc_preserves_order : forall (A : Type) (values : list A) count reversed,
 take_acc count values reversed = List.rev_append reversed (firstn count values).
Proof.
 intros A values. induction values as [|head rest IH]; intros [|count] reversed; cbn; try reflexivity.
 apply IH.
Qed.
Theorem take_equals_firstn : forall (A : Type) count (values : list A),
 Sequence.take count values = firstn count values.
Proof. intros. unfold Sequence.take. rewrite take_acc_preserves_order. reflexivity. Qed.
