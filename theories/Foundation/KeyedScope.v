From Stdlib Require Import List NArith Bool.
From Selvedge.Foundation Require DependencyIndex IndexedRegistry.
Import ListNotations.

Module Slots := IndexedRegistry.Slots.
Definition lookup {A} id (rows : Slots.t A) := Slots.find (IndexedRegistry.key id) rows.
Definition agrees {A} (addresses : A -> list positive) rows (index : DependencyIndex.t N) :=
 forall key id, DependencyIndex.lookup key id index =
 match lookup id rows with
 | Some value => if existsb (Pos.eqb key) (addresses value) then Some id else None
 | None => None end.

Record t {A} (addresses : A -> list positive) := Table {
 rows : Slots.t A;
 order : list N;
 index : DependencyIndex.t N;
 index_agrees : agrees addresses rows index
}.
Arguments rows {A addresses}.
Arguments order {A addresses}.
Arguments index {A addresses}.
Arguments index_agrees {A addresses}.

Definition empty {A} (addresses : A -> list positive) : t addresses.
Proof.
 refine (Table A addresses (Slots.empty A) [] (Slots.empty _) _).
 intros key id. unfold lookup, DependencyIndex.lookup. now rewrite !Slots.gempty.
Defined.

Definition reselect (add : bool) id keys current :=
 fold_left (fun index key =>
   if add then DependencyIndex.include key id id index else DependencyIndex.exclude key id index)
  keys current.
Lemma lookup_reselect add id keys current key reader :
 DependencyIndex.lookup key reader (reselect add id keys current) =
 if existsb (Pos.eqb key) keys && N.eqb reader id then if add then Some id else None
 else DependencyIndex.lookup key reader current.
Proof.
 unfold reselect. revert current.
 induction keys as [|first rest IH]; intro current; [reflexivity|].
 cbn [fold_left existsb]. rewrite IH.
 destruct add; rewrite ?DependencyIndex.lookup_include, ?DependencyIndex.lookup_exclude;
   destruct (Pos.eqb key first), (existsb (Pos.eqb key) rest), (N.eqb reader id); reflexivity.
Qed.

Definition remove_index {A addresses} id (table : @t A addresses) :=
 match lookup id (rows table) with
 | Some old => reselect false id (addresses old) (index table)
 | None => index table end.
Lemma lookup_remove_index {A addresses} id (table : @t A addresses) key reader :
 DependencyIndex.lookup key reader (remove_index id table) =
 if N.eqb reader id then None else DependencyIndex.lookup key reader (index table).
Proof.
 unfold remove_index. destruct (lookup id (rows table)) as [old|] eqn:Found.
 - rewrite lookup_reselect. destruct (N.eqb_spec reader id) as [->|Other].
   + rewrite Bool.andb_true_r, index_agrees, Found.
     now destruct (existsb (Pos.eqb key) (addresses old)).
   + now rewrite Bool.andb_false_r.
 - destruct (N.eqb_spec reader id) as [->|Other]; [now rewrite index_agrees, Found|reflexivity].
Qed.

Definition put {A addresses} (id : N) (value : A) (table : @t A addresses) : t addresses.
Proof.
 refine (Table A addresses (Slots.add (IndexedRegistry.key id) value (rows table))
   (id :: filter (fun old => negb (N.eqb old id)) (order table))
   (reselect true id (addresses value) (remove_index id table)) _).
 intros key reader. rewrite lookup_reselect, lookup_remove_index.
 unfold lookup at 1.
 destruct (N.eqb_spec reader id) as [->|Different].
 - rewrite Slots.gss, Bool.andb_true_r. reflexivity.
 - rewrite Slots.gso by (intro Same; apply Different; now apply IndexedRegistry.key_injective).
   rewrite Bool.andb_false_r. apply index_agrees.
Defined.
Definition remove {A addresses} (id : N) (table : @t A addresses) : t addresses.
Proof.
 refine (Table A addresses (Slots.remove (IndexedRegistry.key id) (rows table))
   (filter (fun old => negb (N.eqb old id)) (order table)) (remove_index id table) _).
 intros key reader. rewrite lookup_remove_index. unfold lookup at 1.
 destruct (N.eqb_spec reader id) as [->|Different].
 - now rewrite Slots.grs.
 - rewrite Slots.gro by (intro Same; apply Different; now apply IndexedRegistry.key_injective).
   apply index_agrees.
Defined.

Definition contents {A addresses} (table : @t A addresses) :=
 flat_map (fun id => match lookup id (rows table) with Some value => [value] | None => [] end) (order table).
Definition members {A addresses} key (table : @t A addresses) :=
 flat_map (fun id => match lookup id (rows table) with Some value => [value] | None => [] end)
   (DependencyIndex.members key (index table)).
Lemma selected_member {A addresses} key id value (table : @t A addresses) :
 lookup id (rows table) = Some value ->
 In key (addresses value) -> In value (members key table).
Proof.
 intros Found Selected. unfold members. apply in_flat_map. exists id.
 split; [|now rewrite Found; left].
 apply DependencyIndex.lookup_in_members with (source:=id).
 rewrite index_agrees, Found.
 assert (Active : existsb (Pos.eqb key) (addresses value) = true).
 { apply existsb_exists. exists key. split; [exact Selected|apply Pos.eqb_refl]. }
 now rewrite Active.
Qed.
Lemma contents_select_member {A addresses} key value (table : @t A addresses) :
 In value (contents table) -> In key (addresses value) -> In value (members key table).
Proof.
 intros Present Selected. unfold contents in Present.
 apply in_flat_map in Present. destruct Present as [id [_ AtId]].
 destruct (lookup id (rows table)) as [current|] eqn:Found; [|contradiction].
 destruct AtId as [<-|[]]. eapply selected_member; eassumption.
Qed.
