From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Foundation Require Import KeyedListProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Codec Conversation Callbacks Tasks LifecycleProofs.
From Selvedge.Features Require Import Domain State TaskGraph TaskGraphSemantics WorktreeProofs.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Module K:=Selvedge.Kernel.State.
Lemma graph_lookup_has_registry_entry : forall id value graph,
 TaskGraph.lookup id value = Some graph ->
 registry_at id (TaskGraph.registry value) = Some (Some graph).
Proof.
 intros id value graph Found. unfold TaskGraph.lookup in Found.
 destruct (registry_at id (TaskGraph.registry value)) as [[present|]|] eqn:Entry;
   try discriminate. inversion Found; reflexivity.
Qed.

Theorem replacing_a_graph_preserves_its_identity : forall id value previous graph,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.store id graph value) = Some graph.
Proof.
 intros id value previous graph Found.
 apply graph_lookup_has_registry_entry in Found.
 unfold TaskGraph.lookup.
 change (match registry_at id
   (if N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace id (Some graph) (TaskGraph.registry value)) with
   | Some graph => graph | None => None end = Some graph).
 destruct (N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))) eqn:Append.
 - apply N.eqb_eq in Append. rewrite Append, registry_lookup_at_appended_index. reflexivity.
 - rewrite (registry_replace_selected _ _ _ _ _ Found). reflexivity.
Qed.

Theorem appending_a_graph_establishes_its_identity : forall value graph,
 let id := N.of_nat (List.length (TaskGraph.registry value)) in
 TaskGraph.lookup id (TaskGraph.store id graph value) = Some graph.
Proof.
 intros value graph; cbv zeta. unfold TaskGraph.lookup.
 change (match registry_at (N.of_nat (List.length (TaskGraph.registry value)))
   (if N.eqb (N.of_nat (List.length (TaskGraph.registry value)))
       (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace (N.of_nat (List.length (TaskGraph.registry value))) (Some graph)
      (TaskGraph.registry value)) with
   | Some graph => graph | None => None end = Some graph).
 rewrite N.eqb_refl, registry_lookup_at_appended_index. reflexivity.
Qed.

Theorem graph_installation_preserves_other_identities : forall id other value graph,
 id <> other ->
 TaskGraph.lookup other (TaskGraph.store id graph value) = TaskGraph.lookup other value.
Proof.
 intros id other value graph Different. unfold TaskGraph.lookup.
 change (match registry_at other
   (if N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace id (Some graph) (TaskGraph.registry value)) with
   | Some graph => graph | None => None end =
   match registry_at other (TaskGraph.registry value) with
   | Some graph => graph | None => None end).
 destruct (N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))) eqn:Append.
 - apply N.eqb_eq in Append. rewrite registry_append_preserves_other_lookup; [reflexivity|lia].
 - rewrite Selvedge.Foundation.RegistryProofs.registry_replace_other; [reflexivity|exact Different].
Qed.
(** Installing a graph never dispatches the pre-existing history again. *)
Theorem unchanged_history_has_no_new_outputs : forall value id task,
 K.find_task id value = Some task -> TaskGraph.new_outputs value id task = [].
Proof.
 intros value id task found. unfold TaskGraph.new_outputs. rewrite found.
 rewrite skipn_all. reflexivity.
Qed.

(** A rule only reacts to the Task identified by its declared source. *)
Theorem different_source_never_dispatches : forall source graph nodes rule output expected,
 TaskGraph.resolve (F.rule_source rule) nodes=Some expected -> source<>expected ->
 TaskGraph.pending_rule source graph nodes rule output=[].
Proof.
 intros source graph nodes rule output expected resolved other.
 unfold TaskGraph.pending_rule. rewrite resolved.
 apply N.eqb_neq in other. now rewrite other.
Qed.

Theorem resolved_installation_follows_the_typed_plan : forall original caller
 (owner : option (Work.owner_scope original)) id (checked : TaskGraph.checked_cached caller original) plans
 (Resolved : TaskGraph.prepare_nodes (TaskGraph.scope_identity owner) caller original
   (TaskGraph.cached_nodes (TaskGraph.checked_cache checked)) = CommandResult.Accepted plans),
 TaskGraph.install_cached id owner checked =
 TaskGraph.install_plan id (TaskGraph.GraphPlan checked plans Resolved).
