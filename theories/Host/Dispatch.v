From Stdlib Require Import String List Bool NArith.
Import ListNotations.
Open Scope N_scope.
Record running := Running { handle : N; key : string; task : option N; cancellable : bool; provider : bool; reduced : bool; settled : bool }.
Record state := State { retired : bool; next_handle : N; active : list running }.
Definition initial := State false 0 [].
Inductive settlement := Accepted | InputLimit | OutputLimit | Rejected | Uncertain.
Record workspace_running := WorkspaceRunning {
  workspace_handle : N;
  workspace_task : option N;
  resource_task : option N;
  resource_local : bool;
  local_overlap : bool
}.
Definition workspace_barrier (owner : N) (local : bool) (entries : list workspace_running) :=
  map workspace_handle (filter (fun entry =>
    (match workspace_task entry with Some task => N.eqb owner task | None => false end) ||
    (match resource_task entry with Some task => N.eqb owner task && Bool.eqb local (resource_local entry)
     | None => local && local_overlap entry end)) entries).
Inductive observation :=
| Launch (name : string) (task : option N) (cancellable provider : bool)
| WorkspaceLimit (create local success : bool)
| AwaitWorkspace (owner : N) (local : bool) (entries : list workspace_running)
| Complete (generation : N) | CancelTask (task : N) | CancelKey (name : string)
| Settlement (generation : N) (outcome : settlement) | Shutdown.
Inductive primitive := Start (generation : N) | Cancel (generation : N) (provider : bool)
| RollbackWorkspace | RetainWorkspace | Await (generation : N) | RetryFailure | Settled | Retire.
Definition cancel_entries (stop_provider : bool) (entries : list running) :=
  map (fun entry => Cancel (handle entry) (stop_provider && provider entry)) entries.
Definition accept (s : state) generation :=
  match find (fun entry => N.eqb generation (handle entry)) (active s) with
  | Some entry => if settled entry then (s, []) else
      (State (retired s) (next_handle s) (map (fun running =>
        if N.eqb generation (handle running) then
          Running (handle running) (key running) (task running) (cancellable running) (provider running) (reduced running) true
        else running) (active s)), [Settled])
  | None => (s, []) end.
Definition step (s : state) (o : observation) : state * list primitive :=
  match o with
  | Settlement generation Accepted => accept s generation
  | Complete generation =>
      (State (retired s) (next_handle s) (filter (fun entry => negb (N.eqb generation (handle entry))) (active s)), [])
  | Shutdown => (State true (next_handle s) (active s), cancel_entries false (active s))
  | _ => if retired s then (s, []) else
      match o with
      | WorkspaceLimit create local success => (s, [if create && negb local && success then RollbackWorkspace else RetainWorkspace])
      | AwaitWorkspace owner local entries => (s, map Await (workspace_barrier owner local entries))
      | Launch name task cancellable provider =>
          let generation := N.succ (next_handle s) in
          (State false generation (Running generation name task cancellable provider false false :: active s), [Start generation])
      | CancelTask task =>
          (s, cancel_entries true (filter (fun entry => (match Dispatch.task entry with Some owner => N.eqb task owner | None => false end) && cancellable entry) (active s)))
      | CancelKey name =>
          (s, cancel_entries true (filter (fun entry => String.eqb name (key entry)) (active s)))
      | Settlement generation outcome =>
          match find (fun entry => N.eqb generation (handle entry)) (active s) with
          | None => (s, [])
          | Some entry => if settled entry then (s, []) else match outcome with
              | Accepted => accept s generation
              | InputLimit | OutputLimit =>
                  if reduced entry then (State true (next_handle s) (active s), [Retire])
                  else (State false (next_handle s) (map (fun running =>
                    if N.eqb generation (handle running) then
                      Running (handle running) (key running) (task running) (cancellable running) (provider running) true false
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
  destruct (find _ a) as [entry|]; simpl; try tauto. destruct (settled entry); simpl; intuition discriminate.
Qed.
Theorem reduced_callback_never_retries s generation outcome entry :
  find (fun running => N.eqb generation (handle running)) (active s) = Some entry ->
  reduced entry = true ->
  ~ In RetryFailure (snd (step s (Settlement generation outcome))).
Proof.
  intros Hentry Hreduced. destruct outcome; unfold step, accept;
    try (rewrite Hentry; destruct (settled entry); cbn; intuition discriminate).
  all: destruct (retired s); simpl; try tauto;
    rewrite Hentry; destruct (settled entry); simpl; try tauto; try rewrite Hreduced; simpl; intuition discriminate.
Qed.

Theorem shutdown_never_cancels_provider s generation stop_provider :
  In (Cancel generation stop_provider) (snd (step s Shutdown)) -> stop_provider = false.
Proof.
  change (In (Cancel generation stop_provider)
    (map (fun entry => Cancel (handle entry) false) (active s)) -> stop_provider = false).
  rewrite in_map_iff. intros [entry [H _]]. inversion H. reflexivity.
Qed.

Theorem accepted_handle_cannot_settle_again s generation entry :
  retired s = false ->
  find (fun running => N.eqb generation (handle running)) (active s) = Some entry ->
  settled entry = true ->
  forall outcome, snd (step s (Settlement generation outcome)) = [].
Proof.
  intros Hretired Hentry Hsettled outcome. destruct outcome; unfold step, accept; rewrite ?Hretired, ?Hentry, ?Hsettled; reflexivity.
Qed.

Theorem launch_installs_handle_before_run s name owner cancellable provider :
  retired s = false ->
  snd (step s (Launch name owner cancellable provider)) = [Start (N.succ (next_handle s))] /\
  In (Running (N.succ (next_handle s)) name owner cancellable provider false false)
    (active (fst (step s (Launch name owner cancellable provider)))).
Proof.
  intros H. unfold step. rewrite H. simpl. auto.
Qed.

Theorem shutdown_preserves_an_accepted_callback s generation entry :
  find (fun running => N.eqb generation (handle running)) (active s) = Some entry ->
  settled entry = false ->
  snd (step (fst (step s Shutdown)) (Settlement generation Accepted)) = [Settled] /\
  retired (fst (step (fst (step s Shutdown)) (Settlement generation Accepted))) = true.
Proof.
  intros Hentry Hsettled. cbn. unfold accept. cbn. rewrite Hentry,Hsettled. cbn. auto.
Qed.
