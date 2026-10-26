From Stdlib Require Import String List Bool NArith Lia Sorting.Permutation.
From Selvedge.Foundation Require Import Json JsonProofs Schema RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs Images
 ContextUpdates Callbacks Scheduler SchedulerChangesProofs CallbackChangesProofs
 WorldInvariant ForkNativeHistoryProofs ForkPreservation NativeResultTicketProofs
 NativeResultWorldFrame.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

(* An allocated result operation_number is fresh in history as well as in the active
   operation registry. Completed receipts remain in history after their leases
   disappear from the active ticket set. *)
Definition historical_result_tickets_below (ceiling : N) (history : list message) :=
 Forall (fun entry => match entry with
 | ToolReceipt _ operation_number _ _ _ | AfterReceipt _ operation_number _ _ => (operation_number < ceiling)%N
 | _ => True end) history.

Lemma the_initial_world_has_no_historical_result_leases :
 Forall (fun task => historical_result_tickets_below (world_next_ticket State.initial) (task_history task))
   (world_tasks State.initial).
Proof. constructor. Qed.

Lemma advancing_the_ticket_supply_preserves_historical_result_leases : forall earlier later history,
 (earlier <= later)%N -> historical_result_tickets_below earlier history ->
 historical_result_tickets_below later history.
Proof.
 intros earlier later history Monotone Valid; eapply Forall_impl; [|exact Valid].
 intros entry Bound; destruct entry; cbn in *; auto; lia.
Qed.

Lemma a_fresh_result_has_no_previous_progress : forall history owner invocation ticket plugins,
 historical_result_tickets_below ticket history ->
 fold_left (WorldInvariant.after_step owner (Operation ticket invocation false (Executing ticket)) plugins)
   history WorldInvariant.ResultAbsent = WorldInvariant.ResultAbsent.
Proof.
 intros history owner invocation ticket plugins Fresh.
 induction Fresh as [|entry rest Bound Tail IH]; [reflexivity|].
 cbn [fold_left].
 assert (Neutral : WorldInvariant.after_step owner (Operation ticket invocation false (Executing ticket))
   plugins WorldInvariant.ResultAbsent entry = WorldInvariant.ResultAbsent).
 { destruct entry; try reflexivity; cbn [WorldInvariant.after_step operation_id].
   all: match type of Bound with (?receipt < ?ceiling)%N =>
     assert (Different : N.eqb receipt ceiling = false) by (apply N.eqb_neq; lia) end.
   all: rewrite Different, andb_false_r; reflexivity. }
 rewrite Neutral; exact IH.
Qed.



Lemma a_fresh_tool_receipt_certifies_the_initial_after_chain :
 forall history owner invocation ticket plugins result failed,
 historical_result_tickets_below ticket history ->
 fold_left (WorldInvariant.after_step owner
   (Operation ticket invocation false (AfterHooksReady plugins result failed)) plugins)
   (history ++ [ToolReceipt owner ticket invocation result failed]) WorldInvariant.ResultAbsent =
 WorldInvariant.ResultWaiting result failed plugins.
Proof.
 intros history owner invocation ticket plugins result failed Fresh.
 rewrite fold_left_app.
 pose proof (a_fresh_result_has_no_previous_progress history owner invocation ticket plugins Fresh) as Empty.
 change (fold_left (WorldInvariant.after_step owner
   (Operation ticket invocation false (AfterHooksReady plugins result failed)) plugins)
   history WorldInvariant.ResultAbsent = WorldInvariant.ResultAbsent) in Empty.
 rewrite Empty.
 cbn [fold_left WorldInvariant.after_step operation_id operation_call].
 rewrite !N.eqb_refl. cbn [andb WorldInvariant.same_call].
 unfold WorldInvariant.same_call; rewrite JsonProofs.equal_is_reflexive; reflexivity.
Qed.

Definition result_task (owner ticket : N) (invocation : call) (remaining : list call)
 (result : json) (failed : bool) (source : task) :=
 match Callbacks.after_plugins source with
 | [] => append_history [FunctionOutput (call_id invocation) result failed]
     (with_activity (PendingCalls remaining) source)
 | plugins => with_operations
     (task_operations source ++ [Operation ticket invocation false (AfterHooksReady plugins result failed)])
     (append_history [ToolReceipt owner ticket invocation result failed]
       (with_activity (PendingCalls remaining) source))
 end.

