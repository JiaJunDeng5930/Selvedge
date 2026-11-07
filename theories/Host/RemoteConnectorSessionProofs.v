From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Host Require Import RemoteConnectorSession.
Import ListNotations.
Open Scope N_scope.

Theorem frame_observation_emits_only_frame_actions s n frame :
 match snd (step s (Observe n (Frame frame))) with
 | Ignore | Disconnect | BecameReady | Opened _ | Closed _ | Requested _ _
 | PairRequested _ | ReceivedPong => True | _ => False end.
Proof.
 destruct s as [g pairing|g pairing|g data];
 unfold step; cbn; destruct (N.eqb g n); cbn; try exact I.
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
 destruct s as [g pairing|g pairing|g data];
 unfold step; cbn; destruct (N.eqb g n); cbn; try tauto.
 destruct (find_connection data id); cbn; tauto.
Qed.

Theorem delivery_observation_emits_only_delivery_actions s n id notice :
 match snd (step s (Observe n (Deliver id notice))) with
 | Ignore | DeliverNotice => True | _ => False end.
Proof.
 destruct s as [g pairing|g pairing|g data];
 unfold step; cbn; destruct (N.eqb g n); cbn; try exact I.
 unfold deliver_notice.
 destruct (notice_eligible data id notice); exact I.
Qed.

Theorem enqueue_observation_emits_only_queue_actions s n id size notice :
 match snd (step s (Observe n (Enqueue id size notice))) with
 | Ignore | Disconnect | Enqueued => True | _ => False end.
Proof.
 destruct s as [g pairing|g pairing|g data];
 unfold step; cbn; destruct (N.eqb g n); cbn; try exact I.
 destruct (find_connection data id); cbn; try exact I.
 repeat match goal with
 | |- context[if ?condition then _ else _] => destruct condition; cbn
 end; exact I.
Qed.

Lemma queued_bytes_accumulator jobs initial :
 fold_left (fun total job => total + bytes job) jobs initial =
 initial + fold_left (fun total job => total + bytes job) jobs 0.
Proof.
 revert initial. induction jobs as [|job jobs IH]; intro initial; cbn [fold_left].
 - now rewrite N.add_0_r.
 - rewrite N.add_0_l, (IH (initial + bytes job)), (IH (bytes job)). lia.
Qed.

Theorem enqueued_work_respects_capacity s n id size notice :
 snd (step s (Observe n (Enqueue id size notice))) = Enqueued ->
 exists before after, s = Ready n before /\
 fst (step s (Observe n (Enqueue id size notice))) = Ready n after /\
 queued_for after id = N.succ (queued_for before id) /\
 N.of_nat (List.length (pending after)) = N.succ (N.of_nat (List.length (pending before))) /\
 queued_bytes after = queued_bytes before + size /\ queued_for after id <= 32 /\
 N.of_nat (List.length (pending after)) <= 256 /\ queued_bytes after <= 33554432.
Proof.
 destruct s as [g p|g p|g data]; unfold step; cbn;
 destruct (N.eqb g n) eqn:Same; cbn; try discriminate.
 destruct (find_connection data id) as [entry|] eqn:Present; [|discriminate].
 destruct (negb notice || match after_notice entry with Some _ => true | None => false end); [|discriminate].
 destruct ((queued_for data id <? 32) && (N.of_nat (List.length (pending data)) <? 256) &&
   (queued_bytes data + size <=? 33554432)) eqn:Budget; [|discriminate].
 intros _. apply N.eqb_eq in Same; subst n.
 repeat rewrite andb_true_iff in Budget. destruct Budget as [[PerConnection Total] Bytes].
 apply N.ltb_lt in PerConnection. apply N.ltb_lt in Total. apply N.leb_le in Bytes.
 set (next := Session (pairing_code data) (connections data) (Queued id size::pending data) (notice_sequence data)).
 assert (ConnectionCount : queued_for next id = N.succ (queued_for data id)).
 { unfold next,queued_for. cbn [pending filter owner]. rewrite String.eqb_refl.
   apply Nat2N.inj_succ. }
 assert (TotalCount : N.of_nat (List.length (pending next)) = N.succ (N.of_nat (List.length (pending data)))).
 { unfold next. cbn [pending List.length]. apply Nat2N.inj_succ. }
 assert (ByteCount : queued_bytes next = queued_bytes data + size).
 { unfold next,queued_bytes. cbn [pending fold_left bytes]. rewrite queued_bytes_accumulator. lia. }
 exists data,next. repeat split; try reflexivity; try assumption; lia.
Qed.

Lemma queued_bytes_cons job jobs :
 fold_left (fun total job => total + bytes job) (job::jobs) 0 =
 bytes job + fold_left (fun total job => total + bytes job) jobs 0.
Proof. cbn [fold_left]. rewrite N.add_0_l. apply queued_bytes_accumulator. Qed.

Lemma release_budget_accounting jobs id size :
 In (Queued id size) jobs ->
 N.of_nat (List.length jobs) = N.succ (N.of_nat (List.length (release_budget jobs id size))) /\
 N.of_nat (List.length (filter (fun job => String.eqb (owner job) id) jobs)) =
   N.succ (N.of_nat (List.length (filter (fun job => String.eqb (owner job) id) (release_budget jobs id size)))) /\
 fold_left (fun total job => total + bytes job) jobs 0 =
   size + fold_left (fun total job => total + bytes job) (release_budget jobs id size) 0.
