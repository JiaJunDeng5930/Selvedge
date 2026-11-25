From Stdlib Require Import List NArith Bool Lia.
From Selvedge.Foundation Require Import IndexedRegistry RegistryProofs.
Import ListNotations.
Open Scope N_scope.
Module Previous := Selvedge.Foundation.Registry.

Lemma lookup_append_before {A} (registry : t A) id entry :
 id <> next registry -> lookup id (append entry registry) = lookup id registry.
Proof.
 intros Different. unfold lookup. cbn [append entries].
 apply Slots.gso. intros Same. apply Different. now apply key_injective.
Qed.

Lemma lookup_append_new {A} (registry : t A) entry :
 lookup (next registry) (append entry registry) = Some entry.
Proof. unfold lookup; cbn [append entries]; apply Slots.gss. Qed.

Lemma next_append {A} (registry : t A) entry :
 next (append entry registry) = N.succ (next registry).
Proof. reflexivity. Qed.

Lemma next_put {A} (registry : t A) id entry :
 next (put id entry registry) = next registry.
Proof. unfold put. now destruct (N.ltb_spec0 _ _). Qed.

Lemma lookup_put_other {A} (registry : t A) id entry other :
 id <> other -> lookup other (put id entry registry) = lookup other registry.
Proof.
 intros Different. unfold put. destruct (N.ltb_spec0 _ _); [|reflexivity].
 unfold lookup; cbn [entries]. apply Slots.gso.
 intros Same; apply Different; symmetry; now apply key_injective.
Qed.

Lemma lookup_put_present {A} (registry : t A) id entry :
 id < next registry -> lookup id (put id entry registry) = Some entry.
Proof.
 intros Included. unfold put. destruct (N.ltb_spec0 _ _); [|contradiction].
 unfold lookup; cbn [entries]. apply Slots.gss.
Qed.

Lemma collect_length {A} (registry : t A) start count :
 start + N.of_nat count <= next registry ->
 N.of_nat (length (collect registry start count)) = N.of_nat count.
Proof.
 revert start. induction count as [|count IH]; intros start Within; [reflexivity|].
 rewrite Nat2N.inj_succ in Within.
 cbn [collect].
 destruct (proj1 (filled registry start) ltac:(lia)) as [current Found].
 change (lookup start registry = Some current) in Found.
 rewrite Found. cbn [length]. rewrite !Nat2N.inj_succ, IH; lia.
Qed.

Lemma contents_length {A} (registry : t A) :
 N.of_nat (length (contents registry)) = next registry.
Proof.
 unfold contents. rewrite collect_length, N2Nat.id; lia.
Qed.

Lemma collect_lookup {A} (registry : t A) start count id :
 start + N.of_nat count <= next registry ->
 id < N.of_nat count ->
 Previous.registry_at id (collect registry start count) = lookup (start + id) registry.
Proof.
 revert start id. induction count as [|count IH]; intros start id Whole Relative; [lia|].
 rewrite Nat2N.inj_succ in Whole, Relative.
 cbn [collect].
 destruct (proj1 (filled registry start) ltac:(lia)) as [current Found].
 change (lookup start registry = Some current) in Found.
 rewrite Found. cbn [Previous.registry_at].
 destruct (id =? 0) eqn:Zero.
 - apply N.eqb_eq in Zero. subst. now rewrite N.add_0_r, Found.
 - apply N.eqb_neq in Zero.
   rewrite IH by lia. f_equal. lia.
Qed.

Lemma lookup_outside {A} (registry : t A) id :
 next registry <= id -> lookup id registry = None.
Proof.
 intros Outside. destruct (lookup id registry) eqn:Found; [|reflexivity].
 change (Slots.find (key id) (entries registry) = Some a) in Found.
 pose proof (proj2 (filled registry id) (ex_intro _ _ Found)); lia.
Qed.

Lemma contents_lookup {A} (registry : t A) id :
 Previous.registry_at id (contents registry) = lookup id registry.
Proof.
 destruct (N.ltb_spec0 id (next registry)) as [Within|Outside].
 - unfold contents. apply collect_lookup; rewrite N2Nat.id, ?N.add_0_l; lia.
 - rewrite lookup_outside by lia.
   destruct (Previous.registry_at id (contents registry)) eqn:Found; [|reflexivity].
   apply registry_lookup_implies_position_bound in Found. rewrite contents_length in Found. lia.