Definition result_lifecycle (running : bool) (phase : activity) (operations : list operation) :=
 if running then Running phase operations else Stopped phase operations.

Lemma result_task_history : forall owner ticket invocation remaining result failed source,
 task_history (result_task owner ticket invocation remaining result failed source) =
 task_history source ++ match Callbacks.after_plugins source with
 | [] => [FunctionOutput (call_id invocation) result failed]
 | _ => [ToolReceipt owner ticket invocation result failed] end.
Proof.
 intros; unfold result_task; destruct (Callbacks.after_plugins source);
 destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
 destruct lifecycle; reflexivity.
Qed.

Lemma changing_an_active_phase_keeps_its_observations : forall source phase operations running next,
 task_lifecycle source = result_lifecycle running phase operations ->
 task_activity (with_activity next source) = next /\
 task_history (with_activity next source) = task_history source /\
 task_operations (with_activity next source) = task_operations source /\
 native_result_task_frame (with_activity next source) = native_result_task_frame source.
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]
   phase operations running next Active; cbn [task_lifecycle] in Active; subst lifecycle;
   destruct running; repeat split; reflexivity.
Qed.

Lemma an_active_result_keeps_its_task_frame : forall owner ticket invocation remaining result failed source phase operations running,
 task_lifecycle source = result_lifecycle running phase operations -> phase <> Idle ->
 native_result_retains_task source (result_task owner ticket invocation remaining result failed source).
Proof.
 intros owner ticket invocation remaining result failed source phase operations running Active NonIdle.
 unfold native_result_retains_task; split.
 - unfold native_result_task_frame, result_task; destruct (Callbacks.after_plugins source);
   destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
   cbn [task_lifecycle] in Active; subst lifecycle; destruct running; reflexivity.
 - split; [eexists; apply result_task_history|].
   rewrite Active; destruct running; [exact I|].
   intro IdlePhase; contradiction.
Qed.

Lemma continuing_an_active_result_keeps_its_task_frame :
 forall owner ticket invocation remaining result failed source phase operations running,
 task_lifecycle source = result_lifecycle running phase operations ->
 native_result_task_frame source = native_result_task_frame
   (result_task owner ticket invocation remaining result failed (with_activity (PendingCalls remaining) source)).
Proof.
 intros owner ticket invocation remaining result failed source phase operations running Active.
 destruct (changing_an_active_phase_keeps_its_observations source phase operations running (PendingCalls remaining) Active)
   as [_ [_ [_ Frame]]].
 rewrite <- Frame at 1; refine (proj1 (an_active_result_keeps_its_task_frame owner ticket invocation remaining result failed
   (with_activity (PendingCalls remaining) source) (PendingCalls remaining) operations running _ _)).
 - destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
   cbn [task_lifecycle] in Active; subst lifecycle; destruct running; reflexivity.
 - discriminate.
Qed.

Lemma result_task_operations : forall owner ticket invocation remaining result failed source,
 task_operations (result_task owner ticket invocation remaining result failed source) =
 task_operations source ++ match Callbacks.after_plugins source with
 | [] => [] | plugins => [Operation ticket invocation false (AfterHooksReady plugins result failed)] end.
Proof.
 intros; unfold result_task; destruct (Callbacks.after_plugins source);
 destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
 destruct lifecycle; cbn; try rewrite app_nil_r; reflexivity.
Qed.

Lemma result_task_contract : forall owner ticket invocation remaining result failed source,
 task_contract (result_task owner ticket invocation remaining result failed source) = task_contract source.
Proof.
 intros; unfold result_task; destruct (Callbacks.after_plugins source);
 destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
 destruct lifecycle; reflexivity.
Qed.

Lemma result_task_phase : forall owner ticket invocation remaining result failed source phase operations running,
 task_lifecycle source = result_lifecycle running phase operations ->
 task_activity (result_task owner ticket invocation remaining result failed source) = PendingCalls remaining.
Proof.
 intros; unfold result_task; destruct (Callbacks.after_plugins source);
 destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
 cbn [task_lifecycle] in H; subst lifecycle; destruct running; reflexivity.
Qed.

Lemma result_task_after_plugins : forall owner ticket invocation remaining result failed source,
 Callbacks.after_plugins (result_task owner ticket invocation remaining result failed source) =
 Callbacks.after_plugins source.
