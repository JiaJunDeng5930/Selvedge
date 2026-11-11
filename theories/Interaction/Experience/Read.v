From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Codec Domain Images Guidance.
From Selvedge.Features Require BoardFilter BoardParameters Domain.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require Attachments Audit World ModelSelection.
From Selvedge.Interaction.Experience Require ContextObservation.
From Selvedge.Interaction.Submission Require Observation.
Import ListNotations.
Open Scope string_scope.
Module KernelDomain := Selvedge.Kernel.Domain.
Module KernelCodec := Selvedge.Kernel.Codec.
Module BoardDomain := Selvedge.Features.Domain.

(** These observations select business information from the published world.
    Each entry decides which facts to present and how to present them. *)
Record task := ObservedTask {
 task_id : N; task_title : string; task_status : string; task_caption : string;
 task_working : bool; task_project : option N; task_work : option N; task_parent : option N
}.
Definition observe_task value :=
 id<-natural_field "id" value;;name<-string_field "title" value;;
 status<-string_field "status" value;;
 if existsb(String.eqb status)["active";"frozen";"stopped";"archived"]then
 caption<-string_field "status_label" value;;working<-bool_field "working" value;;
 settings<-field "settings" value;;project<-id_field "project_id" settings;;
 work<-id_field "work_id" value;;parent<-id_field "parent" value;;
 Some(ObservedTask id name status caption working project work parent)else None.
Definition tasks snapshot := list_field observe_task "tasks" snapshot.
Definition find_task id snapshot := bind(World.find_task id snapshot)observe_task.
Definition same_id lhs rhs := match lhs,rhs with
|None,None=>true|Some lhs,Some rhs=>N.eqb lhs rhs|_,_=>false end.
Definition project_tasks selected := filter(fun value=>same_id selected(task_project value)).
Definition work_tasks selected :=
 filter (fun value=>match selected with None=>true|Some work=>same_id(Some work)(task_work value)end).

Record project := ObservedProject {
 project_id : N; project_name : string; project_workspace : KernelDomain.workspace;
 project_guidance : Guidance.t
}.
Definition observe_project value :=
 id<-natural_field "project_id" value;;name<-string_field "name" value;;
 workspace<-bind(field "workspace" value)KernelCodec.parse_workspace;;
 guidance<-bind(field "guidance" value)(KernelCodec.parse_guidance workspace);;
 Some(ObservedProject id name workspace guidance).
Definition projects snapshot := list_field observe_project "projects" snapshot.
Definition find_project id snapshot :=
 bind(World.find_world "projects" "project_id" id snapshot)observe_project.
Definition guidance_instructions guidance :=
 match Guidance.json guidance with JNull=>None|value=>string_field "instructions" value end.
Definition project_instructions value := guidance_instructions(project_guidance value).

Record work := ObservedWork { work_id : N; work_name : string; work_source : string }.
Definition observe_work value := id<-natural_field "work_id" value;;
 name<-string_field "name" value;;source<-string_field "source" value;;Some(ObservedWork id name source).
Definition works snapshot := list_field observe_work "works" snapshot.
Definition find_work id snapshot := bind(World.find_work id snapshot)observe_work.

Record committed_context := CommittedContext {
 context_project : option N; context_project_name : option string;
 context_workspace : KernelDomain.workspace; context_guidance : Guidance.t;
 context_filesystem : string; context_network : string; context_approval : string
}.
Definition approval_description snapshot approval := match approval with
 |KernelDomain.FullAccess=>"Unrestricted"|KernelDomain.AskForApproval=>"Ask"
 |KernelDomain.ReviewWith reviewer=>"Automatic review: "++ContextObservation.profile_label(Observation.catalog snapshot)reviewer end.
Definition task_context id snapshot :=
 settings<-ContextObservation.task_settings id snapshot;;
 let project:=KernelDomain.settings_project settings in
 let sandbox:=KernelDomain.settings_sandbox settings in
 let approval:=KernelDomain.settings_approval settings in
 Some(CommittedContext project (bind project(fun id=>option_map project_name(find_project id snapshot)))
   (KernelDomain.settings_workspace settings)(KernelDomain.settings_guidance settings)
   (ContextObservation.filesystem_summary sandbox approval)
   (ContextObservation.network_summary sandbox approval)(approval_description snapshot approval)).
Definition context_guidance_root context := string_field "workspace"(Guidance.json(context_guidance context)).
Definition context_guidance_revision context := string_field "revision"(Guidance.json(context_guidance context)).
Definition context_instructions context := guidance_instructions(context_guidance context).