Proof.
 intros original caller owner id checked plans Resolved.
 unfold TaskGraph.install_cached,TaskGraph.install_cached_result,TaskGraph.install_resolution,
   TaskGraph.install_plan,TaskGraph.install_change.
 cbn [TaskGraph.graph_checked TaskGraph.graph_plans].
 now rewrite Resolved.
Qed.
Theorem resolved_installation_succeeds : forall original caller
 (owner : option (Work.owner_scope original)) id (checked : TaskGraph.checked_cached caller original) plans,
 TaskGraph.prepare_nodes (TaskGraph.scope_identity owner) caller original
   (TaskGraph.cached_nodes (TaskGraph.checked_cache checked)) = CommandResult.Accepted plans ->
 bool_default "ok"%string (decision_reply (TaskGraph.install_cached id owner checked)) false = true.
Proof.
 intros; rewrite (resolved_installation_follows_the_typed_plan _ _ _ _ _ _ H).
 apply CommandResult.acceptance_has_a_success_reply.
Qed.
Theorem refused_plan_is_atomic : forall original caller
 (owner : option (Work.owner_scope original)) id (checked : TaskGraph.checked_cached caller original) reason,
 TaskGraph.prepare_nodes (TaskGraph.scope_identity owner) caller original
   (TaskGraph.cached_nodes (TaskGraph.checked_cache checked)) = CommandResult.Rejected reason ->
 TaskGraph.install_cached id owner checked = CommandResult.reject original reason.
Proof.
 intros original caller owner id checked reason Refused.
 unfold TaskGraph.install_cached,TaskGraph.install_cached_result,TaskGraph.install_resolution,
   TaskGraph.install_change.
 cbn [TaskGraph.graph_checked TaskGraph.graph_plans].
 now rewrite Refused.
Qed.
Lemma concat_fragments : forall fragments,
 String.concat "" fragments = fold_right String.append "" fragments.
Proof.
 induction fragments as [|head tail IH]; [reflexivity|].
 destruct tail; cbn in *; [induction head; cbn; congruence|now rewrite IH].
Qed.

Theorem expansion_has_declared_meaning : forall message output,
 message_meaning output message (TaskGraph.expand message output).
Proof.
 fix IH 1. intros [|text|parts] output; try constructor.
 cbn. replace (fold_right (fun part rest=>String.append (TaskGraph.expand part output) rest) "" parts)
   with (String.concat "" (map (fun part=>TaskGraph.expand part output) parts)).
 2: { rewrite concat_fragments. induction parts; cbn; congruence. }
 apply concat_meaning.
 induction parts as [|part parts rest]; constructor; auto.
Qed.

Theorem declared_meaning_is_the_expansion : forall output message text,
 message_meaning output message text -> TaskGraph.expand message output = text.
Proof.
 fix IH 4. intros output message text meaning.
 destruct meaning as [|text|parts fragments related]; [reflexivity|reflexivity|].
 cbn. rewrite concat_fragments.
 induction related as [|part text parts texts head tail rest]; cbn; [reflexivity|].
 rewrite (IH output part text head), rest. reflexivity.
Qed.

Lemma declared_binding_is_resolved : forall key target nodes,
 node_binding key target nodes -> TaskGraph.resolve key nodes=Some target.
Proof.
 intros key target nodes binding. induction binding as [rest|node rest different bound IH].
 - unfold TaskGraph.resolve. cbn. now rewrite String.eqb_refl.
 - unfold TaskGraph.resolve in *. cbn. apply String.eqb_neq in different.
   now rewrite different.
Qed.

Lemma resolved_node_has_declared_binding : forall key target nodes,
 TaskGraph.resolve key nodes=Some target -> node_binding key target nodes.
