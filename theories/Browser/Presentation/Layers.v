From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Domain Commands Codec Images.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require Domain BoardFilter BoardParameters.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services ObjectActions.
From Selvedge.Interaction Require Import Attachments.
From Selvedge.Interaction Require CardDecisions ModelSelection.
From Selvedge.Interaction.Submission Require Draft Observation.
From Selvedge.Interaction.Experience Require Model Activity Observation ContextObservation.
From Selvedge.Browser.Session Require State Navigation.
Module SessionNavigation := Selvedge.Browser.Session.Navigation.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser.Presentation Require Import Projection Editors Navigation Collections Activities Pages.
From Selvedge.Browser.Presentation Require Roles Information Composition.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module G := Selvedge.Generated.Commands.
Definition status_availability status :=match status with
|ObjectActions.Available=>Available|ObjectActions.InFlight=>Busy "正在处理"|ObjectActions.Awaiting=>Unavailable "正在检查"
|ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>Unavailable reason end.
Definition action_nodes subject occurrence parent :=flat_map(fun action=>
 let key:=part parent(ObjectActions.action_key action)in
 let command:=Node key(ObjectActions.action_key action)(ObjectActions.action_label action)Roles.Button
  (Activate(Control(ObjectActions.action_key action)(ObjectActions.action_label action)
    (match ObjectActions.action_confirmation action with Some _=>Destructive|None=>Secondary end)
    (Input.MenuAction subject(ObjectActions.action_key action)occurrence)(status_availability(ObjectActions.action_status action))))[]in
 match ObjectActions.action_status action with
 |ObjectActions.AssessmentFailed reason=>[command;
   information parent("failure/"++ObjectActions.action_key action)Information.Description reason;
   declared parent Roles.Button(secondary("retry/"++ObjectActions.action_key action)"重试"(Input.RetryMenuAssessment subject(ObjectActions.action_key action)occurrence))]
 | _=>[command]end).
Definition card_decision_title decision := match decision with
 |CardDecisions.MoveCard=>"移动卡片"|CardDecisions.LinkCard=>"关联对话"end.
Definition card_decision_controls snapshot subject parent :=
 match subject with
 |CardActions card=>match Read.find_card card snapshot with
 |Some value=>if negb(Read.card_archived value) then
  let decision:=CardDecisions.MoveCard in
  let key:=State.card_decision_key decision in
  [declared parent Roles.Button(secondary key(card_decision_title decision)
    (Input.OpenCardDecision card decision(part parent key)))]
  else []
 |None=>[] end
 |_=>[]end.
Definition menu_nodes snapshot s subject occurrence parent :=
 List.app (card_decision_controls snapshot subject parent)
   (action_nodes subject occurrence parent (ObjectActions.menu_items snapshot s subject)).
Definition card_choice_nodes snapshot s card decision occurrence query parent :=
 let subject:=CardActions card in
 let search:=BoardFilter.lower_text(BoardFilter.trim query)in
 let matches selected:=BoardFilter.contains search(BoardFilter.lower_text
   (ObjectActions.choice_label selected++" "++ObjectActions.choice_key selected))in
 let search_control:=Node(part parent "search")"search"
    (match decision with CardDecisions.MoveCard=>"搜索状态或卡片"|CardDecisions.LinkCard=>"按名称或编号搜索对话"end) Roles.Field
    (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]in
 let empty:=information parent "empty-choices" Information.Description
  (match decision with CardDecisions.MoveCard=>"没有匹配的移动位置。"|CardDecisions.LinkCard=>"没有匹配的对话。"end) in
 search_control :: match CardDecisions.observe snapshot card,State.now s with
 |Some opportunity,Some now=>
  let matching:=filter matches(CardDecisions.choices decision opportunity)in
  let actions:=flat_map(fun selected=>ObjectActions.singleton(ObjectActions.choice_declaration snapshot opportunity now selected))(firstn 24 matching)in
  let summary:=if Nat.ltb 24 (List.length matching) then
    [information parent "search-hint" Information.Description "仅显示前 24 项。搜索可以缩小范围。"]
   else match matching with []=>[empty]|_=>[]end in
  List.app summary(action_nodes subject occurrence parent(map(ObjectActions.observe snapshot s subject)actions))
 |_,_=>[information parent "choices-unavailable" Information.Description "选项不可用。"]end.