Proof. intros; unfold Callbacks.after_plugins; now rewrite result_task_contract. Qed.

Lemma result_task_settings : forall owner ticket invocation remaining result failed source,
 task_current_settings (result_task owner ticket invocation remaining result failed source) = task_current_settings source.
Proof.
 intros; unfold result_task; destruct (Callbacks.after_plugins source);
 destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
 destruct lifecycle; reflexivity.
Qed.

Lemma old_operation_search_skips_a_fresh_ticket : forall operations ticket,
 Forall (fun operation => Forall (fun active => (active < ticket)%N)
   (WorldInvariant.operation_tickets operation)) operations ->
 find (Callbacks.operation_executing ticket) operations = None.
Proof.
 intros operations ticket Bounded; induction Bounded as [|operation rest Bound Tail IH]; [reflexivity|].
 assert (NotExecuting : Callbacks.operation_executing ticket operation = false).
 { destruct operation as [operation_number invocation announced stage].
   destruct stage; cbn [Callbacks.operation_executing WorldInvariant.operation_tickets] in *; try reflexivity.
   all: inversion Bound as [|? ? First Remaining]; subst.
   all: destruct (N.eqb ticket0 operation_number) eqn:Same.
   all: try (apply N.eqb_eq in Same; apply N.eqb_neq; lia).
   all: inversion Remaining as [|? ? Last _]; subst; apply N.eqb_neq; lia. }
 cbn [find]; rewrite NotExecuting; exact IH.
Qed.

Lemma updating_a_fresh_result_preserves_older_operations : forall operations ticket stage,
 Forall (fun operation => (operation_id operation < ticket)%N) operations ->
 map (fun current => if N.eqb ticket (operation_id current)
   then Operation (operation_id current) (operation_call current) (operation_announced current) stage
   else current) operations = operations.
Proof.
 intros operations ticket stage Bounded; induction Bounded as [|operation rest Bound Tail IH]; [reflexivity|].
 cbn [map]. assert (Different : N.eqb ticket (operation_id operation) = false)
   by (apply N.eqb_neq; lia).
 now rewrite Different, IH.
Qed.

Lemma nested_task_replacement_uses_its_last_value : forall value owner first last,
 put_task owner last (put_task owner first value) = put_task owner last value.
Proof.
 intros value owner first last; unfold put_task, with_tasks; cbv [set]; cbn.
 f_equal. revert owner; induction (world_tasks value) as [|head rest IH]; intros owner; [reflexivity|].
 cbn [replace]. destruct (N.eqb owner 0) eqn:Zero; cbn [replace]; rewrite Zero; [reflexivity|].
 f_equal; apply IH.
Qed.

Lemma find_over_append : forall (A : Type) (test : A -> bool) left right,
 find test (left ++ right) = match find test left with Some value => Some value | None => find test right end.
Proof.
 intros A test left; induction left as [|head rest IH]; intros right; [reflexivity|].
 cbn [find app]; destruct (test head); [reflexivity|exact (IH right)].
Qed.

Local Lemma pending_after_hook_results_keep_the_feature_frame :
 forall owner operation result failed current before plugin plugins,
 Callbacks.after_plugins current = plugin :: plugins ->
 Tasks.apply_result owner current (Callbacks.begin_result_plan owner operation result failed current) before =
 put_task owner (Callbacks.begin_result owner operation result failed current) before.
Proof.
 intros owner operation result failed current before plugin plugins Hooks.
 unfold Tasks.apply_result, Callbacks.begin_result, Callbacks.begin_result_changes, Callbacks.begin_result_plan.
 now rewrite Hooks.
Qed.

Theorem internal_native_results_use_the_exact_result_task :
 forall value owner source invocation remaining result failed,
 find_task owner value = Some source ->
 (exists phase operations running, task_lifecycle source = result_lifecycle running phase operations) ->
 Forall (fun operation => Forall (fun active => (active < world_next_ticket value)%N)
   (WorldInvariant.operation_tickets operation)) (task_operations source) ->
 decision_world (Scheduler.internal_result owner invocation remaining result failed source value) =
 put_task owner (result_task owner (world_next_ticket value) invocation remaining result failed source)
   (match Callbacks.after_plugins source with [] => value
    | _ => with_ticket (N.succ (world_next_ticket value)) value end).
