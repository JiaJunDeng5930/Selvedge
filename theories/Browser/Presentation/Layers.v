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
From Selvedge.Interaction Require CardDecisions ObjectDecisions.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Browser.Session Require State Observation Navigation.
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
Module SessionObserve := Selvedge.Browser.Session.Observation.
Definition status_availability status :=match status with
|ObjectActions.Available=>Available|ObjectActions.InFlight=>Busy "This action is pending"|ObjectActions.Awaiting=>Unavailable "Checking action availability"
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
   declared parent Roles.Button(secondary("retry/"++ObjectActions.action_key action)"Retry"(Input.RetryMenuAssessment subject(ObjectActions.action_key action)occurrence))]
 | _=>[command]end).
Definition card_decision_title decision := match decision with
 |CardDecisions.MoveCard=>"移动卡片"|CardDecisions.LinkCard=>"关联对话"end.
Definition card_decision_controls snapshot subject parent :=
 match subject with
 |CardActions card=>if ObjectDecisions.subject_exists snapshot subject then
  let decision:=CardDecisions.MoveCard in
  let key:=State.card_decision_key decision in
  [declared parent Roles.Button(secondary key(card_decision_title decision)
    (Input.OpenCardDecision card decision(part parent key)))]
  else []
 |_=>[]end.
Definition menu_nodes snapshot s subject occurrence parent :=
 title parent "Actions" :: List.app (card_decision_controls snapshot subject parent)
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
  let actions:=flat_map(fun selected=>ObjectActions.singleton(ObjectActions.choice_declaration opportunity now selected))(firstn 24 matching)in
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
 (ObjectActions.items snapshot s subject)).
Definition committed_workspace_facts {A} parent workspace:list(node A) :=
 let primary:=Domain.workspace_primary workspace in
 let roots:=Domain.workspace_roots workspace in
 let selected path:=match primary with Some value=>String.eqb value path|None=>false end in
 match roots with
 |[]=>[read_only parent "working-directory" "Working directory" "No working directory"]
 |[path]=>[read_only parent "working-directory" "Working directory" path]
 |_=>map(fun path=>let key:=part parent("directory/"++path)in
   Node key("directory/"++path)path Roles.Content(DirectoryRow path(selected path))
    [read_only key "path" "" path;
     read_only key "primary" ""(if selected path then "Primary working directory" else "Additional directory")])roots
 end.
Definition context_facts {A} snapshot task parent:list(node A) :=match Read.task_context task snapshot with
|None=>[read_only parent "unavailable" "Execution context" "The committed context is unavailable"]
|Some context=>
 let workspace:=Read.context_workspace context in
 let project_facts:=List.app (match Read.context_project context with
 |None=>[read_only parent "project" "Project" "Projectless task"]
 |Some id=>[read_only parent "project" "Project"
   (value_or ("Project unavailable (ID "++show_natural id++")")(Read.context_project_name context))]end)
 (match Read.context_project context,Read.context_guidance_root context,Read.context_guidance_revision context with
 |Some _,Some root,Some revision=>List.app
   (if existsb (String.eqb root) (Domain.workspace_roots workspace) then []
    else [read_only parent "project-directory" "Guidance directory" root])
   [read_only parent "guidance-revision" "Guidance revision" revision]
 |_,_,_=>[]end) in
 let guidance:=match Read.context_instructions context with
  |None=>"No project guidance"|Some instructions=>
   if String.eqb instructions ""then "No project instructions"else instructions end in
 List.app project_facts (List.app (committed_workspace_facts parent workspace)
  [read_only parent "filesystem" "Filesystem access"(Read.context_filesystem context);
   read_only parent "network" "Network access"(Read.context_network context);
   read_only parent "approval" "Approval policy"(Read.context_approval context);
   read_only parent "guidance" "Project guidance" guidance])end.
