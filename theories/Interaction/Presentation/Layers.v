From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Domain Commands Codec Images.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require Domain BoardFilter BoardParameters.
From Selvedge.Interaction Require Import Codec Identity Input Resource Services Attachments ObjectActions.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.Interaction.Session Require Draft State Observation Navigation.
Module SessionNavigation := Selvedge.Interaction.Session.Navigation.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Projection Editors Navigation Collections Activities Pages.
From Selvedge.Interaction.Presentation Require Roles Information Composition.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module G := Selvedge.Generated.Commands.
Module SessionObserve := Selvedge.Interaction.Session.Observation.
Definition status_availability status :=match status with
|ObjectActions.Available=>Available|ObjectActions.Awaiting=>Unavailable "Checking action availability"
|ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>Unavailable reason end.
Definition menu_nodes snapshot s subject occurrence parent :=flat_map(fun action=>
 let key:=part parent(ObjectActions.action_key action)in
 let command:=Node key(ObjectActions.action_key action)(ObjectActions.action_label action)Roles.Button
  (Activate(Control(ObjectActions.action_key action)(ObjectActions.action_label action)
    (match ObjectActions.action_confirmation action with Some _=>Destructive|None=>Secondary end)
    (Input.MenuAction subject(ObjectActions.action_key action)occurrence)(status_availability(ObjectActions.action_status action))))[]in
 match ObjectActions.action_status action with
 |ObjectActions.AssessmentFailed reason=>[command;
   information parent("failure/"++ObjectActions.action_key action)Information.Description reason;
   declared parent Roles.Button(secondary("retry/"++ObjectActions.action_key action)"Retry"(Input.RetryMenuAssessment subject(ObjectActions.action_key action)occurrence))]
 | _=>[command]end)(ObjectActions.items snapshot s subject).
Definition detail_action_input parent(action:ObjectActions.action):Input.input:=
 let trigger:=part parent(ObjectActions.action_key action)in
 match ObjectActions.action_operation action with
 |ObjectActions.NativeCommand command=>match ObjectActions.action_confirmation action with
  |Some(caption,destination)=>Input.Confirmation command caption destination trigger|None=>Input.Command command end
 |ObjectActions.Destination target=>Input.Navigate target
 |ObjectActions.Editor owner=>Input.OpenEditor owner trigger
 |ObjectActions.SideConversation task=>Input.BeginSide task trigger end.
Definition detail_action_nodes snapshot s subject parent:=map(fun action=>
 declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)
  (match ObjectActions.action_confirmation action with Some _=>Destructive|None=>Secondary end)
  (detail_action_input parent action)(status_availability(ObjectActions.action_status action))))
 (ObjectActions.items snapshot s subject).
