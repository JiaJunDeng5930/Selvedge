From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers ContextTypes Domain Codec State Tasks
 ForkConstructionProofs ForkIdentityProofs WorldInvariant ForkSettingsProofs ForkLineageProofs ForkNativeHistoryProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* These are the children constructed by the production recursion, in registry
   order. The first reference is the actual next registry position, not a
   search through tasks produced by subsequent feature processing. *)
Fixpoint constructed_children (count : nat) (parent_id : N) (parent : task)
 (messages : list content) (settings : task_settings) (entry : Tasks.fork_entry)
 (start owner : N) (invocation : call) : list task :=
 match count with
 | O => []
 | S count =>
   let contents := hd_error messages in
   Tasks.fork_child_receipt entry start owner invocation
     (Tasks.fork_child owner parent_id parent contents settings false) ::
   constructed_children count parent_id parent (tl messages) settings entry
     start (N.succ owner) invocation
 end.

Lemma replacement_keeps_registry_length : forall (A : Type) (values : list A) owner replacement,
 List.length (replace owner replacement values) = List.length values.
Proof.
 intros A values; induction values as [|first rest IH]; intros owner replacement; cbn; [reflexivity|].
 destruct (N.eqb owner 0); cbn; [reflexivity|rewrite IH; reflexivity].
Qed.

Lemma next_task_after_append : forall child before,
 next_task (append_task child before) = N.succ (next_task before).
Proof.
 intros child before; unfold next_task, append_task, with_tasks; cbv [set]; cbn.
 rewrite length_app; cbn. rewrite Nat.add_1_r, Nat2N.inj_succ; reflexivity.
Qed.

Lemma next_task_after_replacement : forall owner child before,
 next_task (put_task owner child before) = next_task before.
Proof.
 intros; unfold next_task, put_task, with_tasks; cbv [set]; cbn.
 now rewrite replacement_keeps_registry_length.
Qed.

Theorem fork_children_are_the_exact_registry_suffix :
 forall count parent_id parent messages settings entry start invocation before,
 world_tasks (Tasks.fork_children count parent_id parent messages settings entry start invocation before) =
 world_tasks before ++ constructed_children count parent_id parent messages settings entry start (next_task before) invocation.
Proof.
 induction count as [|count IH]; intros; cbn [Tasks.fork_children constructed_children]; [now rewrite app_nil_r|].
 rewrite IH, next_task_after_append.
 unfold append_task, with_tasks; cbv [set]; cbn.
 rewrite <- app_assoc; reflexivity.
Qed.

Theorem fork_constructs_exactly_the_requested_number_of_children :
 forall count parent_id parent messages settings entry start owner invocation,
 List.length (constructed_children count parent_id parent messages settings entry start owner invocation) = count.
Proof. induction count; intros; cbn; [reflexivity|rewrite IHcount; reflexivity]. Qed.

Definition child_execution_frame (parent_id : N) (parent : task) (settings : task_settings) (child : task) :=
 task_current_profile child = task_current_profile parent /\
 task_current_settings child = settings /\
 contract_profile (task_contract child) = task_current_profile parent /\
 contract_settings (task_contract child) = settings /\
 contract_tools (task_contract child) = contract_tools (task_contract parent) /\
 contract_plugins (task_contract child) = contract_plugins (task_contract parent) /\
 contract_reviewers (task_contract child) = contract_reviewers (task_contract parent) /\
 contract_max_fork (task_contract child) = contract_max_fork (task_contract parent) /\
 contract_max_descendants (task_contract child) = contract_max_descendants (task_contract parent) /\
 task_lineage child = parent_id :: task_lineage parent /\
 task_operations child = [] /\ task_queued child = [] /\
 task_side_parent child = None.

Theorem every_constructed_child_has_its_inherited_execution_frame :
 forall count parent_id parent messages settings entry start owner invocation,
 Forall (child_execution_frame parent_id parent settings)
   (constructed_children count parent_id parent messages settings entry start owner invocation).
Proof.
 induction count as [|count IH]; intros; [constructor|].
 cbn [constructed_children]; constructor; [|apply IH].
 unfold child_execution_frame, Tasks.fork_child_receipt, Tasks.fork_child,
   with_activity, with_history; cbv [set]; cbn.
 destruct entry; [|destruct remaining]; cbn; repeat split; reflexivity.
Qed.

Theorem fork_children_preserve_the_world_frame :
 forall count parent_id parent messages settings entry start invocation before,
 let after := Tasks.fork_children count parent_id parent messages settings entry start invocation before in
 world_sequence after = world_sequence before /\
 world_next_ticket after = world_next_ticket before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = world_features before.
Proof.
 induction count as [|count IH]; intros; cbn [Tasks.fork_children]; [repeat split; reflexivity|].
 specialize (IH parent_id parent (tl messages) settings entry start invocation
   (append_task (Tasks.fork_child_receipt entry start (next_task before) invocation
     (Tasks.fork_child (next_task before) parent_id parent
       (hd_error messages) settings false)) before)).
 exact IH.
Qed.

Definition fork_admissible (entry : Tasks.fork_entry) (origin : Tasks.fork_settings_origin)
 (owner count : N) (messages : list content) (raw : option json) (before : world)
 (parent : task) (selected : task_settings) :=
 find_task owner before = Some parent /\
 Tasks.fork_parent_ready entry parent = true /\
 TaskConstraints.fork_count_valid count (contract_max_fork (task_contract parent)) = true /\
 TaskConstraints.fork_messages_valid count (List.length messages) = true /\
 Tasks.ancestors_fit (owner :: task_lineage parent) count before = true /\
 Tasks.resolve_settings (task_current_profile parent) raw (Tasks.fork_settings_base origin parent before) before = Some selected /\
 (exists selection, Tasks.admit_fork_selection parent before selected = Some selection /\
   Tasks.fork_selected parent before selection = selected) /\
 (match entry with Tasks.ManualFork => true | Tasks.AcceptedNativeFork _ _ =>
   Workspace.may_delegate selected (task_current_settings parent) && Tasks.no_resource_observation raw end) = true.

Definition fork_invocation (entry : Tasks.fork_entry) (count : N) (messages : list content)
 (parent : task) (before : world) := match entry with
 | Tasks.AcceptedNativeFork invocation _ => invocation
 | Tasks.ManualFork => Call (Tasks.manual_fork_identity (world_next_ticket before) parent) "fork_task"
   (JObject [("child_count",number count);("messages",JArray (map content_json messages))]) InitialAttempt
 end.
Definition fork_retained (entry : Tasks.fork_entry) (owner : N) (invocation : call)
 (parent : task) (before : world) := match entry with
 | Tasks.ManualFork => put_task owner (with_activity WantsModel (append_history
     [FunctionCall invocation; ForkReceipt owner invocation 0] parent))
     (with_ticket (N.succ (world_next_ticket before)) before)
 | Tasks.AcceptedNativeFork _ _ => before
 end.
Definition fork_snapshot_parent (entry : Tasks.fork_entry) (invocation : call) (parent : task) :=
 match entry with Tasks.ManualFork => append_history [FunctionCall invocation] parent | _ => parent end.
Definition fork_candidate (entry : Tasks.fork_entry) (owner count : N) (messages : list content)
 (parent : task) (selected : task_settings) (before : world) :=
 let invocation := fork_invocation entry count messages parent before in
 let retained := fork_retained entry owner invocation parent before in
 Tasks.fork_children (N.to_nat count) owner (fork_snapshot_parent entry invocation parent)
   messages selected entry (next_task before) invocation retained.
Definition fork_reply (count : N) (before : world) := JObject [("children",JArray
 (map (fun offset => number (next_task before + N.of_nat offset)) (seq 0 (N.to_nat count))))].

Theorem every_admissible_fork_constructs_its_positive_business_result :
 forall entry origin owner count messages raw before parent selected,
 fork_admissible entry origin owner count messages raw before parent selected ->
 Tasks.fork_with_caller entry origin owner count messages raw before =
 accept (fork_reply count before) (fork_candidate entry owner count messages parent selected before) [].
Proof.
 intros entry origin owner count messages raw before parent selected
   (Found & Ready & Count & Messages & Ancestors & Resolved & [selection [Admitted Selected]] & Delegation).
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta; rewrite Found, Ready, Count, Messages, Ancestors; cbn.
 rewrite Resolved, Admitted; rewrite Selected; cbn.
 destruct entry as [|invocation remaining]; cbn in *;
   [|rewrite Delegation; cbn]; reflexivity.
Qed.

Lemma fork_history_keeps_all_admitted_context : forall history invocation owner branch,
 ContextUpdates.bindings (history ++ [FunctionCall invocation; ForkReceipt owner invocation branch]) =
 ContextUpdates.bindings history.
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Lemma fork_history_keeps_other_hook_progress : forall history invocation owner branch operation chain progress,
 call_id invocation <> call_id (operation_call operation) ->
 fold_left (WorldInvariant.hook_step owner (call_id (operation_call operation)) chain)
   (history ++ [FunctionCall invocation; ForkReceipt owner invocation branch]) progress =
 fold_left (WorldInvariant.hook_step owner (call_id (operation_call operation)) chain) history progress.
Proof.
 intros history invocation owner branch operation chain progress Different.
 rewrite fold_left_app; cbn [fold_left WorldInvariant.hook_step].
 assert (Unequal : String.eqb (call_id (operation_call operation)) (call_id invocation) = false).
 { apply String.eqb_neq; congruence. }
 rewrite Unequal; reflexivity.
