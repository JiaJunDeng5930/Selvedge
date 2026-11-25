From Stdlib Require Import List NArith SetoidList Sorting.Mergesort Sorting.Permutation.
From Selvedge.Foundation Require IndexedRegistry IndexedRegistryProofs.
Import ListNotations.
Open Scope N_scope.

Module Slots := IndexedRegistry.Slots.
Definition select {A} (matches : A -> bool) (value : option A) :=
 match value with Some current => if matches current then value else None | None => None end.
Definition agrees {A} matches (rows : IndexedRegistry.t A) (selection : Slots.t A) :=
 forall id, Slots.find (IndexedRegistry.key id) selection = select matches (IndexedRegistry.lookup id rows).

Record t {A} (matches : A -> bool) := Table {
 rows : IndexedRegistry.t A;
 selection : Slots.t A;
 selection_agrees : agrees matches rows selection
}.
Arguments rows {A matches}.
Arguments selection {A matches}.
Arguments selection_agrees {A matches}.

Definition empty {A} (matches : A -> bool) : t matches.
Proof.
 refine (@Table A matches IndexedRegistry.empty (Slots.empty A) _).
 intros id. unfold IndexedRegistry.lookup. cbn [IndexedRegistry.empty IndexedRegistry.entries].
 now rewrite !Slots.gempty.
Defined.

Definition reselect {A} (matches : A -> bool) id (value : A) (from : Slots.t A) :=
 let address := IndexedRegistry.key id in
 if matches value then Slots.add address value from
 else match Slots.find address from with Some _ => Slots.remove address from | None => from end.
Local Lemma reselect_here {A} matches id (value : A) from :
 Slots.find (IndexedRegistry.key id) (reselect matches id value from) = select matches (Some value).
Proof.
 unfold reselect, select. destruct (matches value); [apply Slots.gss|].
 destruct (Slots.find (IndexedRegistry.key id) from) eqn:Found; [apply Slots.grs|exact Found].
Qed.
Local Lemma reselect_elsewhere {A} matches id (value : A) from other :
 id <> other ->
 Slots.find (IndexedRegistry.key other) (reselect matches id value from) =
 Slots.find (IndexedRegistry.key other) from.
Proof.
 intro Diff. assert (DifferentKey : IndexedRegistry.key other <> IndexedRegistry.key id).
 { intro Same. apply Diff, IndexedRegistry.key_injective. symmetry; exact Same. }
 unfold reselect. destruct (matches value); [now apply Slots.gso|].
 destruct (Slots.find (IndexedRegistry.key id) from); [now apply Slots.gro|reflexivity].
Qed.

Definition put {A} {matches : A -> bool} (id : N) (value : A) (table : t matches) : t matches.
Proof.
 destruct (N.ltb_spec0 id (IndexedRegistry.next (rows table))) as [Present|]; [|exact table].
 refine (@Table A matches (IndexedRegistry.put id value (rows table))
   (reselect matches id value (selection table)) _).
 intro other. destruct (N.eq_dec id other) as [Same|Different].
 - subst other. now rewrite reselect_here, IndexedRegistryProofs.lookup_put_present.
 - rewrite reselect_elsewhere, IndexedRegistryProofs.lookup_put_other by exact Different.
   apply selection_agrees.
Defined.

Definition append {A} {matches : A -> bool} (value : A) (table : t matches) : t matches.
Proof.
 pose (id := IndexedRegistry.next (rows table)).
 refine (@Table A matches (IndexedRegistry.append value (rows table))
   (reselect matches id value (selection table)) _).
 intro other. destruct (N.eq_dec id other) as [Same|Different].
 - subst other. unfold id. now rewrite reselect_here, IndexedRegistryProofs.lookup_append_new.
 - rewrite reselect_elsewhere by exact Different.
   rewrite IndexedRegistryProofs.lookup_append_before by (fold id; congruence).
   apply selection_agrees.
Defined.

