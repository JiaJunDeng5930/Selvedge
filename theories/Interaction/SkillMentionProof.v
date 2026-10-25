From Stdlib Require Import String Bool Arith Lia.
From Selvedge.Interaction Require Import SkillMention.

Theorem mention_ignored_during_composition : forall text start finish,
  detect text start finish true = None.
Proof. reflexivity. Qed.

Theorem mention_requires_a_caret : forall text start finish composing,
  start <> finish -> detect text start finish composing = None.
Proof.
  intros text start finish composing different; unfold detect.
  assert (Nat.eqb start finish = false) by (apply Nat.eqb_neq; assumption).
  rewrite H; destruct composing; reflexivity.
Qed.

Theorem mention_requires_a_buffer_position : forall text start composing,
  String.length text < start -> detect text start start composing = None.
Proof.
  intros text start composing outside; unfold detect.
  assert (Nat.leb start (String.length text) = false) by (apply Nat.leb_gt; assumption).
  rewrite H; destruct composing; rewrite Bool.orb_true_r; reflexivity.
Qed.

Theorem moved_selection_is_a_candidate : forall backwards selected count,
  0 < count -> move_index backwards selected count < count.
Proof.
  intros backwards selected count positive; unfold move_index.
  destruct count; [lia|].
  pose proof (Nat.mod_upper_bound selected (S count) ltac:(lia)) as bounded.
  destruct backwards.
  - destruct (Nat.eqb (selected mod S count) 0); lia.
  - destruct (Nat.ltb (S (selected mod S count)) (S count)) eqn:next;
      [apply Nat.ltb_lt in next; lia | lia].
Qed.

Local Lemma prefix_slice first rest :
 substring 0 (String.length first) (first ++ rest) = first.
Proof. induction first; [destruct rest; reflexivity|cbn; rewrite IHfirst; reflexivity]. Qed.
Local Lemma full_slice text count : String.length text <= count ->
 substring 0 count text = text.
Proof. revert count. induction text; intros [|count] Enough; cbn in *; try lia; f_equal; auto with arith. Qed.
Local Lemma append_size first rest : String.length(first ++ rest)=String.length first+String.length rest.
Proof. induction first; cbn; congruence. Qed.
Local Lemma suffix_slice first rest count : String.length rest<=count ->
 substring (String.length first) count (first ++ rest)=rest.
Proof. induction first; intros Enough; cbn; [apply full_slice; exact Enough|apply IHfirst; exact Enough]. Qed.

Local Lemma concat_assoc first second third : first ++ (second ++ third) = (first ++ second) ++ third.
Proof. induction first; cbn; congruence. Qed.

Theorem selected_reference_preserves_surrounding_text before replaced after chosen :
 let found := Trigger (String.length before) (String.length (before ++ replaced)) replaced in
 let inserted := insert (before ++ replaced ++ after) found chosen in
 insertion_text inserted = before ++ replacement chosen after ++ after /\
 insertion_caret inserted = String.length before + String.length(replacement chosen after).
Proof.
 cbn [insert insertion_text insertion_caret trigger_start trigger_end Json.substring].
 rewrite prefix_slice.
 assert (Suffix : substring (String.length(before ++ replaced))
   (String.length(before ++ replaced ++ after)) (before ++ replaced ++ after)=after).
 { rewrite concat_assoc. apply suffix_slice. repeat rewrite append_size. lia. }
 unfold Json.substring. rewrite Suffix. split; reflexivity.
Qed.
