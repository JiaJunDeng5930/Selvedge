From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Host Require Import RemoteConnectorSession.
Import ListNotations.
Open Scope N_scope.

(** Queue admission constrains the very acknowledgement consumed by the
    physical Promise queue; counters are projections of the pending jobs. *)
Theorem enqueue_acknowledges_available_budget s n id size notice :
 snd (step s (Observe n (Enqueue id size notice))) = Enqueued ->
 exists data, current s = Ready n data /\ queued_for data id < 32 /\
 N.of_nat (List.length (pending data)) < 256 /\ queued_bytes data + size <= 33554432.
Proof.
 destruct s as [phase sequence]. destruct phase as [g p|g p|g data]; unfold step,phase_step; cbn;
 destruct (N.eqb g n) eqn:Same; cbn; try discriminate.
 destruct (find_connection data id) eqn:Present; [|discriminate].
 destruct (match notice with Some value => notice_eligible sequence data id value | None => true end); [|discriminate].
 destruct ((queued_for data id <? 32) && (N.of_nat (List.length (pending data)) <? 256) &&
   (queued_bytes data + size <=? 33554432)) eqn:Budget; [|discriminate].
 intro Accepted. apply N.eqb_eq in Same; subst n. exists data. split; [reflexivity|].
 repeat rewrite andb_true_iff in Budget. repeat split;
   first [apply N.ltb_lt|apply N.leb_le]; tauto.
Qed.

Theorem grant_refresh_retains_only_current_authority g data sequence values entry :
 match current (fst (step (State (Ready g data) sequence) (Observe g (Grants values)))) with
 | Ready _ next => In entry (connections next) -> permitted values (authority entry) = true
 | _ => True end.
Proof. unfold step,phase_step. cbn. rewrite N.eqb_refl. cbn. rewrite filter_In. tauto. Qed.

Theorem different_grant_cannot_issue_request g data sequence id requested request entry :
 find_connection data (RemoteProtocol.identifier_text id) = Some entry -> same_grant (authority entry) requested = false ->
 step (State (Ready g data) sequence) (Observe g (Frame (Request id requested request))) =
 (State (Ready g data) sequence,Disconnect).
Proof.
 intros Present Different. unfold step,phase_step. cbn. rewrite N.eqb_refl. cbn.
 now rewrite Present, Different.
Qed.

Theorem subscription_capture_records_the_current_notice_cutoff g data sequence id entry :
 find_connection data id = Some entry ->
 step (State (Ready g data) sequence) (Observe g (Snapshot id true)) =
 (State (Ready g (subscription data id (Some sequence))) sequence,CapturedSnapshot).
Proof.
 intro Present. unfold step,phase_step. cbn. rewrite N.eqb_refl. cbn.
 now rewrite Present.
Qed.

Theorem delivered_notice_is_queued_and_beyond_the_current_cutoff g data sequence id notice :
 snd (step (State (Ready g data) sequence) (Observe g (Deliver id notice))) = DeliverNotice ->
 notice_eligible sequence data id notice = true /\ notice_queued data id notice = true.
Proof.
 unfold step,phase_step. cbn. rewrite N.eqb_refl. cbn.
 unfold deliver_notice.
 destruct (notice_eligible sequence data id notice && notice_queued data id notice) eqn:Admitted;
   cbn; [|discriminate]. intro Delivered. now apply andb_true_iff in Admitted.
Qed.

Theorem every_observed_notice_advances_one_sequence s :
 notice_sequence (fst (step s Notice)) = N.succ (notice_sequence s).
Proof. unfold step,phase_step. reflexivity. Qed.

Theorem expired_local_pairing_cannot_retain_a_request deadline pending now :
 deadline <= now -> live_pairing (AwaitingPairing deadline pending) now = PairingIdle.
Proof. intro Expired. cbn [live_pairing]. rewrite (proj2 (N.ltb_ge now deadline) Expired). reflexivity. Qed.
