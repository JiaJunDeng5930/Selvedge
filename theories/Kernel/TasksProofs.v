From Selvedge.Kernel Require Import CallbackChangesProofs.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Features Require Import WorkspaceBinding.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates TaskConstraints Inputs Tasks Callbacks Conversation History State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem manual_fork_parent_is_running_idle parent :
 Tasks.fork_parent_ready Tasks.ManualFork parent=true ->
 exists operations, task_lifecycle parent=Running Idle operations.
Proof.
 unfold Tasks.fork_parent_ready.
 destruct (task_lifecycle parent) as [phase operations|phase operations|phase operations|operations]; try discriminate.
 destruct phase; try discriminate; intros _; eauto.
Qed.

Theorem actual_fork_rejects_observed_ancestor_capacity invoked origin id (count : TaskConstraints.fork_count) messages requested value parent:
 find_task id value=Some parent ->
 TaskConstraints.fork_capacities_valid count
  (map(Tasks.ancestor_capacity value)(id::task_lineage parent))=false ->
 Tasks.fork_with_caller invoked origin id count messages requested value=
 match invoked with
 | Tasks.ManualFork => if Tasks.fork_parent_ready Tasks.ManualFork parent then
    reject "resource_limit" "Fork count, aligned messages, or an ancestor descendant limit is invalid" value
   else reject "task_busy" "A manual fork requires an active, idle task" value
 | Tasks.AcceptedNativeFork _ _ => Tasks.refuse_start Tasks.NativeForkEntry Tasks.DescendantCapacity value end.
Proof.
 intros Found Capacity. rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta. rewrite Found.
 unfold Tasks.ancestors_fit. rewrite Capacity,andb_false_r.
 destruct invoked; unfold Tasks.fork_refusal,Tasks.fork_refusal_reason,Tasks.ancestors_fit;
 rewrite ?Capacity; try destruct (Tasks.fork_parent_ready Tasks.ManualFork parent); reflexivity.
Qed.

Theorem archived_control_is_terminal : forall task operations,
 task_lifecycle task = Archived operations ->
 Tasks.control_task Tasks.Archive task = task.
Proof.
 intros [contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor] operations H.
 cbn in H. subst lifecycle. reflexivity.
Qed.

Theorem archived_send_rejects_without_changing_world : forall id contents value task operations,
 find_task id value = Some task ->
 task_lifecycle task = Archived operations ->
 Tasks.send id contents value =
   reject "invalid_arguments" "Archived tasks cannot accept input" value.
Proof.
 intros id contents value task operations Hfind Harchived.
 rewrite TaskChangesProofs.send_expression; cbv beta zeta. rewrite Hfind, Harchived. reflexivity.
Qed.

Theorem stopped_idle_receive_reactivates : forall contents task,
 task_lifecycle task = Stopped Idle [] ->
 task_lifecycle (Tasks.receive contents task) = Running WantsModel [].
Proof.
 intros contents [contract profile settings lifecycle history queued lineage parent cursor consumed] Stopped.
 cbn [task_lifecycle] in Stopped; subst lifecycle; reflexivity.
Qed.

Theorem interrupt_task_is_idempotent : forall task,
 Tasks.control_task Tasks.Interrupt (Tasks.control_task Tasks.Interrupt task) =
 Tasks.control_task Tasks.Interrupt task.
Proof.
 assert (Stable : forall current, task_lifecycle current = Stopped Idle [] ->
   Tasks.control_task Tasks.Interrupt current = current).
 { intros [contract profile settings lifecycle history queued lineage parent cursor consumed] Stopped.
   cbn [task_lifecycle] in Stopped; subst lifecycle.
   change (Task contract profile settings (Stopped Idle []) (history ++ []) queued lineage parent cursor consumed =
     Task contract profile settings (Stopped Idle []) history queued lineage parent cursor consumed).
   now rewrite app_nil_r. }
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; first [apply Stable; reflexivity | reflexivity].
Qed.