Qed.

Lemma fork_history_keeps_other_open_call : forall history invocation owner branch existing,
 call_id invocation <> call_id existing ->
 WorldInvariant.call_open history existing = true ->
 WorldInvariant.call_open (history ++ [FunctionCall invocation; ForkReceipt owner invocation branch]) existing = true.
Proof.
 intros history invocation owner branch existing Different Valid.
 unfold WorldInvariant.call_open in *.
 rewrite (ForkIdentityProofs.fork_receipt_preserves_other_output history invocation owner branch
   (call_id existing) Different).
 apply andb_true_iff in Valid as [Known Open].
 unfold Callbacks.call_known in Known |- *; rewrite existsb_app, Known; cbn; exact Open.
Qed.

Definition manual_parent_after (ticket owner : N) (parent : task) :=
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task" JNull InitialAttempt in
 with_activity WantsModel (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent).

(* Arguments of the fresh fork invocation are opaque to the existing operation
   certificates. Only the call identity is relevant to their history scanners. *)
Lemma manual_fork_keeps_operation_certificates : forall parent owner ticket arguments operation,
 Tasks.fork_parent_ready Tasks.ManualFork parent = true ->
 In operation (task_operations parent) ->
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task" arguments InitialAttempt in
 let next := with_activity WantsModel (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent) in
 WorldInvariant.hooks_correspond owner next (operation_call operation) [] =
   WorldInvariant.hooks_correspond owner parent (operation_call operation) [] /\
 WorldInvariant.operation_stage_valid owner next operation =
   WorldInvariant.operation_stage_valid owner parent operation /\
 (WorldInvariant.operation_history parent operation = true -> WorldInvariant.operation_history next operation = true).
Proof.
 intros parent owner ticket arguments operation Ready Present invocation next.
 assert (Fresh : call_id invocation <> call_id (operation_call operation)).
 { unfold invocation; cbn; apply manual_fork_identity_fresh_operation; exact Present. }
 assert (History : task_history next = task_history parent ++ [FunctionCall invocation; ForkReceipt owner invocation 0]).
 { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 assert (Tools : task_contract next = task_contract parent).
 { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 assert (Settings : task_current_settings next = task_current_settings parent).
 { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 assert (BeforePlugins : Scheduler.before_plugins next = Scheduler.before_plugins parent).
 { unfold Scheduler.before_plugins; rewrite Tools; reflexivity. }
 assert (AfterPlugins : Callbacks.after_plugins next = Callbacks.after_plugins parent).
 { unfold Callbacks.after_plugins; rewrite Tools; reflexivity. }
 assert (Hooks : WorldInvariant.hooks_correspond owner next (operation_call operation) [] =
   WorldInvariant.hooks_correspond owner parent (operation_call operation) []).
 { unfold WorldInvariant.hooks_correspond. rewrite History, BeforePlugins.
   rewrite fork_history_keeps_other_hook_progress by exact Fresh; reflexivity. }
 assert (Review : forall reviewer, WorldInvariant.review_right next operation reviewer =
   WorldInvariant.review_right parent operation reviewer).
 { intro reviewer; unfold WorldInvariant.review_right; rewrite Tools, Settings; reflexivity. }
 assert (Approval : forall reviewer, WorldInvariant.approval_corresponds owner next operation reviewer =
   WorldInvariant.approval_corresponds owner parent operation reviewer).
 { intro reviewer; unfold WorldInvariant.approval_corresponds; rewrite History, fold_left_app; reflexivity. }
 assert (Result : forall result error pending, WorldInvariant.results_correspond owner next operation result error pending =
   WorldInvariant.results_correspond owner parent operation result error pending).
 { intros result error pending; unfold WorldInvariant.results_correspond.
   rewrite History, AfterPlugins, fold_left_app; reflexivity. }
 repeat split; [exact Hooks| |].
 - unfold WorldInvariant.operation_stage_valid; destruct (operation_stage operation);
     rewrite ?Settings, ?Review, ?Approval, ?Result; reflexivity.
 - unfold WorldInvariant.operation_history; rewrite History, Settings.
   destruct (operation_announced operation).
   + rewrite existsb_app; intro Known; rewrite Known; reflexivity.
   + apply fork_history_keeps_other_open_call; exact Fresh.
Qed.

Theorem manual_fork_preserves_every_running_operation : forall parent owner ticket arguments,
 Tasks.fork_parent_ready Tasks.ManualFork parent = true ->
 WorldInvariant.operations_valid owner parent = true ->
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task" arguments InitialAttempt in
 WorldInvariant.operations_valid owner
   (with_activity WantsModel (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent)) = true.
Proof.
 intros parent owner ticket arguments Ready Valid invocation.
 assert (Phase : task_activity parent = Idle).
 { unfold Tasks.fork_parent_ready in Ready.
   destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate.
   destruct phase; try discriminate; reflexivity. }
 set (next := with_activity WantsModel (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent)).
 assert (Operations : task_operations next = task_operations parent).
 { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 assert (Contract : task_contract next = task_contract parent).
 { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 assert (NextPhase : task_activity next = WantsModel).
 { unfold Tasks.fork_parent_ready in Ready.
   destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate.
   destruct phase; try discriminate; reflexivity. }
 unfold WorldInvariant.operations_valid in *.
 rewrite Operations, Contract, NextPhase, Phase in *; cbn [WorldInvariant.phase_calls] in *.
 apply andb_true_iff in Valid as [Static Certificates].
 apply andb_true_iff; split; [exact Static|].
 rewrite forallb_forall in Certificates |- *; intros operation Present.
 specialize (Certificates operation Present).
 destruct (manual_fork_keeps_operation_certificates parent owner ticket arguments operation Ready Present)
   as [Hooks [Stage History]].
 change (WorldInvariant.hooks_correspond owner next (operation_call operation) [] =
   WorldInvariant.hooks_correspond owner parent (operation_call operation) []) in Hooks.
 change (WorldInvariant.operation_stage_valid owner next operation =
   WorldInvariant.operation_stage_valid owner parent operation) in Stage.
 rewrite Hooks, Stage.
 repeat rewrite andb_true_iff in Certificates |- *.
 destruct Certificates as [[[BeforeHooks BeforeHistory] BeforeStage] Tool].
 repeat split; auto.
Qed.

Lemma valid_bindings_survive_removal : forall key values,
 forallb ContextUpdates.valid_snapshot values = true ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.remove_snapshot key values) = true.
Proof.
 intros key values Valid; unfold ContextUpdates.remove_snapshot.
 rewrite forallb_forall in *; intros snapshot Present.
 apply filter_In in Present as [Present Selected]. apply Valid; exact Present.
Qed.

Definition context_transition (values : list snapshot) (entry : message) :=
 match entry with ContextObservation change => ContextUpdates.apply_change change values | _ => values end.
Definition context_step_admitted (entry : message) := match entry with
 | ContextObservation (Introduce snapshot) => ContextUpdates.valid_snapshot snapshot = true
 | ContextObservation (Amend _ _ _ _) => False
 | _ => True end.

Lemma admitted_context_steps_keep_bindings : forall suffix values,
 Forall context_step_admitted suffix ->
 forallb ContextUpdates.valid_snapshot values = true ->
 forallb ContextUpdates.valid_snapshot (fold_left context_transition suffix values) = true.
Proof.
 induction suffix as [|entry rest IH]; intros values Steps Valid; [exact Valid|].
 inversion Steps as [|? ? Step Rest]; subst; cbn [fold_left]; apply IH; [exact Rest|].
 unfold context_transition; destruct entry; try exact Valid.
 destruct change; cbn [context_step_admitted] in Step; [|contradiction|].
 - cbn [ContextUpdates.apply_change]; apply andb_true_iff; split; [exact Step|].
   apply valid_bindings_survive_removal; exact Valid.
 - cbn [ContextUpdates.apply_change].
   destruct (ContextUpdates.find_snapshot key values); [|exact Valid].
   destruct (String.eqb (snapshot_revision s) base); [|exact Valid].
   apply valid_bindings_survive_removal; exact Valid.
Qed.

Lemma admitted_context_suffix_preserves_bindings : forall history suffix,
 Forall context_step_admitted suffix ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings history) = true ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (history ++ suffix)) = true.
Proof.
 intros history suffix Steps Valid; unfold ContextUpdates.bindings in *.
 rewrite fold_left_app. apply admitted_context_steps_keep_bindings; assumption.
Qed.

Theorem child_context_selection_preserves_admitted_snapshots : forall settings parent history,
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings history) = true ->
 forallb ContextUpdates.valid_snapshot
   (ContextUpdates.bindings (Tasks.selected_context_history settings parent history)) = true.
Proof.
 intros settings parent history Valid; unfold Tasks.selected_context_history.
 destruct (Json.equal (settings_json settings) (settings_json (task_current_settings parent)) &&
   Json.equal (settings_guidance settings) (settings_guidance (task_current_settings parent))); [exact Valid|].
 set (removals := fold_right (fun snapshot rest =>
   if Tasks.context_selected (settings_workspace settings) (snapshot_key snapshot) then rest
   else ContextObservation (Remove (snapshot_key snapshot) (snapshot_revision snapshot)) :: rest)
   [] (ContextUpdates.bindings history)).
 assert (Removals : Forall context_step_admitted removals).
 { unfold removals; generalize (ContextUpdates.bindings history); intros values.
   induction values as [|snapshot rest IH]; cbn; [constructor|].
   destruct (Tasks.context_selected (settings_workspace settings) (snapshot_key snapshot)); [exact IH|].
   constructor; [exact I|exact IH]. }
 assert (Removed : forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (history ++ removals)) = true).
 { apply admitted_context_suffix_preserves_bindings; assumption. }
 destruct (Tasks.initial_project_guidance settings) as [snapshot|] eqn:Guidance.
 - assert (Snapshot : ContextUpdates.valid_snapshot snapshot = true).
   { apply ForkSettingsProofs.initial_project_guidance_is_admitted with settings; exact Guidance. }
   destruct (match ContextUpdates.find_snapshot (snapshot_key snapshot)
      (ContextUpdates.bindings (history ++ removals)) with
     | Some previous => Json.equal (Context.snapshot_json previous) (Context.snapshot_json snapshot)
     | None => false end).
   + apply admitted_context_suffix_preserves_bindings; [repeat constructor|exact Removed].
   + apply admitted_context_suffix_preserves_bindings; [repeat constructor|].
     apply admitted_context_suffix_preserves_bindings; [repeat constructor; exact Snapshot|exact Removed].
 - apply admitted_context_suffix_preserves_bindings; [repeat constructor|exact Removed].