Definition context_facts {A} snapshot task parent:list(node A) :=match SessionObserve.task_settings task snapshot with
|None=>[read_only parent "unavailable" "Execution context" "The committed context is unavailable"]
|Some settings=>
 let workspace:=Domain.settings_workspace settings in
 let sandbox:=Domain.settings_sandbox settings in
 [read_only parent "workspace" "Working directories"(String.concat "
"(Domain.workspace_roots workspace));
  read_only parent "primary" "Primary directory"(value_or ""(Domain.workspace_primary workspace));
  read_only parent "filesystem" "Filesystem access"(match Domain.sandbox_access sandbox with Domain.ReadOnly=>"Read only"|Domain.WorkspaceWrite=>"Workspace write"end);
  read_only parent "network" "Network access"(if Domain.sandbox_network sandbox then "Network enabled"else"Network disabled");
  read_only parent "approval" "Approval policy"(match Domain.settings_approval settings with
   |Domain.FullAccess=>"Unrestricted"|Domain.AskForApproval=>"Ask"
   |Domain.ReviewWith reviewer=>"Automatic review: "++Observation.profile_label reviewer end);
  read_only parent "guidance" "Project guidance"(match Domain.settings_guidance settings with JNull=>"No project guidance"|guidance=>text "instructions" guidance end)]end.
Definition task_details snapshot s task parent :=match find_task task snapshot with
|None=>[read_only parent "missing" "Task unavailable" "The task no longer exists"]
|Some task=>
 (context_facts snapshot(task_id task)parent++
 [read_only parent "model" "Model"(text "model"(task_observation task)++" · "++text "reasoning"(task_observation task));
  read_only parent "status" "Status"(text "status_label"(task_observation task));
  read_only parent "phase" "Phase"(text "phase"(task_observation task));
  read_only parent "lineage" "Lineage"(String.concat ", "(map(fun value=>match natural value with Some id=>show_natural id|None=>"Unavailable"end)(Selvedge.Interaction.Codec.items "lineage"(task_observation task))))] ++
 map(fun tool=>read_only parent(String.append "tool/"(text "name" tool))(text "name" tool)(text "description" tool))(Selvedge.Interaction.Codec.items "tools"(task_observation task))++
 map(fun '(ordinal,contents)=>read_only parent(String.append "queued/"(show_natural(N.of_nat ordinal)))"Queued message"
  (match Selvedge.Kernel.Images.parse_content contents with Some contents=>Domain.content_text contents|None=>"Queued message unavailable"end))
  (combine(seq 0(List.length(Selvedge.Interaction.Codec.items "queued_messages"(task_observation task))))(Selvedge.Interaction.Codec.items "queued_messages"(task_observation task)))++
 Pages.worktree_details snapshot s(task_id task)parent)%list end.
Definition card_details snapshot s id parent :=match Projection.card id snapshot with
|None=>[read_only parent "missing" "Card unavailable" "This card no longer exists"]
|Some card=>match Collections.card_face snapshot s id card with
 |None=>[read_only parent "invalid-card" "Card unavailable" "Card priority observation unavailable"]
 |Some face=>
 ([read_only parent "identifier" "任务"(text "identifier" card);read_only parent "title" "标题"(card_title face);
  read_only parent "description" "描述"(card_description face);read_only parent "stage" "状态"(match BoardParameters.stage(text "status" card)with Some stage=>Selvedge.Features.Domain.stage_label stage|None=>"状态不可用"end);
  read_only parent "activity" "执行"(card_status face);
  read_only parent "priority" "优先级"(Selvedge.Features.Domain.priority_label(card_priority face));read_only parent "owner" "负责人"(card_owner face);
  read_only parent "project" "项目"(card_project face);read_only parent "labels" "标签"(String.concat "
"(card_labels face));
  read_only parent "start-error" "启动错误"(text "start_error" card)]++
 (match field "enrichment" card with Some value=>[read_only parent "enrichment" "生成"(if String.eqb(text "status" value)"running"then
  "正在生成。原始请求已保存；本次生成完成前不能编辑或移动任务。"else text "reason" value)]|None=>[]end)++
 flat_map(fun value=>match decode_attachment value with
  |Some file=>[declared parent Roles.Button(secondary("preview/"++asset_id file)("Preview "++asset_name file)
    (Input.ServiceInput(Services.OpenPreview file(part parent("preview/"++asset_id file)))))]|None=>[]end)(Selvedge.Interaction.Codec.items "attachments" card)++
 (match natural_field "task_id" card with Some task=>match find_task task snapshot with
  |Some entry=>[Navigation.task_entry_tree(State.location(State.navigation_state s))parent(TaskTree entry [])]|None=>[]end|None=>[]end)++
 detail_action_nodes snapshot s(CardActions id)parent )%list end end.
Definition board_settings snapshot s parent :=match Projection.board snapshot with
|None=>[read_only parent "missing" "Board settings" "Board observations unavailable"]
|Some board=>let automatic:=flag "automatic" board in
 let profile:=text "draft_profile" board in
 let toggle:=option_map Input.Command(decode_command Selvedge.Kernel.Commands.command_specs
  (G.encode(G.Cmd_board_settings(G.Build_board_settings(negb automatic)profile))))in
 ((match toggle with None=>[]|Some input=>[declared parent Roles.Button(observe_control(fun input=>domain_availability(Selvedge.Interaction.Session.Authoring.input_availability snapshot s input))(secondary "automation"(if automatic then"关闭自动执行"else"启用自动执行")input))]end)++
 [Node(part parent "drafting-model")"drafting-model" "草稿模型"Roles.Field
  (BoardProfile automatic profile(map(fun value=>Fields.ChoiceValue(Domain.profile_key value)(Observation.profile_label value))(SessionObserve.catalog snapshot))
    (Services.connected(State.service_state s))(fun value=>option_map Input.BoardProfile(as_string value)))[]])%list end.
Definition filter_choices snapshot category :=match category with
|BoardFilter.Status=>map(fun stage=>(Selvedge.Features.Domain.stage_name stage,Selvedge.Features.Domain.stage_label stage))Selvedge.Features.Domain.stages
|BoardFilter.Priority=>map(fun level=>(Selvedge.Features.Domain.priority_name level,Selvedge.Features.Domain.priority_label level))Selvedge.Features.Domain.priorities
|BoardFilter.Date=>[("1","最近 24 小时");("7","最近 7 天");("30","最近 30 天")]
|BoardFilter.Assignee=>("self","我")::("","未分配")::map(fun agent=>("agent/"++match natural_field "agent_id" agent with Some id=>show_natural id|None=>"unavailable"end,text "name" agent))(value_or[](Projection.board_agents snapshot))
|BoardFilter.Creator=>[("self","我")]
|BoardFilter.Project=>map(fun project=>(show_natural(project_id project),project_name project))(value_or[](Projection.projects snapshot))
|BoardFilter.Label=>map(fun value=>(value,value))(nodup string_dec(flat_map(fun card=>value_or[](bind(array_field "labels" card)Selvedge.Kernel.Codec.strings))(value_or[](Projection.board_cards snapshot))))end.
Definition filter_title category :=match category with
|BoardFilter.Status=>"状态"|BoardFilter.Priority=>"优先级"|BoardFilter.Date=>"更新时间"
|BoardFilter.Assignee=>"负责人"|BoardFilter.Creator=>"创建人"|BoardFilter.Project=>"项目"|BoardFilter.Label=>"标签"end.
Definition board_filters snapshot s parent :=map(fun category=>let name:=BoardFilter.category_name category in
 region parent("filter/"++name)(filter_title category)Roles.Section
  (group_title(part parent("filter/"++name))(filter_title category)::map(fun '(value,label)=>
   Node(part parent("filter/"++name++"/"++value))"filter-option"label Roles.Button
    (Choice MultipleChoice(existsb(String.eqb value)(BoardFilter.filter_values(State.board_selection s)category))""
     (secondary("filter/"++name++"/"++value)label(Input.BoardToggle name value)))[])(filter_choices snapshot category)))BoardFilter.categories.
Definition panel_kind capacity panel :=match panel with
|State.PropertyPanel _ (Activity.PropertyActivity UX.ProjectProperty)=>ModalDialog
|State.PropertyPanel _ _|State.ObjectActionsPanel _|State.InformationPanel(State.PropertySource _ _)=>AnchoredMenu
|State.InformationPanel(State.TaskDetails _)|State.SideConversationPanel _=>if details_beside_timeline capacity then TrailingDetails else ModalDialog
|_=>ModalDialog end.
Definition source_origin_matches e request panel:=match panel with
|State.PropertyPanel actual requested=>same_editor e actual&&String.eqb(SessionNavigation.request_key request)(SessionNavigation.request_key requested)
|State.EditorPanel actual=>same_editor e actual
|_=>false end.
Fixpoint visible_layers(layers:list State.layer):list State.layer:=match layers with
|[]=>[]
|layer::rest=>let shown:=visible_layers rest in
 match State.layer_panel layer,rest,shown with
 |State.InformationPanel(State.PropertySource e request),origin::_,_::others=>
  layer::if source_origin_matches e request(State.layer_panel origin)then others else shown
 |_,_,_=>layer::shown end end.
Fixpoint layers_after occurrence(layers:list State.layer):list State.layer:=match layers with
|[]=>[]|layer::rest=>if N.eqb occurrence(State.layer_occurrence layer)then rest else layers_after occurrence rest end.
Definition anchor s layer:=match State.layer_panel layer,layers_after(State.layer_occurrence layer)(State.layers(State.navigation_state s))with
|State.InformationPanel(State.PropertySource e request),origin::_=>
 if source_origin_matches e request(State.layer_panel origin)then State.layer_trigger origin else State.layer_trigger layer
|_,_=>State.layer_trigger layer end.
Definition behavior s capacity layer :=
 let kind:=panel_kind capacity(State.layer_panel layer)in
 let beside:=match kind with TrailingDetails=>details_beside_timeline capacity|_=>false end in
 LayerBehavior kind beside(State.layer_occurrence layer)(State.layer_initial_attention layer)
  (State.layer_trigger layer)"/main"(anchor s layer) Input.ClosePanel(negb beside)(negb beside).
Definition information_panel snapshot s kind parent :=match kind with
|State.TaskDetails task=>task_details snapshot s task parent
|State.TaskContext task=>context_facts snapshot task parent
|State.CardDetails card=>card_details snapshot s card parent
|State.PropertySource e request=>match Observation.property_for_request snapshot s e request with
 |None=>[read_only parent "unavailable" "Source" "The original settings observation is unavailable"]
 |Some property=>
  [read_only parent "owner" "Settings"(UX.property_label property);
   read_only parent "configuration-source" "Source"(Observation.property_source_description snapshot s property)]end end.
Definition side_content snapshot s task parent :=
 let return_control:=match ObjectActions.return_action snapshot s task with
 |Some action=>match ObjectActions.command action with
  |Some command=>[declared parent Roles.Button(Control "return"(ObjectActions.action_label action)Secondary
    (Input.Command command)(status_availability(ObjectActions.action_status action)))]|None=>[]end|None=>[]end in
 let description:=match DocumentState.find_task task snapshot with
 |Some task=>match natural_field "side_parent" task with
  |Some parent=>"源自 task #"++show_natural parent++" · 独立运行。关闭不回传；仅手动追加已保存的新内容。生成中的回复可稍后追加。"
  |None=>"Side conversation"end|None=>"Side conversation unavailable"end in
 region parent "side/actions" "Side conversation actions"Roles.Toolbar
  (return_control++[declared parent Roles.Button(secondary "close" "关闭" Input.ClosePanel)])::
 information parent "side/parent" Information.Description description::
 Pages.conversation_page snapshot s(SideTask task)parent.
Definition layer_view snapshot s capacity layer :=
 let parent:=SessionNavigation.panel_key(State.layer_panel layer)in
 let behavior:=behavior s capacity layer in
 match State.layer_panel layer with
 |State.EditorPanel(Identity.Project project)=>Activities.activity_view snapshot s(Identity.Project project)
   (Activity.PropertyActivity UX.ProjectProperty)(State.layer_occurrence layer)(State.layer_source_expanded layer)parent behavior
 |State.PropertyPanel e request=>Activities.activity_view snapshot s e request(State.layer_occurrence layer)(State.layer_source_expanded layer)parent behavior
 |panel=>let content:=match panel with
  |State.EditorPanel e=>[Editors.editor_view snapshot s e parent]
  |State.SideConversationPanel task=>side_content snapshot s task parent
  |State.NavigationPanel GlobalMenu=>[Navigation.global_menu s parent]
  |State.NavigationPanel WorkOverview=>Navigation.work_overview snapshot s parent
  |State.NavigationPanel TasksDrawer=>[Navigation.task_navigation snapshot s true]
  |State.ObjectActionsPanel subject=>menu_nodes snapshot s subject(State.layer_occurrence layer)parent
  |State.InformationPanel kind=>information_panel snapshot s kind parent
  |State.BoardSettingsPanel=>board_settings snapshot s parent
  |State.BoardFiltersPanel=>board_filters snapshot s parent
  |State.ArchivedCardsPanel=>map(Collections.card_node snapshot s parent parent)(value_or[](Projection.archived_cards snapshot))
  |State.Confirmation command caption destination=>
   [title parent caption;region parent "actions" "Actions"Roles.DialogActions
    [declared parent Roles.DestructiveButton(Control "confirm" "Confirm"Destructive Input.Confirm
      (if State.layer_pending layer then Unavailable "This action is pending"else
       domain_availability(Selvedge.Interaction.Session.Authoring.command_availability snapshot s command)));
     declared parent Roles.Button(secondary "cancel" "Cancel" Input.ClosePanel)]]
  |_=>[]end in
  Node(part parent "layer") "layer" ""(match layer_presentation behavior with ModalDialog=>Roles.Dialog|AnchoredMenu=>Roles.Menu|TrailingDetails=>Roles.Details end)
   (LayerRegion behavior)content end.
