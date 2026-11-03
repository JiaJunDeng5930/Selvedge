From Stdlib Require Import String List Bool NArith Sorting.Permutation.
Import ListNotations.
Open Scope N_scope.
Inductive provider_scope := NoProvider | TaskProvider | IndependentProvider.
Inductive cancellation_scope := NoProviderStop | IndependentProviderStop | AnyProviderStop.
Definition stop_provider scope provider := match scope,provider with
 | NoProviderStop,_ | _,NoProvider => false
 | IndependentProviderStop,TaskProvider => false
 | _,_ => true end.
Record running := Running { handle : N; key : string; task : option N; cancellable : bool; provider : provider_scope; reduced : bool }.
Record state := State { retired : bool; next_handle : N; active : list running }.
Definition initial := State false 0 [].
Inductive settlement := InputLimit | OutputLimit | Rejected | Uncertain.
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
| Launch (name : string) (task : option N) (cancellable : bool) (provider : provider_scope)
| WorkspaceLimit (create local success : bool)
| AwaitWorkspace (owner : N) (local : bool) (entries : list workspace_running)
| Complete (generation : N) | CancelTask (task : N) | CancelKey (name : string)
| Settlement (generation : N) (outcome : settlement) | Shutdown.
Inductive primitive := Start (generation : N) | Cancel (generation : N) (provider : bool)
| RollbackWorkspace | Await (generation : N) | RetryFailure.
Definition cancel_entries (scope : cancellation_scope) (entries : list running) :=
  map (fun entry => Cancel (handle entry) (stop_provider scope (provider entry))) entries.
Definition step (s : state) (o : observation) : state * list primitive :=
  match o with
  | Complete generation =>
      (State (retired s) (next_handle s) (filter (fun entry => negb (N.eqb generation (handle entry))) (active s)), [])
  | Shutdown => (State true (next_handle s) (active s), cancel_entries NoProviderStop (active s))
  | _ => if retired s then (s, []) else
      match o with
      | WorkspaceLimit create local success => (s, if create && negb local && success then [RollbackWorkspace] else [])
      | AwaitWorkspace owner local entries => (s, map Await (workspace_barrier owner local entries))
      | Launch name task cancellable provider =>
          let generation := N.succ (next_handle s) in
          (State false generation (Running generation name task cancellable provider false :: active s), [Start generation])
      | CancelTask task =>
          (* The committed task cancellation already retires the task-wide
             provider owner. Independent requests retain their own identities. *)
          (s, cancel_entries IndependentProviderStop (filter (fun entry => (match Dispatch.task entry with Some owner => N.eqb task owner | None => false end) && cancellable entry) (active s)))
      | CancelKey name =>
          (s, cancel_entries AnyProviderStop (filter (fun entry => String.eqb name (key entry)) (active s)))
      | Settlement generation outcome =>
          match outcome with
          | InputLimit | OutputLimit =>
                  if existsb (fun entry => N.eqb generation (handle entry) && reduced entry) (active s)
                  then (State true (next_handle s) (active s), [])
                  else (State false (next_handle s) (map (fun running =>
                    if N.eqb generation (handle running) then
                      Running (handle running) (key running) (task running) (cancellable running) (provider running) true
                    else running) (active s)), [RetryFailure])
          | Rejected | Uncertain => (State true (next_handle s) (active s), [])
          end
      | _ => (s, [])
      end
  end.
Theorem completion_only_removes_its_generation s generation entry :
  In entry (active (fst (step s (Complete generation)))) <->
  In entry (active s) /\ handle entry <> generation.
Proof.
  simpl. rewrite filter_In, Bool.negb_true_iff, N.eqb_neq.
  intuition congruence.
Qed.
Theorem uncertain_never_retries s generation :
  ~ In RetryFailure (snd (step s (Settlement generation Uncertain))).
Proof.
  unfold step. destruct (retired s); cbn; tauto.
Qed.
Theorem reduced_callback_never_retries s generation outcome entry :
  find (fun running => N.eqb generation (handle running)) (active s) = Some entry ->
  reduced entry = true ->
  ~ In RetryFailure (snd (step s (Settlement generation outcome))).