Qed.

(* Feature references may observe old tasks after a fork. The fork changes a
   retained task's request phase and appends history, while all its persistent
   identity, operations and execution settings remain the same. *)
Definition retained_task_frame (value : task) := match task_lifecycle value with
 | Running _ operations => with_lifecycle (Running Idle operations) (with_history [] value)
 | Archived _ => with_lifecycle (Archived []) (with_history [] value)
 | _ => with_history [] value end.
Definition fork_retains_task (old next : task) :=
 retained_task_frame old = retained_task_frame next /\
 exists suffix, task_history next = task_history old ++ suffix.

Lemma fork_retains_task_reflexive : forall value, fork_retains_task value value.
Proof. intros; split; [reflexivity|exists []; now rewrite app_nil_r]. Qed.

Lemma fork_retains_manual_parent : forall parent owner ticket arguments,
 Tasks.fork_parent_ready Tasks.ManualFork parent = true ->
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task" arguments InitialAttempt in
 fork_retains_task parent (with_activity WantsModel
   (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent)).
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed] owner ticket arguments Ready invocation.
 unfold Tasks.fork_parent_ready in Ready; cbn in Ready.
 destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate.
 destruct phase; try discriminate.
 split; [reflexivity|eexists; reflexivity].
Qed.

Lemma observing_a_retained_task : forall (A : Type) (observe : task -> A) old next,
 (forall value, observe (retained_task_frame value) = observe value) ->
 fork_retains_task old next -> observe old = observe next.
Proof.
 intros A observe old next Stable [Same _].
 rewrite <- (Stable old), <- (Stable next), Same; reflexivity.
Qed.

Theorem every_fork_retains_its_existing_task_fields :
 forall entry owner count messages parent selected before queried old,
 find_task owner before = Some parent -> Tasks.fork_parent_ready entry parent = true ->
 find_task queried before = Some old ->
 exists next, find_task queried (fork_candidate entry owner count messages parent selected before) = Some next /\
 fork_retains_task old next.
Proof.
 intros entry owner count messages parent selected before queried old Parent Ready Found.
 unfold fork_candidate.
 destruct entry as [|invocation remaining].
 - cbn [fork_retained fork_invocation].
   destruct (N.eq_dec queried owner) as [Same|Other].
   + subst queried; rewrite Parent in Found; inversion Found; subst old.
     eexists; split.
     * apply fork_children_preserve_every_existing_task.
       eapply LifecycleProofs.find_put_task; exact Parent.
     * apply fork_retains_manual_parent; exact Ready.
   + exists old; split; [|apply fork_retains_task_reflexive].
     apply fork_children_preserve_every_existing_task.
     unfold find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn.
     rewrite Selvedge.Foundation.RegistryProofs.registry_replace_other by congruence; exact Found.
 - cbn [fork_retained]. exists old; split; [apply fork_children_preserve_every_existing_task; exact Found|].
   apply fork_retains_task_reflexive.
Qed.

Lemma appended_history_preserves_captured_prefix : forall captured history suffix,
 ContextSelection.history_extends captured history = true ->
 ContextSelection.history_extends captured (history ++ suffix) = true.
Proof.
 intros captured history suffix Valid.
 unfold ContextSelection.history_extends, ContextSelection.history_json in *.
 rewrite length_map in *.
 apply andb_true_iff in Valid as [Length Prefix].
 apply Nat.leb_le in Length; apply andb_true_iff; split.
 - apply Nat.leb_le; rewrite length_app; lia.
 - rewrite map_app, firstn_app.
   replace (List.length captured - List.length (map (message_json 0) history))%nat with 0%nat by (rewrite length_map; lia).
   cbn; rewrite app_nil_r; exact Prefix.
Qed.

Lemma appended_history_never_reduces_useful_input : forall history suffix,
 (Selvedge.Features.Compaction.useful history <= Selvedge.Features.Compaction.useful (history ++ suffix))%N.
Proof.
 intros history suffix; unfold Selvedge.Features.Compaction.useful.
 rewrite filter_app, length_app, Nat2N.inj_add; lia.
Qed.

Section FeatureForkFrame.
Variables before after : world.
Hypothesis SameFeatures : world_features before = world_features after.
Hypothesis SameProjects : world_projects before = world_projects after.
Hypothesis LaterTickets : (world_next_ticket before <= world_next_ticket after)%N.
Hypothesis Retained : forall owner old, find_task owner before = Some old ->
 exists next, find_task owner after = Some next /\ fork_retains_task old next.

Local Lemma an_existing_task_remains_present : forall owner,
 WorldInvariant.present (find_task owner before) = true ->
 WorldInvariant.present (find_task owner after) = true.
Proof.
 intros owner Present; destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
 destruct (Retained owner old Found) as [next [After Frame]]. rewrite After; reflexivity.
Qed.

Local Lemma fork_retains_lineage : forall old next,
 fork_retains_task old next -> task_lineage old = task_lineage next.
Proof.
 intros old next Frame; eapply observing_a_retained_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Local Lemma title_survives_a_fork : forall entry,
 WorldInvariant.title_valid entry before = true -> WorldInvariant.title_valid entry after = true.
Proof.
 intros entry Valid; unfold WorldInvariant.title_valid in *.
 apply andb_true_iff in Valid as [Present Valid].
 apply andb_true_iff; split; [apply an_existing_task_remains_present; exact Present|].
 destruct (Selvedge.Features.Domain.title_value entry); try exact Valid.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Ticket Profile] Capable] Budget].
 repeat split; try assumption; apply N.ltb_lt; apply N.ltb_lt in Ticket; lia.
Qed.

Local Lemma tree_survives_a_fork : forall entry,
 WorldInvariant.tree_owner_valid entry before = true -> WorldInvariant.tree_owner_valid entry after = true.
Proof.
 intros entry Valid; unfold WorldInvariant.tree_owner_valid in *.
 destruct (find_task (Selvedge.Features.Domain.worktree_task entry) before) as [old|] eqn:Found;
   [|repeat rewrite andb_false_r in Valid; discriminate].
 destruct (Retained _ old Found) as [next [After [Frame History]]]. rewrite After.
 destruct old as [oc op os ol oh oq oa osp osc omc].
 destruct next as [nc np ns nl nh nq na nsp nsc nmc].
 destruct ol; destruct nl; cbn [retained_task_frame with_activity with_history with_lifecycle] in Frame;
   inversion Frame; subst; exact Valid.
Qed.

Local Lemma card_survives_a_fork : forall card,
 WorldInvariant.card_valid card before = true -> WorldInvariant.card_valid card after = true.
Proof.
 intros card Valid; unfold WorldInvariant.card_valid in *.
 assert (Draft : Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) before =
   Selvedge.Features.Board.valid_draft (Selvedge.Features.Domain.card_contents card) after).
 { unfold Selvedge.Features.Board.valid_draft, Selvedge.Features.BoardFacts.valid_draft,
     Selvedge.Features.BoardFacts.lookup_agent, Selvedge.Features.BoardFacts.registry;
   rewrite SameProjects, SameFeatures; reflexivity. }
 apply andb_true_iff in Valid as [Static Enrichment].
 apply andb_true_iff; split.
 - apply andb_true_iff in Static as [Fixed Linked]; apply andb_true_iff; split.
   + rewrite <- Draft; exact Fixed.
   + destruct (Selvedge.Features.Domain.card_task card); [apply an_existing_task_remains_present; exact Linked|reflexivity].
 - destruct (Selvedge.Features.Domain.card_enrichment card); try exact Enrichment.
   repeat rewrite andb_true_iff in Enrichment |- *.
   destruct Enrichment as [[Ticket Revision] Active]; repeat split; try assumption.
   apply N.ltb_lt; apply N.ltb_lt in Ticket; lia.
Qed.

Local Lemma work_owner_survives_a_fork : forall owner old next,
 find_task owner before = Some old -> find_task owner after = Some next ->
 fork_retains_task old next ->
 Selvedge.Features.Work.task_owner owner before = Selvedge.Features.Work.task_owner owner after.
Proof.
 intros owner old next Found After Frame; unfold Selvedge.Features.Work.task_owner.
 rewrite Found, After, <- SameFeatures, (fork_retains_lineage old next Frame); reflexivity.