Theorem fork_child_inherits_parent_authority_bounds : forall owner parent_id parent contents settings side,
 contract_tools (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) =
   contract_tools (task_contract parent) /\
 contract_max_fork (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) =
   contract_max_fork (task_contract parent) /\
 contract_max_descendants (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) =
   contract_max_descendants (task_contract parent) /\
 contract_plugins (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) =
   contract_plugins (task_contract parent) /\
 contract_reviewers (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) =
   contract_reviewers (task_contract parent) /\
 contract_settings (task_contract (Tasks.fork_child owner parent_id parent contents settings side)) = settings /\
 task_current_profile (Tasks.fork_child owner parent_id parent contents settings side) =
   task_current_profile parent /\
 task_current_settings (Tasks.fork_child owner parent_id parent contents settings side) = settings /\
 task_lineage (Tasks.fork_child owner parent_id parent contents settings side) = parent_id :: task_lineage parent /\
 task_queued (Tasks.fork_child owner parent_id parent contents settings side) = [].
Proof.
 intros. unfold Tasks.fork_child. simpl. repeat split; reflexivity.
Qed.

Lemma selected_context_history_extends_prefix : forall settings parent history,
 exists suffix, Tasks.selected_context_history settings parent history = history ++ suffix.
Proof.
 intros settings parent history.
 unfold Tasks.selected_context_history.
 destruct (Json.equal (settings_json settings) (settings_json (task_current_settings parent)) &&
   Guidance.same (settings_guidance settings) (settings_guidance (task_current_settings parent))) eqn:Hsame.
 - exists []. rewrite app_nil_r. reflexivity.
 - remember (fold_right (fun snapshot rest =>
     if Tasks.context_selected (settings_workspace settings) (snapshot_key snapshot) then rest
     else ContextObservation (Remove (snapshot_key snapshot) (snapshot_revision snapshot)) :: rest)
     [] (ContextUpdates.bindings history)) as removals.
   destruct (Tasks.initial_project_guidance settings) as [snapshot |] eqn:Hguidance.
   + destruct (ContextUpdates.find_snapshot (snapshot_key snapshot)
       (ContextUpdates.bindings (history ++ removals)))
       as [previous |] eqn:Hprevious.
     * destruct (Json.equal (Context.snapshot_json previous) (Context.snapshot_json snapshot)).
       -- exists (removals ++ [SettingsMessage settings (profile_key (task_current_profile parent))
            (profile_reasoning (task_current_profile parent))]).
          subst removals. simpl. rewrite <- app_assoc. reflexivity.
       -- exists (removals ++ [ContextObservation (Introduce snapshot);
            SettingsMessage settings (profile_key (task_current_profile parent))
              (profile_reasoning (task_current_profile parent))]).
          subst removals. simpl. repeat rewrite <- app_assoc. reflexivity.
     * exists (removals ++ [ContextObservation (Introduce snapshot);
         SettingsMessage settings (profile_key (task_current_profile parent))
           (profile_reasoning (task_current_profile parent))]).
       subst removals. simpl. repeat rewrite <- app_assoc. reflexivity.
   + exists (removals ++ [SettingsMessage settings (profile_key (task_current_profile parent))
       (profile_reasoning (task_current_profile parent))]).
     subst removals. simpl. rewrite <- app_assoc. reflexivity.
Qed.

Lemma fork_child_history_keeps_snapshot_prefix : forall owner parent_id parent settings side,
 exists suffix,
   Tasks.fork_child_history owner parent_id parent settings side =
     (if side then History.snapshot_history parent_id parent else History.snapshot_operations parent_id parent) ++ suffix.
Proof.
 intros owner parent_id parent settings side.
 unfold Tasks.fork_child_history.
 destruct (selected_context_history_extends_prefix settings parent
   (if side then History.snapshot_history parent_id parent else History.snapshot_operations parent_id parent)) as [suffix Hprefix].
 rewrite Hprefix. destruct side; simpl.
 - exists (suffix ++ [SideConversationBirth owner parent_id
     (N.succ (N.of_nat (List.length (History.snapshot_history parent_id parent ++ suffix))))]).
   rewrite <- app_assoc. reflexivity.
 - exists suffix. reflexivity.
