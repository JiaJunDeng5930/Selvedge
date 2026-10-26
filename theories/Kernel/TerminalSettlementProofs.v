From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs Schema.
From Selvedge.Kernel Require Import Numbers Domain State Inputs History ContextUpdates ContextSelection
 Tasks Callbacks HookCallbacks HookRules TaskScope TerminalSettlement CallbackChangesProofs
 WorldInvariant WorldInvariantProofs ForkPreservation
 CommitAdmission LifecycleProofs ArchivedRuntimeFrameProofs.
From Selvedge.Features Require Import TaskGraph.
Import ListNotations.
Open Scope list_scope.

Definition result_value (previous : json) (failed : bool) (outcome : after_outcome) :=
 match HookRules.after_apply previous outcome with
 | HookRules.ContinueResult result => (result,failed)
 | HookRules.RefuseResult code reason => (State.failure code reason,true)
 end.
Definition settled_task (owner : N) (original : Domain.operation) (plugin : json)
 (previous : json) (failed : bool) (outcome : after_outcome) (current : task) :=
 let '(result,error) := result_value previous failed outcome in
 with_operations (Callbacks.remove_operation (operation_id original) (task_operations current))
   (append_history [AfterReceipt owner (operation_id original) plugin (Inputs.after_json outcome);
     History.operation_result original result error] current).

Lemma a_terminal_archived_callback_uses_the_exact_settlement :
 forall owner identity ticket outcome before current operations original expected plugin pending previous failed,
 find_task owner before = Some current -> task_lifecycle current = Archived operations ->
 find (fun operation => N.eqb identity (operation_id operation)) operations = Some original ->
 operation_stage original = AwaitingAfterHook expected plugin pending previous failed ->
 expected = ticket ->
 (match HookRules.after_apply previous outcome, pending with
  | HookRules.RefuseResult _ _, _ | _, [] => true | _, _ => false end) = true ->
 HookCallbacks.after_completed owner identity ticket outcome before =
 Callbacks.acknowledged (put_task owner
   (settled_task owner original plugin previous failed outcome current) before).
Proof.
 intros owner identity ticket outcome before current operations original expected plugin pending previous failed
 Found ArchivedTask Owned Stage Same Terminal.
 rewrite CallbackChangesProofs.after_completed_expression, Found.
 unfold task_operations; rewrite ArchivedTask, Owned, Stage, Same, N.eqb_refl.
 unfold settled_task, result_value.
 destruct outcome; cbn [HookRules.after_apply] in Terminal |- *;
 try (destruct pending; try discriminate).
 all: destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
   cbn in ArchivedTask; subst lifecycle;
   cbv [HookCallbacks.after_result_plan HookCallbacks.after_result_plan_for Tasks.apply_result Tasks.result_changes Tasks.prefix_result
     Tasks.mark_context_wake Callbacks.settle_operation_plan
     TaskChange.apply TaskChange.apply_edit List.fold_left Callbacks.settle_operation_changes Tasks.wake_after_result_changes Tasks.promote_changes
     append_history with_history with_operations with_lifecycle task_operations task_lifecycle task_activity RecordSet.set]; cbn;
   repeat rewrite <- app_assoc; reflexivity.
Qed.

Lemma settlement_preserves_the_archived_frame :
 forall owner original plugin previous failed outcome current operations,
 task_lifecycle current = Archived operations ->
 ForkPreservation.fork_retains_task current
   (settled_task owner original plugin previous failed outcome current).
Proof.
 intros owner original plugin previous failed outcome current operations ArchivedTask.
 unfold settled_task; destruct (result_value previous failed outcome).
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn in ArchivedTask; subst lifecycle.
 split; [reflexivity|eexists; reflexivity].
Qed.

Lemma settlement_never_restores_its_operation :
 forall owner original plugin previous failed outcome current operations,
 task_lifecycle current = Archived operations ->
 ~ In (operation_id original)
   (map operation_id (task_operations (settled_task owner original plugin previous failed outcome current))).
Proof.
 intros owner original plugin previous failed outcome current operations ArchivedTask Present.
 unfold settled_task in Present; destruct (result_value previous failed outcome).
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn in ArchivedTask; subst lifecycle; cbn in Present.
 apply in_map_iff in Present as [operation [Same Member]].
 apply filter_In in Member as [_ Remaining].
 apply Bool.negb_true_iff in Remaining; rewrite Same, N.eqb_refl in Remaining; discriminate.
