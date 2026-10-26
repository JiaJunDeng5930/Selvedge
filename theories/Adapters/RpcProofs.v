From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Rpc.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem correlated_identity_is_pending : forall state observed id,
  correlate state observed = Some id ->
  canonical_natural observed = true /\ In id state.(pending).
Proof.
  intros state observed id.
  unfold correlate, issued.
  destruct (canonical_natural observed && contains (nat_value observed) (pending state)) eqn:H;
    intro E; inversion E; subst.
  apply andb_true_iff in H as [C H]. split; [exact C|].
  apply existsb_exists in H as [value [member same]].
  apply N.eqb_eq in same; subst; assumption.
Qed.

Theorem consumed_identity_cannot_remain_pending : forall id ids,
  ~ In id (retire id ids).
Proof.
  intros id ids H. unfold retire in H.
  apply filter_In in H as [_ H].
  rewrite N.eqb_refl in H. discriminate.
Qed.

Theorem unrelated_pending_identity_is_preserved : forall id other ids,
  other <> id -> (In other (retire id ids) <-> In other ids).
Proof.
  intros id other ids different. unfold retire.
  rewrite filter_In. split; [tauto|].
  intro H. split; [exact H|].
  apply negb_true_iff, N.eqb_neq. exact different.
Qed.

Theorem response_consumes_exactly_its_correlated_identity : forall state source message id,
  action_pending (response state source message id) = retire id state.(pending).
Proof.
  intros state source message id. unfold response.
  destruct (Bool.eqb (has message "result") (has message "error")); [reflexivity|].
  destruct (has message "result"); [destruct (contains id (preparable state)); reflexivity|].
  destruct (is_object (get message "error")); [|reflexivity].
  destruct (has (get message "error") "message"); [|reflexivity].
  destruct (as_string (get (get message "error") "message")); reflexivity.
Qed.

Theorem materialization_reserves_and_removes_its_pending_identity state id value :
  ~ In id (action_pending (reserve_materialization state id value)) /\
  In id (action_materializing (reserve_materialization state id value)).
Proof.
  split; [apply consumed_identity_cannot_remain_pending|cbn; auto].
Qed.

Theorem unreserved_materialization_cannot_settle state source :
  contains (nat_value (get source "id")) (materializing state) = false ->
  prepared state source = encode_action (unchanged "ignore" state []).
Proof.
  intro H. unfold prepared. rewrite H, andb_false_r. reflexivity.
Qed.

Theorem consumed_materialization_cannot_remain_active state id kind payload :
  ~ In id (action_materializing (consume kind state id payload)).
Proof. apply consumed_identity_cannot_remain_pending. Qed.

(** This constrains the decoded entry used by the extracted dispatcher, rather
    than a second specification function with identical implementation. *)
Theorem unissued_response_cannot_settle : forall state source,
  is_object (get source "message") = true ->
  str (get source "message") "jsonrpc" = "2.0" ->
  as_string (get (get source "message") "method") = None ->
  correlate state (get (get source "message") "id") = None ->
  message state source = encode_action (unchanged "ignore" state []).
Proof.
  intros state source shape version method identity.
  unfold message. rewrite shape, version. cbn.
  rewrite method, identity. reflexivity.
Qed.