Definition detail_action_input parent(action:ObjectActions.action):Input.input:=
 let trigger:=part parent(ObjectActions.action_key action)in
 match ObjectActions.action_operation action with
 |ObjectActions.NativeCommand command=>match ObjectActions.action_confirmation action with
  |Some(caption,destination)=>Input.Confirmation command caption destination trigger|None=>Input.Command command end
 |ObjectActions.Destination target=>Input.Navigate target
 |ObjectActions.Editor owner=>Input.OpenEditor owner trigger
 |ObjectActions.SideConversation task=>Input.BeginSide task trigger
 |ObjectActions.InspectCard card=>Input.OpenInformation(State.CardDetails card)trigger end.
Definition detail_action_nodes snapshot s subject parent:=List.app (card_decision_controls snapshot subject parent) (map(fun action=>
 declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)
  (match ObjectActions.action_confirmation action with Some _=>Destructive|None=>Secondary end)
  (detail_action_input parent action)(status_availability(ObjectActions.action_status action))))
 (ObjectActions.menu_items snapshot s subject)).
Definition committed_workspace_facts parent workspace:list(node Input.input) :=
 let primary:=Domain.workspace_primary workspace in
 let roots:=Domain.workspace_roots workspace in
 let selected path:=match primary with Some value=>String.eqb value path|None=>false end in
 match roots with
 |[]=>[information parent "working-directory" Information.Description "未设置工作目录"]
 |[path]=>[Pages.directory_details parent "working-directory" "工作目录" path]
 |_=>map(fun path=>Pages.directory_details parent ("directory/"++path)
   (if selected path then "主目录" else "附加目录") path)roots
 end.
Definition detail_group {A} parent key caption (facts:list(node A)) :=
 region parent key caption Roles.Section (group_title(part parent key)caption::facts).
Definition context_facts snapshot task parent:list(node Input.input) :=match Read.task_context task snapshot with
|None=>[read_only parent "unavailable" "工作环境" "无法读取已提交的工作环境"]
|Some context=>
 let workspace:=Read.context_workspace context in
 let project_facts:=List.app (match Read.context_project context with
 |None=>[information parent "project" Information.Description "未关联项目"]
 |Some id=>[read_only parent "project" "项目"
   (value_or ("项目 #"++show_natural id++" 不可用")(Read.context_project_name context))]end)
 (match Read.context_project context,Read.context_guidance_root context,Read.context_guidance_revision context with
 |Some _,Some root,Some revision=>List.app
   (if existsb (String.eqb root) (Domain.workspace_roots workspace) then []
    else [Pages.directory_details parent "project-directory" "指引目录" root])
   [read_only parent "guidance-revision" "指引版本" revision]
 |_,_,_=>[]end) in
 let guidance:=match Read.context_instructions context with
  |Some instructions=>if String.eqb instructions "" then [] else
   [Node(part parent "guidance")"project-guidance" "项目指引" Roles.Content ContentDisclosure
    [read_only (part parent "guidance") "instructions" "" instructions]]
  |None=>[]end in
 [detail_group parent "task-environment" "工作环境"
   (committed_workspace_facts parent workspace++project_facts++guidance);
  detail_group parent "task-permissions" "权限"
   [read_only parent "filesystem" "文件系统"(Read.context_filesystem context);
    read_only parent "network" "网络"(Read.context_network context);
    read_only parent "approval" "审批"(Read.context_approval context)]]end.
Definition task_execution_caption task :=match Read.task_status task with
 |"active"=>if Read.task_working task then "运行中"else"就绪"
 |"frozen"=>"已暂停"|"stopped"=>"已停止"|"archived"=>"已归档"
 |_=>Read.task_caption task end.