Record task_operation := TaskOperation {
 operation_id : N; operation_tool : string; operation_call_id : string;
 operation_stage : string; operation_status : string; operation_arguments : option json;
 operation_human : bool; operation_directory : option string; operation_reviewer : option string
}.
Definition observe_operation snapshot value :=
 id<-natural_field "operation_id" value;;tool<-string_field "tool" value;;
 call_id<-string_field "call_id" value;;stage<-string_field "stage" value;;
 status<-string_field "status" value;;human<-bool_field "awaitingHuman" value;;
 let directory:=bind(field "context" value)(fun settings=>
   bind(field "workspace" settings)(string_field "primary_root")) in
 let reviewer:=bind(bind(field "reviewer" value)(field "profile"))KernelCodec.parse_profile in
 Some(TaskOperation id tool call_id stage status (bind(field "call" value)(field "arguments"))
  human directory(option_map(fun profile=>ContextObservation.profile_label(Observation.catalog snapshot)profile)reviewer)).
Definition task_operations id snapshot :=
 bind(World.find_task id snapshot)(list_field(observe_operation snapshot)"operations").
Definition pending_approvals operations :=
 filter(fun operation=>String.eqb "approval_pending"(operation_stage operation))operations.

Record task_worktree := TaskWorktree {
 worktree_status : string; worktree_caption : string; worktree_source : string;
 worktree_root : option string; worktree_message : string
}.
Definition worktree_status_caption status := match status with
 |"creating"=>"Creating workspace…"
 |"creating_archived"=>"Creating workspace before archiving…"
 |"ready"=>"Workspace ready"
 |"create_failed"=>"Workspace creation failed"
 |"archiving"=>"Archiving workspace…"
 |"archived"=>"Workspace archived"
 |"archive_failed"=>"Workspace archive failed"
 |_=>"" end.
Definition observe_worktree value :=
 status<-string_field "status" value;;source<-string_field "source_root" value;;
 root<-field "root" value;;message<-string_field "message" value;;
 Some(TaskWorktree status(worktree_status_caption status)source(as_string root)message).
Definition task_workspace id snapshot :=
 bind(World.find_world "worktrees" "task_id" id snapshot)observe_worktree.

Record task_details := TaskDetails {
 task_detail_model : string; task_detail_reasoning : string; task_detail_phase : string;
 task_detail_lineage : list N; task_detail_tools : list(string*string);
 task_detail_queued : list string
}.
Definition observe_tool value :=
 name<-string_field "name" value;;description<-string_field "description" value;;Some(name,description).
Definition observe_task_details value :=
 model<-string_field "model" value;;reasoning<-string_field "reasoning" value;;
 phase<-string_field "phase" value;;lineage<-list_field natural "lineage" value;;
 tools<-list_field observe_tool "tools" value;;
 queued<-list_field (fun value=>option_map KernelDomain.content_text(Images.parse_content value)) "queued_messages" value;;
 Some(TaskDetails model reasoning phase lineage tools queued).
Definition task_details_for id snapshot :=
 bind(World.find_task id snapshot)observe_task_details.
Definition task_side_parent snapshot task :=
 value<-World.find_task task snapshot;;
 natural_field "side_parent" value.
Definition task_timeline id snapshot :=
 value<-World.find_task id snapshot;;
 option_map(Audit.retained 0)(array_field "history" value).

Definition board_value snapshot := field "board" snapshot.
Definition card_link_stage task snapshot :=
 value<-World.find_task task snapshot;;
 bind(string_field "card_link_stage" value)BoardParameters.stage.

Inductive generation := Idle | Generating | GenerationFailed(reason:string).
Definition observe_generation value := match string_field "status" value with
 |Some "idle"=>Some Idle|Some "running"=>Some Generating
 |Some "failed"=>option_map GenerationFailed(string_field "reason" value)|_=>None end.
Definition generation_caption generation := match generation with
 |Idle=>""|Generating=>"正在生成。原始请求已保存；本次生成完成前不能编辑或移动任务。"
 |GenerationFailed reason=>reason end.
Definition generation_status generation := match generation with
 |Idle=>"idle"|Generating=>"running"|GenerationFailed _=>"failed" end.
Record card := ObservedCard {
 card_id : N; card_identifier : string; card_title : string; card_description : string;
 card_stage : BoardDomain.board_stage; card_priority : BoardDomain.priority;
 card_revision : N; card_pinned : bool; card_archived : bool; card_activity : string;
 card_project : option N; card_owner : BoardDomain.owner; card_labels : list string;
 card_updated : N; card_start_error : string; card_generation : generation;
 card_attachments : list Attachments.attachment; card_task : option N
}.
Definition observe_card value :=
 id<-natural_field "card_id" value;;identifier<-string_field "identifier" value;;
 title<-string_field "title" value;;description<-string_field "description" value;;
 stage<-bind(string_field "status" value)BoardParameters.stage;;
 priority<-bind(string_field "priority" value)BoardParameters.priority;;
 revision<-natural_field "revision" value;;pinned<-bool_field "pinned" value;;archived<-bool_field "archived" value;;
 activity<-string_field "activity" value;;project<-bind(string_field "project" value)BoardParameters.optional_project;;
 owner<-bind(string_field "assignee" value)BoardParameters.owner;;labels<-list_field as_string "labels" value;;
 updated<-bind(string_field "updated_at" value)parse_natural;;start_error<-string_field "start_error" value;;
 generation<-bind(field "enrichment" value)observe_generation;;
 attachments<-list_field Attachments.decode_attachment "attachments" value;;task<-id_field "task_id" value;;
 Some(ObservedCard id identifier title description stage priority revision pinned archived activity project owner labels
  updated start_error generation attachments task).
