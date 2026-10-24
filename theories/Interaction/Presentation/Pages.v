From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Commands Domain.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction Require Import Codec Identity Input Context AuditReading Documents ObjectActions.
From Selvedge.Interaction.Experience Require Model Observation.
From Selvedge.Interaction.Session Require Draft State Observation Navigation.
Module SessionNavigation := Selvedge.Interaction.Session.Navigation.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Projection Editors Navigation Collections.
From Selvedge.Interaction.Presentation Require Roles Information Composition.
Import ListNotations.
Open Scope string_scope.
Module Observe := Selvedge.Interaction.Experience.Observation.
Module SessionObserve := Selvedge.Interaction.Session.Observation.
Module UX := Selvedge.Interaction.Experience.Model.
Module G := Selvedge.Generated.Commands.
Definition missing {A} parent message:list(node A) :=[page_region parent Composition.UnavailableMessage Composition.BodyPosition
 [read_only parent "unavailable-message" "Unavailable"message]].
Definition creation_heading snapshot s e :=match SessionObserve.draft_preview snapshot(State.current_draft s e)with
|Context.ProspectiveContext _ (Some project) _ _ _ _=>match find_project project snapshot with
 |Some project=>"Work on "++project_name project|None=>"What would you like to build?"end
|_=>"What would you like to build?"end.
Definition creation_page snapshot s parent :=
 let e:=NewTask(State.active_work(State.navigation_state s))in
 let properties:=filter(fun property=>match UX.property_kind_of property with
  |UX.ProjectProperty|UX.WorkspaceProperty=>true|_=>false end)(Observe.observe_properties snapshot s e)in
 [page_region parent Composition.CreationIntroduction Composition.BodyPosition
   [information parent "creation/title" Information.IntroductionTitle(creation_heading snapshot s e)];
  page_region parent Composition.ComposerInput Composition.BodyPosition
   ((match properties with []=>[]|_=>[Node(part parent(part "region" "creation-context"))
     "creation-context" "Task context" Roles.Toolbar
     (PageRegion Composition.CreationContext Composition.BodyPosition)
     (Editors.property_controls snapshot s e parent properties)]end)++
    match Editors.composer_view snapshot s e(editor_key e)with Some composer=>[composer]|None=>[]end)%list].
Definition approval_availability value:=match ObjectActions.action_status value with
|ObjectActions.Available=>Available|ObjectActions.Awaiting=>Unavailable "Checking action availability"
|ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>Unavailable reason end.
Definition approval_argument_label name := match name with
| "command" => "Command" | "justification" => "Reason" | other => other end.
Definition approval_arguments {A} parent operation:list(node A):=match bind(field "call" operation)(field "arguments")with
|Some(JObject arguments)=>map(fun '(name,value)=>read_only parent("argument/"++name)(approval_argument_label name)
 (match value with JString value=>value|_=>TextJson.render_json value end))arguments
|Some value=>[read_only parent "arguments" "Arguments"(TextJson.render_json value)]|None=>[]end.
Definition approval_node snapshot s task parent operation :=
 match natural_field "operation_id" operation with
 |None=>read_only parent "approval-unavailable" "Approval unavailable" "Operation identity unavailable"
 |Some id=>let key:=part parent("approval/"++show_natural id)in
 let human:=flag "awaitingHuman" operation in
 Node key "approval"(if human then"Approval required"else"Automatic review")Roles.Approval Region
  ([group_title key(text "tool" operation)]++
   (match bind(field "context" operation)(fun settings=>bind(field "workspace" settings)(string_field "primary_root"))with
    |Some directory=>[read_only key "directory" "Default working directory" directory]|None=>[]end)++
   approval_arguments key operation++
   if human then flat_map(fun allow=>match ObjectActions.approval_action snapshot s task id allow with
    |Some action=>match ObjectActions.command action with
     |Some command=>[declared key(if allow then Roles.PrimaryButton else Roles.Button)
       (Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]
     |None=>[]end|None=>[]end)[true;false]
   else[read_only key "reviewer" "Reviewer model"(match bind(field "reviewer" operation)(field "profile")with
     |Some reviewer=>match Selvedge.Kernel.Codec.parse_profile reviewer with Some reviewer=>Observe.profile_label reviewer|None=>"Reviewer observation unavailable"end
     |None=>"Reviewer observation unavailable"end)])%list end.
Definition approvals snapshot s task parent value :=
 let operations:=filter(fun operation=>String.eqb(text "stage" operation)"approval_pending")(Selvedge.Interaction.Codec.items "operations" value)in
 match operations with []=>[]|_=>[page_region parent Composition.ApprovalDecisions Composition.DockPosition
  [region parent "approval-queue" "Approvals"Roles.ApprovalQueue(map(approval_node snapshot s task parent)operations)]]end.
Definition reader_disclosures task s :=State.disclosures(SessionNavigation.reader_for s task).
Definition reading_actions := AuditReading.ReadingActions Input.SetDisclosure Input.Interactive Input.RetainedOutput.
Definition operation_cancel_control snapshot s task parent operation :=
 match natural_field "operation_id" operation with
 |None=>[]|Some id=>match ObjectActions.cancellation_action snapshot s task id with
  |Some action=>match ObjectActions.command action with
   |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary
     (Input.Command command)(approval_availability action))]|None=>[]end
  |None=>[]end end.
