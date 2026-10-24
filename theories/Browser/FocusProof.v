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

Theorem retained_ineligible_activity_focuses_its_initial_target : forall identity initial restore_target fallback_target occurrence,
 request [Temporary identity initial restore_target fallback_target occurrence]
   [Temporary identity initial restore_target fallback_target occurrence] false = Some(initial,fallback_target).
Proof.
 intros. unfold request,top,transition,invalid_retained,changed,same_scope,
   same_occurrence,fallback.
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

Theorem published_document_recovers_its_lost_target : forall key,
 observed_request [Document] [Document] false (Some key) None = Some(key,key).
Proof. reflexivity. Qed.
Theorem published_document_keeps_an_observed_target : forall eligible before after,
 observed_request [Document] [Document] eligible before (Some after) = None.
Proof. intros; destruct before; reflexivity. Qed.
Theorem publication_does_not_invent_previous_focus : forall eligible,
 observed_request [Document] [Document] eligible None None = None.
Proof. reflexivity. Qed.

Theorem retained_loading_root_hands_focus_to_its_input : forall identity target restore fallback occurrence before,
 String.eqb identity target = false ->
 observed_request [Temporary identity identity restore fallback occurrence]
   [Temporary identity target restore fallback occurrence] true before (Some identity) = Some(target,fallback).
Proof.
 intros. unfold observed_request,request,top,transition,changed,invalid_retained,
   root_handoff,same_scope,same_occurrence,initial,Focus.fallback.
 simpl. rewrite String.eqb_refl. destruct occurrence; simpl; rewrite ?N.eqb_refl; simpl;
 now rewrite ?String.eqb_refl,H.
Qed.

Theorem retained_loading_root_respects_a_users_focus : forall identity target restore fallback occurrence before focused,
 String.eqb focused identity = false ->
 observed_request [Temporary identity identity restore fallback occurrence]
   [Temporary identity target restore fallback occurrence] true before (Some focused) = None.
Proof.
 intros. unfold observed_request,request,top,transition,changed,invalid_retained,
   root_handoff,same_scope,same_occurrence.
 simpl. rewrite String.eqb_refl. destruct occurrence; simpl; rewrite ?N.eqb_refl; simpl;
 now rewrite ?String.eqb_refl,H.
Qed.

Theorem hidden_temporary_child_recovers_to_a_visible_root : forall previous identity initial restore fallback occurrence eligible before focused,
 physical_request previous [Temporary identity initial restore fallback occurrence] eligible before (Some focused)
   false true true = Some(identity,identity).
Proof. reflexivity. Qed.
Theorem visible_temporary_focus_keeps_its_scope_policy : forall previous identity initial restore fallback occurrence eligible before after root_visible root_eligible,
 physical_request previous [Temporary identity initial restore fallback occurrence] eligible before after
   true root_visible root_eligible =
 observed_request previous [Temporary identity initial restore fallback occurrence] eligible before after.
Proof. intros; destruct after; reflexivity. Qed.
Theorem document_focus_keeps_its_scope_policy : forall previous eligible before after focused_visible root_visible root_eligible,
 physical_request previous [Document] eligible before after focused_visible root_visible root_eligible =
 observed_request previous [Document] eligible before after.
Proof. reflexivity. Qed.
