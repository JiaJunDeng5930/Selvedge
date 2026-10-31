From Stdlib Require Import List Bool NArith Lia.
From Selvedge.Programming Require Import Constructor Focus.
From Selvedge.Foundation Require Import Registry RegistryProofs KeyedListProofs.
From Selvedge.Programming Require Import Receiver.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

Lemma at_put_at : forall entry (entries : list entry) position value,
 N.leb position (N.of_nat (List.length entries)) = true ->
 registry_at position (put_at position value entries) = Some value.
Proof.
 intros entry entries position value Bound; apply N.leb_le in Bound.
 unfold put_at; destruct (N.eqb position (N.of_nat (List.length entries))) eqn:Append.
 - apply N.eqb_eq in Append; subst position. apply registry_lookup_at_appended_index.
 - apply N.eqb_neq in Append.
   destruct (registry_lookup_exists_below_length entry entries position ltac:(lia)) as [old Found].
   eapply registry_replace_selected; exact Found.
Qed.

(** Every composition retrieves the exact input that was installed. New domain
    protocols compose paths and constructors; they add no law or proof case. *)
Theorem installed : forall state input (selected : t state input) request before,
 positioned selected before ->
 lookup selected request (install selected request before) = Some request.
Proof.
 intros state input selected; induction selected; intros request before Position; cbn in *;
 unfold lookup in *; cbn in *.
 - now rewrite N.eqb_refl.
 - apply at_put_at; apply N.leb_le. destruct Position as [Append|[value Found]].
   + rewrite Append; apply N.le_refl.
   + pose proof (registry_lookup_implies_position_bound _ _ _ _ Found); lia.
 - apply at_put_at; apply N.leb_le. destruct Position as [Append|[value Found]].
   + rewrite Append; apply N.le_refl.
   + pose proof (registry_lookup_implies_position_bound _ _ _ _ Found); lia.
 - rewrite set_get; now apply IHselected.
 - rewrite Focus.modification_has_its_selected_value; now apply IHselected.
 - rewrite IHselected by assumption; apply Constructor.project_inject.
 - rewrite IHselected by assumption; rewrite set_get; apply Constructor.project_inject.
Qed.
Arguments installed {state input}.


Theorem lookup_has_position : forall state input (selected : t state input) request before found,
 lookup selected request before = Some found -> positioned selected before.
Proof.
 intros state input selected; induction selected; intros request before found Found;
 unfold lookup in *; cbn in *.
 - exact I.
 - right; eauto.
 - right; eauto.
 - eapply IHselected; exact Found.
 - eapply IHselected; exact Found.
 - destruct (read_at selected (address selected (constructor request)) before) as [stored|] eqn:Stored;
   [eapply IHselected; exact Stored|discriminate].
 - destruct (read_at selected _ before) as [stored|] eqn:Stored;
   [eapply IHselected; exact Stored|discriminate].
Qed.
Arguments lookup_has_position {state input}.

(** Reads at any other address observe the original entry. The path language
    carries this law through fields, constructor views and focused records. *)
Theorem other_address : forall state input (selected : t state input) request before identity,
 identity <> address selected request ->
 read_at selected identity (install selected request before) = read_at selected identity before.
Proof.
 intros state input selected; induction selected; intros request before identity Different; cbn in *.
 - assert (Other : N.eqb identity (n request) = false) by (apply N.eqb_neq; exact Different).
   rewrite Other. eapply filtering_another_key_preserves_lookup;
   [intros; now apply N.eqb_eq|exact Different].
 - unfold put_at; destruct (N.eqb n (N.of_nat (List.length before))) eqn:Append.
   + apply N.eqb_eq in Append; subst n. apply registry_append_preserves_other_lookup; exact Different.
   + apply registry_replace_other; congruence.
 - unfold put_at; destruct (N.eqb n (N.of_nat (List.length (fst before)))) eqn:Append.
   + apply N.eqb_eq in Append; subst n. apply registry_append_preserves_other_lookup; exact Different.
   + apply registry_replace_other; congruence.
 - rewrite set_get; now apply IHselected.
 - rewrite Focus.modification_has_its_selected_value; now apply IHselected.
 - now rewrite IHselected.
 - now rewrite IHselected.
Qed.
Arguments other_address {state input}.

Theorem keyed_read_has_address : forall entry (key : entry -> N) identity entries value,
 read_at (keyed key) identity entries = Some value -> key value = identity.
Proof.
 intros entry key identity entries value Found.
 apply find_some in Found as [_ Selected]; apply N.eqb_eq in Selected; symmetry; exact Selected.
Qed.