Qed.

Lemma settlement_does_not_produce_graph_output :
 forall before owner current operations original plugin previous failed outcome,
 find_task owner before = Some current -> task_lifecycle current = Archived operations ->
 TaskGraph.new_outputs before owner
  (settled_task owner original plugin previous failed outcome current) = [].
Proof.
 intros before owner current operations original plugin previous failed outcome Found ArchivedTask.
 unfold TaskGraph.new_outputs; rewrite Found.
 unfold settled_task; destruct (result_value previous failed outcome).
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn in ArchivedTask; subst lifecycle.
 cbv [task_history with_operations with_lifecycle append_history with_history task_operations task_lifecycle RecordSet.set]; cbn.
 rewrite skipn_app, skipn_all, Nat.sub_diag; cbn.
 unfold History.operation_result; destruct (operation_announced original); reflexivity.
Qed.

Definition terminal_suffix owner original plugin outcome result error :=
 [AfterReceipt owner (operation_id original) plugin (Inputs.after_json outcome);
  History.operation_result original result error].

Lemma terminal_receipts_preserve_context_bindings : forall history owner original plugin outcome result error,
 ContextUpdates.bindings (history ++ terminal_suffix owner original plugin outcome result error) =
 ContextUpdates.bindings history.
Proof.
 intros; unfold ContextUpdates.bindings; rewrite fold_left_app.
 unfold terminal_suffix, History.operation_result; destruct (operation_announced original); reflexivity.
Qed.

Lemma terminal_receipts_preserve_hook_progress :
 forall history owner invocation chain progress actual original plugin outcome result error,
 fold_left (WorldInvariant.hook_step owner invocation chain)
  (history ++ terminal_suffix actual original plugin outcome result error) progress =
 fold_left (WorldInvariant.hook_step owner invocation chain) history progress.
Proof.
 intros; rewrite fold_left_app; unfold terminal_suffix, History.operation_result;
 destruct (operation_announced original); reflexivity.
Qed.

Lemma terminal_receipts_preserve_open_calls : forall history owner original plugin outcome result error invocation,
 call_id invocation <> call_id (operation_call original) ->
 WorldInvariant.call_open
   (history ++ terminal_suffix owner original plugin outcome result error) invocation =
 WorldInvariant.call_open history invocation.
Proof.
 intros history owner original plugin outcome result error invocation Different.
 assert (Distinct : String.eqb (call_id (operation_call original)) (call_id invocation) = false)
   by (apply String.eqb_neq; congruence).
 unfold WorldInvariant.call_open, Callbacks.call_known, ContextSelection.has_output.
 rewrite !existsb_app; unfold terminal_suffix, History.operation_result.
 destruct (operation_call original) eqn:Invocation; cbn in Distinct |- *.
 destruct (operation_announced original); cbn; rewrite ?Distinct, !orb_false_r; reflexivity.
Qed.

Lemma terminal_receipts_preserve_result_progress :
 forall history owner selected chain progress actual original plugin outcome result error,
 operation_id selected <> operation_id original ->
 fold_left (WorldInvariant.after_step owner selected chain)
  (history ++ terminal_suffix actual original plugin outcome result error) progress =
 fold_left (WorldInvariant.after_step owner selected chain) history progress.
Proof.
 intros history owner selected chain progress actual original plugin outcome result error Different.
 assert (Distinct : N.eqb (operation_id original) (operation_id selected) = false)
   by (apply N.eqb_neq; congruence).
 rewrite fold_left_app; unfold terminal_suffix, History.operation_result.
 destruct (operation_announced original); cbn [fold_left WorldInvariant.after_step];
 rewrite Distinct, andb_false_r; reflexivity.
Qed.

Lemma terminal_receipts_preserve_approval :
 forall owner selected reviewer current actual original plugin outcome result error,
 WorldInvariant.approval_corresponds owner
   (with_history (task_history current ++ terminal_suffix actual original plugin outcome result error) current)
   selected reviewer = WorldInvariant.approval_corresponds owner current selected reviewer.
Proof.
 intros owner selected reviewer [contract profile settings lifecycle history queued lineage parent cursor consumed]
 actual original plugin outcome result error.
 unfold WorldInvariant.approval_corresponds; cbv [task_history with_history RecordSet.set]; cbn.
 rewrite fold_left_app; unfold terminal_suffix, History.operation_result;
 destruct (operation_announced original); reflexivity.
Qed.