Qed.

Theorem fork_child_inherits_parent_snapshot : forall owner parent_id parent contents settings side,
 exists suffix,
   task_history (Tasks.fork_child owner parent_id parent contents settings side) =
     (if side then History.snapshot_history parent_id parent else History.snapshot_operations parent_id parent) ++ suffix.
Proof.
 intros owner parent_id parent contents settings side.
 destruct (fork_child_history_keeps_snapshot_prefix owner parent_id parent settings side)
   as [suffix Hprefix].
 unfold Tasks.fork_child. simpl. rewrite Hprefix.
 destruct contents as [contents|]; cbn [Tasks.optional_input].
 - exists (suffix ++ [UserMessage contents]). rewrite <- app_assoc. reflexivity.
 - exists suffix. rewrite app_nil_r. reflexivity.
Qed.

Theorem invoked_fork_rejects_unpermitted_settings : forall invocation remaining origin id count messages requested value parent selected selection,
 find_task id value = Some parent ->
 (Tasks.fork_parent_ready (Tasks.AcceptedNativeFork invocation remaining) parent &&
   TaskConstraints.fork_count_fits count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (id :: task_lineage parent) count value) = true ->
 Tasks.resolve_settings (task_current_profile parent) requested
   (Tasks.fork_settings_base origin parent value) value = Some selected ->
 Tasks.admit_fork_selection parent value selected = Some selection ->
 Workspace.may_delegate (Tasks.fork_selected parent value selection) (task_current_settings parent) = false ->
 Tasks.fork_with_caller (Tasks.AcceptedNativeFork invocation remaining) origin id count messages requested value =
   Tasks.refuse_start Tasks.NativeForkEntry Tasks.AuthorityExpansion value.
Proof.
 intros invocation remaining origin id count messages requested value parent selected selection Hfind Heligible Hresolved Hselection Hdelegate.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta. rewrite Hfind, Heligible, Hresolved, Hselection.
 cbn. rewrite Hdelegate. reflexivity.
Qed.

Definition model_output_has_origin (owner ticket : N) (mode : output_mode) (value : message) : Prop :=
 match value with
 | AssistantMessage origin _ =>
     origin_producer origin = owner /\ origin_operation origin = ticket /\ origin_mode origin = mode
 | ModelContext origin content =>
     origin_producer origin = owner /\ origin_operation origin = ticket /\
     origin_mode origin = Conversation.context_output_mode content mode
 | _ => True
 end.

Theorem model_item_messages_preserve_output_origin : forall owner ticket mode items,
 Forall (model_output_has_origin owner ticket mode)
   (Callbacks.item_messages owner ticket mode items).
Proof.
 intros owner ticket mode items. induction items as [|item rest IH]; simpl.
 - constructor.
 - destruct item; simpl; constructor.
   + repeat split; reflexivity.
   + exact IH.
   + exact I.
   + exact IH.
   + repeat split; reflexivity.
   + exact IH.
Qed.

(** Presence is the public fork contract. Even an explicitly empty content is a
    child instruction; only an omitted list element is absent. *)
Theorem supplied_fork_input_remains_after_its_receipt :
 forall owner parent_id parent contents settings entry start invocation,
 task_history (Tasks.fork_child_receipt entry start owner invocation
   (Tasks.fork_child owner parent_id parent (Some contents) settings false)) =
 Tasks.fork_child_history owner parent_id parent settings false ++
   [ForkReceipt owner invocation (N.succ (owner-start)%N); UserMessage contents].
Proof.
 intros. unfold Tasks.fork_child_receipt, Tasks.fork_child.
 cbn [Tasks.optional_input task_history with_history with_activity with_lifecycle].
 unfold History.fork_receipt_history. rewrite rev_app_distr; cbn. now rewrite rev_involutive.
Qed.
