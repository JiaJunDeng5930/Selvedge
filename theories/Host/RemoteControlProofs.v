From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Host Require Import RemoteProtocol RemoteControl.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** Late socket callbacks cannot change the current connector state. *)
Theorem stale_connector_event_is_ignored : forall state event,
 str event "kind" <> "enable" -> str event "kind" <> "start" -> str event "kind" <> "stop" ->
 current state event = false -> connector_step state event = result state "ignore".
Proof.
 intros state event Enable Start Stop Stale. unfold connector_step.
 destruct (String.eqb (str event "kind") "enable") eqn:E; [apply String.eqb_eq in E; contradiction|].
 destruct (String.eqb (str event "kind") "start") eqn:S; [apply String.eqb_eq in S; contradiction|].
 destruct (String.eqb (str event "kind") "stop") eqn:T; [apply String.eqb_eq in T; contradiction|].
 now rewrite Stale.
Qed.

Lemma consumed_digest_absent : forall digest tickets,
 find (fun entry=>String.eqb (str entry "digest") digest)
   (filter (fun entry=>negb (String.eqb (str entry "digest") digest)) tickets) = None.
Proof.
 intros digest tickets; induction tickets as [|entry rest IH]; cbn; auto.
 destruct (String.eqb (str entry "digest") digest) eqn:Same; cbn; auto.
 now rewrite Same.
Qed.

(** Consumption removes every occurrence of its ticket identity. The relay
    publishes this attachment before it can accept or authorize a socket. *)
Theorem relay_ticket_consumption_removes_identity : forall state event,
 str event "kind" = "ticket_consume" ->
 find (fun entry=>String.eqb (str entry "digest") (str event "digest"))
 (items (get (get (relay_step state event) "state") "tickets")) = None.
Proof.
 intros state event Kind. unfold relay_step; rewrite Kind; cbn [String.eqb].
 unfold get, set; destruct state; cbn; try reflexivity.
 apply consumed_digest_absent.
Qed.

Theorem disabled_connector_is_not_current : forall state event,
 enabled state = false -> current state event = false.
Proof. intros state event Disabled; unfold current; now rewrite Disabled. Qed.

(** Grant and generation are both required for delivery; matching an old
    connection id cannot confer authority in a replacement host session. *)
Theorem stale_relay_generation_cannot_deliver : forall source,
 N.eqb (num (get source "connection") "generation") (num source "generation") = false ->
 delivery_allowed source = false.
Proof. intros source Stale; unfold delivery_allowed; rewrite Stale; now destruct (equal _ _). Qed.

Theorem replaced_pairing_request_cannot_be_delivered : forall state event,
 str event "kind" = "pair_delivery" ->
 N.eqb (num state "pairing_revision") (num event "revision") = false ->
 get (relay_step state event) "allowed" = JBool false.
Proof.
 intros state event Kind Replaced. unfold relay_step; rewrite Kind; cbn [String.eqb].
 rewrite Replaced; reflexivity.
Qed.