Lemma unique_call_names_are_distinct : forall names,
 Schema.unique_names names = true -> NoDup names.
Proof.
 intros names; induction names as [|first rest IH]; intros Valid; [constructor|].
 cbn in Valid; apply andb_true_iff in Valid as [Fresh Tail]; constructor; [|apply IH; exact Tail].
 intro Present; apply negb_true_iff in Fresh.
 assert (existsb (String.eqb first) rest = true).
 { apply existsb_exists; exists first; split; [exact Present|apply String.eqb_refl]. }
 congruence.
Qed.

Lemma a_unique_projection_selects_one_member : forall A B (project : A -> B) values selected other,
 NoDup (map project values) -> In selected values -> In other values ->
 project selected = project other -> selected = other.
Proof.
 intros A B project values; induction values as [|first rest IH]; intros selected other Unique Selected Other Same;
 [contradiction|].
 cbn in Unique; inversion Unique as [|? ? Fresh Tail]; subst.
 destruct Selected as [<-|Selected]; destruct Other as [<-|Other]; [reflexivity| | |].
 - exfalso; apply Fresh; apply in_map_iff; exists other; auto.
 - exfalso; apply Fresh; apply in_map_iff; exists selected; split; [exact Same|exact Selected].
 - eapply IH; eauto.
Qed.

Lemma filtered_projection_keeps_unique_names : forall A (project : A -> string) keep values,
 Schema.unique_names (map project values) = true ->
 Schema.unique_names (map project (filter keep values)) = true.
Proof.
 intros A project keep values; induction values as [|first rest IH]; intros Unique; [reflexivity|].
 cbn in Unique; apply andb_true_iff in Unique as [Fresh Tail].
 cbn [filter]; destruct (keep first); [|apply IH; exact Tail].
 cbn [map Schema.unique_names]; apply andb_true_iff; split; [|apply IH; exact Tail].
 apply negb_true_iff; apply negb_true_iff in Fresh.
 apply Bool.not_true_iff_false; intro Present; apply existsb_exists in Present as [name [Member Equal]].
 apply in_map_iff in Member as [value [Name Member]].
 apply filter_In in Member as [Member _].
 assert (existsb (String.eqb (project first)) (map project rest) = true).
 { apply existsb_exists; exists name; split; [apply in_map_iff; exists value; auto|exact Equal]. }
 congruence.
Qed.

Lemma terminal_receipts_preserve_operation_history :
 forall history owner original plugin outcome result error selected current,
 task_history current = history ->
 call_id (operation_call selected) <> call_id (operation_call original) ->
 WorldInvariant.operation_history
  (with_history (history ++ terminal_suffix owner original plugin outcome result error) current) selected =
 WorldInvariant.operation_history current selected.
Proof.
 intros history owner original plugin outcome result error selected
 [contract profile settings lifecycle old_history queued lineage parent cursor consumed] History Different;
 cbn in History; subst old_history.
 assert (Distinct : String.eqb (call_id (operation_call original)) (call_id (operation_call selected)) = false)
   by (apply String.eqb_neq; congruence).
 unfold WorldInvariant.operation_history;
 cbv [with_history task_history task_current_settings RecordSet.set]; cbn.
 destruct (operation_announced selected).
 - rewrite existsb_app; unfold terminal_suffix, History.operation_result.
   destruct (operation_call original) eqn:Invocation; cbn in Distinct |- *.
   destruct (operation_announced original); destruct error; cbn; rewrite ?Distinct, ?andb_false_l, ?orb_false_r; reflexivity.
 - apply terminal_receipts_preserve_open_calls; exact Different.
Qed.

Lemma terminal_receipts_preserve_operation_stage :
 forall owner actual original plugin outcome result error selected current,
 operation_id selected <> operation_id original ->
 WorldInvariant.operation_stage_valid owner
  (with_history (task_history current ++ terminal_suffix actual original plugin outcome result error) current) selected =
 WorldInvariant.operation_stage_valid owner current selected.
Proof.
 intros owner actual original plugin outcome result error selected
 [contract profile settings lifecycle history queued lineage parent cursor consumed] Different.
 unfold WorldInvariant.operation_stage_valid.
 destruct (operation_stage selected); rewrite ?terminal_receipts_preserve_approval;
 cbv [with_history task_current_settings task_contract RecordSet.set]; cbn; try reflexivity.
 all: unfold WorldInvariant.results_correspond, Callbacks.after_plugins;
   cbv [with_history task_history task_contract RecordSet.set]; cbn;
   rewrite terminal_receipts_preserve_result_progress by exact Different; reflexivity.
