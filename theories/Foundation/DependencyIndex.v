From Stdlib Require Import String Ascii List NArith Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require IndexedRegistry.
Import ListNotations.
Open Scope N_scope.

Module Slots := IndexedRegistry.Slots.
Definition t (A : Type) := Slots.t (Slots.t A).
Definition values {A} (entries : Slots.t A) := map snd (Slots.elements entries).
Definition members {A} (key : positive) (index : t A) : list A :=
 match Slots.find key index with
 | Some entries => values entries
 | None => []
 end.

Definition include {A} key source (value : A) (index : t A) :=
 let entries := match Slots.find key index with
   | Some entries => entries | None => Slots.empty A end in
 Slots.add key (Slots.add (IndexedRegistry.key source) value entries) index.

Definition exclude {A} key source (index : t A) :=
 match Slots.find key index with
 | None => index
 | Some entries =>
   let remaining := Slots.remove (IndexedRegistry.key source) entries in
   match remaining with
   | @Slots.Leaf _ => Slots.remove key index
   | _ => Slots.add key remaining index
   end
 end.

Definition lookup {A} key source (index : t A) :=
 match Slots.find key index with
 | Some entries => Slots.find (IndexedRegistry.key source) entries
 | None => None
 end.
Lemma lookup_in_members {A} key source (value : A) index :
 lookup key source index = Some value -> In value (members key index).
Proof.
 unfold lookup, members, values. destruct (Slots.find key index) as [entries|]; [|discriminate].
 intro Found. apply in_map_iff. exists (IndexedRegistry.key source, value).
 split; [reflexivity|now apply Slots.elements_correct].
Qed.
Lemma lookup_include {A} key source (value : A) index observed id :
 lookup observed id (include key source value index) =
 if Pos.eqb observed key && N.eqb id source then Some value else lookup observed id index.
Proof.
 unfold lookup, include. destruct (Pos.eqb_spec observed key) as [->|Other].
 - rewrite Slots.gss. destruct (N.eqb_spec id source) as [->|Different]; [apply Slots.gss|].
   rewrite Slots.gso by (intro Same; apply Different; now apply IndexedRegistry.key_injective).
   destruct (Slots.find key index); [reflexivity|apply Slots.gempty].
 - rewrite Slots.gso by exact Other. reflexivity.
Qed.
Lemma lookup_exclude {A} key source (index : t A) observed id :
 lookup observed id (exclude key source index) =
 if Pos.eqb observed key && N.eqb id source then None else lookup observed id index.
Proof.
 unfold lookup, exclude.
 destruct (Slots.find key index) as [entries|] eqn:Found.
 - destruct (Pos.eqb_spec observed key) as [->|Other].
   + assert (Read : Slots.find (IndexedRegistry.key id) (Slots.remove (IndexedRegistry.key source) entries) =
       if N.eqb id source then None else Slots.find (IndexedRegistry.key id) entries).
     { destruct (N.eqb_spec id source) as [->|Different]; [apply Slots.grs|].
       apply Slots.gro. intro Same; apply Different; now apply IndexedRegistry.key_injective. }
     destruct (Slots.remove (IndexedRegistry.key source) entries) as [|left row right].
     * rewrite Slots.grs, Found. cbn [andb]. rewrite <- Read. symmetry; apply Slots.gempty.
     * rewrite Slots.gss, Found. exact Read.
   + destruct (Slots.remove (IndexedRegistry.key source) entries); [now rewrite Slots.gro|now rewrite Slots.gso].
 - destruct (Pos.eqb_spec observed key) as [->|Other]; [now rewrite Found; destruct (N.eqb id source)|reflexivity].
Qed.

Fixpoint text_address (name : string) : positive :=
 match name with
 | EmptyString => xH
 | String (Ascii a b c d e f g h) rest =>
   let bit (flag : bool) next := if flag then xI next else xO next in
   bit a (bit b (bit c (bit d (bit e (bit f (bit g (bit h (text_address rest))))))))
 end.

Definition registry_changes {A} (before current : IndexedRegistry.t A) :=
 IndexedRegistry.changes shared_value shared_value before current.

Definition changed_ids {A} (before current : IndexedRegistry.t A) : list N :=
 match registry_changes before current with
 | Some differences => map (IndexedRegistry.difference_id A) differences
 | None => map (fun entry => N.pred (N.pos (fst entry))) (Slots.elements (IndexedRegistry.entries current))
 end.

Definition project {A B} (empty : B)
 (install : N -> A -> B -> B) (remove : N -> A -> B -> B) : IndexedRegistry.t A -> B :=
 let rebuild current := Slots.fold
   (fun address value index => install (N.pred (N.pos address)) value index)
   (IndexedRegistry.entries current) empty in
 reuse_projection rebuild (fun before current index =>
   match registry_changes before current with
   | None => match registry_changes current before with
     | None => rebuild current
     | Some differences => fold_left (fun index difference =>
         let id := IndexedRegistry.difference_id A difference in
         let index := remove id (IndexedRegistry.difference_after A difference) index in
         match IndexedRegistry.difference_before A difference with
         | Some current => install id current index | None => index end)
         differences index
     end
   | Some differences => fold_left (fun index difference =>
       let id := IndexedRegistry.difference_id A difference in
       let index := match IndexedRegistry.difference_before A difference with
         | Some previous => remove id previous index | None => index end in
       install id (IndexedRegistry.difference_after A difference) index)
       differences index
   end).
