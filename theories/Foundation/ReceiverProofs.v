From Stdlib Require Import List Bool NArith Lia.
From Selvedge.Foundation Require Import Constructor Focus Registry RegistryProofs Receiver.
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
 available selected request before = true ->
 lookup selected (install selected request before) = Some request.
Proof.
 intros state input selected; induction selected; intros request before Available; cbn in *.
 - now rewrite Available.
 - now apply at_put_at.
 - now apply at_put_at.
 - rewrite set_get; now apply IHselected.
 - rewrite Focus.modification_has_its_selected_value; now apply IHselected.
 - rewrite IHselected by assumption; apply Constructor.project_inject.
 - rewrite IHselected by assumption; rewrite set_get; apply Constructor.project_inject.
Qed.
Arguments installed {state input}.