Proof.
 intros key target nodes. induction nodes as [|[name task] nodes IH]; cbn; [discriminate|].
 unfold TaskGraph.resolve in *. cbn.
 destruct (String.eqb key name) eqn:matches; cbn.
 - intros same. inversion same; subst. apply String.eqb_eq in matches. subst. constructor.
 - intros bound. apply binding_later; [now apply String.eqb_neq|now apply IH].
Qed.

Lemma unresolved_node_has_no_declared_binding : forall key nodes,
 TaskGraph.resolve key nodes=None -> forall target, ~node_binding key target nodes.
Proof.
 intros key nodes missing target binding.
 apply declared_binding_is_resolved in binding. congruence.
Qed.

(** Both positive delivery and order are required. A dispatcher that always
    returns [] fails this theorem for a matching bound action. *)
Theorem pending_rule_obeys_declaration : forall source graph nodes rule output,
 rule_meaning source graph nodes rule output
   (TaskGraph.pending_rule source graph nodes rule output).
Proof.
 intros source graph nodes rule output. unfold TaskGraph.pending_rule.
 destruct (TaskGraph.resolve (F.rule_source rule) nodes) as [expected|] eqn:resolved.
 - destruct (N.eqb source expected) eqn:selected.
   + apply N.eqb_eq in selected. subst expected. apply matching_source;
     [now apply resolved_node_has_declared_binding|].
     induction (F.rule_actions rule) as [|action actions rest]; cbn; [constructor|].
     destruct (TaskGraph.resolve (F.action_target action) nodes) as [target|] eqn:bound.
     * econstructor; [now apply resolved_node_has_declared_binding|apply expansion_has_declared_meaning|exact rest].
     * econstructor; [now apply unresolved_node_has_no_declared_binding|exact rest].
   + eapply other_source with (expected:=expected);
     [now apply resolved_node_has_declared_binding|now apply N.eqb_neq].
 - apply missing_source. now apply unresolved_node_has_no_declared_binding.
Qed.

Theorem every_declared_handoff_is_delivered : forall source graph nodes rule output item,
 declared_handoff source graph nodes rule output item ->
 In item (TaskGraph.pending_rule source graph nodes rule output).
Proof.
 intros source graph nodes rule output [actual_graph actual_rule target text]
   [source_bound [action [member [target_bound [graph_same [rule_same meaning]]]]]].
 cbn in *. subst actual_graph actual_rule.
 apply declared_binding_is_resolved in source_bound.
 apply declared_binding_is_resolved in target_bound.
 unfold TaskGraph.pending_rule. rewrite source_bound, N.eqb_refl.
 induction (F.rule_actions rule) as [|head tail IH]; cbn in *; [contradiction|].
 destruct member as [<-|member].
 - rewrite target_bound. left. f_equal. now apply declared_meaning_is_the_expansion.
 - destruct (TaskGraph.resolve (F.action_target head) nodes); cbn; auto.
Qed.

Theorem registered_handoff_is_pending : forall source graph value declaration rule output item,
 In (graph,Some declaration)
   (indexed (fun id entry=>(id,entry)) 0 (TaskGraph.registry value)) ->
 In rule (F.graph_rules declaration) ->
 declared_handoff source graph (F.graph_nodes declaration) rule output item ->
 In item (TaskGraph.pending_deliveries source output value).
Proof.
 intros source graph value declaration rule output item registered member handoff.
 unfold TaskGraph.pending_deliveries. apply in_flat_map.
 exists (graph,Some declaration). split; [exact registered|]. cbn.
 apply in_flat_map. exists rule. split; [exact member|].
 now apply every_declared_handoff_is_delivered.
Qed.

(** A newly accepted nonempty assistant reply is observable by the real reaction
    hook. The freshness premise is about the stored origin identity; graph
    installation and repeated transition hooks cannot replay old history. *)
Theorem fresh_reply_is_observed : forall before source task origin text,
 K.find_task source before=Some task ->
 origin_producer origin=source -> String.eqb text ""=false ->
 TaskGraph.seen_origin origin task=false ->
 TaskGraph.new_outputs before source (append_history [AssistantMessage origin text] task)=[text].
