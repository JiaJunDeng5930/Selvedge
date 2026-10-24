From Stdlib Require Import String List Bool Sorting.Permutation.
From Selvedge.Foundation Require Import Json JsonObjects.
Import ListNotations.

Theorem equivalent_is_reflexive : forall value, equivalent value value = true.
Proof.
 fix recur 1. intro value. destruct value; cbn.
 - reflexivity.
 - apply Bool.eqb_reflx.
 - apply String.eqb_refl.
 - apply String.eqb_refl.
 - induction values as [|head rest IH]; cbn; [reflexivity|].
   rewrite recur, IH. reflexivity.
 - induction fields as [|[key value] rest IH]; cbn; [reflexivity|].
   rewrite String.eqb_refl. cbn. rewrite recur, IH. reflexivity.
Qed.

(** Objects preserve their key/value associations regardless of field order;
    arrays retain order, and scalar values retain their exact representation. *)
Inductive same_json_meaning : json -> json -> Prop :=
| SameNull : same_json_meaning JNull JNull
| SameBool value : same_json_meaning (JBool value) (JBool value)
| SameNumber spelling : same_json_meaning (JNumber spelling) (JNumber spelling)
| SameText text : same_json_meaning (JString text) (JString text)
| SameArray left right : Forall2 same_json_meaning left right ->
    same_json_meaning (JArray left) (JArray right)
| SameObject left reordered right :
    Forall2 (fun a b => fst a = fst b /\ same_json_meaning (snd a) (snd b)) left reordered ->
    Permutation reordered right -> same_json_meaning (JObject left) (JObject right).

Lemma selected_field_preserves_members : forall key fields value remaining,
  select_field key fields = Some (value, remaining) ->
  Permutation ((key, value) :: remaining) fields.
Proof.
 intros key fields. induction fields as [|[name item] rest IH]; intros value remaining Found; cbn in Found.
 - discriminate.
 - destruct (String.eqb key name) eqn:Name.
   + apply String.eqb_eq in Name; subst. inversion Found; subst. apply Permutation_refl.
   + destruct (select_field key rest) as [[selected tail]|] eqn:Selected; try discriminate.
     inversion Found; subst. eapply Permutation_trans; [apply perm_swap|].
     apply perm_skip. apply IH. reflexivity.
Qed.

Theorem equivalent_preserves_json_meaning : forall left right,
  equivalent left right = true -> same_json_meaning left right.
Proof.
 fix recur 1. intros left right Same.
 destruct left as [|left|left|left|left|left];
 destruct right as [|right|right|right|right|right]; cbn in Same; try discriminate.
 - constructor.
 - apply Bool.eqb_prop in Same; subst. constructor.
 - apply String.eqb_eq in Same; subst. constructor.
 - apply String.eqb_eq in Same; subst. constructor.
 - apply SameArray. revert right Same.
   induction left as [|item rest IH]; intros [|other tail] Same; cbn in Same; try discriminate.
   + constructor.
   + apply andb_true_iff in Same as [Head Tail]. constructor.
     * apply recur. exact Head.
     * apply IH. exact Tail.
 - assert (Matching : exists reordered,
       Forall2 (fun a b => fst a = fst b /\ same_json_meaning (snd a) (snd b)) left reordered /\
       Permutation reordered right).
   { revert right Same. induction left as [|[key value] rest IH]; intros right Same; cbn in Same.
     - destruct right; try discriminate. exists []; split; constructor.
     - destruct (select_field key right) as [[other remaining]|] eqn:Selected; try discriminate.
       apply andb_true_iff in Same as [Head Tail].
       destruct (IH remaining Tail) as [reordered [Related Permuted]].
       exists ((key, other) :: reordered). split.
       + constructor; [split; [reflexivity|apply recur; exact Head]|exact Related].
       + eapply Permutation_trans; [apply perm_skip; exact Permuted|].
         apply selected_field_preserves_members. exact Selected. }
   destruct Matching as [reordered [Related Permuted]].
   eapply SameObject; eassumption.
Qed.

Theorem distinct_fields_can_swap : forall prefix first second left right suffix,
  first <> second ->
  equivalent (JObject (prefix ++ (first, left) :: (second, right) :: suffix))
    (JObject (prefix ++ (second, right) :: (first, left) :: suffix)) = true.
Proof.
 intros prefix first second left right suffix Different.
 induction prefix as [|[key value] rest IH]; cbn.
 - assert (Names : String.eqb first second = false) by (apply String.eqb_neq; exact Different).
   rewrite Names, String.eqb_refl. cbn.
   rewrite String.eqb_refl. cbn.
   rewrite !equivalent_is_reflexive.
   change (equivalent (JObject suffix) (JObject suffix) = true).
   apply equivalent_is_reflexive.
 - rewrite String.eqb_refl. cbn. rewrite equivalent_is_reflexive. exact IH.
Qed.
