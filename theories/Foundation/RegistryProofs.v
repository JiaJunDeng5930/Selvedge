From Stdlib Require Import List NArith Lia.
From Selvedge.Foundation Require Import Registry.
Import ListNotations.

Lemma registry_lookup_is_member : forall (A : Type) (values : list A) index selected,
 registry_at index values = Some selected -> In selected values.
Proof.
 intros A values; induction values as [|first rest IH]; intros index selected Found; [discriminate|].
 cbn in Found; destruct (N.eqb index 0).
 - inversion Found; subst; left; reflexivity.
 - right; eapply IH; exact Found.
Qed.

Lemma registry_replace_selected : forall (A : Type) (values : list A) index previous replacement,
 registry_at index values = Some previous -> registry_at index (replace index replacement values) = Some replacement.
Proof.
 intros A values; induction values as [|head rest IH]; intros index previous replacement H; cbn in H; try discriminate.
 cbn; destruct (N.eqb index 0) eqn:E; cbn; rewrite E; [reflexivity|].
 apply IH with previous; exact H.
Qed.

Lemma registry_replace_length : forall (A : Type) (values : list A) index replacement,
 List.length (replace index replacement values) = List.length values.
Proof. intros A values; induction values as [|head rest IH]; intros; cbn; [reflexivity|].
 destruct (N.eqb index 0); cbn; [reflexivity|rewrite IH; reflexivity]. Qed.

Lemma registry_replace_other : forall (A : Type) (values : list A) selected queried replacement,
 selected <> queried ->
 registry_at queried (replace selected replacement values) = registry_at queried values.
Proof.
 intros A values; induction values as [|head rest IH]; intros selected queried replacement Different; cbn; [reflexivity|].
 destruct (N.eqb selected 0) eqn:Selected; destruct (N.eqb queried 0) eqn:Queried;
   cbn; rewrite ?Queried; try reflexivity.
 - apply N.eqb_eq in Selected; apply N.eqb_eq in Queried; congruence.
 - apply IH. apply N.eqb_neq in Selected; apply N.eqb_neq in Queried; lia.
Qed.

Lemma registry_lookup_at_appended_index : forall (A : Type) (entries : list A) value,
 registry_at (N.of_nat (List.length entries)) (entries ++ [value]) = Some value.
Proof.
 intros A entries; induction entries as [|head rest IH]; intro value; [reflexivity|].
 change ((if N.eqb (N.of_nat (S (List.length rest))) 0 then Some head
   else registry_at (N.pred (N.of_nat (S (List.length rest)))) (rest ++ [value])) = Some value).
 assert (Positive : N.eqb (N.of_nat (S (List.length rest))) 0 = false)
   by (apply N.eqb_neq; lia).
 rewrite Positive.
 replace (N.pred (N.of_nat (S (List.length rest)))) with (N.of_nat (List.length rest)) by lia.
 apply IH.
Qed.

Lemma registry_append_preserves_other_lookup : forall (A : Type) (entries : list A) index value,
 index <> N.of_nat (List.length entries) ->
 registry_at index (entries ++ [value]) = registry_at index entries.
Proof.
 intros A entries; induction entries as [|head rest IH]; intros index value Different.
 - cbn. destruct (N.eqb index 0) eqn:Selected; [|reflexivity].
   apply N.eqb_eq in Selected. exfalso; apply Different; exact Selected.
 - cbn [List.app registry_at]. destruct (N.eqb index 0) eqn:Selected; [reflexivity|].
   apply IH. apply N.eqb_neq in Selected. intro Equal. apply Different.
   cbn [List.length]. rewrite Nat2N.inj_succ, <- Equal.
   symmetry; now apply N.succ_pred.
Qed.

Lemma registry_lookup_commutes_with_mapping : forall (A B : Type) (f : A -> B) values owner,
 registry_at owner (map f values) = option_map f (registry_at owner values).
Proof.
 intros A B f values; induction values as [|first rest IH]; intros owner; cbn; [reflexivity|].
 destruct (N.eqb owner 0); [reflexivity|apply IH].
Qed.

