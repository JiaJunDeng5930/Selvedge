From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Host Require Import RemoteConnectorSession.
Import ListNotations.
Open Scope N_scope.

(** Queue admission constrains the very acknowledgement consumed by the
    physical Promise queue; counters are projections of the pending jobs. *)
Theorem enqueue_acknowledges_available_budget current n id size :
 snd (step current (Observe n (Enqueue id size))) = Enqueued ->
 exists data, current = Ready n data /\ queued_for data id < 32 /\
 N.of_nat (List.length (pending data)) < 256 /\ queued_bytes data + size <= 33554432.
Proof.
 destruct current as [g p|g p|g data]; cbn [step generation];
 destruct (N.eqb g n) eqn:Same; cbn; try discriminate.
 destruct (find_connection data id); [|discriminate].
 destruct ((queued_for data id <? 32) && (N.of_nat (List.length (pending data)) <? 256) &&
   (queued_bytes data + size <=? 33554432)) eqn:Budget; [|discriminate].
 intro Accepted. apply N.eqb_eq in Same; subst n. exists data. split; [reflexivity|].
 repeat rewrite andb_true_iff in Budget. repeat split;
   first [apply N.ltb_lt|apply N.leb_le]; tauto.
Qed.

Theorem grant_refresh_retains_only_current_authority g data values entry :
 match fst (step (Ready g data) (Observe g (Grants values))) with
 | Ready _ next => In entry (connections next) -> permitted values (authority entry) = true
 | _ => True end.
Proof. cbn [step generation]. rewrite N.eqb_refl. cbn. rewrite filter_In. tauto. Qed.

Theorem different_grant_cannot_issue_request g data id requested entry :
 find_connection data id = Some entry -> same_grant (authority entry) requested = false ->
 step (Ready g data) (Observe g (Frame (Request id requested))) = (Ready g data,Disconnect).
Proof.
 intros Present Different. cbn [step generation]. rewrite N.eqb_refl. cbn.
 now rewrite Present, Different.
Qed.

Theorem expired_local_pairing_cannot_retain_a_request deadline pending now :
 deadline <= now -> live_pairing (AwaitingPairing deadline pending) now = PairingIdle.
Proof. intro Expired. cbn [live_pairing]. rewrite (proj2 (N.ltb_ge now deadline) Expired). reflexivity. Qed.
