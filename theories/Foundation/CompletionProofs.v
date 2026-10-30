From Stdlib Require Import NArith.
From Selvedge.Foundation Require Import Completion ReceiverProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.

Lemma observed_write : forall state phase (selected : slot state phase) before current write,
 observe selected before = Some (current,write) ->
 forall next, read selected (write next) = Some next.
Proof.
 intros state phase selected before current write Found next.
 destruct selected as [path Address|row path Address get law]; cbn in Found.
 - destruct (Receiver.read_at path (@identity _ _ path Address) before) as [stored|] eqn:Stored;
   [|discriminate]. inversion Found; subst current write.
   assert (Position : Receiver.positioned path before).
   { apply (ReceiverProofs.lookup_has_position path stored before stored).
     unfold Receiver.lookup; rewrite fixed_address; exact Stored. }
   pose proof (ReceiverProofs.installed path next before Position) as Installed.
   unfold Receiver.lookup in Installed; rewrite fixed_address in Installed.
   unfold read; cbn; rewrite Installed; reflexivity.
 - destruct (Receiver.read_at path (@identity _ _ path Address) before) as [stored|] eqn:Stored;
   [|discriminate]. inversion Found; subst current write.
   assert (Position : Receiver.positioned path before).
   { apply (ReceiverProofs.lookup_has_position path stored before stored).
     unfold Receiver.lookup; rewrite fixed_address; exact Stored. }
   pose proof (ReceiverProofs.installed path
     (@set _ _ get (@set_wf _ _ get law) (fun _ => next) stored) before Position) as Installed.
   unfold Receiver.lookup in Installed; rewrite fixed_address in Installed.
   unfold read; cbn; rewrite Installed; cbn; rewrite set_get; reflexivity.
Qed.

Theorem no_receiver_is_ignored : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.View pending) mode address finish before current,
 read selected before = Some current ->
 Constructor.project pending current = None ->
 @run _ _ _ selected pending View mode address finish before = (false,before).
Proof.
 intros state phase input selected pending View mode address finish before current Found Retired.
 unfold read in Found; unfold run.
 destruct (observe selected before) as [[observed write]|]; [|discriminate].
 injection Found as Equal; subst observed; now rewrite Retired.
Qed.

(** The declaration's terminal type is sufficient for every receiver. A
    callback cannot revive the phase it consumes, even if delivered repeatedly. *)
Theorem consumed_once : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.View pending) mode address finish before,
 let first := @run _ _ _ selected pending View mode address finish before in
 @run _ _ _ selected pending View mode address finish (snd first) = (false,snd first).
Proof.
 intros state phase input selected pending View mode address finish before; cbv zeta.
 unfold run.
 destruct (observe selected before) as [[current write]|] eqn:Observed.
 - destruct (Constructor.project pending current) as [request|] eqn:Pending.
   + destruct (matches mode address request) eqn:Matches; cbn.
     * eapply no_receiver_is_ignored.
       -- exact (observed_write _ _ selected before current write Observed _).
       -- apply no_receiver.
     * unfold run; now rewrite Observed,Pending,Matches.
   + cbn; unfold run; now rewrite Observed,Pending.
 - cbn; unfold run; now rewrite Observed.
Qed.

Theorem wrong_ticket_is_ignored : forall state phase payload (selected : slot state phase)
 (pending : RequestEnvelope.t payload -> phase) (View : Constructor.View pending)
 before current expected input ticket finish,
 read selected before = Some current ->
 Constructor.project pending current = Some (RequestEnvelope.Envelope expected input) ->
 ticket <> expected ->
 @run _ _ _ selected pending View Ticket ticket finish before = (false,before).
Proof.
 intros state phase payload selected pending View before current expected input ticket finish Found Pending Different.
 unfold read in Found; unfold run.
 destruct (observe selected before) as [[observed write]|]; [|discriminate].
 injection Found as Equal; subst observed; rewrite Pending; cbn.
 apply N.eqb_neq in Different; now rewrite Different.
Qed.

Theorem current_completion_is_observed : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.View pending) mode address finish before current request,
 read selected before = Some current ->
 Constructor.project pending current = Some request -> matches mode address request = true ->
 read selected (snd (@run _ _ _ selected pending View mode address finish before)) =
 Some (outcome (finish request)).
Proof.
 intros state phase input selected pending View mode address finish before current request Found Pending Matches.
 unfold read in Found; unfold run.
 destruct (observe selected before) as [[observed write]|] eqn:Observed; [|discriminate].
 injection Found as Equal; subst observed; rewrite Pending,Matches; cbn.
 exact (observed_write _ _ selected before current write Observed _).
Qed.