Definition operation_node snapshot s task parent operation :=
 match natural_field "operation_id" operation with
 |None=>[]|Some id=>let key:=part parent("operation/"++show_natural id)in
  [region key "operation"("Operation #"++show_natural id)Roles.Activity
    ([read_only key "call" "Tool call"(text "tool" operation++" · "++text "call_id" operation);
      read_only key "state" "State"(text "stage" operation);
      read_only key "status" "Status"(text "status" operation)]++
     approval_arguments key operation++operation_cancel_control snapshot s task key operation)]end.
Definition operation_controls snapshot s task parent observation :=
 match flat_map(operation_node snapshot s task parent)(Codec.items "operations" observation)with
 |[]=>[]|operations=>[region parent "active-operations" "Active operations"Roles.Activity operations]end.
Definition worktree_status name:=value_or ""
 (option_map snd(find(fun entry=>String.eqb name(fst entry))
 [("creating","Creating workspace…");("creating_archived","Creating workspace before archiving…");
  ("ready","Workspace ready");("create_failed","Workspace creation failed");("archiving","Archiving workspace…");
  ("archived","Workspace archived");("archive_failed","Workspace archive failed")])).
Definition worktree_observation snapshot task:=DocumentState.find_world "worktrees" "task_id" task snapshot.
Definition worktree_feedback {A} snapshot task parent:list(node A):=match worktree_observation snapshot task with
|None=>[]|Some value=>match text "status" value with
 |"creating"|"creating_archived"|"archiving"=>[information parent "worktree/status" Information.Status(worktree_status(text "status" value))]
 |"create_failed"|"archive_failed"=>[region parent "worktree/error" "Workspace" Roles.Alert
   [read_only (part parent "worktree/error") "message" "Workspace"(String.concat ": "[worktree_status(text "status" value);text "message" value])]]
 |_=>[]end end.
Definition worktree_details snapshot s task parent:=match worktree_observation snapshot task with
|None=>[]|Some value=>List.app
 [read_only parent "worktree/status" "Workspace status"(worktree_status(text "status" value));
  read_only parent "worktree/source" "Source repository"(text "source_root" value);
  read_only parent "worktree/root" "Managed workspace"(text "root" value)]
 (List.app(if String.eqb(text "message" value)""then[]else[read_only parent "worktree/error" "Workspace"(text "message" value)])
  (match ObjectActions.worktree_retry_action snapshot s task with
   |Some action=>match ObjectActions.command action with
    |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]
    |None=>[]end|None=>[]end))end.
Definition task_side_controls snapshot s task parent:=match ObjectActions.return_action snapshot s task with
|None=>[]|Some action=>List.app
 (match ObjectActions.command action with
  |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]|None=>[]end)
 [declared parent Roles.Button(secondary "side/show" "打开侧窗口"(Input.ShowSide task(part parent "side/show")))]end.
Definition discarded_unfinished_notice s task parent:=
 let count:=Documents.discarded_count task(State.document_retention s)in
 if N.eqb count 0 then [] else
 let key:=part parent "discarded-unfinished" in
 [region parent "discarded-unfinished" "未完成回复" Roles.Alert
  [information key "discarded-unfinished-count" Information.Description
    ("已有 "++show_natural count++" 条未完成回复因会话容量限制被移除。");
   declared key Roles.Button(secondary "clear-discarded-unfinished" "清除此提示"(Input.ClearDiscarded task))]].