Proof.
 intros value owner source invocation remaining result failed Found [phase [operations [running Running]]] Bounded.
 unfold Scheduler.internal_result, result_task.
 destruct (Callbacks.after_plugins source) as [|plugin plugins] eqn:Plugins.
 - cbn [acknowledged accept decision_world].
   rewrite (commit_changes_use_the_observed_owner owner _ value source Found).
   destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
     cbn [task_lifecycle] in Running; subst lifecycle; destruct running; reflexivity.
 - cbn [allocate_ticket].
   assert (Allocated : find_task owner (with_ticket (N.succ (world_next_ticket value)) value) = Some source)
     by exact Found.
   rewrite (commit_changes_use_the_observed_owner owner _ _ source Allocated).
   rewrite tool_completed_expression.
   assert (Added : find_task owner (put_task owner
     (TaskChange.apply [TaskChange.AddOperation (Operation (world_next_ticket value) invocation false
       (Executing (world_next_ticket value))); TaskChange.ChangePhase (PendingCalls remaining)] source)
     (with_ticket (N.succ (world_next_ticket value)) value)) = Some
     (TaskChange.apply [TaskChange.AddOperation (Operation (world_next_ticket value) invocation false
       (Executing (world_next_ticket value))); TaskChange.ChangePhase (PendingCalls remaining)] source)).
   { apply registry_replace_selected with (previous:=source); exact Allocated. }
   rewrite Added.
   assert (Changes : TaskChange.apply [TaskChange.AddOperation (Operation (world_next_ticket value) invocation false
       (Executing (world_next_ticket value))); TaskChange.ChangePhase (PendingCalls remaining)] source =
     with_operations (task_operations source ++ [Operation (world_next_ticket value) invocation false
       (Executing (world_next_ticket value))]) (with_activity (PendingCalls remaining) source)).
   { destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
       cbn [task_lifecycle] in Running; subst lifecycle; destruct running; reflexivity. }
   rewrite Changes.
   assert (Operations : task_operations (with_operations (task_operations source ++
       [Operation (world_next_ticket value) invocation false (Executing (world_next_ticket value))])
       (with_activity (PendingCalls remaining) source)) = task_operations source ++
       [Operation (world_next_ticket value) invocation false (Executing (world_next_ticket value))]).
   { destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
       cbn [task_lifecycle] in Running; subst lifecycle; destruct running; reflexivity. }
   rewrite Operations, find_over_append, (old_operation_search_skips_a_fresh_ticket _ _ Bounded).
   cbn [find Callbacks.operation_executing RequestReceiver.operation_executing
     RequestReceiver.operation_receiver operation_stage]. rewrite N.eqb_refl.
   cbn [acknowledged accept decision_world].
   assert (SamePlugins : Callbacks.after_plugins
     (with_operations (task_operations source ++ [Operation (world_next_ticket value) invocation false
       (Executing (world_next_ticket value))]) (with_activity (PendingCalls remaining) source)) =
     plugin :: plugins).
   { destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
       cbn [task_lifecycle] in Running; subst lifecycle; destruct running; exact Plugins. }
   rewrite pending_after_hook_results_keep_the_feature_frame with (plugin:=plugin) (plugins:=plugins)
     by exact SamePlugins.
   unfold Callbacks.begin_result, Callbacks.begin_result_changes, Callbacks.begin_result_plan.
   rewrite SamePlugins; cbn [Tasks.result_changes TaskChange.apply TaskChange.apply_edit fold_left].
   rewrite TaskChangeProofs.appending_history_keeps_operations, Operations, map_app.
   assert (Ids : Forall (fun operation => (operation_id operation < world_next_ticket value)%N)
     (task_operations source)).
   { eapply Forall_impl; [|exact Bounded]. intros operation Bound; inversion Bound; assumption. }
   rewrite updating_a_fresh_result_preserves_older_operations by exact Ids.
   cbn [map operation_id operation_call operation_announced]. rewrite N.eqb_refl.
   rewrite nested_task_replacement_uses_its_last_value. f_equal.
   destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
     cbn [task_lifecycle] in Running; subst lifecycle; destruct running; reflexivity.
Qed.