Proof.
 intros before source task origin text found producer nonempty unseen.
 unfold TaskGraph.new_outputs. rewrite found.
 assert (history : task_history (append_history [AssistantMessage origin text] task)=
   task_history task++[AssistantMessage origin text]) by (destruct task; reflexivity).
 rewrite history.
 rewrite skipn_app,skipn_all,Nat.sub_diag. cbn.
 rewrite producer,nonempty,unseen,N.eqb_refl. reflexivity.
Qed.

Definition observed_provider_reply (text : string) : json := JObject [
 ("type",JString "provider_receipt");
 ("item",JObject [("type",JString "message");("role",JString "assistant");
   ("content",JArray [JObject [("type",JString "output_text");("text",JString text)]])]);
 ("markdown_fences",JArray [])].
Definition provider_reply_with_empty_output_text : json := observed_provider_reply "".

Local Lemma string_append_empty : forall text, String.append text ""=text.
Proof. intro text; induction text as [|character rest IH]; simpl; [reflexivity|now rewrite IH]. Qed.

Theorem provider_empty_output_text_is_still_an_assistant_reply :
 Conversation.provider_assistant_message provider_reply_with_empty_output_text = true /\
 Conversation.provider_text provider_reply_with_empty_output_text = "".
Proof. split; reflexivity. Qed.

Theorem nonassistant_provider_context_is_not_a_graph_output : forall origin content,
 Conversation.provider_assistant_message content=false ->
 TaskGraph.assistant_output (ModelContext origin content)=None.
Proof. intros; cbn [TaskGraph.assistant_output]; now rewrite H. Qed.

Theorem fresh_provider_reply_is_observed : forall before source task origin text,
 K.find_task source before=Some task ->
 origin_producer origin=source -> String.eqb text ""=false ->
 TaskGraph.seen_origin origin task=false ->
 TaskGraph.new_outputs before source
   (append_history [ModelContext origin (observed_provider_reply text)] task)=[text].
Proof.
 intros before source task origin text found producer nonempty unseen.
 unfold TaskGraph.new_outputs. rewrite found.
 assert (history : task_history (append_history [ModelContext origin (observed_provider_reply text)] task)=
   task_history task++[ModelContext origin (observed_provider_reply text)]) by (destruct task; reflexivity).
 rewrite history.
 rewrite skipn_app,skipn_all,Nat.sub_diag. cbn.
 unfold TaskGraph.assistant_output.
 cbn [Conversation.provider_assistant_message Conversation.provider_text].
 rewrite producer,unseen,N.eqb_refl,string_append_empty,nonempty. reflexivity.
Qed.

Theorem fresh_empty_provider_reply_is_ignored : forall before source task origin,
 K.find_task source before=Some task ->
 TaskGraph.new_outputs before source
   (append_history [ModelContext origin provider_reply_with_empty_output_text] task)=[].
Proof.
 intros before source task origin Found.
 unfold TaskGraph.new_outputs. rewrite Found.
 assert (History : task_history (append_history [ModelContext origin provider_reply_with_empty_output_text] task)=
   task_history task++[ModelContext origin provider_reply_with_empty_output_text]) by (destruct task; reflexivity).
 rewrite History,skipn_app,skipn_all,Nat.sub_diag. cbn.
 destruct (N.eqb source (origin_producer origin)); reflexivity.
Qed.

Theorem observed_provider_text_retains_its_requested_mode_and_is_routed :
 forall before source task ticket part text,
 K.find_task source before=Some task -> String.eqb text ""=false ->
 TaskGraph.seen_origin (OutputOrigin source ticket part InteractiveOutput) task=false ->
 TaskGraph.new_outputs before source
   (append_history
     (Callbacks.item_messages source ticket InteractiveOutput
       [ContextItem part (observed_provider_reply text)]) task)=[text].