Qed.

Lemma terminal_receipts_preserve_hook_correspondence :
 forall owner current invocation pending actual original plugin outcome result error,
 WorldInvariant.hooks_correspond owner
  (with_history (task_history current ++ terminal_suffix actual original plugin outcome result error) current)
  invocation pending = WorldInvariant.hooks_correspond owner current invocation pending.
Proof.
 intros owner [contract profile settings lifecycle history queued lineage parent cursor consumed]
 invocation pending actual original plugin outcome result error.
 unfold WorldInvariant.hooks_correspond, Callbacks.after_plugins, Scheduler.before_plugins.
 cbv [with_history task_history task_contract RecordSet.set]; cbn.
 rewrite terminal_receipts_preserve_hook_progress; reflexivity.
Qed.

Lemma other_operations_do_not_change_a_certificate : forall owner current operations selected,
 WorldInvariant.hooks_correspond owner (with_operations operations current) (operation_call selected) [] &&
 WorldInvariant.operation_history (with_operations operations current) selected &&
 WorldInvariant.operation_stage_valid owner (with_operations operations current) selected &&
 (match find_tool (call_name (operation_call selected)) (contract_tools (task_contract (with_operations operations current))) with
  | Some _ => true | None => false end) =
 WorldInvariant.hooks_correspond owner current (operation_call selected) [] &&
 WorldInvariant.operation_history current selected &&
 WorldInvariant.operation_stage_valid owner current selected &&
 (match find_tool (call_name (operation_call selected)) (contract_tools (task_contract current)) with
  | Some _ => true | None => false end).
Proof.
 intros owner [contract profile settings lifecycle history queued lineage parent cursor consumed] operations selected;
 destruct lifecycle; reflexivity.
Qed.

Lemma terminal_receipts_preserve_another_certificate :
 forall owner current selected actual original plugin outcome result error,
 operation_id selected <> operation_id original ->
 call_id (operation_call selected) <> call_id (operation_call original) ->
 let updated := with_history
   (task_history current ++ terminal_suffix actual original plugin outcome result error) current in
 WorldInvariant.hooks_correspond owner updated (operation_call selected) [] &&
 WorldInvariant.operation_history updated selected &&
 WorldInvariant.operation_stage_valid owner updated selected &&
 (match find_tool (call_name (operation_call selected)) (contract_tools (task_contract updated)) with
  | Some _ => true | None => false end) =
 WorldInvariant.hooks_correspond owner current (operation_call selected) [] &&
 WorldInvariant.operation_history current selected &&
 WorldInvariant.operation_stage_valid owner current selected &&
 (match find_tool (call_name (operation_call selected)) (contract_tools (task_contract current)) with
  | Some _ => true | None => false end).
Proof.
 intros owner current selected actual original plugin outcome result error DistinctId DistinctCall updated.
 unfold updated; rewrite terminal_receipts_preserve_hook_correspondence,
 terminal_receipts_preserve_operation_history with (history:=task_history current) by auto.
 rewrite terminal_receipts_preserve_operation_stage by exact DistinctId.
 destruct current; reflexivity.
Qed.

Theorem terminal_settlement_preserves_the_remaining_operation_rights :
 forall owner current operations original plugin previous failed outcome,
 task_lifecycle current = Archived operations -> In original operations ->
 WorldInvariant.operations_valid owner current = true ->
 WorldInvariant.operations_valid owner
   (settled_task owner original plugin previous failed outcome current) = true.