Lemma result_tasks_keep_unrelated_calls_open :
 forall owner ticket invocation remaining result failed source pending,
 call_id invocation <> call_id pending ->
 WorldInvariant.call_open (task_history
   (result_task owner ticket invocation remaining result failed source)) pending =
 WorldInvariant.call_open (task_history source) pending.
Proof.
 intros owner ticket invocation remaining result failed source pending Different.
 rewrite result_task_history.
 unfold WorldInvariant.call_open, Callbacks.call_known, ContextSelection.has_output.
 destruct (Callbacks.after_plugins source); rewrite !existsb_app; cbn [existsb].
 all: assert (Apart : String.eqb (call_id invocation) (call_id pending) = false)
   by (apply String.eqb_neq; exact Different).
 all: rewrite ?Apart, ?orb_false_r; reflexivity.
Qed.

Lemma result_tasks_keep_before_hook_certificates :
 forall owner ticket invocation remaining result failed source pending plugins,
 WorldInvariant.hooks_correspond owner
   (result_task owner ticket invocation remaining result failed source) pending plugins =
 WorldInvariant.hooks_correspond owner source pending plugins.
Proof.
 intros. unfold WorldInvariant.hooks_correspond, Scheduler.before_plugins.
 rewrite result_task_history, result_task_contract.
 destruct (Callbacks.after_plugins source); rewrite fold_left_app; reflexivity.
Qed.

Lemma result_tasks_keep_existing_stage_certificates :
 forall owner ticket invocation remaining result failed source operation,
 ticket <> operation_id operation ->
 WorldInvariant.operation_stage_valid owner
   (result_task owner ticket invocation remaining result failed source) operation =
 WorldInvariant.operation_stage_valid owner source operation.
Proof.
 intros owner ticket invocation remaining result failed source operation Apart.
 destruct operation as [operation_number pending announced stage]; cbn [operation_id] in Apart.
 unfold WorldInvariant.operation_stage_valid; destruct stage;
 unfold WorldInvariant.approval_corresponds, WorldInvariant.results_correspond, WorldInvariant.review_right;
 rewrite ?result_task_history, ?result_task_contract, ?result_task_settings, ?result_task_after_plugins;
 destruct (Callbacks.after_plugins source); rewrite ?fold_left_app;
 cbn [fold_left WorldInvariant.after_step operation_id]; try reflexivity.
 all: assert (Different : N.eqb ticket operation_number = false) by (apply N.eqb_neq; exact Apart).
 all: rewrite Different, andb_false_r; reflexivity.
Qed.

Lemma result_tasks_keep_existing_operation_histories :
 forall owner ticket invocation remaining result failed source operation,
 call_id invocation <> call_id (operation_call operation) ->
 WorldInvariant.operation_history
   (result_task owner ticket invocation remaining result failed source) operation =
 WorldInvariant.operation_history source operation.
Proof.
 intros owner ticket invocation remaining result failed source operation Apart.
 unfold WorldInvariant.operation_history; destruct (operation_announced operation).
 - rewrite result_task_history, result_task_settings.
   destruct (Callbacks.after_plugins source); rewrite existsb_app; cbn [existsb].
   all: try rewrite orb_false_r; try reflexivity.
   all: destruct failed; cbn; rewrite ?orb_false_r; try reflexivity.
   all: assert (Different : String.eqb (call_id invocation) (call_id (operation_call operation)) = false)
     by (apply String.eqb_neq; exact Apart).
   all: rewrite Different; cbn; rewrite orb_false_r; reflexivity.
 - apply result_tasks_keep_unrelated_calls_open; exact Apart.
Qed.

Lemma result_tasks_preserve_context_bindings :
 forall owner ticket invocation remaining result failed source,
 ContextUpdates.bindings (task_history
   (result_task owner ticket invocation remaining result failed source)) =
 ContextUpdates.bindings (task_history source).
Proof.
 intros; rewrite result_task_history; unfold ContextUpdates.bindings.
 destruct (Callbacks.after_plugins source); rewrite fold_left_app; reflexivity.
Qed.

Lemma result_task_phase_is_valid : forall owner ticket invocation remaining result failed source phase operations running,
 task_lifecycle source = result_lifecycle running phase operations ->
 WorldInvariant.calls_valid (task_history source) (invocation :: remaining) = true ->
 WorldInvariant.phase_valid (result_task owner ticket invocation remaining result failed source) = true /\
 WorldInvariant.checked_phase owner (result_task owner ticket invocation remaining result failed source) = true.