Proof.
 intros before source task ticket part text Found Nonempty Fresh.
 assert (Message : Callbacks.item_messages source ticket InteractiveOutput
   [ContextItem part (observed_provider_reply text)] =
   [ModelContext (OutputOrigin source ticket part InteractiveOutput) (observed_provider_reply text)]).
 { unfold Callbacks.item_messages; cbn [List.map].
   unfold Conversation.context_output_mode.
   assert (Assistant : Conversation.provider_assistant_message (observed_provider_reply text)=true)
     by (cbn [Conversation.provider_assistant_message Conversation.provider_value Conversation.provider_assistant]; reflexivity).
   rewrite Assistant. reflexivity.
 }
 rewrite Message.
 eapply fresh_provider_reply_is_observed; try assumption; reflexivity.
Qed.

Lemma recording_receipt_preserves_tasks : forall graph receipt value,
 world_tasks (TaskGraph.record_receipt graph receipt value)=world_tasks value.
Proof.
 intros. unfold TaskGraph.record_receipt. destruct (TaskGraph.lookup graph value); [|reflexivity].
 unfold TaskGraph.store. reflexivity.
Qed.

(** A handoff uses the public input gate. A failed workspace is a rejected
    delivery, recorded in the graph without changing the recipient or causing
    unrelated scheduling effects. *)
Theorem failed_workspace_delivery_records_rejection : forall source item result,
 Worktree.execution_allowed (TaskGraph.delivery_target item) (decision_world result)=false ->
 TaskGraph.send_delivery source item result =
 Decision
   (TaskGraph.record_receipt (TaskGraph.delivery_graph item)
     (F.GraphReceipt source (TaskGraph.delivery_rule item) (TaskGraph.delivery_target item)
       (decision_reply (Worktree.failed_execution (decision_world result))))
     (decision_world result))
   (decision_reply result) (decision_effects result).
Proof.
 intros source item result unavailable.
 unfold TaskGraph.send_delivery, Worktree.execution_guard. rewrite unavailable.
 cbn [Worktree.failed_execution reject decision_world decision_reply decision_effects].
 now rewrite app_nil_r.
Qed.

Theorem failed_workspace_delivery_preserves_every_task : forall source item result,
 Worktree.execution_allowed (TaskGraph.delivery_target item) (decision_world result)=false ->
 world_tasks (decision_world (TaskGraph.send_delivery source item result)) =
 world_tasks (decision_world result).
Proof.
 intros source item result unavailable.
 rewrite failed_workspace_delivery_records_rejection by exact unavailable.
 cbn [decision_world]. apply recording_receipt_preserves_tasks.
Qed.

Theorem available_workspace_delivery_records_the_ordinary_send_result : forall source item result,
 Worktree.execution_allowed (TaskGraph.delivery_target item) (decision_world result)=true ->
 let sent := Tasks.send (TaskGraph.delivery_target item)
   [TextPart (TaskGraph.delivery_text item)] (decision_world result) in
 TaskGraph.send_delivery source item result =
 Decision
   (TaskGraph.record_receipt (TaskGraph.delivery_graph item)
     (F.GraphReceipt source (TaskGraph.delivery_rule item) (TaskGraph.delivery_target item)
       (decision_reply sent)) (decision_world sent))
   (decision_reply result) (decision_effects result ++ decision_effects sent).
Proof.
 intros source item result available.
 unfold TaskGraph.send_delivery, Worktree.execution_guard. now rewrite available.
Qed.

(** The actual dispatcher writes the delivered text through the ordinary Task
    input operation. This is a state-update guarantee; it makes no assumption
    about an external model eventually producing a reply. *)
Theorem actual_delivery_reaches_idle_task : forall source item result task,
 Worktree.execution_allowed (TaskGraph.delivery_target item) (decision_world result)=true ->
 K.find_task (TaskGraph.delivery_target item) (decision_world result)=Some task ->
 task_lifecycle task=Running Idle [] ->
 content_nonempty [TextPart (TaskGraph.delivery_text item)]=true ->
 exists received,
 K.find_task (TaskGraph.delivery_target item)
   (decision_world (TaskGraph.send_delivery source item result))=Some received /\
 task_history received=task_history task ++
   map UserMessage (task_queued task ++ [[TextPart (TaskGraph.delivery_text item)]]) /\
 task_lifecycle received=Running WantsModel [].
