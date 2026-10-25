From Stdlib Require Import String List Bool NArith.
From Selvedge.Host Require Import RemoteRelaySession.
Open Scope string_scope.
Open Scope N_scope.

Lemma consumed_digest_absent digest tickets :
 find (fun entry=>String.eqb entry.(ticket_digest) digest)
 (filter (fun entry=>negb (String.eqb entry.(ticket_digest) digest)) tickets) = None.
Proof.
 induction tickets as [|entry rest IH]; cbn; auto.
 destruct (String.eqb entry.(ticket_digest) digest) eqn:Same; cbn; auto.
 now rewrite Same.
Qed.

Definition tickets_of current := match current with Ready _ tickets=>tickets|_=>nil end.

(** Even a rejected attempt consumes every copy of the selected ticket identity. *)
Theorem consumption_removes_ticket current now grants digest count :
 find (fun entry=>String.eqb entry.(ticket_digest) digest)
 (tickets_of (fst (step current (ConsumeTicket now grants digest count)))) = None.
Proof. destruct current; cbn; try reflexivity. apply consumed_digest_absent. Qed.

Theorem stale_generation_cannot_deliver connection expected grants host_ready :
 N.eqb connection.(controller_generation) expected = false ->
 snd (step (Controller connection) (Delivery expected grants host_ready)) = Decision Deny.
Proof.
 intro stale.
 change (Decision (decide (host_ready && (N.eqb connection.(controller_generation) expected &&
 granted grants connection.(connection_grant)))) = Decision Deny).
 rewrite stale. destruct host_ready; reflexivity.
Qed.

Theorem replaced_pairing_cannot_be_delivered current now revision expiry :
 (match pairing_of current with
 | Some previous=>N.eqb previous.(pairing_revision) revision | None=>false end) = false ->
 snd (step current (DeliverPairing now revision expiry)) = Decision Deny.
Proof. destruct current; cbn; intro stale; try reflexivity; now rewrite stale. Qed.

Theorem replaced_hash_cannot_install_pairing current now revision value :
 (match pairing_of current with
 | Some previous=>N.eqb previous.(pairing_revision) revision | None=>false end) = false ->
 step current (InstallPairing now revision value) = (current,Decision Deny).
Proof. destruct current; cbn; intro stale; try reflexivity; now rewrite stale. Qed.