Definition board_cards snapshot := bind(board_value snapshot)(list_field observe_card "cards").
Definition find_card id snapshot := value<-board_value snapshot;;
 bind(World.find_world "cards" "card_id" id value)observe_card.
Definition card_activity_label name:=value_or "未开始"
 (option_map snd(find(fun entry=>String.eqb name(fst entry))
 [("generating","生成中");("draft_failed","生成失败");("queued","排队中");("working","工作中");
  ("evaluating","评估推理等级");("compacting","整理上下文");("awaiting_approval","等待授权");
  ("completed","已完成");("failed","运行失败");("interrupted","已中断");("paused","已暂停");("archived","会话已归档")])).
Definition card_owner_label snapshot owner:=match owner with
|BoardDomain.Unassigned=>"未分配"|BoardDomain.Self=>"我"
|BoardDomain.ProfileOwner key=>match ModelSelection.observed_profile snapshot key with
 |Some profile=>ContextObservation.profile_label(ModelSelection.selectable_profiles(Observation.catalog snapshot))profile
 |None=>"模型 "++key++" 不可用"end end.
Definition card_project_label snapshot project := match project with
 |Some id=>match find_project id snapshot with
  |Some project=>project_name project|None=>"项目 #"++show_natural id++" 不可用"end|None=>""end.
Definition ordered_cards snapshot :=
 value<-board_value snapshot;;order<-list_field natural "order" value;;
 traverse(fun id=>World.find_world "cards" "card_id" id value)order.
Definition visible_card_values snapshot selection now :=
 values<-ordered_cards snapshot;;
 Some(BoardFilter.apply_in_world selection now values snapshot).
Definition visible_cards snapshot selection now :=
 values<-visible_card_values snapshot selection now;;traverse observe_card values.
Definition display_cards (cards:list card) := List.app (filter card_pinned cards) (filter(fun value=>negb(card_pinned value))cards).
Definition archived_cards snapshot := option_map(filter card_archived)(board_cards snapshot).
Definition count_working snapshot selection now :=
 option_map(fun cards=>N.of_nat(List.length cards))
  (visible_card_values snapshot (BoardFilter.set_tab "working" selection) now).
Record board_settings := BoardSettings { board_automatic : bool; board_draft_profile : string }.
Definition board_configuration snapshot :=
 value<-board_value snapshot;;automatic<-bool_field "automatic" value;;
 profile<-string_field "draft_profile" value;;Some(BoardSettings automatic profile).

Record graph_node := GraphNode { node_key : string; node_task : N }.
Record graph_action := GraphAction { action_target : string; action_message : json }.
Record graph_rule := GraphRule { rule_key : string; rule_source : string; rule_actions : list graph_action }.
Record graph_receipt := GraphReceipt {
 receipt_source : N; receipt_target : N; receipt_rule : string; receipt_reply : json
}.
Record graph := ObservedGraph {
 graph_id : N; graph_name : string; graph_work : option N;
 graph_nodes : list graph_node; graph_rules : list graph_rule; graph_receipts : list graph_receipt
}.
Definition observe_graph_node value :=
 key<-string_field "key" value;;task<-natural_field "task_id" value;;Some(GraphNode key task).
Definition observe_graph_action value :=
 target<-string_field "target" value;;message<-field "message" value;;Some(GraphAction target message).
Definition observe_graph_rule value :=
 key<-string_field "key" value;;source<-string_field "source" value;;
 actions<-list_field observe_graph_action "actions" value;;Some(GraphRule key source actions).
Definition observe_graph_receipt value :=
 source<-natural_field "source" value;;target<-natural_field "target" value;;
 rule<-string_field "rule" value;;reply<-field "reply" value;;Some(GraphReceipt source target rule reply).
Definition observe_graph value :=
 id<-natural_field "graph_id" value;;name<-string_field "name" value;;work<-id_field "work_id" value;;
 nodes<-list_field observe_graph_node "nodes" value;;rules<-list_field observe_graph_rule "rules" value;;
 receipts<-list_field observe_graph_receipt "receipts" value;;Some(ObservedGraph id name work nodes rules receipts).
Definition graphs snapshot := list_field observe_graph "graphs" snapshot.
Definition find_graph id snapshot := bind(World.find_world "graphs" "graph_id" id snapshot)observe_graph.
Definition graph_endpoint value name :=
 option_map node_task(find(fun node=>String.eqb name(node_key node))(graph_nodes value)).