Proof.
 intros source item result task available found idle nonempty.
 unfold TaskGraph.send_delivery, Worktree.execution_guard. rewrite available.
 rewrite TaskChangesProofs.send_expression. cbv beta zeta. rewrite found, idle, nonempty.
 cbn [decision_world].
 assert (tasks_same : forall id graph receipt value,
   K.find_task id (TaskGraph.record_receipt graph receipt value)=K.find_task id value).
 { intros. unfold K.find_task. now rewrite recording_receipt_preserves_tasks. }
 rewrite tasks_same.
 exists (Tasks.receive [TextPart (TaskGraph.delivery_text item)] task).
 split; [now apply find_put_task with task|].
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 cbn [task_lifecycle] in idle; subst lifecycle; split; reflexivity.
Qed.

(** Preparation is different from failure: a live binding can accept its next
    input while the resource gate delays actual execution. *)
Theorem actual_delivery_to_preparing_workspace_reaches_idle_task :
 forall source item result task tree retiring,
 WorkspaceBinding.for_task (TaskGraph.delivery_target item) (decision_world result)=Some tree ->
 F.worktree_phase tree=F.TreeCreating retiring ->
 K.find_task (TaskGraph.delivery_target item) (decision_world result)=Some task ->
 task_lifecycle task=Running Idle [] ->
 content_nonempty [TextPart (TaskGraph.delivery_text item)]=true ->
 exists received,
 K.find_task (TaskGraph.delivery_target item)
   (decision_world (TaskGraph.send_delivery source item result))=Some received /\
 task_history received=task_history task ++
   map UserMessage (task_queued task ++ [[TextPart (TaskGraph.delivery_text item)]]) /\
 task_lifecycle received=Running WantsModel [].
Proof.
 intros source item result task tree retiring bound preparing found idle nonempty.
 apply (actual_delivery_reaches_idle_task source item result task); try assumption.
 unfold Worktree.execution_allowed. now rewrite bound, preparing.
Qed.



Theorem installed_plan_associates_its_work : forall original caller
 (owner : Work.owner_scope original) id (plan : TaskGraph.graph_plan original caller (Some owner)),
 F.association id (F.feature_graph_owners (world_features
   (decision_world (TaskGraph.install_plan id plan)))) = Some (Work.owner_identity owner).
Proof.
 intros original caller owner id plan.
 unfold TaskGraph.install_plan,TaskGraph.install_change,CommandResult.accept.
 destruct (fold_left (fun progress node => TaskGraph.birth (Some owner) node progress)
   (TaskGraph.graph_plans plan) (TaskGraph.initial_births original)) as [prepared frame nodes effects].
 unfold F.association,K.with_features,Selvedge.Features.State.with_graph_owners.
 destruct (TaskGraph.store id
   (F.TaskGraph (TaskGraph.declaration_name (TaskGraph.cached_source (TaskGraph.checked_cache (TaskGraph.graph_checked plan)))) nodes
     (TaskGraph.declaration_rules (TaskGraph.cached_source (TaskGraph.checked_cache (TaskGraph.graph_checked plan)))) []) prepared)
   as [sequence tasks ticket environment projects features].
 destruct features. unfold set. cbn -[N.eqb]; now rewrite N.eqb_refl.
Qed.
Theorem resolved_installation_associates_its_work : forall original caller
 (owner : Work.owner_scope original) id (checked : TaskGraph.checked_cached caller original) plans,
 TaskGraph.prepare_nodes (TaskGraph.scope_identity (Some owner)) caller original
   (TaskGraph.cached_nodes (TaskGraph.checked_cache checked)) = CommandResult.Accepted plans ->
 F.association id (F.feature_graph_owners (world_features
   (decision_world (TaskGraph.install_cached id (Some owner) checked)))) = Some (Work.owner_identity owner).
Proof.
 intros original caller owner id checked plans Prepared.
 rewrite (resolved_installation_follows_the_typed_plan _ _ _ _ _ _ Prepared).
 apply installed_plan_associates_its_work.
