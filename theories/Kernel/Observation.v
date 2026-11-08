From Selvedge.Programming Require RequestTypes.
From Selvedge.Programming Require Variant.
From Selvedge.Kernel Require Import ModelDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Numbers Domain Codec Context Commands State Tasks ContextUpdates Reasoning ReasoningView ApprovalProtocol ContextSelection WorkspaceBackend Workspace.
From Selvedge.Features Require Import Domain CompactionCodec WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition indexed {A B : Type} := @Selvedge.Foundation.Registry.indexed A B.
Definition task_owner (id : N) (value : task) (features : Selvedge.Features.Domain.state) := Selvedge.Features.Domain.owner_id id (task_lineage value) features.
Definition operation_status (value : operation) := match operation_stage value with
 | Executing _ | Elevated _ _ => "running"
 | AwaitingApproval _ _ => "awaiting_approval"
 | Granted _ => "approved_waiting_to_run"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_stage_name (value : operation) := match operation_stage value with
 | Executing _ => "executing" | Elevated _ _ => "elevated_executing"
 | AwaitingApproval _ _ => "approval_pending" | Granted _ => "approval_granted"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_summary (settings : task_settings) (value : operation) := JObject ([
 ("call",call_json (operation_call value));("context",settings_json settings);
 ("reviewer",match operation_stage value with
 | AwaitingApproval _ reviewer | Granted reviewer | Elevated _ reviewer => Codec.reviewer_json reviewer | _ => JNull end);
 ("operation_id", number (operation_id value)); ("call_id", JString (call_id (operation_call value)));
 ("tool", JString (call_name (operation_call value))); ("status", JString (operation_status value));
 ("announced", JBool (operation_announced value));
 ("stage",JString (operation_stage_name value));
 ("awaitingHuman", JBool (match operation_stage value with AwaitingApproval _ HumanReviewer => true | _ => false end))] ++
 (match operation_stage value with
  | AwaitingApproval _ _ | Granted _ =>
    [("arguments", call_arguments (operation_call value))]
  | Elevated ticket _ => [("execution_ticket", number ticket)]
  | _ => [] end)).
Definition project_fields (id : N) (value : project) := [
 ("id", number id); ("project_id", number id); ("name", JString (project_name value));
 ("workspace", workspace_json (project_workspace value)); ("guidance", Guidance.json (Domain.project_guidance value));
 ("workspace_resource",optional_number (project_resource value)); ("create_worktree", JBool (project_worktree value))].
Definition project_json (id : N) (value : project) := JObject (project_fields id value).
Definition effect_packet (state : world) (value : effect) := match value with
 | ObserveContext id ticket task => Variant.pack ModelDeclarations.observe_context
   [!id;ticket;settings_json (task_current_settings task);WorkspaceBinding.execution (task_current_settings task) state;
    map definition_json definitions;map Context.snapshot_json (ContextUpdates.bindings (task_history task))!]
 | RequestModel request =>
   let id := ModelRequest.owner request in
   let model := ModelRequest.model (ModelRequest.selection request) in
   let task := ModelRequest.context_task request in
   let scope := ModelRequest.scope request in let reserve := ModelRequest.reserve request in
   let source := ContextSelection.history_json id (task_history task) in
   let selected := ContextSelection.latest source (if (0 <? reserve)%N then scope else "") 0 ContextSelection.Original in
   Variant.pack ModelDeclarations.request_model [!id;ModelRequest.ticket request;model_json model;
    WorkspaceBinding.execution (task_current_settings task) state;
    Reasoning.sampling model (task_current_profile task);
    (if (0 <? reserve)%N then ContextSelection.assemble selected source scope else ContextSelection.portable_messages source);
    (0 <? reserve)%N;scope;(match selected with ContextSelection.Replacement length _ => Some length | _ => None end);
    reserve;N.of_nat (List.length (task_history task));map tool_json (contract_tools (task_contract task));ModelRequest.callable request!]
 | RequestReasoning id ticket task => let model := task_current_profile task in Variant.pack ModelDeclarations.reasoning
   [!id;ticket;model_json model;Reasoning.evaluator_history task;Reasoning.evaluator_project_context task!]
 | ExecuteTool id ticket operation tool call settings access => Variant.pack ModelDeclarations.tool
   [!id;ticket;operation;tool_json tool;wire_call_json call;
    JObject [("workspace",workspace_json (settings_workspace settings));("resource",WorkspaceBinding.execution settings state);
      ("sandbox",sandbox_json (settings_sandbox settings));("access",JString (match access with DefaultAccess=>"sandboxed"|ElevatedAccess=>"unrestricted" end))]!]
 | RequestApproval id ticket profile call task => Variant.pack ModelDeclarations.approval
   [!id;ticket;model_json profile;wire_call_json call;settings_json (task_current_settings task);
    ApprovalProtocol.instructions;ApprovalProtocol.user_request_text (task_history task)!]
 | CheckTool id ticket plugin tool call => Variant.pack ModelDeclarations.hook [!id;ticket;plugin;tool_json tool;wire_call_json call!]
 | CheckResult id ticket operation plugin call value error => Variant.pack ModelDeclarations.after_hook [!id;ticket;operation;plugin;wire_call_json call;value;error!]
 | ResetModelSession id => Variant.pack ModelDeclarations.reset_model_session [!id!]
 | CancelTask id => Variant.pack ModelDeclarations.cancel [!id!]
 | CancelTicket id ticket => Variant.pack ModelDeclarations.cancel_ticket [!id;ticket!] | ContinueScheduling => Variant.pack ModelDeclarations.continue [!!]
 | CreateWorktree id root workspace backend => Variant.pack ModelDeclarations.worktree_create [!WorkspaceBackend.to_value backend;id;root;workspace_json workspace!]
 | ArchiveWorktree id source root backend => Variant.pack ModelDeclarations.worktree_archive [!WorkspaceBackend.to_value backend;id;root;source!]
 | RequestFeature sent => RequestTypes.encode_packet sent (world_features state)
 | CancelConnectionJob id => Variant.pack ModelDeclarations.chatgpt_cancel [!id!]
 | MaintainContext request => Selvedge.Features.CompactionCodec.effect_packet request
 end.
Definition effect_json state value := Variant.encode_packet (effect_packet state value).
Definition envelope_with_effects (durable : bool) (reply : json) (effects : list json) := JObject [
 ("durable", JBool durable); ("reply", reply); ("effects", JArray effects)].
Definition envelope (durable : bool) (value : decision) :=
 envelope_with_effects durable (decision_reply value)
   (map (effect_json (decision_world value)) (decision_effects value)).