Qed.

Local Lemma graph_survives_a_fork : forall owner graph,
 WorldInvariant.graph_valid owner graph before = true -> WorldInvariant.graph_valid owner graph after = true.
Proof.
 intros owner graph Valid; unfold WorldInvariant.graph_valid in *; rewrite <- SameFeatures.
 apply andb_true_iff in Valid as [Static Nodes]; apply andb_true_iff; split; [exact Static|].
 rewrite forallb_forall in Nodes |- *; intros node Member; specialize (Nodes node Member).
 apply andb_true_iff in Nodes as [Present InWork]; apply andb_true_iff; split.
 - apply an_existing_task_remains_present; exact Present.
 - destruct (find_task (Selvedge.Features.Domain.node_task node) before) as [old|] eqn:Found; [|discriminate].
   destruct (Retained _ old Found) as [next [After Frame]].
   unfold Selvedge.Features.TaskGraph.task_in_work in *.
   destruct (Selvedge.Features.Domain.association owner
     (Selvedge.Features.Domain.feature_graph_owners (world_features before))); [|exact InWork].
   rewrite <- (work_owner_survives_a_fork _ old next Found After Frame); exact InWork.
Qed.

Local Lemma graphs_survive_a_fork : forall owner entries,
 WorldInvariant.graphs_valid owner entries before = true ->
 WorldInvariant.graphs_valid owner entries after = true.
Proof.
 intros owner entries; revert owner; induction entries as [|graph rest IH]; intros owner Valid; [reflexivity|].
 cbn [WorldInvariant.graphs_valid] in *; apply andb_true_iff in Valid as [Head Tail].
 apply andb_true_iff; split; [|apply IH; exact Tail].
 destruct graph; [apply graph_survives_a_fork; exact Head|reflexivity].
Qed.

Local Lemma maintenance_survives_a_fork : forall entry,
 WorldInvariant.maintenance_entry_valid entry before = true ->
 WorldInvariant.maintenance_entry_valid entry after = true.
Proof.
 intros [owner entry] Valid; unfold WorldInvariant.maintenance_entry_valid in *.
 destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
 destruct (Retained _ old Found) as [next [After [Frame [suffix History]]]]. rewrite After, History.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Maintained Attempted] Useful] Job]; repeat split; try assumption.
 - apply N.leb_le; apply N.leb_le in Attempted.
   pose proof (appended_history_never_reduces_useful_input (task_history old) suffix); lia.
 - apply N.leb_le; apply N.leb_le in Useful.
   pose proof (appended_history_never_reduces_useful_input (task_history old) suffix); lia.
 - unfold WorldInvariant.job_history_valid in *.
   destruct (Selvedge.Features.CompactionTypes.entry_job entry); try exact Job;
     apply appended_history_preserves_captured_prefix; exact Job.
Qed.

Theorem feature_requirements_survive_a_fork :
 WorldInvariant.features_valid before = true -> WorldInvariant.features_valid after = true.
Proof.
 intro Valid; unfold WorldInvariant.features_valid in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works] Maintenance].
 repeat split.
 - unfold WorldInvariant.titles_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Titles |- *; destruct Titles as [[[TaskPrompt AgentPrompt] Unique] Entries].
   repeat split; try assumption. apply forallb_forall; intros entry Member.
   apply title_survives_a_fork; apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.remote_valid in *; rewrite <- SameFeatures; exact Remote.
 - unfold WorldInvariant.worktrees_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Trees as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply tree_survives_a_fork.
   apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.board_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Board |- *.
   destruct Board as [[[[[[[Cards Agents] CardBound] AgentBound] Entries] Unique] AgentEntries] Draft].
   repeat split; try assumption. apply forallb_forall; intros card Member.
   apply card_survives_a_fork; apply forallb_forall with (x:=card) in Entries; assumption.
 - unfold WorldInvariant.sharing_valid in *;
     unfold Selvedge.Features.WorkspaceBinding.resource_ready, Selvedge.Features.WorkspaceBinding.owned in *.
   rewrite <- SameFeatures, <- SameProjects; exact Sharing.
 - unfold WorldInvariant.graph_registry_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Graphs as [Count Entries]; apply andb_true_iff; split; [exact Count|].
   apply graphs_survive_a_fork; exact Entries.
 - unfold WorldInvariant.works_valid, WorldInvariant.work_owners_valid, Selvedge.Features.Work.lookup in *;
     rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Works |- *.
   destruct Works as [[[[[Bound Entries] [TaskUnique TaskEntries]] [GraphUnique GraphEntries]] Roots] GraphRoots].
   repeat split; try assumption.
   apply forallb_forall; intros [owner work] Member.
   apply forallb_forall with (x:=(owner,work)) in Roots; [|exact Member].
   cbn in Roots |- *.
   destruct (find_task owner before) as [old|] eqn:Found; [|discriminate].
   destruct (Retained _ old Found) as [next [After Frame]]. rewrite After.
   rewrite <- (fork_retains_lineage old next Frame); exact Roots.
 - unfold WorldInvariant.compaction_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Maintenance as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; apply maintenance_survives_a_fork.
   apply forallb_forall with (x:=entry) in Entries; assumption.
Qed.
End FeatureForkFrame.

Lemma constructed_fork_children_do_not_own_existing_tickets : forall count owner parent messages settings entry start invocation before,
 flat_map WorldInvariant.task_tickets
   (world_tasks (Tasks.fork_children count owner parent messages settings entry start invocation before)) =
 flat_map WorldInvariant.task_tickets (world_tasks before).
Proof.
 induction count as [|count IH]; intros; [reflexivity|].
 cbn [Tasks.fork_children]; rewrite IH.
 change (flat_map WorldInvariant.task_tickets (world_tasks before ++
   [Tasks.fork_child_receipt entry start (next_task before) invocation
     (Tasks.fork_child (next_task before) owner parent
       (hd_error messages) settings false)]) = flat_map WorldInvariant.task_tickets (world_tasks before)).
 rewrite flat_map_app.
 assert (Empty : WorldInvariant.task_tickets
   (Tasks.fork_child_receipt entry start (next_task before) invocation
     (Tasks.fork_child (next_task before) owner parent
       (hd_error messages) settings false)) = []).
 { unfold Tasks.fork_child_receipt, Tasks.fork_child, with_activity, with_history;
     cbv [set]; cbn; destruct entry; [|destruct remaining]; reflexivity. }
 change (flat_map WorldInvariant.task_tickets (world_tasks before) ++
   (WorldInvariant.task_tickets (Tasks.fork_child_receipt entry start (next_task before) invocation
     (Tasks.fork_child (next_task before) owner parent
       (hd_error messages) settings false)) ++ []) =
   flat_map WorldInvariant.task_tickets (world_tasks before)).
 rewrite Empty; cbn; now rewrite app_nil_r.
Qed.

Lemma replacing_equal_ticket_ownership_keeps_the_registry_supply :
 forall (values : list task) owner old next,
 registry_at owner values = Some old ->
 WorldInvariant.task_tickets old = WorldInvariant.task_tickets next ->
 flat_map WorldInvariant.task_tickets (replace owner next values) =
 flat_map WorldInvariant.task_tickets values.
Proof.
 intros values; induction values as [|first rest IH]; intros owner old next Found Same; [discriminate|].
 cbn in Found; cbn [replace flat_map]; destruct (N.eqb owner 0).
 - inversion Found; subst first; rewrite Same; reflexivity.
 - cbn [flat_map]; rewrite IH with (old:=old) by assumption; reflexivity.
Qed.

Theorem forks_keep_exactly_the_existing_ticket_owners :
 forall entry owner count messages parent selected before,
 find_task owner before = Some parent -> Tasks.fork_parent_ready entry parent = true ->
 flat_map WorldInvariant.task_tickets
   (world_tasks (fork_candidate entry owner count messages parent selected before)) =
 flat_map WorldInvariant.task_tickets (world_tasks before).
Proof.
 intros entry owner count messages parent selected before Found Ready.
 unfold fork_candidate; rewrite constructed_fork_children_do_not_own_existing_tickets.
 destruct entry as [|invocation remaining]; [|reflexivity].
 cbn [fork_retained].
 apply replacing_equal_ticket_ownership_keeps_the_registry_supply with parent; [exact Found|].
 unfold Tasks.fork_parent_ready in Ready.
 destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate.
 destruct phase; try discriminate; reflexivity.
Qed.

Theorem forks_never_revoke_the_existing_ticket_supply :
 forall entry owner count messages parent selected before,
 (world_next_ticket before <= world_next_ticket
   (fork_candidate entry owner count messages parent selected before))%N.