Qed.

Lemma ordered_lookup_unique {A} (left right : list A) :
 (forall id, Previous.registry_at id left = Previous.registry_at id right) -> left = right.
Proof.
 revert right. induction left as [|first rest IH]; intros [|head tail] Same; try reflexivity;
 specialize (Same 0) as Initial; cbn in Initial; try discriminate.
 injection Initial as Equal; subst head. f_equal. apply IH.
 intro id. specialize (Same (N.succ id)). cbn [Previous.registry_at] in Same.
 rewrite (proj2 (N.eqb_neq _ _) (N.neq_succ_0 id)), N.pred_succ in Same; exact Same.
Qed.

Lemma contents_append {A} (registry : t A) value :
 contents (append value registry) = contents registry ++ [value].
Proof.
 apply ordered_lookup_unique. intro id. rewrite contents_lookup.
 destruct (N.eq_dec id (next registry)) as [Same|Different].
 - subst. rewrite lookup_append_new. rewrite <- contents_length at 1.
   now rewrite registry_lookup_at_appended_index.
 - rewrite lookup_append_before by exact Different.
   rewrite registry_append_preserves_other_lookup by now rewrite contents_length.
   symmetry; apply contents_lookup.
Qed.

Lemma contents_put {A} (registry : t A) id value :
 contents (put id value registry) = Previous.replace id value (contents registry).
Proof.
 apply ordered_lookup_unique. intro other. rewrite contents_lookup.
 destruct (N.eq_dec id other) as [Same|Different].
 - subst. destruct (Previous.registry_at other (contents registry)) eqn:Found.
   + rewrite (registry_replace_selected _ _ _ _ _ Found).
     apply lookup_put_present.
     apply registry_lookup_implies_position_bound in Found. now rewrite contents_length in Found.
   + assert (Outside : next registry <= other).
     { destruct (N.ltb_spec0 other (next registry)) as [Within|]; [|lia].
       rewrite contents_lookup in Found.
       destruct (proj1 (filled registry other) Within) as [entry Present].
       unfold lookup in Found; congruence. }
     assert (Replaced : Previous.registry_at other (Previous.replace other value (contents registry)) = None).
     { destruct (Previous.registry_at other (Previous.replace other value (contents registry))) eqn:Candidate; [|reflexivity].
       apply registry_lookup_implies_position_bound in Candidate.
       rewrite registry_replace_length, contents_length in Candidate. lia. }
     rewrite Replaced. apply lookup_outside. rewrite next_put. exact Outside.
 - rewrite lookup_put_other by exact Different.
   rewrite registry_replace_other by exact Different. symmetry; apply contents_lookup.
Qed.

Lemma fold_append_contents {A} (records : list A) registry :
 contents (fold_left (fun acc value => append value acc) records registry) =
 contents registry ++ records.
Proof.
 revert registry. induction records as [|entry rest IH]; intro registry; cbn [fold_left].
 - now rewrite app_nil_r.
 - rewrite IH, contents_append, <- app_assoc. reflexivity.
Qed.

Lemma contents_from_list {A} (records : list A) : contents (from_list records) = records.
Proof. unfold from_list, extend; rewrite fold_append_contents; reflexivity. Qed.

(** Count the nodes inspected by [Slots.find], including the terminal
    node or leaf. Numeric ordering and collection size do not enter this path. *)
Fixpoint lookup_node_reads {A} (address : positive) (tree : Slots.t A) : nat :=
 match tree with
 | Slots.Leaf => 1%nat
 | Slots.Node even _ odd =>
   match address with
   | xH => 1%nat
   | xO rest => S (lookup_node_reads rest even)
   | xI rest => S (lookup_node_reads rest odd)
   end
 end.
Theorem lookup_node_reads_are_bounded_by_the_address {A} address (tree : Slots.t A) :
 (lookup_node_reads address tree <= Pos.size_nat address)%nat.
Proof.
 revert tree; induction address; intros [|even value odd]; cbn; try lia.
 all: apply le_n_S; apply IHaddress.
Qed.