Definition task_details snapshot s id parent :=match Projection.task_details_observation snapshot id with
|Some(task,details)=>
 (context_facts snapshot id parent++
  (match Read.task_work task with
  |None=>[]|Some work=>[read_only parent "work" "Work"
    (match Read.find_work work snapshot with Some entry=>Read.work_name entry|None=>"Work unavailable"end)]end)++
 [read_only parent "model" "Model"(Read.task_detail_model details++" · "++Read.task_detail_reasoning details);
  read_only parent "status" "Status"(Read.task_caption task)] ++
 (match bind (Read.task_parent task) (fun source=>Read.find_task source snapshot) with
  |Some source=>[declared parent Roles.Button(secondary "lineage" ("Open parent: "++Read.task_title source)
    (Input.Navigate(Conversation(Read.task_id source))))]|None=>[]end)++
 map(fun '(ordinal,contents)=>read_only parent(String.append "queued/"(show_natural(N.of_nat ordinal)))"Queued message" contents)
  (combine(seq 0(List.length(Read.task_detail_queued details)))(Read.task_detail_queued details))++
 Pages.worktree_details snapshot s id parent)%list
|None=>[read_only parent "missing" "Task unavailable" "The task no longer exists"]end.
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
  |None=>Collections.card_conversation snapshot parent card end)++
 [region parent "card-detail-actions" "卡片操作" Roles.Toolbar
   (detail_action_nodes snapshot s(CardActions id)parent)])%list end.
Definition board_settings snapshot s parent :=match Read.board_configuration snapshot with
|None=>[read_only parent "missing" "Board settings" "Board observations unavailable"]
|Some board=>let automatic:=Read.board_automatic board in
 let profile:=Read.board_draft_profile board in
 let busy:=existsb(fun pending=>String.eqb "board_settings"
   (text "op"(Schema.encode_command(State.accepted_command pending))))
   (State.awaiting(State.authoring_state s)) in
 let toggle:=option_map Input.Command(decode_command Selvedge.Kernel.Commands.command_specs
  (G.encode(G.Cmd_board_settings(G.Build_board_settings(negb automatic)profile))))in
 ((match toggle with None=>[]|Some input=>[declared parent Roles.Button(observe_control(fun input=>domain_availability(Selvedge.Browser.Session.Authoring.input_availability snapshot s input))(secondary "automation"(if automatic then"关闭自动执行"else"启用自动执行")input))]end)++
 [Node(part parent "drafting-model")"drafting-model" "草稿模型"Roles.Field
  (BoardProfile automatic profile(map(fun value=>Fields.ChoiceValue(Domain.profile_key value)(Observation.profile_label value))(Observation.selectable_profiles(SessionObserve.catalog snapshot)))
    (Services.connected(State.service_state s))busy(fun value=>option_map Input.BoardProfile(as_string value)))[]])%list end.
Definition filter_choices snapshot category :=match category with
|BoardFilter.Status=>map(fun stage=>(Selvedge.Features.Domain.stage_name stage,Selvedge.Features.Domain.stage_label stage))Selvedge.Features.Domain.stages
|BoardFilter.Priority=>map(fun level=>(Selvedge.Features.Domain.priority_name level,Selvedge.Features.Domain.priority_label level))Selvedge.Features.Domain.priorities
|BoardFilter.Date=>[("1","最近 24 小时");("7","最近 7 天");("30","最近 30 天")]
|BoardFilter.Assignee=>("self","我")::(Selvedge.Features.Domain.owner_name Selvedge.Features.Domain.Unassigned,"未分配")::
 map(fun profile=>(Selvedge.Features.Domain.owner_name(Selvedge.Features.Domain.ProfileOwner(Selvedge.Kernel.Domain.profile_key profile)),Observation.profile_label profile))(Observation.selectable_profiles(SessionObserve.catalog snapshot))