Proof.
 intros; unfold fork_candidate.
 destruct (fork_children_preserve_the_world_frame (N.to_nat count) owner
   (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
   messages selected entry (next_task before) (fork_invocation entry count messages parent before)
   (fork_retained entry owner (fork_invocation entry count messages parent before) parent before))
   as [_ [Ticket _]].
 rewrite Ticket; destruct entry; [change (world_next_ticket before <= N.succ (world_next_ticket before))%N|change (world_next_ticket before <= world_next_ticket before)%N]; lia.
Qed.

Theorem fork_ticket_requirements_are_preserved :
 forall entry owner count messages parent selected before,
 find_task owner before = Some parent -> Tasks.fork_parent_ready entry parent = true ->
 WorldInvariant.tickets_valid before = true ->
 WorldInvariant.tickets_valid (fork_candidate entry owner count messages parent selected before) = true.
Proof.
 intros entry owner count messages parent selected before Found Ready Valid.
 unfold WorldInvariant.tickets_valid in *.
 rewrite forks_keep_exactly_the_existing_ticket_owners by assumption.
 unfold fork_candidate.
 destruct (fork_children_preserve_the_world_frame (N.to_nat count) owner
   (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
   messages selected entry (next_task before) (fork_invocation entry count messages parent before)
   (fork_retained entry owner (fork_invocation entry count messages parent before) parent before))
   as [_ [Ticket [_ [_ Features]]]].
 assert (SameFeatures : world_features
   (fork_retained entry owner (fork_invocation entry count messages parent before) parent before) =
   world_features before) by (destruct entry; reflexivity).
 rewrite Features, SameFeatures.
 apply andb_true_iff in Valid as [Unique Bounded]; apply andb_true_iff; split; [exact Unique|].
 rewrite forallb_forall in Bounded |- *; intros ticket Member; specialize (Bounded ticket Member).
 apply N.ltb_lt; apply N.ltb_lt in Bounded.
 pose proof (forks_never_revoke_the_existing_ticket_supply entry owner count messages parent selected before) as Later.
 unfold fork_candidate in Later; lia.
Qed.

Lemma fork_receipt_preserves_context_bindings : forall history owner invocation branch,
 ContextUpdates.bindings (History.fork_receipt_history (ForkReceipt owner invocation branch) history) =
 ContextUpdates.bindings history.
Proof.
 intros history owner invocation branch; unfold History.fork_receipt_history.
 destruct (rev history) as [|last rest] eqn:Reversed.
 - apply (f_equal (@rev message)) in Reversed; rewrite rev_involutive in Reversed; cbn in Reversed; subst history; reflexivity.
 - assert (History : history = rev rest ++ [last]).
   { apply (f_equal (@rev message)) in Reversed; rewrite rev_involutive in Reversed.
     cbn in Reversed; exact Reversed. }
   destruct last; try (unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity).
   rewrite History; unfold ContextUpdates.bindings; rewrite !fold_left_app; reflexivity.
Qed.

Lemma closing_inherited_operations_preserves_context_bindings : forall parent_id parent,
 ContextUpdates.bindings (History.snapshot_operations parent_id parent) = ContextUpdates.bindings (task_history parent).
Proof.
 intros parent_id parent; unfold History.snapshot_operations, History.close_operations, ContextUpdates.bindings.
 rewrite fold_left_app.
 generalize (fold_left (fun values message => match message with
   ContextObservation change => ContextUpdates.apply_change change values | _ => values end) (task_history parent) []).
 generalize (task_operations parent); intros operations; induction operations as [|operation rest IH]; intros values; [reflexivity|].
 cbn [map fold_left]; unfold History.interrupted_result, History.operation_result.
 destruct (operation_stage operation); destruct (operation_announced operation); apply IH.
Qed.

Theorem fork_child_context_remains_admitted : forall parent_id owner start entry parent contents selected invocation,
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history parent)) = true ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history
   (Tasks.fork_child_receipt entry start owner invocation
     (Tasks.fork_child owner parent_id parent contents selected false)))) = true.
Proof.
 intros parent_id owner start entry parent contents selected invocation Valid.
 unfold Tasks.fork_child_receipt; cbn [task_history with_history with_activity].
 assert (HistoryFrame : forall phase history task,
   task_history (with_activity phase (with_history history task)) = history).
 { intros phase history [contract profile settings lifecycle previous queued lineage side cursor consumed].
   destruct lifecycle; reflexivity. }
 rewrite HistoryFrame, fork_receipt_preserves_context_bindings.
 unfold Tasks.fork_child; cbn [task_history].
 destruct contents.
 - apply admitted_context_suffix_preserves_bindings; [repeat constructor|].
   cbn [Tasks.fork_child_history]. apply child_context_selection_preserves_admitted_snapshots.
   rewrite closing_inherited_operations_preserves_context_bindings; exact Valid.
 - rewrite app_nil_r; cbn [Tasks.fork_child_history].
   apply child_context_selection_preserves_admitted_snapshots.
   rewrite closing_inherited_operations_preserves_context_bindings; exact Valid.
Qed.

Theorem every_manual_child_has_valid_execution_state : forall parent_id owner start parent contents selected invocation,
 let child := Tasks.fork_child_receipt Tasks.ManualFork start owner invocation
   (Tasks.fork_child owner parent_id parent contents selected false) in
 WorldInvariant.phase_valid child = true /\
 WorldInvariant.checked_phase owner child = true /\
 WorldInvariant.operations_valid owner child = true.
Proof. intros; repeat split; reflexivity. Qed.

Lemma replacing_equal_projection_keeps_registry_observations :
 forall (A B : Type) (observe : A -> B) values owner old next,
 registry_at owner values = Some old -> observe old = observe next ->
 map observe (replace owner next values) = map observe values.
Proof.
 intros A B observe values; induction values as [|first rest IH]; intros owner old next Found Same; [discriminate|].
 cbn in Found; cbn [replace map]; destruct (N.eqb owner 0).
 - inversion Found; subst first; rewrite Same; reflexivity.
 - cbn [map]; rewrite IH with (old:=old) by assumption; reflexivity.
Qed.

Lemma fork_retained_keeps_all_original_lineages : forall entry owner invocation parent before,
 find_task owner before = Some parent ->
 map task_lineage (world_tasks (fork_retained entry owner invocation parent before)) =
 map task_lineage (world_tasks before).
Proof.
 intros entry owner invocation parent before Found; destruct entry; [|reflexivity].
 cbn [fork_retained put_task with_tasks with_ticket].
 apply replacing_equal_projection_keeps_registry_observations with parent; [exact Found|].
 destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Lemma fork_retained_keeps_the_registry_length : forall entry owner invocation parent before,
 List.length (world_tasks (fork_retained entry owner invocation parent before)) = List.length (world_tasks before).
Proof.
 intros entry owner invocation parent before; destruct entry; [|reflexivity].
 cbn [fork_retained put_task with_tasks with_ticket]; apply replacement_keeps_registry_length.
Qed.

Lemma fork_candidate_registry : forall entry owner count messages parent selected before,
 world_tasks (fork_candidate entry owner count messages parent selected before) =
 world_tasks (fork_retained entry owner (fork_invocation entry count messages parent before) parent before) ++
 constructed_children (N.to_nat count) owner
   (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
   messages selected entry (next_task before) (next_task before)
   (fork_invocation entry count messages parent before).
Proof.
 intros; unfold fork_candidate; rewrite fork_children_are_the_exact_registry_suffix.
 assert (Position : next_task
   (fork_retained entry owner (fork_invocation entry count messages parent before) parent before) = next_task before).
 { unfold next_task; rewrite fork_retained_keeps_the_registry_length; reflexivity. }
 rewrite Position; reflexivity.
Qed.

Theorem fork_candidate_keeps_the_non_task_world_frame : forall entry owner count messages parent selected before,
 let after := fork_candidate entry owner count messages parent selected before in
 world_sequence after = world_sequence before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = world_features before.
Proof.
 intros entry owner count messages parent selected before; unfold fork_candidate.
 destruct (fork_children_preserve_the_world_frame (N.to_nat count) owner
   (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
   messages selected entry (next_task before) (fork_invocation entry count messages parent before)
   (fork_retained entry owner (fork_invocation entry count messages parent before) parent before))
   as [Sequence [Ticket [Environment [Projects Features]]]].
 rewrite Sequence, Environment, Projects, Features; destruct entry; repeat split; reflexivity.
Qed.

Lemma task_frame_preserves_contract : forall old next,
 fork_retains_task old next -> task_contract old = task_contract next.
Proof.
 intros old next Frame; eapply observing_a_retained_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma task_frame_preserves_profile : forall old next,
 fork_retains_task old next -> task_current_profile old = task_current_profile next.
Proof.
 intros old next Frame; eapply observing_a_retained_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma task_frame_preserves_settings : forall old next,
 fork_retains_task old next -> task_current_settings old = task_current_settings next.
Proof.
 intros old next Frame; eapply observing_a_retained_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma task_frame_preserves_lineage : forall old next,
 fork_retains_task old next -> task_lineage old = task_lineage next.
Proof.
 intros old next Frame; eapply observing_a_retained_task; [|exact Frame].
 intros [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.

Lemma existing_lineage_survives_a_fork : forall owner old next before after,
 fork_retains_task old next ->
 (forall ancestor original, find_task ancestor before = Some original ->
   exists current, find_task ancestor after = Some current /\ fork_retains_task original current) ->
 WorldInvariant.lineage_valid owner old before = true ->
 WorldInvariant.lineage_valid owner next after = true.
Proof.
 intros owner old next before after Frame Retained Valid.
 unfold WorldInvariant.lineage_valid in *.
 rewrite <- (task_frame_preserves_lineage _ _ Frame), <- (task_frame_preserves_contract _ _ Frame).
 destruct (task_lineage old) as [|ancestor tail]; [reflexivity|].
 destruct (find_task ancestor before) as [original|] eqn:Found; [|discriminate].
 destruct (Retained ancestor original Found) as [current [After ParentFrame]]. rewrite After.
 rewrite <- (task_frame_preserves_lineage _ _ ParentFrame), <- (task_frame_preserves_contract _ _ ParentFrame).
 exact Valid.
Qed.

Lemma retained_task_requirements_lift : forall owner old next before after,
 fork_retains_task old next -> world_projects before = world_projects after ->
 WorldInvariant.lineage_valid owner next after = true ->
 (Tasks.descendant_count owner (world_tasks after) <= contract_max_descendants (task_contract next))%N ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true ->
 WorldInvariant.phase_valid next = true -> WorldInvariant.checked_phase owner next = true ->
 WorldInvariant.operations_valid owner next = true ->
 WorldInvariant.task_valid owner old before = true -> WorldInvariant.task_valid owner next after = true.
Proof.
 intros owner old next before after Frame Projects Lineage Capacity Context Phase Checked Operations Valid.
 unfold WorldInvariant.task_valid in *; repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[[[[Contract Profile] Settings] OldContext] ContractProject] CurrentProject] OldLineage]
   OldCapacity] OldPhase] OldChecked] OldOperations].
 repeat split; try assumption.
 - rewrite <- (task_frame_preserves_contract _ _ Frame); exact Contract.
 - rewrite <- (task_frame_preserves_profile _ _ Frame); exact Profile.
 - rewrite <- (task_frame_preserves_settings _ _ Frame); exact Settings.
 - unfold WorldInvariant.project_binding in *; rewrite <- (task_frame_preserves_contract _ _ Frame), <- Projects; exact ContractProject.
 - unfold WorldInvariant.project_binding in *; rewrite <- (task_frame_preserves_settings _ _ Frame), <- Projects; exact CurrentProject.
 - now apply N.leb_le.