Definition task_details_control s task parent :=
 let expanded:=existsb(fun layer=>match State.layer_panel layer with
  |State.InformationPanel(State.TaskDetails actual)=>N.eqb task actual|_=>false end)
  (State.layers(State.navigation_state s))in
 Node(part parent "details")"details" "Task details"Roles.Button
  (PanelToggle expanded(secondary "details" "Task details"
    (Input.OpenInformation(State.TaskDetails task)(part parent "details"))))[].
Definition task_has_composer s task :=negb(String.eqb(task_status task)"archived")||
 match Draft.find_draft(Message(task_id task))(State.drafts(State.authoring_state s))with Some _=>true|None=>false end.
Definition task_contents snapshot s view parent task :=
 let id:=task_id task in
 let observation:=task_observation task in
 let timeline:=AuditReading.timeline reading_actions(document_context snapshot s)(State.document_retention s)
   (State.interactive_state s)view(reader_disclosures id s)in
 let timeline:=List.app timeline(operation_controls snapshot s id parent observation)in
 ([page_region parent Composition.ConversationHeader Composition.HeadingPosition
   [page_region parent Composition.ConversationTitle Composition.HeadingPosition(title parent(task_title task)::worktree_feedback snapshot id parent);
  page_region parent Composition.TaskActions Composition.HeadingPosition
   (List.app [task_details_control s id parent;
    Collections.more parent(TaskActions id)](task_side_controls snapshot s id parent))];
  page_region parent Composition.TimelineContent Composition.BodyPosition
   (discarded_unfinished_notice s id parent ++
    [Node(Identity.task_view_key view "timeline")"timeline" "Conversation"Roles.Timeline
      (ReadingTimeline view(State.reader_generation(SessionNavigation.reader_for s id)))timeline])] ++
 (if SessionNavigation.return_latest s id then
 [page_region parent Composition.LatestAction Composition.DockPosition
  [declared parent Roles.Button(secondary "latest" "Return to latest"(Input.FollowLatest id))]]else[]) ++
 approvals snapshot s id parent observation ++
 if task_has_composer s task then match Editors.composer_view snapshot s(Message id)(Identity.task_view_key view(editor_key(Message id)))with
   |None=>[]|Some composer=>[page_region parent Composition.ComposerInput Composition.DockPosition[composer]]end else[])%list.
Definition conversation_page snapshot s view parent :=
 match find_task(Identity.task_view_task view)snapshot with
 |None=>missing parent "This task no longer exists"
 |Some task=>[Node(part parent "conversation")"conversation" ""Roles.Section(PageContext(Some view))
  (task_contents snapshot s view parent task)]end.
Definition history_scope (project:bool) selected choices parent :=
 Node(part parent(if project then"history/project"else"history/work"))"history-scope"(if project then"项目"else"Work")Roles.Field
  (HistorySearchScope project selected choices(fun value=>
   selected<-(match value with JString ""=>Some None|JString value=>option_map(@Some N)(parse_natural value)|_=>Identity.decode_id value end);;
   Some(Input.ChooseHistoryScope project selected))) [].
Definition history_hit parent hit :=
 match field "task" hit,natural_field "message_index" hit with
 |Some task,Some index=>match natural_field "id" task with
  |None=>[]|Some id=>let key:=part parent("hit/"++show_natural id++"/"++show_natural index)in
   [region key "result" "Search result"Roles.Card
    ([declared key Roles.Button(secondary "open"(text "title" task++" · 消息 #"++show_natural(N.succ index))(Input.OpenHistoryMessage id index))]++
     (if String.eqb(text "before" hit)""then[]else[read_only key "before" "上一条"(text "before" hit)])++
     [read_only key "snippet" "命中消息"(text "snippet" hit)]++
     (if String.eqb(text "after" hit)""then[]else[read_only key "after" "下一条"(text "after" hit)]))]end|_,_=>[]end.
