From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Features Require Import WorkspaceBinding.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates TaskConstraints Inputs Tasks Callbacks Conversation History State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem actual_fork_parent_is_running invoked parent:
 Tasks.fork_parent_ready invoked parent=true ->
 exists phase queued,task_lifecycle parent=Running phase queued.
Proof.
 unfold Tasks.fork_parent_ready.
 destruct(task_lifecycle parent)eqn:Lifecycle;try discriminate.
 intros _. eauto.
Qed.

Theorem actual_fork_rejects_observed_ancestor_capacity invoked origin id count messages requested value parent:
 find_task id value=Some parent ->
 TaskConstraints.fork_capacities_valid count
  (map(Tasks.ancestor_capacity value)(id::task_lineage parent))=false ->
 Tasks.fork_with_caller invoked origin id count messages requested value=
 reject "fork_unavailable"
  "Forking requires an eligible task, a positive count within its fork limit, no messages or exactly one per child, and capacity within every ancestor's descendant limit" value.
Proof.
 intros Found Capacity. unfold Tasks.fork_with_caller. rewrite Found.
 unfold Tasks.ancestors_fit. rewrite Capacity,andb_false_r. reflexivity.
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
   reject "task_archived" "Archived tasks cannot accept input" value.
Proof.
 intros id contents value task operations Hfind Harchived.
 unfold Tasks.send. rewrite Hfind, Harchived. reflexivity.
Qed.

Theorem stopped_idle_receive_reactivates : forall contents task,
 task_lifecycle task = Stopped Idle [] ->
 task_lifecycle (Tasks.receive contents task) = Running WantsModel [].
Proof.
 intros contents task Hstopped.
 assert (Hget : forall state value,
   task_lifecycle (Domain.with_lifecycle state value) = state).
 { intros state value. unfold Domain.with_lifecycle.
   exact (@set_get Domain.task Domain.lifecycle task_lifecycle _ (fun _ => state) value). }
 unfold Tasks.receive. rewrite Hstopped, Hget. reflexivity.
Qed.

Theorem interrupt_task_is_idempotent : forall task,
 Tasks.control_task Tasks.Interrupt (Tasks.control_task Tasks.Interrupt task) =
 Tasks.control_task Tasks.Interrupt task.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor].
 destruct lifecycle;
 unfold Tasks.control_task, Tasks.control_target, Tasks.control_transition, Tasks.unknown_operations,
   with_lifecycle, append_history, with_history;
 cbn [task_lifecycle task_activity task_operations History.interrupted_phase];
 try rewrite app_nil_r; reflexivity.
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
   Json.equal (settings_guidance settings) (settings_guidance (task_current_settings parent))) eqn:Hsame.
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
 destruct (Tasks.content_nonempty contents).
 - exists (suffix ++ [UserMessage contents]). rewrite <- app_assoc. reflexivity.
 - exists suffix. rewrite app_nil_r. reflexivity.
Qed.

Theorem invoked_fork_rejects_unpermitted_settings : forall origin id count messages requested value parent selected,
 find_task id value = Some parent ->
 (Tasks.fork_parent_ready true parent &&
   TaskConstraints.fork_count_valid count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (id :: task_lineage parent) count value) = true ->
 Tasks.resolve_settings (task_current_profile parent) requested
   (Tasks.fork_settings_base origin parent value) value = Some selected ->
 Workspace.may_delegate selected (task_current_settings parent) = false ->
 Tasks.fork_with_caller true origin id count messages requested value =
   reject "settings_forbidden"
     "Task tools cannot expand the caller's workspace, sandbox or approval authority" value.
Proof.
 intros origin id count messages requested value parent selected Hfind Heligible Hresolved Hdelegate.
 unfold Tasks.fork_with_caller. rewrite Hfind, Heligible, Hresolved.
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

Theorem accepted_model_success_uses_origin_scoped_messages : forall owner ticket allowed mode items task,
 Callbacks.permitted_items items allowed task [] [] = true ->
 Callbacks.model_result owner ticket allowed mode (ModelSuccess items) task =
   match Callbacks.item_calls items with
   | [] => Callbacks.settle_model
       (Domain.append_history (Callbacks.item_messages owner ticket mode items) task)
   | calls => Domain.with_activity (PendingCalls calls)
       (Domain.append_history (Callbacks.item_messages owner ticket mode items) task)
   end /\
 Forall (model_output_has_origin owner ticket mode)
   (Callbacks.item_messages owner ticket mode items).
Proof.
 intros owner ticket allowed mode items task Hpermitted. split.
 - unfold Callbacks.model_result. rewrite Hpermitted. destruct (Callbacks.item_calls items); reflexivity.
 - apply model_item_messages_preserve_output_origin.
Qed.