Qed.

Definition registry_lookup_after_head := @Selvedge.Foundation.RegistryProofs.registry_lookup_after_head.

Lemma task_registry_requirement_from_every_lookup : forall entries owner state,
 (forall offset value, registry_at offset entries = Some value ->
   WorldInvariant.task_valid (owner + offset)%N value state = true) ->
 WorldInvariant.tasks_valid owner entries state = true.
Proof.
 intros entries; induction entries as [|first rest IH]; intros owner state Valid; [reflexivity|].
 cbn [WorldInvariant.tasks_valid]; apply andb_true_iff; split.
 - replace owner with (owner+0)%N by lia; apply Valid; reflexivity.
 - apply IH; intros offset value Found.
   replace (N.succ owner + offset)%N with (owner + N.succ offset)%N by lia.
   apply Valid; rewrite registry_lookup_after_head; exact Found.
Qed.

Definition registry_lookup_exists_below_length := @Selvedge.Foundation.RegistryProofs.registry_lookup_exists_below_length.

Lemma admitted_fork_selection_keeps_the_resolved_value : forall parent before selected selection,
 Tasks.admit_fork_selection parent before selected = Some selection ->
 Tasks.fork_selected parent before selection = selected.
Proof.
 intros parent before selected selection Admitted; unfold Tasks.admit_fork_selection in Admitted.
 revert Admitted; generalize (eq_refl (Tasks.fork_selection_fixed parent selected before)).
 generalize (Tasks.fork_selection_fixed parent selected before) at 2 3.
 intros allowed; destruct allowed; intros proof Admitted; inversion Admitted; reflexivity.
Qed.

Definition task_progress_requirements (owner : N) (value : task) :=
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history value)) = true /\
 WorldInvariant.phase_valid value = true /\ WorldInvariant.checked_phase owner value = true /\
 WorldInvariant.operations_valid owner value = true.

Lemma a_valid_task_has_its_progress_requirements : forall owner value before,
 WorldInvariant.task_valid owner value before = true -> task_progress_requirements owner value.
Proof.
 intros owner value before Valid; unfold WorldInvariant.task_valid in Valid.
 repeat rewrite andb_true_iff in Valid; unfold task_progress_requirements; tauto.
Qed.

Lemma manual_fork_parent_keeps_progress_requirements : forall parent owner ticket arguments,
 Tasks.fork_parent_ready Tasks.ManualFork parent = true ->
 task_progress_requirements owner parent ->
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task" arguments InitialAttempt in
 task_progress_requirements owner (with_activity WantsModel
   (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent)).
Proof.
 intros parent owner ticket arguments Ready [Context [Phase [Checked Operations]]] invocation.
 unfold task_progress_requirements; repeat split.
 - assert (History : task_history (with_activity WantsModel
     (append_history [FunctionCall invocation; ForkReceipt owner invocation 0] parent)) =
     task_history parent ++ [FunctionCall invocation; ForkReceipt owner invocation 0]).
   { destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity. }
   rewrite History, fork_history_keeps_all_admitted_context; exact Context.
 - unfold Tasks.fork_parent_ready in Ready.
   destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate; destruct phase; try discriminate; reflexivity.
 - unfold Tasks.fork_parent_ready in Ready.
   destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle as [phase ops|phase ops|phase ops|ops]; try discriminate; destruct phase; try discriminate; reflexivity.
 - apply manual_fork_preserves_every_running_operation; assumption.
Qed.

Lemma fork_retained_progress : forall entry owner count messages parent before queried next,
 WorldInvariant.well_formed before -> find_task owner before = Some parent ->
 Tasks.fork_parent_ready entry parent = true ->
 find_task queried (fork_retained entry owner (fork_invocation entry count messages parent before) parent before) = Some next ->
 exists old, find_task queried before = Some old /\ fork_retains_task old next /\ task_progress_requirements queried next.
Proof.
 intros entry owner count messages parent before queried next Valid Parent Ready Found.
 destruct entry as [|invocation remaining].
 - destruct (N.eq_dec queried owner) as [Same|Other].
   + subst queried.
     assert (Installed : find_task owner
       (fork_retained Tasks.ManualFork owner (fork_invocation Tasks.ManualFork count messages parent before) parent before) =
       Some (with_activity WantsModel (append_history
         [FunctionCall (fork_invocation Tasks.ManualFork count messages parent before);
          ForkReceipt owner (fork_invocation Tasks.ManualFork count messages parent before) 0] parent))).
     { cbn [fork_retained]; eapply LifecycleProofs.find_put_task; exact Parent. }
     rewrite Installed in Found; inversion Found; subst next.
     exists parent; split; [exact Parent|]; split; [apply fork_retains_manual_parent; exact Ready|].
     apply manual_fork_parent_keeps_progress_requirements; [exact Ready|].
     eapply a_valid_task_has_its_progress_requirements; eapply ForkLineageProofs.lookup_task_requirements; eauto.
   + assert (Same : find_task queried
       (fork_retained Tasks.ManualFork owner (fork_invocation Tasks.ManualFork count messages parent before) parent before) =
       find_task queried before).
     { unfold fork_retained, find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn.
       rewrite Selvedge.Foundation.RegistryProofs.registry_replace_other by congruence; reflexivity. }
     rewrite Same in Found; exists next; split; [exact Found|]; split; [apply fork_retains_task_reflexive|].
     eapply a_valid_task_has_its_progress_requirements; eapply ForkLineageProofs.lookup_task_requirements; eauto.
 - cbn [fork_retained] in Found; exists next; split; [exact Found|]; split; [apply fork_retains_task_reflexive|].
   eapply a_valid_task_has_its_progress_requirements; eapply ForkLineageProofs.lookup_task_requirements; eauto.
Qed.

Lemma constructed_children_have_their_parent_lineage : forall count owner parent messages selected entry start fresh invocation,
 Forall (fun child => task_lineage child = owner :: task_lineage parent)
   (constructed_children count owner parent messages selected entry start fresh invocation).
Proof.
 intros; eapply Forall_impl; [|apply every_constructed_child_has_its_inherited_execution_frame].
 intros child Frame; unfold child_execution_frame in Frame; tauto.
Qed.

Lemma fork_snapshot_has_the_original_lineage : forall entry invocation parent,
 task_lineage (fork_snapshot_parent entry invocation parent) = task_lineage parent.
Proof. intros; destruct entry; reflexivity. Qed.

Lemma fork_snapshot_has_the_original_contract : forall entry invocation parent,
 task_contract (fork_snapshot_parent entry invocation parent) = task_contract parent.
Proof. intros; destruct entry; reflexivity. Qed.

Lemma constructed_children_have_the_original_parent_lineage : forall count owner parent messages selected entry start fresh invocation,
 Forall (fun child => task_lineage child = owner :: task_lineage parent)
   (constructed_children count owner (fork_snapshot_parent entry invocation parent) messages selected entry start fresh invocation).
Proof.
 intros; pose proof (constructed_children_have_their_parent_lineage count owner
   (fork_snapshot_parent entry invocation parent) messages selected entry start fresh invocation) as Lineages.
 rewrite fork_snapshot_has_the_original_lineage in Lineages; exact Lineages.
Qed.

Lemma retained_registry_requirements_survive_a_fork :
 forall entry origin owner count messages raw before parent selected,
 WorldInvariant.well_formed before ->
 fork_admissible entry origin owner count messages raw before parent selected ->
 WorldInvariant.tasks_valid 0
   (world_tasks (fork_retained entry owner (fork_invocation entry count messages parent before) parent before))
   (fork_candidate entry owner count messages parent selected before) = true.