Proof.
 intros owner ticket invocation remaining result failed source phase operations running Running Calls.
 unfold WorldInvariant.phase_valid, WorldInvariant.checked_phase.
 rewrite (result_task_phase owner ticket invocation remaining result failed source phase operations running Running).
 cbn [WorldInvariant.phase_calls]. split; [|reflexivity].
 unfold WorldInvariant.calls_valid in Calls |- *.
 apply andb_true_iff in Calls as [Open Unique].
 cbn [forallb] in Open; apply andb_true_iff in Open as [_ RemainingOpen].
 apply unique_names_nodup in Unique; inversion Unique as [|? ? Apart Tail]; subst.
 assert (AllOpen : forallb (WorldInvariant.call_open (task_history
   (result_task owner ticket invocation remaining result failed source))) remaining = true).
 { apply forallb_forall; intros pending Present.
   rewrite result_tasks_keep_unrelated_calls_open.
   - apply forallb_forall with (x:=pending) in RemainingOpen; assumption.
   - intro Equal; apply Apart; rewrite Equal; apply in_map; exact Present. }
 rewrite AllOpen; cbn [andb]; rewrite andb_true_r; apply unique_names_nodup; exact Tail.
Qed.

Lemma result_tasks_preserve_the_history_ticket_supply :
 forall owner ticket invocation remaining result failed source,
 historical_result_tickets_below ticket (task_history source) ->
 historical_result_tickets_below
   (match Callbacks.after_plugins source with [] => ticket | _ => N.succ ticket end)
   (task_history (result_task owner ticket invocation remaining result failed source)).
Proof.
 intros owner ticket invocation remaining result failed source Fresh.
 rewrite result_task_history. destruct (Callbacks.after_plugins source); apply Forall_app; split.
 - exact Fresh.
 - constructor; [exact I|constructor].
 - eapply Forall_impl; [|exact Fresh]. intros entry Bound; destruct entry; cbn in *; auto; lia.
 - constructor; [cbn; lia|constructor].
Qed.

Lemma after_hook_results_leave_every_call_open :
 forall owner ticket invocation remaining result failed source pending plugin plugins,
 Callbacks.after_plugins source = plugin :: plugins ->
 WorldInvariant.call_open (task_history
   (result_task owner ticket invocation remaining result failed source)) pending =
 WorldInvariant.call_open (task_history source) pending.
Proof.
 intros. rewrite result_task_history, H.
 unfold WorldInvariant.call_open, Callbacks.call_known, ContextSelection.has_output.
 rewrite !existsb_app; cbn [existsb]; now rewrite !orb_false_r.
Qed.

Theorem accepted_native_results_preserve_the_local_progress_requirements :
 forall owner ticket invocation remaining result failed source phase operations running,
 task_lifecycle source = result_lifecycle running phase operations ->
 WorldInvariant.calls_valid (task_history source) (invocation :: remaining) = true ->
 Schema.unique_names (map call_id (invocation :: remaining) ++
   map (fun operation => call_id (operation_call operation)) (task_operations source)) = true ->
 WorldInvariant.operations_valid owner source = true ->
 WorldInvariant.hooks_correspond owner source invocation [] = true ->
 (exists definition, find_tool (call_name invocation) (contract_tools (task_contract source)) = Some definition) ->
 historical_result_tickets_below ticket (task_history source) ->
 Forall (fun operation => (operation_id operation < ticket)%N) (task_operations source) ->
 Scheduler.internal_result_available source = true ->
 let next := result_task owner ticket invocation remaining result failed source in
 WorldInvariant.phase_valid next = true /\
 WorldInvariant.checked_phase owner next = true /\
 WorldInvariant.operations_valid owner next = true.
