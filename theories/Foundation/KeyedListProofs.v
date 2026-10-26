From Stdlib Require Import List Bool.
From Selvedge.Foundation Require Import KeyedList.
Import ListNotations.

(* Keyed associations preserve list order and the first matching entry. These
   laws concern filtering by a key, independently of positional registries. *)
Lemma filtering_another_key_preserves_lookup :
 forall (A Key : Type) (key : A -> Key) (same : Key -> Key -> bool),
 (forall first second, same first second = true -> first = second) ->
 forall entries selected removed, selected <> removed ->
 find (fun entry => same selected (key entry))
   (filter (fun entry => negb (same removed (key entry))) entries) =
 find (fun entry => same selected (key entry)) entries.
Proof.
 intros A Key key same Reflects entries; induction entries as [|first rest IH];
   intros selected removed Different; [reflexivity|].
 cbn [filter find]; destruct (same removed (key first)) eqn:Removed;
   destruct (same selected (key first)) eqn:Selected; cbn;
   rewrite ?Selected; try reflexivity; try (apply IH; exact Different).
 apply Reflects in Removed, Selected; congruence.
Qed.

Lemma removing_a_key_clears_its_lookup :
 forall (A Key : Type) (key : A -> Key) (same : Key -> Key -> bool) entries removed,
 find (fun entry => same removed (key entry))
   (filter (fun entry => negb (same removed (key entry))) entries) = None.
Proof.
 intros A Key key same entries; induction entries as [|first rest IH]; intro removed; [reflexivity|].
 cbn [filter find]; destruct (same removed (key first)) eqn:Selected; cbn;
   rewrite ?Selected; apply IH.
Qed.

Lemma filtering_preserves_unique_keys : forall (A Key : Type) (key : A -> Key) keep entries,
 NoDup (map key entries) -> NoDup (map key (filter (fun entry => keep (key entry)) entries)).
Proof. intros; rewrite <- filter_map_swap; apply NoDup_filter; assumption. Qed.

Theorem keyed_retention_follows_each_lookup : forall Entry Key Value key lookup relation before after,
 (forall previous, In previous before -> relation previous (lookup (key previous) after) = true) ->
 @KeyedList.retains Entry Key Value key lookup relation before after = true.
Proof. intros; apply forallb_forall; assumption. Qed.
