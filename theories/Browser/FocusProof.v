From Stdlib Require Import Bool String List NArith.
Import ListNotations.
From Selvedge.Browser Require Import Focus.

Theorem retained_document_keeps_focus : forall eligible,
  transition Document Document eligible = false.
Proof. reflexivity. Qed.
Theorem invalid_retained_activity_requests_focus : forall identity initial restore fallback occurrence previous,
  transition previous (Temporary identity initial restore fallback occurrence) false = true.
Proof. intros; unfold transition; simpl; apply orb_true_r. Qed.
Theorem same_activity_occurrence_keeps_eligible_focus : forall identity initial restore fallback occurrence,
  transition (Temporary identity initial restore fallback occurrence)
    (Temporary identity initial restore fallback occurrence) true = false.
Proof.
  intros; unfold transition, changed, invalid_retained, same_occurrence; simpl.
  rewrite String.eqb_refl; destruct occurrence; simpl; rewrite ?N.eqb_refl; reflexivity.
Qed.

Theorem retained_ineligible_activity_focuses_its_container : forall identity initial restore_target fallback_target occurrence,
 request [Temporary identity initial restore_target fallback_target occurrence]
   [Temporary identity initial restore_target fallback_target occurrence] false = Some(identity,fallback_target).
Proof.
 intros. unfold request,top,transition,invalid_retained,changed,same_scope,
   same_occurrence,retained_scope_target,fallback.
 simpl. rewrite String.eqb_refl. destruct occurrence; simpl; rewrite ?N.eqb_refl; reflexivity.
Qed.

Theorem opening_activity_keeps_its_initial_focus : forall identity initial restore fallback occurrence,
 request [Document] [Temporary identity initial restore fallback occurrence] false = Some(initial,fallback).
Proof. reflexivity. Qed.

(** Popping a child activity returns to its invoking control in the still-open
    owner; it must not restart that owner's initial focus policy. *)
Theorem closing_child_restores_owner : forall parent child
 parent_initial parent_restore parent_fallback parent_occurrence
 child_initial child_restore child_fallback child_occurrence eligible,
 String.eqb child parent = false ->
 request
  [Temporary parent parent_initial parent_restore parent_fallback parent_occurrence;
   Temporary child child_initial child_restore child_fallback child_occurrence]
  [Temporary parent parent_initial parent_restore parent_fallback parent_occurrence]
  eligible = Some(child_restore,parent_initial).
Proof.
 intros. unfold request,top,transition,changed,invalid_retained,same_scope.
 simpl. rewrite H,String.eqb_refl. simpl.
 destruct parent_occurrence; simpl; rewrite ?N.eqb_refl; reflexivity.
Qed.

Theorem exact_focus_target_precedes_aliases requested preferred candidates found:
 find(fun candidate=>String.eqb requested(target_key candidate))candidates=Some found ->
 resolve requested preferred candidates=Some(target_key found).
Proof. intro Found; unfold resolve; now rewrite Found. Qed.
Theorem existing_return_target_precedes_fallback requested fallback preferred candidates key:
 resolve requested preferred candidates=Some key ->
 resolve_return requested fallback preferred candidates=Some key.
Proof. intro Found; unfold resolve_return; now rewrite Found. Qed.
Theorem missing_return_target_uses_declared_fallback requested fallback preferred candidates:
 resolve requested preferred candidates=None ->
 resolve_return requested fallback preferred candidates=resolve fallback preferred candidates.
Proof. intro Missing; unfold resolve_return; now rewrite Missing. Qed.