Proof.
 intros owner ticket invocation remaining result failed source phase operations running
   Running Calls Unique Previous Hooks Known Historical Bounded Room next.
 pose proof (result_task_phase_is_valid owner ticket invocation remaining result failed source
   phase operations running Running Calls) as [Phase Checked].
 split; [exact Phase|]. split; [exact Checked|].
 unfold WorldInvariant.operations_valid in Previous.
 repeat rewrite andb_true_iff in Previous.
 destruct Previous as [[Capacity _] ValidOperations].
 apply unique_names_nodup in Unique; cbn [map app] in Unique.
 inversion Unique as [|? ? Apart Tail]; subst.
 assert (OldOperations : forallb (fun operation =>
   WorldInvariant.hooks_correspond owner next (operation_call operation) [] &&
   WorldInvariant.operation_history next operation && WorldInvariant.operation_stage_valid owner next operation &&
   match find_tool (call_name (operation_call operation)) (contract_tools (task_contract next)) with
   | Some _ => true | None => false end) (task_operations source) = true).
 { apply forallb_forall; intros operation Present.
   apply forallb_forall with (x:=operation) in ValidOperations; [|exact Present].
   unfold next.
   rewrite result_tasks_keep_before_hook_certificates, result_tasks_keep_existing_stage_certificates,
     result_tasks_keep_existing_operation_histories, result_task_contract; try exact ValidOperations.
   - intro Equal; apply Apart; apply in_or_app; right; rewrite Equal; apply in_map_iff; exists operation; auto.
   - apply Forall_forall with (x:=operation) in Bounded; [lia|exact Present]. }
 unfold next; unfold WorldInvariant.operations_valid.
 rewrite (result_task_phase owner ticket invocation remaining result failed source phase operations running Running),
   result_task_operations.
 cbn [WorldInvariant.phase_calls]. fold next.
 destruct (Callbacks.after_plugins source) as [|plugin plugins] eqn:Plugins.
 - rewrite app_nil_r. repeat rewrite andb_true_iff; repeat split; try exact Capacity; try exact OldOperations.
   apply unique_names_nodup; exact Tail.
 - rewrite length_app; cbn [length].
   repeat rewrite andb_true_iff; repeat split.
   + unfold Scheduler.internal_result_available in Room; rewrite Plugins in Room.
     apply N.leb_le; apply N.ltb_lt in Room; rewrite Nat2N.inj_add; cbn; lia.
   + apply unique_names_nodup. rewrite map_app; cbn [map operation_call].
     rewrite app_assoc. eapply Permutation_NoDup; [|exact Unique].
     exact (Permutation_app_comm [call_id invocation]
       (map call_id remaining ++ map (fun operation => call_id (operation_call operation)) (task_operations source))).
   + rewrite forallb_app, OldOperations. cbn [andb forallb].
     repeat rewrite andb_true_iff; repeat split.
     * unfold next; rewrite result_tasks_keep_before_hook_certificates; exact Hooks.
     * unfold WorldInvariant.operation_history; cbn [operation_announced operation_call].
       unfold next; rewrite (after_hook_results_leave_every_call_open owner ticket invocation remaining result failed source invocation plugin plugins Plugins).
       unfold WorldInvariant.calls_valid in Calls; apply andb_true_iff in Calls as [Open _].
       cbn [forallb] in Open; apply andb_true_iff in Open as [First _]; exact First.
     * cbn [WorldInvariant.operation_stage_valid operation_stage].
       unfold WorldInvariant.results_correspond; unfold next.
       rewrite result_task_after_plugins, result_task_history, Plugins.
       rewrite (a_fresh_tool_receipt_certifies_the_initial_after_chain
         (task_history source) owner invocation ticket (plugin :: plugins) result failed Historical).
       unfold WorldInvariant.same_references, WorldInvariant.same_values.
       rewrite !JsonProofs.equal_is_reflexive, Bool.eqb_reflx; reflexivity.
     * destruct Known as [definition Found]. unfold next; rewrite result_task_contract; cbn [operation_call]; rewrite Found; reflexivity.
Qed.

Lemma result_tasks_own_exactly_the_result_lease :
 forall owner ticket invocation remaining result failed source operations running,
 task_lifecycle source = result_lifecycle running (PendingCalls remaining) operations ->
 WorldInvariant.task_tickets (result_task owner ticket invocation remaining result failed source) =
 WorldInvariant.task_tickets source ++
   match Callbacks.after_plugins source with [] => [] | _ => [ticket] end.
Proof.
 intros owner ticket invocation remaining result failed source operations running Running.
 unfold WorldInvariant.task_tickets.
 rewrite (result_task_phase owner ticket invocation remaining result failed source
   (PendingCalls remaining) operations running Running), result_task_operations.
 assert (Phase : task_activity source = PendingCalls remaining).
 { destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed];
   cbn [task_lifecycle] in Running; subst lifecycle; destruct running; reflexivity. }
 rewrite Phase; cbn [WorldInvariant.phase_tickets].
 destruct (Callbacks.after_plugins source); rewrite flat_map_app; cbn [flat_map WorldInvariant.operation_tickets];
 rewrite ?app_nil_r; reflexivity.