Proof.
 intros owner current operations original plugin previous failed outcome ArchivedTask Owned Valid.
 unfold settled_task; destruct (result_value previous failed outcome) as [result error].
 assert (Operations : task_operations current = operations) by (unfold task_operations; rewrite ArchivedTask; reflexivity).
 rewrite Operations.
 unfold WorldInvariant.operations_valid in Valid |- *.
 assert (OldPhase : WorldInvariant.phase_calls (task_activity current) = [])
   by (unfold task_activity; rewrite ArchivedTask; reflexivity).
 rewrite Operations, OldPhase in Valid; cbn [app] in Valid.
 apply andb_true_iff in Valid as [Bounds Certificates]; apply andb_true_iff in Bounds as [Bound Unique].
 assert (NewOperations : forall history,
  task_operations (with_operations (Callbacks.remove_operation (operation_id original) operations)
    (with_history history current)) = Callbacks.remove_operation (operation_id original) operations).
 { intros history; destruct current as [contract profile settings lifecycle old queued lineage parent cursor consumed];
   cbn in ArchivedTask; subst lifecycle; reflexivity. }
 assert (NewPhase : forall history,
  WorldInvariant.phase_calls (task_activity
   (with_operations (Callbacks.remove_operation (operation_id original) operations) (with_history history current))) = []).
 { intros history; destruct current as [contract profile settings lifecycle old queued lineage parent cursor consumed];
   cbn in ArchivedTask; subst lifecycle; reflexivity. }
 assert (NewContract : forall history,
  task_contract (with_operations (Callbacks.remove_operation (operation_id original) operations)
    (with_history history current)) = task_contract current).
 { intros history; destruct current as [contract profile settings lifecycle old queued lineage parent cursor consumed];
   cbn in ArchivedTask; subst lifecycle; reflexivity. }
 unfold append_history. rewrite NewOperations, NewPhase. cbn [app].
 rewrite NewContract.
 change (N.leb (N.of_nat (List.length (Callbacks.remove_operation (operation_id original) operations))) Limits.operation_limit &&
  Schema.unique_names (map (fun operation => call_id (operation_call operation))
    (Callbacks.remove_operation (operation_id original) operations)) &&
  forallb (fun operation =>
   WorldInvariant.hooks_correspond owner
    (with_operations (Callbacks.remove_operation (operation_id original) operations)
      (with_history (task_history current ++ terminal_suffix owner original plugin outcome result error) current))
      (operation_call operation) [] &&
   WorldInvariant.operation_history
    (with_operations (Callbacks.remove_operation (operation_id original) operations)
      (with_history (task_history current ++ terminal_suffix owner original plugin outcome result error) current)) operation &&
   WorldInvariant.operation_stage_valid owner
    (with_operations (Callbacks.remove_operation (operation_id original) operations)
      (with_history (task_history current ++ terminal_suffix owner original plugin outcome result error) current)) operation &&
   (match find_tool (call_name (operation_call operation)) (contract_tools (task_contract current)) with Some _=>true | None=>false end))
   (Callbacks.remove_operation (operation_id original) operations) = true).
 repeat rewrite andb_true_iff; repeat split.
 - apply N.leb_le; apply N.leb_le in Bound; unfold Callbacks.remove_operation.
   eapply N.le_trans; [|exact Bound].
   rewrite <- (filter_length (fun operation => negb (N.eqb (operation_id original) (operation_id operation))) operations), Nat2N.inj_add.
   lia.
 - apply filtered_projection_keeps_unique_names; exact Unique.
 - apply forallb_forall; intros selected Remaining.
   apply filter_In in Remaining as [Member Different].
   apply negb_true_iff in Different; apply N.eqb_neq in Different.
   assert (DistinctCall : call_id (operation_call selected) <> call_id (operation_call original)).
   { intro Same.
     assert (selected = original) by
      (eapply a_unique_projection_selects_one_member; [apply unique_call_names_are_distinct; exact Unique|exact Member|exact Owned|exact Same]).
     congruence. }
   rewrite <- (NewContract (task_history current ++ terminal_suffix owner original plugin outcome result error)).
   rewrite other_operations_do_not_change_a_certificate.
   rewrite terminal_receipts_preserve_another_certificate by congruence.
   apply forallb_forall with (x:=selected) in Certificates; assumption.
Qed.

Lemma terminal_settlement_keeps_its_history_suffix :
 forall owner original plugin previous failed outcome current,
 task_history (settled_task owner original plugin previous failed outcome current) =
 task_history current ++ terminal_suffix owner original plugin outcome
   (fst (result_value previous failed outcome)) (snd (result_value previous failed outcome)).
Proof.
 intros; unfold settled_task; destruct (result_value previous failed outcome).
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 destruct lifecycle; reflexivity.
Qed.

Lemma terminal_settlement_keeps_its_archived_lifecycle :
 forall owner original plugin previous failed outcome current operations,
 task_lifecycle current = Archived operations ->
 task_lifecycle (settled_task owner original plugin previous failed outcome current) =
 Archived (Callbacks.remove_operation (operation_id original) operations).
Proof.
 intros owner original plugin previous failed outcome current operations ArchivedTask.
 unfold settled_task; destruct (result_value previous failed outcome).
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn in ArchivedTask; subst lifecycle; reflexivity.
Qed.