Lemma registry_lookup_preserved_by_append : forall (A : Type) (values : list A) index existing suffix,
 registry_at index values = Some existing -> registry_at index (values ++ suffix) = Some existing.
Proof.
 intros A values; induction values as [|head rest IH]; intros index existing suffix Found; cbn in *; [discriminate|].
 destruct (N.eqb index 0); [exact Found|]. eapply IH; exact Found.
Qed.

Lemma registry_lookup_implies_position_bound : forall (A : Type) (entries : list A) owner value,
 registry_at owner entries = Some value -> (owner < N.of_nat (List.length entries))%N.
Proof.
 intros A entries; induction entries as [|head tail IH]; intros owner value Found; [discriminate|].
 cbn [registry_at] in Found; cbn [List.length]; rewrite Nat2N.inj_succ.
 destruct (N.eqb owner 0) eqn:Zero.
 - apply N.eqb_eq in Zero; subst; lia.
 - apply N.eqb_neq in Zero; specialize (IH _ _ Found); lia.
Qed.

Lemma a_registry_member_has_a_position : forall (A : Type) (entries : list A) value,
 In value entries -> exists owner, registry_at owner entries = Some value.
Proof.
 intros A entries; induction entries as [|head tail IH]; intros value Member; [contradiction|].
 destruct Member as [Same|Member].
 - subst; exists 0%N; reflexivity.
 - destruct (IH value Member) as [owner Found].
   exists (N.succ owner); cbn [registry_at].
   assert (Nonzero : N.eqb (N.succ owner) 0 = false) by (apply N.eqb_neq; lia).
   rewrite Nonzero, N.pred_succ; exact Found.
Qed.

Lemma registry_lookup_after_head : forall (A : Type) (first : A) rest owner,
 registry_at (N.succ owner) (first :: rest) = registry_at owner rest.
Proof.
 intros; cbn [registry_at]. rewrite N.pred_succ.
 assert (Positive : N.eqb (N.succ owner) 0 = false) by (apply N.eqb_neq; lia).
 rewrite Positive; reflexivity.
Qed.

Lemma registry_lookup_exists_below_length : forall (A : Type) (entries : list A) owner,
 (owner < N.of_nat (List.length entries))%N -> exists value, registry_at owner entries = Some value.
Proof.
 intros A entries; induction entries as [|first rest IH]; intros owner Bound; [cbn in Bound; lia|].
 cbn [registry_at]; destruct (N.eqb owner 0) eqn:Zero; [exists first; reflexivity|].
 apply N.eqb_neq in Zero; apply IH.
 change (owner < N.of_nat (S (List.length rest)))%N in Bound.
 rewrite Nat2N.inj_succ in Bound; lia.
Qed.

Lemma registry_lookup_at_numbered_map : forall (A B : Type) (f : N -> A -> B) values offset index previous,
 registry_at index values = Some previous ->
 registry_at index (indexed f offset values) = Some (f (offset+index)%N previous).
Proof.
 intros A B f values; induction values as [|first rest IH]; intros offset index previous Found;
 cbn [registry_at indexed] in Found |- *; [discriminate|].
 destruct (N.eqb index 0) eqn:Zero.
 - apply N.eqb_eq in Zero; subst index; inversion Found; subst previous.
   now rewrite N.add_0_r.
 - rewrite (IH (N.succ offset) (N.pred index) previous Found).
   f_equal; f_equal; apply N.eqb_neq in Zero; lia.
Qed.

Lemma indexed_members_have_actual_positions : forall (A B : Type) (project : N -> A -> B) entries offset member,
 In member (indexed project offset entries) ->
 exists position current, registry_at position entries = Some current /\ member = project (offset + position)%N current.
Proof.
 intros A B project entries; induction entries as [|first rest IH]; intros offset member Member; [contradiction|].
 cbn [indexed] in Member; destruct Member as [Same|Member].
 - subst member; exists 0%N,first; split; [reflexivity|now rewrite N.add_0_r].
 - destruct (IH (N.succ offset) member Member) as [position [current [Found Same]]].
   exists (N.succ position),current; split.
   + rewrite registry_lookup_after_head; exact Found.
   + rewrite Same,N.add_succ_l,N.add_succ_r; reflexivity.
Qed.