Qed.

Lemma with_the_current_ticket_is_the_original_world : forall value,
 with_ticket (world_next_ticket value) value = value.
Proof. intros []; reflexivity. Qed.

Theorem actual_internal_native_results_preserve_every_world_requirement :
 forall value owner source invocation remaining result failed operations running,
 WorldInvariant.well_formed value ->
 find_task owner value = Some source ->
 task_lifecycle source = result_lifecycle running (PendingCalls remaining) operations ->
 WorldInvariant.calls_valid (task_history source) (invocation :: remaining) = true ->
 Schema.unique_names (map call_id (invocation :: remaining) ++
   map (fun operation => call_id (operation_call operation)) (task_operations source)) = true ->
 WorldInvariant.hooks_correspond owner source invocation [] = true ->
 (exists definition, find_tool (call_name invocation) (contract_tools (task_contract source)) = Some definition) ->
 historical_result_tickets_below (world_next_ticket value) (task_history source) ->
 Scheduler.internal_result_available source = true ->
 WorldInvariant.well_formed
   (decision_world (Scheduler.internal_result owner invocation remaining result failed source value)).
Proof.
 intros value owner source invocation remaining result failed operations running
   Valid Found Running Calls Unique Hooks Known Historical Room.
 pose proof (owned_operation_tickets_precede_the_next_ticket value owner source Valid Found) as Leases.
 assert (Ids : Forall (fun operation => (operation_id operation < world_next_ticket value)%N)
   (task_operations source)).
 { eapply Forall_impl; [|exact Leases]. intros operation Bound; inversion Bound; assumption. }
 pose proof (ForkLineageProofs.lookup_task_requirements value owner source Valid Found) as SourceValid.
 rewrite task_requirements_ignore_the_journal_cursor in SourceValid.
 pose proof (a_valid_task_has_its_progress_requirements owner source value SourceValid)
   as [Context [Phase [Checked Operations]]].
 pose proof (accepted_native_results_preserve_the_local_progress_requirements owner
   (world_next_ticket value) invocation remaining result failed source
   (PendingCalls remaining) operations running Running Calls Unique Operations Hooks Known Historical Ids Room)
   as [NextPhase [NextChecked NextOperations]].
 rewrite (internal_native_results_use_the_exact_result_task value owner source invocation remaining result failed
   Found (ex_intro _ (PendingCalls remaining) (ex_intro _ operations (ex_intro _ running Running))) Leases).
 set (next := result_task owner (world_next_ticket value) invocation remaining result failed source).
 assert (ContextAfter : forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true).
 { unfold next; rewrite result_tasks_preserve_context_bindings; exact Context. }
 assert (Tickets : WorldInvariant.tickets_valid (put_task owner next
   (with_ticket (match Callbacks.after_plugins source with
     [] => world_next_ticket value | _ => N.succ (world_next_ticket value) end) value)) = true).
 { pose proof (result_tasks_own_exactly_the_result_lease owner (world_next_ticket value)
     invocation remaining result failed source operations running Running) as Owned.
   destruct (Callbacks.after_plugins source) eqn:Plugins.
   - apply (a_native_result_preserves_global_ticket_ownership value owner source next false Valid Found).
     unfold next; rewrite Owned; reflexivity.
   - apply (a_native_result_preserves_global_ticket_ownership value owner source next true Valid Found).
     unfold next; rewrite Owned; reflexivity. }
 assert (Frame : native_result_retains_task source next).
 { unfold next; eapply an_active_result_keeps_its_task_frame; [exact Running|discriminate]. }
 assert (Settled : WorldInvariant.well_formed (put_task owner next
   (with_ticket (match Callbacks.after_plugins source with
     [] => world_next_ticket value | _ => N.succ (world_next_ticket value) end) value))).
 { apply native_result_replacement_preserves_every_world_requirement with (old:=source);
     try assumption.
   destruct (Callbacks.after_plugins source); lia. }
 destruct (Callbacks.after_plugins source); [rewrite with_the_current_ticket_is_the_original_world in Settled|];
 exact Settled.
Qed.