Proof.
 induction jobs as [|[job_owner job_bytes] jobs IH]; intro Present; [contradiction|].
 cbn [release_budget owner bytes].
 destruct (String.eqb job_owner id && N.eqb job_bytes size) eqn:Matching.
 - apply andb_true_iff in Matching. destruct Matching as [Owner Size].
   apply String.eqb_eq in Owner. apply N.eqb_eq in Size. subst job_owner job_bytes.
   cbn [List.length filter owner]. rewrite String.eqb_refl.
   rewrite queued_bytes_cons. cbn [List.length bytes].
   repeat split; try apply Nat2N.inj_succ; reflexivity.
 - assert (In (Queued id size) jobs) as Tail.
   { destruct Present as [Same|Tail]; [|exact Tail].
     inversion Same; subst. rewrite String.eqb_refl,N.eqb_refl in Matching. discriminate. }
   destruct (IH Tail) as [Total [PerConnection Bytes]].
   cbn [List.length filter owner]. rewrite !queued_bytes_cons. cbn [bytes].
   destruct (String.eqb job_owner id); cbn [List.length];
     repeat rewrite Nat2N.inj_succ; repeat split; lia.
Qed.

Theorem completed_queue_work_releases_capacity g data id size :
 In (Queued id size) (pending data) ->
 exists next, fst (step (Ready g data) (Observe g (Dequeue id size))) = Ready g next /\
 queued_for data id = N.succ (queued_for next id) /\
 N.of_nat (List.length (pending data)) = N.succ (N.of_nat (List.length (pending next))) /\
 queued_bytes data = size + queued_bytes next.
Proof.
 intro Present. unfold step. cbn. rewrite N.eqb_refl. cbn.
 exists (Session (pairing_code data) (connections data) (release_budget (pending data) id size) (notice_sequence data)).
 split; [reflexivity|]. unfold queued_for,queued_bytes. cbn [pending].
 pose proof (release_budget_accounting (pending data) id size Present) as [Total [PerConnection Bytes]].
 repeat split; assumption.
Qed.

Theorem notice_queue_admission_matches_subscription g data id size entry :
 find_connection data id = Some entry -> queued_for data id < 32 ->
 N.of_nat (List.length (pending data)) < 256 -> queued_bytes data + size <= 33554432 ->
 match after_notice entry with
 | Some _ => snd (step (Ready g data) (Observe g (Enqueue id size true))) = Enqueued
 | None => step (Ready g data) (Observe g (Enqueue id size true)) =
     (Ready g data,Ignore)
 end.
Proof.
 intros Present PerConnection Total Bytes.
 unfold step. cbn. rewrite N.eqb_refl. cbn. rewrite Present. cbn.
 destruct (after_notice entry); [|reflexivity].
 rewrite (proj2 (N.ltb_lt _ _) PerConnection), (proj2 (N.ltb_lt _ _) Total),
   (proj2 (N.leb_le _ _) Bytes). reflexivity.
Qed.

Theorem grant_refresh_retains_only_current_authority g data values entry :
 match fst (step (Ready g data) (Observe g (Grants values))) with
 | Ready _ next => In entry (connections next) -> permitted values (authority entry) = true
 | _ => True end.
Proof. unfold step. cbn. rewrite N.eqb_refl. cbn. rewrite filter_In. tauto. Qed.

Theorem different_grant_cannot_issue_request g data id requested request entry :
 find_connection data (RemoteProtocol.identifier_text id) = Some entry -> same_grant (authority entry) requested = false ->
 snd (step (Ready g data)
   (Observe g (Frame (RemoteProtocol.RelayRequest id requested request)))) = Disconnect.
Proof.
 intros Present Different. unfold step. cbn. rewrite N.eqb_refl. cbn.
 now rewrite Present, Different.
Qed.

Theorem subscription_capture_records_the_current_notice_cutoff g data id entry :
 find_connection data id = Some entry ->
 step (Ready g data) (Observe g (Snapshot id true)) =
 (Ready g (subscription data id (Some (notice_sequence data))),CapturedSnapshot).
Proof.
 intro Present. unfold step. cbn. rewrite N.eqb_refl. cbn.
 now rewrite Present.
Qed.

Theorem notice_delivery_matches_the_current_subscription g data id notice :
 snd (step (Ready g data) (Observe g (Deliver id notice))) = DeliverNotice <->
 exists entry after, find_connection data id = Some entry /\
 after_notice entry = Some after /\ after < notice.
Proof.
 unfold step. cbn. rewrite N.eqb_refl. cbn.
 unfold deliver_notice,notice_eligible.
 split.
 - destruct (find_connection data id) as [entry|] eqn:Found; [|discriminate].
   destruct (after_notice entry) as [after|] eqn:Subscribed; [|discriminate].
   destruct (after <? notice) eqn:Later; [|discriminate].
   intros _. exists entry, after. repeat split; try assumption. now apply N.ltb_lt.
 - intros [entry [after [Found [Subscribed Later]]]].
   now rewrite Found, Subscribed, (proj2 (N.ltb_lt _ _) Later).
Qed.

Theorem session_notice_advances_the_cursor g data :
 exists next, fst (step (Ready g data) Notice) = Ready g next /\
 notice_sequence data < notice_sequence next.
Proof. eexists; split; [reflexivity|apply N.lt_succ_diag_r]. Qed.

Theorem expired_local_pairing_cannot_retain_a_request deadline pending now :
 deadline <= now -> live_pairing (AwaitingPairing deadline pending) now = PairingIdle.
Proof. intro Expired. cbn [live_pairing]. rewrite (proj2 (N.ltb_ge now deadline) Expired). reflexivity. Qed.
