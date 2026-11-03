From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Host Require Import RemoteConnectorSession.
Import ListNotations.
Open Scope N_scope.

Theorem frame_observation_emits_only_frame_actions s n frame :
 match snd (step s (Observe n (Frame frame))) with
 | Ignore | Disconnect | BecameReady | Opened _ | Closed _ | Requested _ _
 | PairRequested _ | ReceivedPong => True | _ => False end.
Proof.
 destruct s as [phase sequence]. destruct phase as [g pairing|g pairing|g data];
 unfold step,phase_step; cbn; destruct (N.eqb g n); cbn; try exact I.
 all: destruct frame; cbn; try exact I.
 all: repeat match goal with
 | |- context[find_connection ?data ?id] => destruct (find_connection data id); cbn
 | |- context[if ?condition then _ else _] => destruct condition; cbn
 end; exact I.
Qed.

Theorem capture_observations_emit_only_capture_actions s n id subscribe :
 (match snd (step s (Observe n (Snapshot id subscribe))) with
  | Ignore | CapturedSnapshot => True | _ => False end) /\
 (match snd (step s (Observe n (Unsubscribe id))) with
  | Ignore | Unsubscribed => True | _ => False end).
Proof.
 destruct s as [phase sequence]. destruct phase as [g pairing|g pairing|g data];
 unfold step,phase_step; cbn; destruct (N.eqb g n); cbn; try tauto.
 destruct (find_connection data id); cbn; tauto.
Qed.

Theorem delivery_observation_emits_only_delivery_actions s n id notice :
 match snd (step s (Observe n (Deliver id notice))) with
 | Ignore | DeliverNotice => True | _ => False end.
Proof.
 destruct s as [phase sequence]. destruct phase as [g pairing|g pairing|g data];
 unfold step,phase_step; cbn; destruct (N.eqb g n); cbn; try exact I.
 unfold deliver_notice.
 destruct (notice_eligible sequence data id notice && notice_queued data id notice); exact I.
Qed.

Theorem enqueue_observation_emits_only_queue_actions s n id size notice :
 match snd (step s (Observe n (Enqueue id size notice))) with
 | Ignore | Disconnect | Enqueued => True | _ => False end.
Proof.
 destruct s as [phase sequence]. destruct phase as [g pairing|g pairing|g data];
 unfold step,phase_step; cbn; destruct (N.eqb g n); cbn; try exact I.
 destruct (find_connection data id); cbn; try exact I.
 repeat match goal with
 | |- context[if ?condition then _ else _] => destruct condition; cbn
 end; exact I.
Qed.

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
 snd (step (State (Ready g data) sequence)
   (Observe g (Frame (RemoteProtocol.RelayRequest id requested request)))) = Disconnect.
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

Theorem every_observed_notice_advances_the_cursor s :
 notice_sequence s < notice_sequence (fst (step s Notice)).
Proof. unfold step,phase_step. apply N.lt_succ_diag_r. Qed.

Theorem expired_local_pairing_cannot_retain_a_request deadline pending now :
 deadline <= now -> live_pairing (AwaitingPairing deadline pending) now = PairingIdle.
Proof. intro Expired. cbn [live_pairing]. rewrite (proj2 (N.ltb_ge now deadline) Expired). reflexivity. Qed.
