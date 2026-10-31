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

Lemma distinct_app_parts : forall (A : Type) (left right : list A),
 NoDup (left ++ right) ->
 NoDup left /\ NoDup right /\
 (forall ticket, In ticket left -> ~ In ticket right).
Proof.
 intros A left; induction left as [|first rest IH]; intros right Unique.
 - cbn in *; repeat split; auto; constructor.
 - cbn in Unique; inversion Unique as [|? ? Fresh Tail]; subst.
   destruct (IH right Tail) as [Prefix [Suffix Disjoint]].
   split; [constructor; [intro Member; apply Fresh; apply in_or_app; auto|exact Prefix]|].
   split; [exact Suffix|]. intros ticket [Same|Member] Later.
   + subst ticket; apply Fresh; apply in_or_app; right; exact Later.
   + exact (Disjoint ticket Member Later).
Qed.