Definition task_details snapshot s id parent :=match Projection.task_details_observation snapshot id with
|Some(task,details)=>
 (context_facts snapshot id parent++[detail_group parent "task-execution" "运行信息"
 ([read_only parent "status" "状态"(task_execution_caption task);
   read_only parent "model" "模型"(Read.task_detail_model details++" · "++Read.task_detail_reasoning details)]++
  (match Read.task_work task with
  |None=>[]|Some work=>[read_only parent "work" "工作组"
    (match Read.find_work work snapshot with Some entry=>Read.work_name entry|None=>"工作组不可用"end)]end)++
 (match bind (Read.task_parent task) (fun source=>Read.find_task source snapshot) with
  |Some source=>[declared parent Roles.Button(secondary "lineage" ("打开来源对话 · "++Read.task_title source)
    (Input.Navigate(Conversation(Read.task_id source))))]|None=>[]end)++
 map(fun '(ordinal,contents)=>read_only parent(String.append "queued/"(show_natural(N.of_nat ordinal)))"排队中的消息" contents)
  (combine(seq 0(List.length(Read.task_detail_queued details)))(Read.task_detail_queued details))++
 Pages.worktree_details snapshot s id parent)])%list
|None=>[read_only parent "missing" "任务不可用" "这条对话已不存在"]end.
Definition card_details snapshot s id parent :=match Read.find_card id snapshot with
|None=>[information parent "missing" Information.Description "这张卡片已不存在。"]
|Some card=>
 let face:=Collections.card_face snapshot s card in
 ([read_only parent "identifier" "卡片编号"(Read.card_identifier card);read_only parent "title" "标题"(Model.card_title face);
  read_only parent "description" "描述"(Model.card_description face);read_only parent "stage" "状态"(Selvedge.Features.Domain.stage_label(Read.card_stage card));
  read_only parent "activity" "执行"(Model.card_status face);
  read_only parent "priority" "优先级"(Selvedge.Features.Domain.priority_label(Model.card_priority face));read_only parent "owner" "负责人"(Model.card_owner face);
  read_only parent "project" "项目"(Model.card_project face);read_only parent "labels" "标签"(String.concat "
"(Model.card_labels face));
  read_only parent "start-error" "启动错误"(Read.card_start_error card);
  read_only parent "enrichment" "生成"(Read.generation_caption(Read.card_generation card))]++
 map(fun file=>declared parent Roles.Button(secondary("preview/"++asset_id file)("Preview "++asset_name file)
   (Input.ServiceInput(Services.OpenPreview file(part parent("preview/"++asset_id file))))))(Read.card_attachments card)++
 (match bind(Read.card_task card)(fun task=>find_task task snapshot)with
  |Some entry=>[group_title (part parent "conversation") "关联对话";
    Navigation.task_entry_tree(State.location(State.navigation_state s))[] parent(TaskTree entry [])]
  |None=>Collections.card_conversation snapshot parent card "" end)++
 [region parent "card-detail-actions" "卡片操作" Roles.Toolbar
   (detail_action_nodes snapshot s(CardActions id)parent)])%list end.
Definition board_automation_description (automatic:bool) :=
 if automatic then "关闭后，正在运行的对话会继续。"
 else "启用后，符合条件的现有卡片会自动排队。".
Definition board_settings snapshot s parent :=match Read.board_configuration snapshot with
|None=>[read_only parent "missing" "Board settings" "Board observations unavailable"]
|Some board=>let automatic:=Read.board_automatic board in
 let profile:=Read.board_draft_profile board in
 let choices:=Observation.drafting_profile_choices snapshot in
 let selected:=if existsb(fun choice=>String.eqb profile(Fields.choice_value_of choice))choices then profile else "" in
 let busy:=existsb(fun pending=>String.eqb "board_settings"
   (text "op"(Schema.encode_command(State.accepted_command pending))))
   (State.awaiting(State.authoring_state s)) in
 let toggle:=option_map Input.Command(decode_command Selvedge.Kernel.Commands.command_specs
  (G.encode(G.Cmd_board_settings(G.Build_board_settings(negb automatic)profile))))in
 ((match toggle with None=>[]|Some input=>
 [region parent "board-automation" "" Roles.Section
   [region parent "automation-copy" "" Roles.Content
     [information parent "automation-label" Information.FieldLabel "自动执行";
      information parent "automation-effect" Information.Description (board_automation_description automatic)];
    Node(part parent "automation")"automation" "自动执行"Roles.Button
     (Choice ToggleChoice automatic ""
       (Control "automation" "自动执行" Secondary input
         (if busy then Busy "正在更新设置" else
          domain_availability(Selvedge.Browser.Session.Authoring.input_availability snapshot s input))))[]]]end)++
 [Node(part parent "drafting-model")"drafting-model" "默认整理模型"Roles.Field
  (BoardProfile automatic selected choices
    (Services.connected(State.service_state s))busy(fun value=>option_map Input.BoardProfile(as_string value)))[];
  information parent "drafting-model-purpose" Information.Description "用于整理卡片的标题和描述。";
  declared parent Roles.Button(secondary "edit-board-title-prompt" "编辑卡片提示词"
    (Input.OpenEditor (TitlePrompts BoardTitles) (part parent "edit-board-title-prompt")))])%list end.
Definition filter_choices snapshot category :=match category with
|BoardFilter.Status=>map(fun stage=>(Selvedge.Features.Domain.stage_name stage,Selvedge.Features.Domain.stage_label stage))Selvedge.Features.Domain.stages
|BoardFilter.Priority=>map(fun level=>(Selvedge.Features.Domain.priority_name level,Selvedge.Features.Domain.priority_label level))Selvedge.Features.Domain.priorities
|BoardFilter.Date=>[("1","最近 24 小时");("7","最近 7 天");("30","最近 30 天")]
|BoardFilter.Assignee=>[]
|BoardFilter.Creator=>[("self","我")]
|BoardFilter.Project=>("","未分配项目")::map(fun project=>(show_natural(project_id project),project_name project))(value_or[](Read.projects snapshot))
|BoardFilter.Label=>map(fun value=>(value,value))(nodup string_dec(flat_map Read.card_labels(value_or[](Read.board_cards snapshot))))end.
Definition filter_title category :=match category with
|BoardFilter.Status=>"状态"|BoardFilter.Priority=>"优先级"|BoardFilter.Date=>"更新时间"
|BoardFilter.Assignee=>"负责人"|BoardFilter.Creator=>"创建人"|BoardFilter.Project=>"项目"|BoardFilter.Label=>"标签"end.
Definition filter_option parent category selected '(value,label) :=
 let name:=BoardFilter.category_name category in
 let identity:="filter/"++name++"/"++value in
 Node(part parent identity)"filter-option"label Roles.Button
  (Choice MultipleChoice(existsb(String.eqb value)selected)""
    (secondary identity label(Input.BoardToggle name value)))[].
Definition assignee_filter snapshot selection occurrence query parent :=
 let category:=BoardFilter.Assignee in
 let selected:=BoardFilter.filter_values selection category in
 let search:=BoardFilter.lower_text(BoardFilter.trim query)in
 let key:=part parent "filter/assignee" in
 let matching '(value,label):=existsb(String.eqb value)selected||
    BoardFilter.contains search(BoardFilter.lower_text(label++" "++value)) in
 let group name heading values:=match filter matching values with
 |[]=>[]
 |choices=>[region key name heading Roles.Section
   (group_title (part key name) heading::map(filter_option parent category selected)choices)]
 end in
 let profiles:=ModelSelection.selectable_profiles(Selvedge.Interaction.Submission.Observation.catalog snapshot)in
 let models:=map(fun profile=>(Selvedge.Features.Domain.owner_name
    (Selvedge.Features.Domain.ProfileOwner(Selvedge.Kernel.Domain.profile_key profile)),
    ContextObservation.localized_profile_label profiles profile))profiles in
 let choices:=(group "filter-assignee-people" "人员" [("self","我")] ++
   (if matching (Selvedge.Features.Domain.owner_name Selvedge.Features.Domain.Unassigned,"未分配")
    then [filter_option parent category selected
      (Selvedge.Features.Domain.owner_name Selvedge.Features.Domain.Unassigned,"未分配")]
    else []) ++ group "filter-assignee-models" "模型" models)%list in
 let caption:=filter_title category++match selected with
   |[]=>""|_=>" · "++show_natural(N.of_nat(List.length selected))end in
 Node key "filter/assignee" caption Roles.Section ContentDisclosure
  [Node(part key "search")"search" "搜索负责人"Roles.Field
    (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[];
   region key "filter-assignee-options" "负责人选项" Roles.Section
    (match choices with
    |[]=>[information key "empty" Information.Status "没有匹配的负责人。"]
    |_=>choices end)].
Definition board_filters snapshot s occurrence query parent :=
 let selection:=State.board_selection s in
 flat_map(fun category=>match category with
 |BoardFilter.Assignee=>[assignee_filter snapshot selection occurrence query parent]
 |_=>match filter_choices snapshot category with
  |[]=>[]
  |choices=>let key:=part parent("filter/"++BoardFilter.category_name category)in
   [Node key "board-filter-group" (filter_title category)Roles.Section Region
     [group_title key(filter_title category);
      region key "filter-choices" "" Roles.Content
       (map(filter_option parent category(BoardFilter.filter_values selection category))choices)]]
  end end)BoardFilter.categories.
Definition panel_kind capacity panel :=match panel with
|State.PropertyPanel _ _|State.ObjectActionsPanel _|State.InformationPanel(State.PropertySource _ _)
|State.NavigationPanel GlobalMenu|State.NavigationPanel WorkOverview=>AnchoredMenu
|State.ArchivedCardsPanel=>if navigation_beside_content capacity then AnchoredDialog else ModalDialog
|State.InformationPanel(State.TaskDetails _)|State.SideConversationPanel _=>if details_beside_timeline capacity then TrailingDetails else ModalDialog
|_=>ModalDialog end.
Definition source_origin_matches e request panel:=match panel with
|State.PropertyPanel actual requested=>same_editor e actual&&String.eqb(SessionNavigation.request_key request)(SessionNavigation.request_key requested)
|State.EditorPanel actual=>same_editor e actual
|_=>false end.
Definition context_submenu panel origin:=match panel with
 |State.PropertyPanel e request=>
  (Activities.workspace_request request||Activities.project_request request)&&
  run_environment_panel e origin
 |_=>false end.
Fixpoint visible_layers(layers:list State.layer):list State.layer:=match layers with
|[]=>[]
|layer::rest=>let shown:=visible_layers rest in
 match State.layer_panel layer,rest,shown with
 |State.InformationPanel(State.PropertySource e request),origin::_,_::others=>
  layer::if source_origin_matches e request(State.layer_panel origin)then others else shown
 |panel,origin::_,_::others=>
  layer::if context_submenu panel(State.layer_panel origin)then others else shown
 |_,_,_=>layer::shown end end.
Fixpoint layers_after occurrence(layers:list State.layer):list State.layer:=match layers with
|[]=>[]|layer::rest=>if N.eqb occurrence(State.layer_occurrence layer)then rest else layers_after occurrence rest end.
Definition anchor s layer:=match State.layer_panel layer,layers_after(State.layer_occurrence layer)(State.layers(State.navigation_state s))with
|State.InformationPanel(State.PropertySource e request),origin::_=>
 if source_origin_matches e request(State.layer_panel origin)then State.layer_trigger origin else State.layer_trigger layer
|panel,origin::_=>
 if context_submenu panel(State.layer_panel origin)then State.layer_trigger origin else State.layer_trigger layer
|_,_=>State.layer_trigger layer end.
Definition behavior s capacity layer :=
 let panel:=State.layer_panel layer in
 let composer_menu:=match panel with
  |State.PropertyPanel _ request=>is_run_environment_request request ||
    match layers_after(State.layer_occurrence layer)(State.layers(State.navigation_state s))with
    |origin::_=>context_submenu panel(State.layer_panel origin)|[]=>false end
  |_=>false end in
 let kind:=if composer_menu then ComposerMenu else panel_kind capacity panel in
 let beside:=match kind with TrailingDetails=>details_beside_timeline capacity|_=>false end in
 let dismissal:=match State.layer_panel layer with
  |State.InformationPanel(State.TaskDetails _)|State.SideConversationPanel _=>false
  |_=>negb beside end in
 LayerBehavior kind beside(State.layer_occurrence layer)(State.layer_initial_attention layer)
  (State.layer_trigger layer)"/main"(anchor s layer) Input.ClosePanel dismissal dismissal.
Definition information_panel snapshot (s:State.state) kind parent :=match kind with
|State.TaskDetails task=>task_details snapshot s task parent
|State.TaskContext task=>context_facts snapshot task parent
|State.CardDetails card=>card_details snapshot s card parent
|State.PropertySource e request=>
 let label (project other:string):=match e with Identity.Project _=>project|_=>other end in
 match Observation.property_for_request snapshot s e request with
 |None=>[read_only parent "unavailable" (label "来源" "Source")
   (label "未能读取当前项目设置。" "The original settings observation is unavailable")]
 |Some property=>
  [Activities.navigation_header parent (Activities.configuration_source_label e) (label "返回" "Back") Input.ClosePanel;
   read_only parent "owner" (label "设置" "Settings")(label "项目"(UX.property_label property));
   read_only parent "configuration-source" (label "来源" "Source")
    (Observation.property_source_description snapshot s property)]end end.
Definition side_content snapshot s task parent :=
 let return_control:=match ObjectActions.return_action snapshot s task with
 |Some action=>match ObjectActions.command action with
  |Some command=>[declared parent Roles.Button(Control "return"(ObjectActions.action_label action)Secondary
    (Input.Command command)(status_availability(ObjectActions.action_status action)))]|None=>[]end|None=>[]end in
 let heading:=match Read.find_task task snapshot with
 |Some entry=>Read.task_title entry|None=>"Side conversation unavailable"end in
 let source:=match bind(Read.task_side_parent snapshot task)(fun source=>Read.find_task source snapshot)with
 |Some entry=>[information parent "side/parent" Information.Description ("Branched from "++Read.task_title entry)]
 |None=>[]end in
 [dialog_header parent
   [region parent "side/heading" "" Roles.Toolbar
    [title parent heading;declared parent Roles.Button(secondary "close" "关闭" Input.ClosePanel)]];
  dialog_body parent
   (source++[region parent "side/actions" "Side conversation actions" Roles.Toolbar
     ((match Read.find_task task snapshot with
       |Some entry=>Pages.task_run_controls snapshot s entry parent|None=>[]end)++
      [Pages.task_details_control s task parent;Collections.more parent(TaskActions task)]++return_control)]++
    Pages.conversation_page snapshot s(SideTask task)parent)].
Definition panel_title panel := match panel with
 |State.EditorPanel owner=>Editors.editor_title owner
 |State.SideConversationPanel _=>"Side conversation"
 |State.NavigationPanel GlobalMenu=>"Global navigation"
 |State.NavigationPanel WorkOverview=>Navigation.conversation_scope_label|State.NavigationPanel TasksDrawer=>"Task tree"
 |State.ObjectActionsPanel subject=>ObjectActions.menu_label subject
 |State.CardDecisionPanel _ decision=>card_decision_title decision
 |State.InformationPanel(State.TaskDetails _)=>Pages.task_details_label
 |State.InformationPanel(State.TaskContext _)=>"执行环境"
 |State.InformationPanel(State.CardDetails _)=>"卡片详情"
 |State.InformationPanel(State.PropertySource e _)=>Activities.configuration_source_label e
 |State.BoardSettingsPanel=>"看板设置"|State.BoardFiltersPanel=>"筛选卡片"
 |State.ArchivedCardsPanel=>"归档卡片"|State.Confirmation _ caption _=>caption
 |State.PropertyPanel _ _=>"Settings"end.
Definition dismissible_heading parent caption : node Input.input :=
 dialog_header parent [title parent caption;
  declared parent Roles.Button(secondary "close" "Close panel" Input.ClosePanel)].
Definition layer_view_with_side render_side snapshot s capacity compact_model_picker layer :=
 let parent:=SessionNavigation.panel_key(State.layer_panel layer)in
 let behavior:=behavior s capacity layer in
 match State.layer_panel layer with
 |State.EditorPanel(Identity.Project project)=>Activities.activity_view snapshot s(Identity.Project project)
   (Activity.PropertyActivity UX.ProjectProperty)(State.layer_occurrence layer)(State.layer_source_expanded layer)parent behavior compact_model_picker
 |State.PropertyPanel e request=>Activities.activity_view snapshot s e request(State.layer_occurrence layer)(State.layer_source_expanded layer)parent behavior compact_model_picker
 |panel=>let content:=match panel with
  |State.EditorPanel e=>Editors.editor_view snapshot s e parent
  |State.SideConversationPanel task=>render_side snapshot s task parent
  |State.NavigationPanel GlobalMenu=>Navigation.global_menu s parent
  |State.NavigationPanel WorkOverview=>Navigation.work_overview snapshot s parent
  |State.NavigationPanel TasksDrawer=>
    [dialog_header parent [title parent "Tasks"];
     dialog_body parent [Navigation.task_navigation snapshot s]]
  |State.ObjectActionsPanel subject=>menu_nodes snapshot s subject(State.layer_occurrence layer)parent
  |State.CardDecisionPanel card decision=>card_choice_nodes snapshot s card decision(State.layer_occurrence layer)(State.layer_query layer)parent
  |State.InformationPanel kind=>information_panel snapshot s kind parent
  |State.BoardSettingsPanel=>board_settings snapshot s parent
  |State.BoardFiltersPanel=>board_filters snapshot s(State.layer_occurrence layer)(State.layer_query layer)parent
  |State.ArchivedCardsPanel=>
   let candidates:=value_or[](Read.board_cards snapshot)in
   match filter Read.card_archived candidates with
   |[]=>[information parent "empty" Information.Description "没有归档的卡片。"]
   |archived=>map(Collections.card_node snapshot s parent candidates parent)archived end
  |State.Confirmation command caption destination=>
   ([dialog_header parent [title parent caption]] ++
    (match State.layer_feedback layer with
     |None=>[]|Some reason=>[dialog_body parent
       [Node(part parent "feedback")"confirmation-feedback" "Action failed"Roles.Alert(ReadOnly(Codec.diagnostic_message reason))[]]]end) ++
    [dialog_actions parent
    [declared parent Roles.Button(secondary "cancel" "Cancel" Input.ClosePanel);
     declared parent Roles.DestructiveButton(Control "confirm" "Confirm"Destructive Input.Confirm
      (if State.layer_pending layer then Busy "This action is pending"else
       domain_availability(Selvedge.Browser.Session.Authoring.confirmation_availability snapshot s command)))]])%list
  |_=>[]end in
  let content:=match State.layer_panel layer with
  |State.EditorPanel _|State.SideConversationPanel _|State.NavigationPanel _
  |State.Confirmation _ _ _=>content
  |State.ObjectActionsPanel _|State.CardDecisionPanel _ _=>
    let feedback:=match State.layer_feedback layer with
      |None=>[]|Some reason=>[Node(part parent "feedback")"menu-feedback" "Action failed" Roles.Alert
        (ReadOnly(Codec.diagnostic_message reason))[]]end in
    match panel with
    |State.CardDecisionPanel _ _=>[dismissible_heading parent (panel_title panel);dialog_body parent (List.app feedback content)]
    |_=>List.app content feedback end
  |State.InformationPanel(State.TaskDetails _)=>
    [dialog_header parent [title parent Pages.task_details_label;
      declared parent Roles.Button(secondary "close" "关闭任务详情" Input.ClosePanel)]; dialog_body parent content]
  |State.BoardFiltersPanel=>
    [dialog_header parent [title parent (panel_title panel);
      declared parent Roles.Button(secondary "filters/clear" "清除筛选" Input.BoardClear);
      declared parent Roles.Button(secondary "close" "Close panel" Input.ClosePanel)];
     dialog_body parent content]
  |State.InformationPanel(State.TaskContext _)
  |State.InformationPanel(State.CardDetails _)|State.BoardSettingsPanel
  |State.ArchivedCardsPanel=>[dismissible_heading parent (panel_title panel);dialog_body parent content]
  |_=>if Model.modal_layer behavior then [dialog_body parent content] else content end in
  let semantic:=match panel with
    |State.SideConversationPanel _=>"side-conversation"
    |State.EditorPanel (Identity.TitlePrompts _)=>"settings-title-editor"
    |State.EditorPanel(Identity.WorkName _)=>"work-name-editor"
    |State.NavigationPanel GlobalMenu=>"global-navigation-menu"
    |State.NavigationPanel WorkOverview=>"work-overview"
    |State.EditorPanel _=>"object-editor"
    |State.ObjectActionsPanel _=>"object-actions"
    |State.CardDecisionPanel _ _=>"card-decision"
    |State.InformationPanel(State.PropertySource _ _)=>"property-source"
    |State.InformationPanel(State.TaskDetails _)=>"task-details"
    |State.InformationPanel(State.TaskContext _)=>"task-context"
    |State.InformationPanel(State.CardDetails _)=>"card-details"
    |State.BoardSettingsPanel=>"board-settings"
    |State.BoardFiltersPanel=>"board-filters"
    |State.ArchivedCardsPanel=>"archived-cards"
    |State.Confirmation _ _ _=>"confirmation"
    |_=>"layer"end in
  Node(part parent "layer") semantic (panel_title panel)(match layer_presentation behavior with ModalDialog|AnchoredDialog=>Roles.Dialog|AnchoredMenu|ComposerMenu=>Roles.Menu|TrailingDetails=>Roles.Details end)
   (match State.layer_panel layer with State.NavigationPanel panel=>NavigationRegion panel behavior|_=>LayerRegion behavior end)content end.

Definition layer_view := layer_view_with_side side_content.
(* A covered side conversation keeps its focus scope without deriving its history. *)
Definition layer_scope_view := layer_view_with_side(fun _ _ _ _=>[]).