Proof.
  intros Hentry Hreduced.
  apply find_some in Hentry as [Present Matches].
  assert (Reduced : existsb (fun running => N.eqb generation (handle running) && reduced running) (active s) = true).
  { apply existsb_exists. exists entry. split; [exact Present|]. now rewrite Matches,Hreduced. }
  destruct outcome; unfold step; destruct (retired s); cbn;
    rewrite ?Reduced; cbn; intuition discriminate.
Qed.

Local Lemma retirement_stops_starts_and_retries s observation generation :
  retired s = true ->
  ~ In (Start generation) (snd (step s observation)) /\
  ~ In RetryFailure (snd (step s observation)).
Proof.
  intros Retired. destruct observation; cbn [step]; rewrite ?Retired; cbn;
    try solve [split; tauto].
  unfold cancel_entries. rewrite !in_map_iff. split;
    intros [entry [Impossible _]]; discriminate.
Qed.

Theorem terminal_settlement_prevents_new_work s generation outcome observation next :
  ~ In RetryFailure (snd (step s (Settlement generation outcome))) ->
  ~ In (Start next) (snd (step (fst (step s (Settlement generation outcome))) observation)) /\
  ~ In RetryFailure (snd (step (fst (step s (Settlement generation outcome))) observation)).
Proof.
  intros NoRetry. apply retirement_stops_starts_and_retries.
  unfold step in *. destruct (retired s) eqn:Retired; [exact Retired|].
  destruct outcome; cbn in *; try reflexivity;
    destruct (existsb _ _); cbn in *; try reflexivity;
    exfalso; apply NoRetry; now left.
Qed.

Theorem shutdown_never_cancels_provider s generation stop_provider :
  In (Cancel generation stop_provider) (snd (step s Shutdown)) -> stop_provider = false.
Proof.
  change (In (Cancel generation stop_provider)
    (map (fun entry => Cancel (handle entry) false) (active s)) -> stop_provider = false).
  rewrite in_map_iff. intros [entry [H _]]. inversion H. reflexivity.
Qed.

Theorem ticket_provider_cancellation_keeps_registered_handle s name generation :
 In (Cancel generation true) (snd (step s (CancelKey name))) ->
 exists entry, In entry (active s) /\ handle entry = generation /\
   key entry = name /\ provider entry <> NoProvider.
Proof.
 unfold step. destruct (retired s); [cbn;tauto|].
 unfold snd, cancel_entries. rewrite in_map_iff.
 intros [entry [Action Selected]]. apply filter_In in Selected as [Present Named].
 apply String.eqb_eq in Named. injection Action as Handle Stops.
 exists entry. repeat split; try congruence.
 destruct (provider entry); cbn in Stops; congruence.
Qed.

Theorem task_provider_cancellation_only_stops_independent_entries s owner generation :
 In (Cancel generation true) (snd (step s (CancelTask owner))) ->
 exists entry, In entry (active s) /\ handle entry = generation /\
   provider entry = IndependentProvider.
Proof.
 unfold step. destruct (retired s); [cbn;tauto|].
 unfold snd, cancel_entries. rewrite in_map_iff.
 intros [entry [Action Selected]]. apply filter_In in Selected as [Present _].
 injection Action as Handle Stops. exists entry. repeat split; try congruence.
 destruct (provider entry); cbn in Stops; congruence.
Qed.

Theorem launch_installs_handle_before_run s name owner cancellable provider :
  retired s = false ->
  exists generation,
  let result := step s (Launch name owner cancellable provider) in
  next_handle s < generation /\
  next_handle (fst result) = generation /\
  retired (fst result) = false /\
  snd result = [Start generation] /\
  Permutation (Running generation name owner cancellable provider false :: active s)
    (active (fst result)).
Proof.
  intros H. exists (N.succ (next_handle s)). unfold step. rewrite H. cbn.
  repeat split; auto using N.lt_succ_diag_r, Permutation_refl.
Qed.
