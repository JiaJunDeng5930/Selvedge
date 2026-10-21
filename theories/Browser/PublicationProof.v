From Stdlib Require Import Bool NArith.
From Selvedge.Browser Require Import Publication.

Theorem semantic_change_invalidates_old_element : forall current requested,
  admit requested (advance current) = false.
Proof. intros; unfold admit, advance; simpl; apply andb_false_r. Qed.
Theorem unpublished_document_is_not_ready : forall generation namespace sequence,
  fresh (State generation Prepared namespace sequence) = false.
Proof. reflexivity. Qed.
Theorem publication_needs_current_prepared_document : forall current requested,
  current_phase current = AwaitingDocument -> publish requested current = current.
Proof. intros current requested phase; unfold publish; destruct (N.eqb requested (generation current)); rewrite ?phase; reflexivity. Qed.
Theorem stale_document_cannot_advance_publication : forall current requested,
  requested <> generation current -> document_ready requested current = current.
Proof. intros current requested stale; unfold document_ready; apply N.eqb_neq in stale; rewrite stale; reflexivity. Qed.
Theorem stale_completion_cannot_advance_publication : forall current requested,
  requested <> generation current -> publish requested current = current.
Proof. intros current requested stale; unfold publish; apply N.eqb_neq in stale; rewrite stale; reflexivity. Qed.
