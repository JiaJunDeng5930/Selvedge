From Stdlib Require Import String List Bool NArith.
Import ListNotations.
Open Scope N_scope.
Record running := Running { handle : N; key : string; task : option N; cancellable : bool; provider : bool; reduced : bool }.
Record state := State { retired : bool; next_handle : N; active : list running }.
Definition initial := State false 0 [].
Inductive settlement := Accepted | InputLimit | OutputLimit | Rejected | Uncertain.
Inductive observation :=
| Launch (name : string) (task : option N) (cancellable provider : bool)
| Complete (generation : N) | CancelTask (task : N) | CancelKey (name : string)
| Settlement (generation : N) (outcome : settlement) | Shutdown.
Inductive primitive := Start (generation : N) | Cancel (generation : N) (provider : bool)
| RetryFailure | Settled | Retire.
Definition cancel_entries (stop_provider : bool) (entries : list running) :=
  map (fun entry => Cancel (handle entry) (stop_provider && provider entry)) entries.
Definition step (s : state) (o : observation) : state * list primitive :=
  match o with
  | Complete generation =>
      (State (retired s) (next_handle s) (filter (fun entry => negb (N.eqb generation (handle entry))) (active s)), [])
  | Shutdown => (State true (next_handle s) (active s), cancel_entries false (active s))
  | _ => if retired s then (s, []) else
      match o with
      | Launch name task cancellable provider =>
          let generation := N.succ (next_handle s) in
          (State false generation (Running generation name task cancellable provider false :: active s), [Start generation])
      | CancelTask task =>
          (s, cancel_entries true (filter (fun entry => (match Dispatch.task entry with Some owner => N.eqb task owner | None => false end) && cancellable entry) (active s)))
      | CancelKey name =>
          (s, cancel_entries true (filter (fun entry => String.eqb name (key entry)) (active s)))
      | Settlement generation outcome =>
          match find (fun entry => N.eqb generation (handle entry)) (active s) with
          | None => (s, [])
          | Some entry => match outcome with
              | Accepted => (s, [Settled])
              | InputLimit | OutputLimit =>
                  if reduced entry then (State true (next_handle s) (active s), [Retire])
                  else (State false (next_handle s) (map (fun running =>
                    if N.eqb generation (handle running) then
                      Running (handle running) (key running) (task running) (cancellable running) (provider running) true
                    else running) (active s)), [RetryFailure])
              | Rejected | Uncertain => (State true (next_handle s) (active s), [Retire])
              end
          end
      | _ => (s, [])
      end
  end.
Theorem completion_only_removes_its_generation s generation entry :
  In entry (active (fst (step s (Complete generation)))) -> In entry (active s) /\ handle entry <> generation.
Proof.
  simpl. rewrite filter_In. intros [H Hkeep]. split; auto.
  apply Bool.negb_true_iff in Hkeep. apply N.eqb_neq in Hkeep. congruence.
Qed.
Theorem uncertain_never_retries s generation :
  ~ In RetryFailure (snd (step s (Settlement generation Uncertain))).
Proof.
  destruct s as [r n a]; simpl. destruct r; simpl; try tauto.
  destruct (find _ a); simpl; intuition discriminate.
Qed.
Theorem reduced_callback_never_retries s generation outcome entry :
  find (fun running => N.eqb generation (handle running)) (active s) = Some entry ->
  reduced entry = true ->
  ~ In RetryFailure (snd (step s (Settlement generation outcome))).
Proof.
  intros Hentry Hreduced. unfold step. destruct (retired s); simpl; try tauto.
  rewrite Hentry. destruct outcome; simpl; try (rewrite Hreduced); simpl; intuition discriminate.
Qed.

Theorem shutdown_never_cancels_provider s generation stop_provider :
  In (Cancel generation stop_provider) (snd (step s Shutdown)) -> stop_provider = false.
Proof.
  change (In (Cancel generation stop_provider)
    (map (fun entry => Cancel (handle entry) false) (active s)) -> stop_provider = false).
  rewrite in_map_iff. intros [entry [H _]]. inversion H. reflexivity.
Qed.
