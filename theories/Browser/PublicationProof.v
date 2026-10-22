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

Theorem superseded_authentication_cannot_install_its_snapshot : forall
  ticket connection expected incoming incoming_sequence current,
  Services.connection_matches ticket connection = false ->
  admit_authenticated_snapshot ticket connection expected incoming incoming_sequence current = false.
Proof.
  intros ticket connection expected incoming incoming_sequence current Stale.
  unfold admit_authenticated_snapshot. rewrite Stale, andb_false_r. reflexivity.
Qed.
Theorem inactive_connection_cannot_install_an_authenticated_snapshot : forall
  ticket connection expected incoming incoming_sequence current,
  Services.connection_active connection = false ->
  admit_authenticated_snapshot ticket connection expected incoming incoming_sequence current = false.
Proof.
  intros ticket connection expected incoming incoming_sequence current Inactive.
  unfold admit_authenticated_snapshot. rewrite Inactive. reflexivity.
Qed.

Theorem an_admission_refresh_does_not_restore_connection_freshness : forall accepted,
  snapshot_freshness ExistingSession accepted false = false.
Proof. intro accepted; destruct accepted; reflexivity. Qed.
Theorem an_admission_refresh_retains_connection_observation : forall accepted previous,
  snapshot_freshness ExistingSession accepted previous = previous.
Proof. intros accepted previous; destruct accepted; reflexivity. Qed.
Theorem accepted_authentication_restores_fresh_sources : forall previous,
  snapshot_freshness Authentication true previous = true.
Proof. reflexivity. Qed.
Theorem rejected_snapshots_retain_source_freshness : forall origin previous,
  snapshot_freshness origin false previous = previous.
Proof. reflexivity. Qed.