Proof.
 intros entry origin owner count messages raw before parent selected Valid Admissible.
 destruct Admissible as (Parent & Ready & Count & Messages & Ancestors & Settings & Selection & Delegation).
 apply task_registry_requirement_from_every_lookup; intros queried next Found.
 change (WorldInvariant.task_valid queried next (fork_candidate entry owner count messages parent selected before) = true).
 destruct (fork_retained_progress entry owner count messages parent before queried next Valid Parent Ready Found)
   as [old [Old [Frame [Context [Phase [Checked Operations]]]]]].
 assert (AfterFound : find_task queried (fork_candidate entry owner count messages parent selected before) = Some next).
 { unfold find_task; rewrite fork_candidate_registry; eapply registry_lookup_preserved_by_append; exact Found. }
 pose proof (fork_candidate_keeps_the_non_task_world_frame entry owner count messages parent selected before)
   as [Sequence [Environment [Projects Features]]].
 eapply retained_task_requirements_lift; [exact Frame|symmetry; exact Projects| | |exact Context|exact Phase|exact Checked|exact Operations|].
 - eapply existing_lineage_survives_a_fork; [exact Frame| |].
   + intros ancestor original FoundOriginal.
     eapply every_fork_retains_its_existing_task_fields; [exact Parent|exact Ready|exact FoundOriginal].
   + pose proof (ForkLineageProofs.lookup_task_requirements before queried old Valid Old) as OldValid.
     change (WorldInvariant.task_valid queried old before = true) in OldValid.
     unfold WorldInvariant.task_valid in OldValid; repeat rewrite andb_true_iff in OldValid; tauto.
 - rewrite <- (task_frame_preserves_contract _ _ Frame), fork_candidate_registry.
   eapply ForkLineageProofs.fork_preserves_existing_descendant_capacity; try eassumption.
   + apply fork_retained_keeps_all_original_lineages; exact Parent.
   + apply constructed_children_have_the_original_parent_lineage.
   + apply fork_constructs_exactly_the_requested_number_of_children.
 - pose proof (ForkLineageProofs.lookup_task_requirements before queried old Valid Old) as OldValid.
   change (WorldInvariant.task_valid queried old before = true) in OldValid; exact OldValid.
Qed.

Lemma child_requirements_from_its_construction :
 forall parent_id fresh parent selected child after,
 child_execution_frame parent_id parent selected child ->
 WorldInvariant.contract_valid (task_contract parent) = true ->
 WorldInvariant.profile_valid (task_current_profile parent) = true ->
 WorldInvariant.settings_valid selected = true -> WorldInvariant.project_binding selected after = true ->
 WorldInvariant.lineage_valid fresh child after = true ->
 Tasks.descendant_count fresh (world_tasks after) = 0%N ->
 task_progress_requirements fresh child ->
 WorldInvariant.task_valid fresh child after = true.
Proof.
 intros parent_id fresh parent selected child after
   (Profile & Settings & CreationProfile & CreationSettings & Tools & Plugins & Reviewers & Fork & Descendants & Lineage & Operations & Queued & Side)
   Contract ParentProfile Selected Project ChildLineage Capacity [Context [Phase [Checked Pending]]].
 unfold WorldInvariant.contract_valid in Contract.
 repeat rewrite andb_true_iff in Contract.
 destruct Contract as [[[[[CreationProfileValid ToolsValid] Sources] PluginsValid] CreationSettingsValid] [ForkPositive DescendantsPositive]].
 unfold WorldInvariant.task_valid, WorldInvariant.contract_valid.
 rewrite Profile, Settings, CreationProfile, CreationSettings, Tools, Plugins, Fork, Descendants,
   ParentProfile, ToolsValid, Sources, PluginsValid, Selected, ForkPositive, DescendantsPositive,
   Context, Project, ChildLineage, Capacity, Phase, Checked, Pending.
 destruct (contract_max_descendants (task_contract parent)); reflexivity.
Qed.

Lemma task_registry_requirements_for_constructed_children :
 forall count parent_id parent messages selected entry start fresh invocation after,
 (forall actual contents, (fresh <= actual)%N ->
   WorldInvariant.task_valid actual
     (Tasks.fork_child_receipt entry start actual invocation
       (Tasks.fork_child actual parent_id parent contents selected false)) after = true) ->
 WorldInvariant.tasks_valid fresh
   (constructed_children count parent_id parent messages selected entry start fresh invocation) after = true.
Proof.
 induction count as [|count IH]; intros; [reflexivity|].
 cbn [constructed_children WorldInvariant.tasks_valid]; apply andb_true_iff; split.
 - apply H; lia.
 - apply IH; intros actual contents Later; apply H; lia.
Qed.

Definition accepted_fork_entry (entry : Tasks.fork_entry) (parent : task) := match entry with
 | Tasks.ManualFork => True
 | Tasks.AcceptedNativeFork invocation remaining =>
   ForkNativeHistoryProofs.native_fork_certificate invocation remaining parent
 end.

Lemma a_fork_snapshot_keeps_context_requirements : forall entry invocation parent,
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history parent)) = true ->
 forallb ContextUpdates.valid_snapshot
   (ContextUpdates.bindings (task_history (fork_snapshot_parent entry invocation parent))) = true.
Proof.
 intros entry invocation parent Valid; destruct entry; [|exact Valid].
 change (forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings
   (task_history parent ++ [FunctionCall invocation])) = true).
 unfold ContextUpdates.bindings in *; rewrite fold_left_app; exact Valid.
Qed.