Module KeyOrder.
 Definition t := positive.
 Definition leb (left right : positive) := N.leb (N.pos left) (N.pos right).
 Lemma leb_total : forall left right, leb left right = true \/ leb right left = true.
 Proof.
  intros left right. unfold leb. destruct (N.le_ge_cases (N.pos left) (N.pos right));
   [left|right]; now apply N.leb_le.
 Qed.
End KeyOrder.
Module Ordered := Mergesort.Sort KeyOrder.

Definition selected_entries {A matches} (table : @t A matches) : list (N * A) :=
 let active := selection table in
 fold_right (fun address rest => match Slots.find address active with
 | Some value => (N.pred (N.pos address), value) :: rest | None => rest end)
 [] (Ordered.sort (map fst (Slots.elements active))).

Local Lemma address_identity address : IndexedRegistry.key (N.pred (N.pos address)) = address.
Proof.
 assert (Same : N.pos (IndexedRegistry.key (N.pred (N.pos address))) = N.pos address).
 { unfold IndexedRegistry.key. rewrite N.succ_pos_spec. apply N.succ_pred. discriminate. }
 now injection Same.
Qed.
Local Lemma identity_address id : N.pred (N.pos (IndexedRegistry.key id)) = id.
Proof. unfold IndexedRegistry.key. now rewrite N.succ_pos_spec, N.pred_succ. Qed.

Local Lemma member_of_selected_keys {A} (active : Slots.t A) keys id value :
 In (id,value) (fold_right (fun address rest => match Slots.find address active with
 | Some current => (N.pred (N.pos address), current) :: rest | None => rest end) [] keys) <->
 In (IndexedRegistry.key id) keys /\ Slots.find (IndexedRegistry.key id) active = Some value.
Proof.
 induction keys as [|address rest IH]; cbn; [tauto|].
 destruct (Slots.find address active) as [current|] eqn:Found; cbn.
 - rewrite IH. split.
   + intros [Same|[Member Match]].
     * inversion Same; subst. pose proof (address_identity address) as Key. cbn in Key. now rewrite Key; auto.
     * auto.
   + intros [[Same|Member] Match].
     * rewrite <- Same, Found in Match. inversion Match; subst current.
       left. rewrite Same. pose proof (identity_address id) as Key. cbn in Key. now rewrite Key.
     * auto.
 - rewrite IH. split; [tauto|].
   intros [[Same|Member] Match]; [rewrite <- Same, Found in Match; discriminate|auto].
Qed.

Theorem selected_entries_match_the_rows {A matches} (table : @t A matches) id value :
 In (id,value) (selected_entries table) <->
 IndexedRegistry.lookup id (rows table) = Some value /\ matches value = true.
Proof.
 unfold selected_entries. rewrite member_of_selected_keys.
 assert (KeyPresent : Slots.find (IndexedRegistry.key id) (selection table) = Some value ->
   In (IndexedRegistry.key id) (Ordered.sort (map fst (Slots.elements (selection table))))).
 { intro Found. apply (Permutation_in _ (Ordered.Permuted_sort _)).
   apply Slots.find_2, Slots.elements_1, InA_alt in Found.
   destruct Found as [[address current] [[Key Current] Member]].
   change (IndexedRegistry.key id = address) in Key. subst address.
   apply in_map_iff. exists (IndexedRegistry.key id,current); auto. }
 rewrite (selection_agrees table id). unfold select.
 destruct (IndexedRegistry.lookup id (rows table)) as [current|] eqn:Found; [|intuition discriminate].
 destruct (matches current) eqn:Selected; split.
 - intros [_ Same]. now inversion Same; subst.
 - intros [Same _]. inversion Same; subst. split; [apply KeyPresent|reflexivity].
   now rewrite (selection_agrees table id), Found; unfold select; rewrite Selected.
 - intuition discriminate.
 - intros [Same Eligible]. inversion Same; subst. congruence.
Qed.
