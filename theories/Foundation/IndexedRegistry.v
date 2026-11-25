From Stdlib Require Import List NArith Bool FSets.FMapPositive.
Import ListNotations.
Open Scope N_scope.

Module Slots := PositiveMap.
Arguments Slots.Leaf {A}.
Arguments Slots.Node {A} _ _ _.

(** The next identity is part of the dense registry. A position uses the
    positive key [id + 1] and therefore has a path independent of other
    positions. Insertion rebuilds only nodes on that path. *)
Definition key := N.succ_pos.
Lemma key_injective left right : key left = key right -> left = right.
Proof.
 intro Equal. apply N.succ_inj.
 rewrite <- !N.succ_pos_spec. now unfold key in Equal; rewrite Equal.
Qed.

Record t (A : Type) := Registry {
 next : N;
 entries : Slots.t A;
 filled : forall id, id < next <-> exists value, Slots.find (key id) entries = Some value
}.
Arguments next {A}.
Arguments entries {A}.
Arguments filled {A}.

Definition lookup {A} (id : N) (registry : t A) := Slots.find (key id) (entries registry).

Definition empty {A} : t A.
Proof.
 refine (Registry A 0 (Slots.empty A) _).
 intros id. rewrite Slots.gempty. split.
 - intros Negative. exfalso. exact (N.nlt_0_r id Negative).
 - intros [? Impossible]. discriminate.
Defined.

Definition append {A} (value : A) (registry : t A) : t A.
Proof.
 refine (Registry A (N.succ (next registry))
  (Slots.add (key (next registry)) value (entries registry)) _).
 intros id. destruct (N.eq_dec id (next registry)) as [Same|Different].
 - subst; rewrite Slots.gss; split; [eauto|intros _; apply N.lt_succ_diag_r].
 - rewrite Slots.gso by (intros Equal; apply Different; now apply key_injective).
   rewrite <- filled, N.lt_succ_r, N.le_lteq. split.
   + intros [Within|Equal]; [exact Within|contradiction].
   + intros Within; left; exact Within.
Defined.

Definition put {A} (id : N) (value : A) (registry : t A) : t A.
Proof.
 destruct (N.ltb_spec0 id (next registry)) as [Exists|]; [|exact registry].
 refine (Registry A (next registry) (Slots.add (key id) value (entries registry)) _).
 intros other. destruct (N.eq_dec other id) as [Same|Different].
 - subst; rewrite Slots.gss; split; [eauto|intros _; exact Exists].
 - rewrite Slots.gso by (intros Equal; apply Different; now apply key_injective).
   apply filled.
Defined.

(** Only a collection read needs an ordered list. Point operations use the
    same dense registry directly. *)
Fixpoint collect {A} (registry : t A) (start : N) (count : nat) : list A :=
 match count with
 | O => []
 | S count =>
   match lookup start registry with
   | Some value => value :: collect registry (N.succ start) count
   | None => []
   end
 end.

Definition contents {A} (registry : t A) := collect registry 0 (N.to_nat (next registry)).
Definition extend {A} (values : list A) (registry : t A) :=
 fold_left (fun acc value => append value acc) values registry.
Definition from_list {A} (values : list A) := extend values empty.

Record difference (A : Type) := Difference {
 difference_id : N;
 difference_before : option A;
 difference_after : A
}.

Fixpoint diff_trie {A} (same_tree : Slots.t A -> Slots.t A -> bool)
 (same_value : A -> A -> bool) (before after : Slots.t A)
 (low place : N) (changes : list (difference A)) {struct after}
 : option (list (difference A)) :=
 if same_tree before after then Some changes else
 match after with
 | Slots.Leaf => match before with Slots.Leaf=>Some changes | Slots.Node _ _ _=>None end
 | Slots.Node current_even current_value current_odd =>
 let '(prior_even, prior_value, prior_odd) :=
   match before with Slots.Leaf => (Slots.Leaf,None,Slots.Leaf) | Slots.Node e v o => (e,v,o) end in
 let current_changes := match prior_value, current_value with
  | None, None => Some changes
  | Some _, None => None
  | Some prior, Some current => if same_value prior current then Some changes
    else Some (Difference A (N.pred (low + place)) prior_value current :: changes)
  | None, Some current => Some (Difference A (N.pred (low + place)) None current :: changes)
 end in
 let step := N.double place in
 match current_changes with
 | None=>None
 | Some changed =>
  match diff_trie same_tree same_value prior_odd current_odd (low + place) step changed with
  | None=>None
  | Some changed=>diff_trie same_tree same_value prior_even current_even low step changed
  end
 end
 end.

Definition changes {A} same_tree same_value (before after : t A) :=
 diff_trie same_tree same_value (entries before) (entries after) 0 1 [].
