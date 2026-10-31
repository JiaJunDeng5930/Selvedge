From Stdlib Require Import NArith.
From Selvedge.Programming Require Import Completion ReceiverProofs OptionObservationProofs.
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

Theorem candidate_spec : forall phase input (pending : input -> phase)
 (View : Constructor.Case pending) mode address current request,
 @candidate _ _ pending View mode address current = Some request ->
 Constructor.recognize pending current = Some request /\ matches mode address request = true.
Proof.
 intros phase input pending View mode address current request Found; unfold candidate in Found.
 destruct (Constructor.recognize pending current) as [selected|] eqn:Pending; [|discriminate].
 destruct (matches mode address selected) eqn:Matches; [|discriminate].
 injection Found as Equal; subst selected; split; [reflexivity|exact Matches].
Qed.

Theorem no_receiver_is_ignored : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.Case pending) mode address finish before current,
 read selected before = Some current ->
 Constructor.recognize pending current = None ->
 @run _ _ _ selected pending View mode address finish before = (false,before).
Proof.
 intros state phase input selected pending View mode address finish before current Found Retired.
 unfold read in Found; unfold run,candidate.
 destruct (observe selected before) as [[observed write]|]; [|discriminate].
 injection Found as Equal; subst observed; now rewrite Retired.
Qed.

(** The declaration's terminal type is sufficient for every receiver. A
    callback cannot revive the phase it consumes, even if delivered repeatedly. *)
Theorem consumed_once : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.Case pending) mode address finish before,
 let first := @run _ _ _ selected pending View mode address finish before in
 @run _ _ _ selected pending View mode address finish (snd first) = (false,snd first).
Proof.
 intros state phase input selected pending View mode address finish before; cbv zeta.
 unfold run,candidate.
 destruct (observe selected before) as [[current write]|] eqn:Observed.
 - destruct (Constructor.recognize pending current) as [request|] eqn:Pending.
   + destruct (matches mode address request) eqn:Matches; cbn.
     * eapply no_receiver_is_ignored.
       -- exact (observed_write _ _ selected before current write Observed _).
       -- apply no_receiver.
     * now rewrite Observed,Pending,Matches.
   + cbn; now rewrite Observed,Pending.
 - cbn; now rewrite Observed.
Qed.

Theorem wrong_ticket_is_ignored : forall state phase payload (selected : slot state phase)
 (pending : RequestEnvelope.t payload -> phase) (View : Constructor.Case pending)
 before current expected input ticket finish,
 read selected before = Some current ->
 Constructor.recognize pending current = Some (RequestEnvelope.Envelope expected input) ->
 ticket <> expected ->
 @run _ _ _ selected pending View Ticket ticket finish before = (false,before).
Proof.
 intros state phase payload selected pending View before current expected input ticket finish Found Pending Different.
 unfold read in Found; unfold run,candidate.
 destruct (observe selected before) as [[observed write]|]; [|discriminate].
 injection Found as Equal; subst observed; rewrite Pending; cbn.
 apply N.eqb_neq in Different; now rewrite Different.
Qed.

Theorem current_completion_is_observed : forall state phase input (selected : slot state phase)
 (pending : input -> phase) (View : Constructor.Case pending) mode address finish before current request,
 read selected before = Some current ->
 Constructor.recognize pending current = Some request -> matches mode address request = true ->
 read selected (snd (@run _ _ _ selected pending View mode address finish before)) =
 Some (outcome (finish request)).
Proof.
 intros state phase input selected pending View mode address finish before current request Found Pending Matches.
 unfold read in Found; unfold run,candidate.
 destruct (observe selected before) as [[observed write]|] eqn:Observed; [|discriminate].
 injection Found as Equal; subst observed; rewrite Pending,Matches; cbn.
 exact (observed_write _ _ selected before current write Observed _).
Qed.

Section Receipts.
Context {state row phase input} (path : Receiver.t state row) (location : Addressed path)
 (get : row -> phase) (setter : SetterWf get) (pending : input -> phase) (view : Constructor.Case pending)
 (mode : correlation input) (address : coordinate mode)
 (choose : row -> input -> option (@Row.amendment row input phase pending view)) (before : state)
 (received : @Row.receipt state row phase input path location get setter pending view mode address choose before).
Local Existing Instances location setter view.

Theorem updated_phase_is_terminal : get (Row.updated received) =
 outcome (Row.conclusion (Row.change received)).
Proof.
 unfold Row.updated,Row.finish.
 exact (@set_get row phase get setter
   (fun _ => outcome (Row.conclusion (Row.change received)))
   (Row.apply (Row.assignments (Row.change received)) (Row.previous received))).
Qed.

Theorem received_row_is_installed :
 Receiver.read_at path (@identity _ _ path location) (Row.after received) = Some (Row.updated received).
Proof.
 assert (Position : Receiver.positioned path before).
 { apply (ReceiverProofs.lookup_has_position path (Row.previous received) before (Row.previous received)).
   unfold Receiver.lookup; rewrite fixed_address; apply Row.observed. }
 pose proof (ReceiverProofs.installed path (Row.updated received) before Position) as Installed.
 unfold Receiver.lookup in Installed; rewrite fixed_address in Installed; exact Installed.
Qed.

(** Field assignments cannot resurrect the consumed phase: the interpreter
    writes its terminal constructor last, then installs it at the same owner. *)
Theorem received_candidate_is_retired :
 candidate pending mode address (get (Row.updated received)) = None.
Proof. unfold candidate; rewrite updated_phase_is_terminal,no_receiver; reflexivity. Qed.

Theorem receipt_rejects_repeated_completion :
 Row.consume path get pending mode address choose (Row.after received) = None.
Proof.
 unfold Row.consume.
 eapply OptionObservationProofs.observe_present; [apply received_row_is_installed|].
 intro Found; eapply OptionObservationProofs.observe_absent; [apply received_candidate_is_retired|].
 intros; reflexivity.
Qed.
End Receipts.