Qed.

Theorem graph_removal_preserves_other_identities : forall request caller value previous,
 TaskGraph.lookup (Selvedge.Generated.Commands.delete_task_graph_graph_id request) value = Some previous ->
 exists result,
 TaskGraph.handle_delete_task_graph request caller value = result /\
 TaskGraph.lookup (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
   (decision_world result) = None /\
 F.association (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
   (F.feature_graph_owners (world_features (decision_world result))) = None /\
 forall other, Selvedge.Generated.Commands.delete_task_graph_graph_id request <> other ->
 TaskGraph.lookup other (decision_world result) = TaskGraph.lookup other value.
Proof.
 intros request caller value previous Found.
 unfold TaskGraph.handle_delete_task_graph. rewrite Found.
 eexists; split; [reflexivity|].
 pose proof (graph_lookup_has_registry_entry _ _ _ Found) as Entry.
 split.
 - change (match registry_at (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
     (replace (Selvedge.Generated.Commands.delete_task_graph_graph_id request) None
       (TaskGraph.registry value)) with Some graph => graph | None => None end = None).
   rewrite (registry_replace_selected _ _ _ _ _ Entry). reflexivity.
 - split.
   + change (F.association (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
       (filter (fun entry => negb (N.eqb (Selvedge.Generated.Commands.delete_task_graph_graph_id request) (fst entry)))
         (F.feature_graph_owners (world_features value))) = None).
     unfold F.association; rewrite removing_a_key_clears_its_lookup; reflexivity.
   + intros other Different. unfold TaskGraph.lookup.
   change (match registry_at other
     (replace (Selvedge.Generated.Commands.delete_task_graph_graph_id request) None
       (TaskGraph.registry value)) with Some graph => graph | None => None end =
     match registry_at other (TaskGraph.registry value) with Some graph => graph | None => None end).
     rewrite Selvedge.Foundation.RegistryProofs.registry_replace_other; [reflexivity|exact Different].
Qed.

Theorem recording_a_receipt_retains_the_latest_history : forall id receipt value previous,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.record_receipt id receipt value) =
 Some (F.TaskGraph (F.graph_name previous) (F.graph_nodes previous) (F.graph_rules previous)
   (skipn (List.length (F.graph_receipts previous ++ [receipt]) - 256)
     (F.graph_receipts previous ++ [receipt]))).
Proof.
 intros id receipt value previous Found. unfold TaskGraph.record_receipt. rewrite Found.
 now apply replacing_a_graph_preserves_its_identity with previous.
Qed.

Theorem recording_a_receipt_preserves_other_graphs : forall id other receipt value,
 id <> other ->
 TaskGraph.lookup other (TaskGraph.record_receipt id receipt value) = TaskGraph.lookup other value.
Proof.
 intros id other receipt value Different. unfold TaskGraph.record_receipt.
 destruct (TaskGraph.lookup id value); [|reflexivity].
 now apply graph_installation_preserves_other_identities.
Qed.

Theorem recording_a_receipt_bounds_the_retained_history : forall id receipt value previous current,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.record_receipt id receipt value) = Some current ->
 (List.length (F.graph_receipts current) <= 256)%nat.
Proof.
 intros id receipt value previous current Found Recorded.
 rewrite (recording_a_receipt_retains_the_latest_history _ _ _ _ Found) in Recorded.
 inversion Recorded; subst current. cbn [F.graph_receipts]. rewrite length_skipn.
 assert (Bound : forall total limit : nat, (total - (total - limit) <= limit)%nat)
   by (intros; lia).
 apply Bound.
Qed.

Theorem pending_deliveries_obey_registry_order : forall source output value,
 registry_meaning source output
   (indexed (fun id entry => (id,entry)) 0 (TaskGraph.registry value))
   (TaskGraph.pending_deliveries source output value).
Proof.
 intros source output value. unfold TaskGraph.pending_deliveries.
 generalize (indexed (fun id entry => (id,entry)) 0 (TaskGraph.registry value)).
 intro entries; induction entries as [|[id [graph|]] entries IH]; cbn.
 - constructor.
 - assert (Rules : exists fragments,
     Forall2 (fun rule parts => rule_meaning source id (F.graph_nodes graph) rule output parts)
       (F.graph_rules graph) fragments /\
     flat_map (fun rule => TaskGraph.pending_rule source id (F.graph_nodes graph) rule output)
       (F.graph_rules graph) = List.concat fragments).
   { induction (F.graph_rules graph) as [|rule rules [fragments [Meanings Expanded]]].
     - exists []; split; [constructor|reflexivity].
     - exists (TaskGraph.pending_rule source id (F.graph_nodes graph) rule output :: fragments).
       split; [constructor; [apply pending_rule_obeys_declaration|exact Meanings]|].
       cbn. now rewrite Expanded. }
   destruct Rules as [fragments [Meanings Expanded]]. rewrite Expanded.
   econstructor; eauto.
 - now constructor.
Qed.


Lemma planned_node_preserves_existing_tasks : forall original
 (owner : option (Work.owner_scope original))
 (plan : TaskGraph.node_plan original (TaskGraph.scope_identity owner)) progress id task,
 find_task id (TaskGraph.born_world progress)=Some task ->
 find_task id (TaskGraph.born_world (TaskGraph.birth owner plan progress))=Some task.
Proof.
 intros original owner plan [current frame nodes effects] id task Found.
 destruct plan as [key target previous observed membership|key start]; [exact Found|].
 apply WorktreeProofs.scoped_birth_preserves_existing_tasks; exact Found.
Qed.
Lemma planned_nodes_preserve_existing_tasks : forall original
 (owner : option (Work.owner_scope original))
 (plans : list (TaskGraph.node_plan original (TaskGraph.scope_identity owner))) progress id task,
 find_task id (TaskGraph.born_world progress)=Some task ->
 find_task id (TaskGraph.born_world (fold_left (fun progress plan=>TaskGraph.birth owner plan progress) plans progress))=Some task.
Proof.
 intros original owner plans; induction plans as [|plan rest IH]; intros progress id task Found; [exact Found|].
 cbn [fold_left]. apply IH. apply planned_node_preserves_existing_tasks. exact Found.
Qed.
Theorem installed_plan_preserves_original_task_references : forall original caller
 (owner : option (Work.owner_scope original)) id (plan : TaskGraph.graph_plan original caller owner) task_id task,
 find_task task_id original=Some task ->
 find_task task_id (decision_world (TaskGraph.install_plan id plan))=Some task.
Proof.
 intros original caller owner id plan task_id task Found.
 pose proof (WorktreeProofs.a_batch_preserves_original_task_observations original
   (TaskGraph.born_world (fold_left (fun progress node=>TaskGraph.birth owner node progress)
     (TaskGraph.graph_plans plan) (TaskGraph.initial_births original)))
   (TaskGraph.born_frame (fold_left (fun progress node=>TaskGraph.birth owner node progress)
     (TaskGraph.graph_plans plan) (TaskGraph.initial_births original))) task_id task Found) as Retained.
 unfold TaskGraph.install_plan,TaskGraph.install_change,CommandResult.accept.
 destruct owner; exact Retained.
Qed.
Theorem installation_preserves_original_task_references : forall original caller
 (owner : option (Work.owner_scope original)) id (checked : TaskGraph.checked_cached caller original) task_id task,
 find_task task_id original=Some task ->
 find_task task_id (decision_world (TaskGraph.install_cached id owner checked))=Some task.
Proof.
 intros original caller owner id checked task_id task Found.
 destruct (TaskGraph.prepare_nodes (TaskGraph.scope_identity owner) caller original
   (TaskGraph.cached_nodes (TaskGraph.checked_cache checked))) as [plans|reason] eqn:Prepared.
 - rewrite (resolved_installation_follows_the_typed_plan _ _ _ _ _ _ Prepared).
   now apply installed_plan_preserves_original_task_references.
 - rewrite (refused_plan_is_atomic _ _ _ _ _ _ Prepared); exact Found.
Qed.