Lemma new_registry_requirements_survive_a_fork :
 forall entry origin owner count messages raw before parent selected,
 WorldInvariant.well_formed before ->
 fork_admissible entry origin owner count messages raw before parent selected ->
 accepted_fork_entry entry parent ->
 WorldInvariant.tasks_valid (next_task before)
   (constructed_children (N.to_nat count) owner
     (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
     messages selected entry (next_task before) (next_task before)
     (fork_invocation entry count messages parent before))
   (fork_candidate entry owner count messages parent selected before) = true.
Proof.
 intros entry origin owner count messages raw before parent selected Valid Admissible Accepted.
 destruct Admissible as (Parent & Ready & Count & Messages & Ancestors & Resolved & Selection & Delegation).
 pose proof (ForkLineageProofs.lookup_task_requirements before owner parent Valid Parent) as ParentValid.
 change (WorldInvariant.task_valid owner parent before = true) in ParentValid.
 pose proof ParentValid as Requirements; unfold WorldInvariant.task_valid in Requirements.
 repeat rewrite andb_true_iff in Requirements.
 destruct Requirements as [[[[[[[[[[Contract Profile] Settings] Context] ContractProject] CurrentProject] ParentLineage]
   ParentCapacity] ParentPhase] ParentChecked] ParentOperations].
 destruct (ForkSettingsProofs.resolved_fork_settings_are_valid origin owner raw before parent selected Valid Parent Resolved)
   as [Selected SelectedProject].
 pose proof (fork_candidate_keeps_the_non_task_world_frame entry owner count messages parent selected before)
   as [Sequence [Environment [Projects Features]]].
 destruct (every_fork_retains_its_existing_task_fields entry owner count messages parent selected before owner parent Parent Ready Parent)
   as [current [ParentAfter ParentFrame]].
 apply task_registry_requirements_for_constructed_children; intros fresh contents Fresh.
 eapply child_requirements_from_its_construction.
 - unfold child_execution_frame, Tasks.fork_child_receipt, Tasks.fork_child, with_activity, with_history;
     cbv [set]; cbn; destruct entry; [|destruct remaining]; repeat split; reflexivity.
 - rewrite fork_snapshot_has_the_original_contract; exact Contract.
 - destruct entry; exact Profile.
 - exact Selected.
 - unfold WorldInvariant.project_binding in *; rewrite Projects; exact SelectedProject.
 - eapply ForkLineageProofs.a_fork_child_has_its_parent_lineage_requirement with
     (parent:=parent) (current:=current).
   + exact ParentAfter.
   + symmetry; apply task_frame_preserves_lineage; exact ParentFrame.
   + symmetry; apply task_frame_preserves_contract; exact ParentFrame.
   + pose proof (Selvedge.Foundation.RegistryProofs.registry_lookup_implies_position_bound _ _ _ _ Parent); unfold next_task in Fresh; lia.
   + destruct entry; [reflexivity|destruct remaining; reflexivity].
   + destruct entry; [reflexivity|destruct remaining; reflexivity].
   + destruct entry; [reflexivity|destruct remaining; reflexivity].
   + destruct entry; [reflexivity|destruct remaining; reflexivity].
   + destruct entry; [reflexivity|destruct remaining; reflexivity].
 - rewrite fork_candidate_registry.
   eapply ForkLineageProofs.fresh_fork_references_have_no_descendants; try eassumption.
   + apply fork_retained_keeps_all_original_lineages; exact Parent.
   + apply constructed_children_have_the_original_parent_lineage.
 - unfold task_progress_requirements; split.
   + apply fork_child_context_remains_admitted; apply a_fork_snapshot_keeps_context_requirements; exact Context.
   + destruct entry as [|invocation remaining].
     * destruct (every_manual_child_has_valid_execution_state owner fresh (next_task before)
       (fork_snapshot_parent Tasks.ManualFork (fork_invocation Tasks.ManualFork count messages parent before) parent)
       contents selected (fork_invocation Tasks.ManualFork count messages parent before)) as [Phase [Checked Operations]].
       repeat split; assumption.
     * cbn [fork_snapshot_parent fork_invocation].
       apply ForkNativeHistoryProofs.every_native_child_has_valid_execution_state; assumption.
Qed.

Lemma task_registry_requirements_append : forall first before after state,
 WorldInvariant.tasks_valid first (before ++ after) state =
 (WorldInvariant.tasks_valid first before state &&
  WorldInvariant.tasks_valid (first + N.of_nat (List.length before))%N after state).
Proof.
 intros first before; revert first; induction before as [|head rest IH]; intros first after state; cbn [WorldInvariant.tasks_valid app List.length].
 - now rewrite N.add_0_r.
 - rewrite IH.
   replace (first + N.of_nat (S (List.length rest)))%N with (N.succ first + N.of_nat (List.length rest))%N
     by (rewrite Nat2N.inj_succ; lia).
   now rewrite andb_assoc.
Qed.

Lemma task_requirements_ignore_the_journal_cursor : forall owner value state,
 WorldInvariant.task_valid owner value (WorldInvariant.world_structure state) =
 WorldInvariant.task_valid owner value state.
Proof. intros owner value [sequence tasks ticket environment projects features]; reflexivity. Qed.

Lemma task_registry_requirements_ignore_the_journal_cursor : forall entries owner state,
 WorldInvariant.tasks_valid owner entries (WorldInvariant.world_structure state) =
 WorldInvariant.tasks_valid owner entries state.
Proof.
 intros entries; induction entries as [|head rest IH]; intros owner state; [reflexivity|].
 cbn [WorldInvariant.tasks_valid]; rewrite task_requirements_ignore_the_journal_cursor, IH; reflexivity.
Qed.

Theorem admissible_forks_preserve_every_world_requirement :
 forall entry origin owner count messages raw before parent selected,
 WorldInvariant.well_formed before ->
 fork_admissible entry origin owner count messages raw before parent selected ->
 accepted_fork_entry entry parent ->
 WorldInvariant.well_formed (fork_candidate entry owner count messages parent selected before).
Proof.
 intros entry origin owner count messages raw before parent selected Valid Admissible Accepted.
 pose proof Admissible as (Parent & Ready & Count & Messages & Ancestors & Resolved & Selection & Delegation).
 pose proof (fork_candidate_keeps_the_non_task_world_frame entry owner count messages parent selected before)
   as [Sequence [Environment [Projects Features]]].
 constructor.
 - change (WorldInvariant.environment_valid (world_environment
     (fork_candidate entry owner count messages parent selected before)) = true).
   rewrite Environment; exact (WorldInvariant.environment_requirement before Valid).
 - change (WorldInvariant.projects_valid (fork_candidate entry owner count messages parent selected before) = true).
   unfold WorldInvariant.projects_valid; rewrite Projects; exact (WorldInvariant.projects_requirement before Valid).
 - rewrite task_registry_requirements_ignore_the_journal_cursor.
   change (WorldInvariant.tasks_valid 0 (world_tasks (fork_candidate entry owner count messages parent selected before))
     (fork_candidate entry owner count messages parent selected before) = true).
   rewrite fork_candidate_registry, task_registry_requirements_append.
   apply andb_true_iff; split.
   + eapply retained_registry_requirements_survive_a_fork; eassumption.
   + rewrite N.add_0_l, fork_retained_keeps_the_registry_length.
     apply new_registry_requirements_survive_a_fork with origin raw; assumption.
 - change (WorldInvariant.tickets_valid (fork_candidate entry owner count messages parent selected before) = true).
   apply fork_ticket_requirements_are_preserved; try assumption; exact (WorldInvariant.tickets_requirement before Valid).
 - eapply feature_requirements_survive_a_fork with (before:=WorldInvariant.world_structure before).
   + change (world_features before = world_features (fork_candidate entry owner count messages parent selected before)).
     symmetry; exact Features.
   + change (world_projects before = world_projects (fork_candidate entry owner count messages parent selected before)).
     symmetry; exact Projects.
   + change (world_next_ticket before <= world_next_ticket (fork_candidate entry owner count messages parent selected before))%N.
     apply forks_never_revoke_the_existing_ticket_supply.
   + intros queried old Found.
     change (find_task queried before = Some old) in Found.
     destruct (every_fork_retains_its_existing_task_fields entry owner count messages parent selected before queried old Parent Ready Found)
       as [next [After Frame]].
     exists next; split; [change (find_task queried (fork_candidate entry owner count messages parent selected before) = Some next); exact After|exact Frame].
   + exact (WorldInvariant.features_requirement before Valid).
Qed.

Theorem actual_forks_preserve_every_world_requirement :
 forall entry origin owner count messages raw before,
 WorldInvariant.well_formed before ->
 (forall parent, find_task owner before = Some parent -> accepted_fork_entry entry parent) ->
 WorldInvariant.well_formed (decision_world (Tasks.fork_with_caller entry origin owner count messages raw before)).
Proof.
 intros entry origin owner count messages raw before Valid Accepted.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta.
 destruct (find_task owner before) as [parent|] eqn:Parent; [|exact Valid].
 destruct (Tasks.fork_parent_ready entry parent &&
   TaskConstraints.fork_count_valid count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (owner :: task_lineage parent) count before) eqn:Business.
 2: { unfold Tasks.fork_refusal; destruct entry;
      try destruct (Tasks.fork_parent_ready Tasks.ManualFork parent); exact Valid. }
 destruct (Tasks.resolve_settings (task_current_profile parent) raw (Tasks.fork_settings_base origin parent before) before)
   as [selected|] eqn:Resolved; [|exact Valid].
 destruct (Tasks.admit_fork_selection parent before selected) as [selection|] eqn:Selection; [|exact Valid].
 pose proof (admitted_fork_selection_keeps_the_resolved_value _ _ _ _ Selection) as Selected.
 rewrite Selected.
 destruct (match entry with Tasks.ManualFork => false | Tasks.AcceptedNativeFork _ _ =>
   negb (Workspace.may_delegate selected (task_current_settings parent) && Tasks.no_resource_observation raw) end)
   eqn:Denied; [exact Valid|].
 assert (Delegate : (match entry with Tasks.ManualFork => true | Tasks.AcceptedNativeFork _ _ =>
   Workspace.may_delegate selected (task_current_settings parent) && Tasks.no_resource_observation raw end) = true).
 { destruct entry; [reflexivity|]; apply negb_false_iff in Denied; exact Denied. }
 match goal with |- WorldInvariant.well_formed ?actual =>
   replace actual with (fork_candidate entry owner count messages parent selected before) by (destruct entry; reflexivity) end.
 eapply admissible_forks_preserve_every_world_requirement with (origin:=origin) (raw:=raw); [exact Valid| |apply Accepted; reflexivity].
 unfold fork_admissible.
 repeat rewrite andb_true_iff in Business.
 destruct Business as [[[Ready Count] Messages] Capacity].
 repeat split; try assumption; exists selection; split; assumption.
Qed.

Corollary every_manual_fork_preserves_every_world_requirement :
 forall origin owner count messages raw before,
 WorldInvariant.well_formed before ->
 WorldInvariant.well_formed (decision_world
   (Tasks.fork_with_caller Tasks.ManualFork origin owner count messages raw before)).
Proof.
 intros; apply actual_forks_preserve_every_world_requirement; [assumption|intros; exact I].
Qed.


(** The executor removes the accepted invocation from pending calls before
    running the native command. Its certificate therefore moves from the
    pre-dispatch task to the actual [started] registry entry. *)
Theorem actual_native_fork_start_carries_its_accepted_call_certificate :
 forall value owner source invocation remaining,
 WorldInvariant.well_formed value -> find_task owner value = Some source ->
 WorldInvariant.phase_calls (task_activity source) = invocation :: remaining ->
 let started := put_task owner (with_activity (PendingCalls remaining) source) value in
 forall parent, find_task owner started = Some parent ->
 accepted_fork_entry (Tasks.AcceptedNativeFork invocation remaining) parent.
Proof.
 intros value owner source invocation remaining Valid Found Phase started parent Installed.
 assert (Current : find_task owner started = Some (with_activity (PendingCalls remaining) source)).
 { unfold started; eapply LifecycleProofs.find_put_task; exact Found. }
 rewrite Current in Installed; inversion Installed; subst parent.
 unfold accepted_fork_entry; apply ForkNativeHistoryProofs.checked_native_dispatch_certifies_remaining; [exact Phase|].
 pose proof (ForkLineageProofs.lookup_task_requirements value owner source Valid Found) as Requirements.
 change (WorldInvariant.task_valid owner source value = true) in Requirements.
 destruct (a_valid_task_has_its_progress_requirements owner source value Requirements)
   as [Context [PhaseValid Rest]]. exact PhaseValid.
Qed.

Corollary actual_started_native_forks_preserve_every_world_requirement :
 forall value owner source invocation remaining origin count messages raw,
 WorldInvariant.well_formed value -> find_task owner value = Some source ->
 WorldInvariant.phase_calls (task_activity source) = invocation :: remaining ->
 let started := put_task owner (with_activity (PendingCalls remaining) source) value in
 WorldInvariant.well_formed started ->
 WorldInvariant.well_formed (decision_world
   (Tasks.fork_with_caller (Tasks.AcceptedNativeFork invocation remaining)
     origin owner count messages raw started)).
Proof.
 intros value owner source invocation remaining origin count messages raw Valid Found Phase started StartedValid.
 apply actual_forks_preserve_every_world_requirement; [exact StartedValid|].
 intros parent Installed.
 exact (actual_native_fork_start_carries_its_accepted_call_certificate
   value owner source invocation remaining Valid Found Phase parent Installed).
Qed.
