From Stdlib Require Import String List PeanoNat Lia.
From Selvedge.Foundation Require Import FreshNames.
Import ListNotations.
Open Scope string_scope.

Lemma longest_name_bounds : forall names name,
 In name names -> (String.length name <= String.length (longest_name names))%nat.
Proof.
 induction names as [|first rest IH]; intros name Present; [contradiction|].
 cbn [longest_name]. destruct (Nat.leb (String.length first)
   (String.length (longest_name rest))) eqn:Comparison.
 - apply Nat.leb_le in Comparison. destruct Present as [<-|Present]; [exact Comparison|].
   now apply IH.
 - apply Nat.leb_gt in Comparison. destruct Present as [<-|Present]; [lia|].
   pose proof (IH name Present); lia.
Qed.

Lemma append_length : forall prefix suffix,
 String.length (prefix ++ suffix) = (String.length prefix + String.length suffix)%nat.
Proof. induction prefix; intros suffix; cbn; [reflexivity|now rewrite IHprefix]. Qed.

Theorem fresh_name_longer : forall prefix names name,
 prefix <> "" -> In name names ->
 (String.length name < String.length (fresh_name prefix names))%nat.
Proof.
 intros prefix names name Nonempty Present.
 unfold fresh_name; rewrite append_length.
 pose proof (longest_name_bounds names name Present).
 destruct prefix; [contradiction|cbn; lia].
Qed.

Theorem fresh_name_is_fresh : forall prefix names name,
 prefix <> "" -> In name names -> fresh_name prefix names <> name.
Proof.
 intros prefix names name Nonempty Present Same.
 pose proof (fresh_name_longer prefix names name Nonempty Present).
 rewrite Same in H; lia.
Qed.