|BoardFilter.Creator=>[("self","我")]
|BoardFilter.Project=>("","未分配项目")::map(fun project=>(show_natural(project_id project),project_name project))(value_or[](Read.projects snapshot))
|BoardFilter.Label=>map(fun value=>(value,value))(nodup string_dec(flat_map Read.card_labels(value_or[](Read.board_cards snapshot))))end.
Definition filter_title category :=match category with
|BoardFilter.Status=>"状态"|BoardFilter.Priority=>"优先级"|BoardFilter.Date=>"更新时间"
|BoardFilter.Assignee=>"负责人"|BoardFilter.Creator=>"创建人"|BoardFilter.Project=>"项目"|BoardFilter.Label=>"标签"end.
Definition board_filters snapshot s parent :=
 declared parent Roles.Button(secondary "filters/clear" "清除筛选" Input.BoardClear)::map(fun category=>let name:=BoardFilter.category_name category in
 region parent("filter/"++name)(filter_title category)Roles.Section
  (group_title(part parent("filter/"++name))(filter_title category)::map(fun '(value,label)=>
   Node(part parent("filter/"++name++"/"++value))"filter-option"label Roles.Button
    (Choice MultipleChoice(existsb(String.eqb value)(BoardFilter.filter_values(State.board_selection s)category))""
     (secondary("filter/"++name++"/"++value)label(Input.BoardToggle name value)))[])(filter_choices snapshot category)))BoardFilter.categories.
Definition panel_kind capacity panel :=match panel with
|State.PropertyPanel _ _|State.ObjectActionsPanel _|State.InformationPanel(State.PropertySource _ _)
|State.NavigationPanel GlobalMenu=>AnchoredMenu
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
 let dismissal:=match State.layer_panel layer with
  |State.InformationPanel(State.TaskDetails _)|State.SideConversationPanel _=>false
  |_=>negb beside end in
 LayerBehavior kind beside(State.layer_occurrence layer)(State.layer_initial_attention layer)
  (State.layer_trigger layer)"/main"(anchor s layer) Input.ClosePanel dismissal dismissal.
Definition information_panel snapshot (s:State.state) kind parent :=match kind with
|State.TaskDetails task=>task_details snapshot s task parent
|State.TaskContext task=>context_facts snapshot task parent
|State.CardDetails card=>card_details snapshot s card parent
|State.PropertySource e request=>match Observation.property_for_request snapshot s e request with
 |None=>[read_only parent "unavailable" "Source" "The original settings observation is unavailable"]
 |Some property=>
  [Activities.navigation_header parent "Configuration source" Input.ClosePanel;
   read_only parent "owner" "Settings"(UX.property_label property);
   read_only parent "configuration-source" "Source"(Observation.property_source_description snapshot s property)]end end.
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
 |State.ObjectActionsPanel _=>"Actions"
 |State.CardDecisionPanel _ decision=>card_decision_title decision
 |State.InformationPanel(State.TaskDetails _)=>"Task details"
 |State.InformationPanel(State.TaskContext _)=>"Execution context"
 |State.InformationPanel(State.CardDetails _)=>"卡片详情"
 |State.InformationPanel(State.PropertySource _ _)=>"Configuration source"
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
  |State.BoardFiltersPanel=>board_filters snapshot s parent
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
    [dismissible_heading parent (panel_title panel); dialog_body parent content]
  |State.InformationPanel(State.TaskContext _)
  |State.InformationPanel(State.CardDetails _)|State.BoardSettingsPanel|State.BoardFiltersPanel
  |State.ArchivedCardsPanel=>[dismissible_heading parent (panel_title panel);dialog_body parent content]
  |_=>if Model.modal_layer behavior then [dialog_body parent content] else content end in
  let semantic:=match panel with
    |State.SideConversationPanel _=>"side-conversation"
    |State.EditorPanel Identity.TitlePrompts=>"settings-title-editor"
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
  Node(part parent "layer") semantic (panel_title panel)(match layer_presentation behavior with ModalDialog=>Roles.Dialog|AnchoredMenu=>Roles.Menu|TrailingDetails=>Roles.Details end)
   (match State.layer_panel layer with State.NavigationPanel panel=>NavigationRegion panel behavior|_=>LayerRegion behavior end)content end.

Definition layer_view := layer_view_with_side side_content.
(* A covered side conversation keeps its focus scope without deriving its history. *)
Definition layer_scope_view := layer_view_with_side(fun _ _ _ _=>[]).
