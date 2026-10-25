From Stdlib Require Import String Bool NArith.
From Selvedge.Browser Require Import Publication.

Theorem retained_document_keeps_its_input_authority current requested :
 admit requested(advance current)=admit requested current.
Proof. unfold admit,advance; reflexivity. Qed.
Theorem unpublished_document_is_not_ready : forall generation namespace sequence,
 fresh(State generation Prepared namespace sequence None)=false.
Proof. reflexivity. Qed.
Theorem a_prepared_document_has_no_input_authority generation namespace sequence requested :
 admit requested(State generation Prepared namespace sequence None)=false.
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
  unfold admit_authenticated_snapshot, admit_authentication. rewrite Stale, andb_false_r. reflexivity.
Qed.
Theorem inactive_connection_cannot_install_an_authenticated_snapshot : forall
  ticket connection expected incoming incoming_sequence current,
  Services.connection_active connection = false ->
  admit_authenticated_snapshot ticket connection expected incoming incoming_sequence current = false.
Proof.
  intros ticket connection expected incoming incoming_sequence current Inactive.
  unfold admit_authenticated_snapshot, admit_authentication. rewrite Inactive. reflexivity.
Qed.

Theorem an_admission_refresh_does_not_restore_connection_freshness : forall accepted,
  snapshot_freshness ExistingSession accepted false = false.
Proof. intro accepted; destruct accepted; reflexivity. Qed.
Theorem an_admission_refresh_retains_connection_observation : forall accepted previous,
  snapshot_freshness ExistingSession accepted previous = previous.
Proof. intros accepted previous; destruct accepted; reflexivity. Qed.
Theorem owned_authentication_restores_fresh_sources : forall previous,
  snapshot_freshness Authentication true previous = true.
Proof. reflexivity. Qed.
Theorem unauthenticated_observations_retain_source_freshness : forall origin previous,
  snapshot_freshness origin false previous = previous.
Proof. reflexivity. Qed.

Theorem invalid_namespace_cannot_install_a_snapshot : forall origin expected incoming seq current,
 Origin.valid_namespace incoming=false -> admit_snapshot origin expected incoming seq current=false.
Proof. intros. unfold admit_snapshot. now rewrite H. Qed.
Theorem foreign_completion_cannot_settle_a_request : forall expected incoming current,
 String.eqb incoming(namespace current)=false -> admit_completion expected incoming current=false.
Proof. intros. unfold admit_completion. rewrite H. apply andb_false_r. Qed.
Theorem invalid_commit_sequence_refreshes : forall ns fresh connection current,
 refresh_needed ns None fresh connection current=true.
Proof. intros. destruct ns; reflexivity. Qed.
Theorem recovery_survives_source_replacement : forall reason current,
 recovery_reason(invalidate(failed reason current))=Some reason.
Proof. reflexivity. Qed.
Theorem observation_cannot_dismiss_recovery : forall reason current,
 recovery_reason(advance(failed reason current))=Some reason.
Proof. reflexivity. Qed.
Theorem retry_reopens_document_preparation : forall current,
 current_phase(retry current)=AwaitingDocument /\ recovery_reason(retry current)=None.
Proof. split; reflexivity. Qed.

Theorem equal_cursor_keeps_the_installed_world : forall current,
 install_snapshot(namespace current)(sequence current)current=false.
Proof. intro; unfold install_snapshot; now rewrite String.eqb_refl,N.ltb_irrefl. Qed.

Theorem presentation_preserves_semantic_pending : forall current,
 semantic_pending(present current)=semantic_pending current.
Proof. intro; destruct current as [generation phase namespace sequence displayed]; destruct phase; reflexivity. Qed.
Theorem unpublished_semantic_change_survives_presentation : forall current,
 semantic_pending(present(advance current))=true.
Proof. intro; destruct current as [generation phase namespace sequence displayed]; destruct phase; reflexivity. Qed.
Theorem prepared_presentation_preserves_semantic_freshness generation namespace sequence :
 semantic_pending(State generation PreparedPresentation namespace sequence None)=false /\
 admit generation(State generation PreparedPresentation namespace sequence None)=false.
Proof. split;reflexivity. Qed.
Theorem remeasurement_preserves_display_readiness_and_admission generation displayed namespace sequence :
 fresh(State generation AwaitingPresentation namespace sequence(Some displayed))=true /\
 admit displayed(State generation AwaitingPresentation namespace sequence(Some displayed))=true.
Proof. split;[reflexivity|apply N.eqb_refl]. Qed.
Theorem renderer_receipt_establishes_the_displayed_identity generation namespace sequence requested :
 requested=generation ->
 displayed_generation(publish requested(State generation Prepared namespace sequence None))=Some requested.
Proof. intro Same;subst;unfold publish;simpl;now rewrite N.eqb_refl. Qed.
Theorem newer_cursor_rejects_an_older_request_failure expected seq ticket connection current :
 N.eqb seq (sequence current)=false ->
 admit_request_failure expected seq ticket connection current=false.
Proof. intros Older; unfold admit_request_failure; rewrite Older,andb_false_r; reflexivity. Qed.
Theorem superseded_connection_rejects_a_request_failure expected seq ticket connection current :
 Services.connection_matches ticket connection=false ->
 admit_request_failure expected seq ticket connection current=false.
Proof. intros Stale; unfold admit_request_failure; rewrite Stale,andb_false_r; reflexivity. Qed.