Definition history_page snapshot s parent :=
 let search:=State.history_search(State.authoring_state s)in
 let submit:=observe_control(fun input=>domain_availability(Selvedge.Interaction.Session.Authoring.input_availability snapshot s input))(secondary "history/submit" "搜索"(Input.SubmitHistorySearch 0))in
 let project_choices:=Fields.ChoiceValue "" "全部"::map(fun p=>Fields.ChoiceValue(show_natural(project_id p))(project_name p))(value_or[](projects snapshot))in
 let work_choices:=Fields.ChoiceValue "" "全部"::map(fun w=>Fields.ChoiceValue(show_natural(work_id w))(work_name w))(value_or[](works snapshot))in
 [page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "搜索对话"];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [Node(part parent "history/query")"history-query" "关键词"Roles.Field
     (HistorySearchQuery(State.keyword search)(fun value=>option_map Input.WriteHistoryQuery(as_string value))submit)[];
    history_scope true(State.project_filter search)project_choices parent;
    history_scope false(State.work_filter search)work_choices parent;
    declared parent Roles.Button submit];
  page_region parent Composition.ProjectEntries Composition.BodyPosition
   (match State.search_result search with
   |None=>[read_only parent "prompt" "搜索说明" "输入关键词，选择项目或 Work，然后搜索对话。"]
   |Some reply=>match field "result" reply with
    |Some result=>(
      (match Selvedge.Interaction.Codec.items "hits" result with []=>[read_only parent "history-empty" "搜索结果" "没有找到匹配的消息。"]
       |hits=>flat_map(history_hit parent)hits end)++
      (match natural_field "after" result with Some after=>if N.eqb after 0 then[]else
        [declared parent Roles.Button(observe_control(fun input=>domain_availability(Selvedge.Interaction.Session.Authoring.input_availability snapshot s input))
          (secondary "history/previous" "上一页"(Input.SubmitHistorySearch(N.sub after 20))))]|None=>[]end)++
      match natural_field "next_after" result with
      |Some after=>[declared parent Roles.Button(observe_control(fun input=>domain_availability(Selvedge.Interaction.Session.Authoring.input_availability snapshot s input))(secondary "history/more" "更多结果"(Input.SubmitHistorySearch after)))]|None=>[]end)%list
    |None=>[read_only parent "search-error" "Search failed"(Selvedge.Interaction.Codec.diagnostic_message(Selvedge.Interaction.Codec.command_failure(inr reply)))]end end)].
Definition shared_page snapshot s work parent :=
 match find_work work snapshot with
 |None=>missing parent "This Work no longer exists"
 |Some work=>[page_region parent Composition.SharedTitle Composition.HeadingPosition
    [title parent "共享 UI";read_only parent "work-name" "Work"(work_name work)];
   page_region parent Composition.SharedContent Composition.BodyPosition
    (let contents:=AuditReading.shared_ui Input.Interactive(document_context snapshot s)(State.document_retention s)(State.interactive_state s)in
     match contents with []=>[read_only parent "shared-empty" "共享 UI 尚未创建" "请让智能体创建共享 UI。"]|_=>contents end)]end.
Definition page_contents snapshot s parent :=match State.location(State.navigation_state s)with
|Start=>creation_page snapshot s parent
|Conversation task=>conversation_page snapshot s(PrimaryTask task)parent
|Projects=>Collections.projects_page snapshot s parent
|ProjectHome id=>match find_project id snapshot with Some project=>Collections.project_page snapshot s parent project|None=>missing parent "This project no longer exists"end
|Board=>Collections.board_page snapshot s parent|Agents=>Collections.agents_page snapshot s parent
|Graphs=>Collections.graphs_page snapshot s parent|HistorySearch=>history_page snapshot s parent
|SharedUI work task=>shared_page snapshot s work parent end.
Definition page_kind snapshot s :=match State.location(State.navigation_state s)with
|Start=>Composition.Creation true
|Conversation task=>match find_task task snapshot with
 |None=>Composition.Unavailable
 |Some value=>Composition.Conversation(task_has_composer s value)
   (existsb(fun operation=>String.eqb(text "stage" operation)"approval_pending")(Selvedge.Interaction.Codec.items "operations"(task_observation value)))
   (SessionNavigation.return_latest s task)end
|Projects=>Composition.ProjectCollection
|ProjectHome id=>match find_project id snapshot with Some _=>Composition.ProjectOverview|None=>Composition.Unavailable end
|Board=>Composition.TaskBoard|Agents=>Composition.AgentCollection|Graphs=>Composition.TaskGraphCollection
|HistorySearch=>Composition.ProjectCollection
|SharedUI work _=>match find_work work snapshot with Some _=>Composition.SharedInterface|None=>Composition.Unavailable end end.
Definition main snapshot s :=Node "/main" "main" "Main content"Roles.Main(PageBody(page_kind snapshot s))(page_contents snapshot s "/main").
