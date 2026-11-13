From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Kernel Require Commands Domain Search.
From Selvedge.Generated Require Commands.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity Context.
From Selvedge.Browser.Session Require Import Input ObjectActions.
From Selvedge.Browser Require Import AuditReading Documents.
From Selvedge.Interaction.Experience Require Model Observation Read HistoryObservation Activity.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Browser.Session Require State Observation Navigation Services.
Module SessionNavigation := Selvedge.Browser.Session.Navigation.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection Editors Navigation Collections.
From Selvedge.Browser.Presentation Require Roles Information Composition.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Module Observe := Selvedge.Interaction.Experience.Observation.
Module SessionObserve := Selvedge.Browser.Session.Observation.
Module UX := Selvedge.Interaction.Experience.Model.
Module G := Selvedge.Generated.Commands.
Definition missing {A} parent message:list(node A) :=[page_region parent Composition.UnavailableMessage Composition.BodyPosition
 [read_only parent "unavailable-message" "Unavailable"message]].
Definition creation_heading snapshot s e :=match SessionObserve.draft_preview snapshot(State.current_draft s e)with
|Context.ProspectiveContext _ (Some project) _ _ _ _=>match find_project project snapshot with
 |Some project=>Navigation.new_conversation_label++" · "++project_name project
 |None=>Navigation.new_conversation_label end
|_=>Navigation.new_conversation_label end.
Definition run_environment_configuring (s:State.state) owner :=
 match State.layers(State.navigation_state s)with
 |top::_=>run_environment_panel owner(State.layer_panel top)|[]=>false end.
Definition creation_composer snapshot (s:State.state) parent :=
 let e:=NewTask(State.active_work(State.navigation_state s))in
 let owner:=editor_key e in
 let status:=if run_environment_configuring s e then [] else match Observe.run_environment_problem_for snapshot s (State.current_draft s e) with
  |Some problem=>[information parent "run-environment-status" Information.Status(Observe.environment_problem_message problem)]
  |None=>[]end in
 page_region parent Composition.ComposerInput Composition.BodyPosition
   ((match Editors.composer_view snapshot s e owner with Some composer=>[composer]|None=>[]end)++status)%list.
Definition creation_introduction snapshot s parent :=
 let e:=NewTask(State.active_work(State.navigation_state s))in
 let graph_return:=match State.location(State.navigation_state s)with
  |GraphConversation _ _=>
   [declared parent Roles.Button(secondary "return-to-graph" "返回任务图" Input.ReturnToGraphSetup)]
  |_=>[]end in
 page_region parent Composition.CreationIntroduction Composition.BodyPosition
   (information parent "creation/title" Information.IntroductionTitle(creation_heading snapshot s e)::graph_return).
Definition creation_page snapshot s parent :=
 [creation_introduction snapshot s parent; creation_composer snapshot s parent].
Definition creating_conversation_page parent (message:Draft.text) : list(node Input.input) :=
 let pending:=part parent "pending-conversation" in
 [Node pending "pending-conversation" "Conversation" Roles.Section (PageContext None)
  [page_region pending Composition.ConversationHeader Composition.HeadingPosition
    [page_region pending Composition.ConversationTitle Composition.HeadingPosition
      [title pending Navigation.new_conversation_label]];
   page_region pending Composition.TimelineContent Composition.BodyPosition
    [region pending "pending-conversation-reading" "Conversation" Roles.Section
     (let text:=Draft.text_value message in
      (if String.eqb text "" then [] else
       [region pending "pending-user-message" "Message" Roles.UserMessage
        [Node(part pending "message-text")"message-text" "" Roles.Content (ReadOnly text)[]]])++
      [information pending "pending-first-reply" Information.Status "正在提交消息…"])]]].
Definition approval_availability value:=match ObjectActions.action_status value with
|ObjectActions.Available=>Available|ObjectActions.InFlight=>Busy "This action is pending"|ObjectActions.Awaiting=>Unavailable "Checking action availability"
|ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>Unavailable reason end.
Definition approval_argument_label name := match name with
| "command" => "Command" | "justification" => "Reason" | other => other end.
Definition approval_arguments {A} parent operation:list(node A):=match Read.operation_arguments operation with
|Some(JObject arguments)=>map(fun '(name,value)=>read_only parent("argument/"++name)(approval_argument_label name)
 (match value with JString value=>value|_=>TextJson.render_json value end))arguments
|Some value=>[read_only parent "arguments" "Arguments"(TextJson.render_json value)]|None=>[]end.
Definition operation_cancel_control snapshot s task parent id :=
 match ObjectActions.cancellation_action snapshot s task id with
 |Some action=>match ObjectActions.command action with
  |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary
    (Input.Command command)(approval_availability action))]|None=>[]end
 |None=>[]end.
Definition approval_node snapshot s task parent operation :=
 let id:=Read.operation_id operation in
 let key:=part parent("approval/"++show_natural id)in
 let human:=Read.operation_human operation in
 let status:=if human then"Approval required"else"Automatic review"in
 let decisions:=if human then flat_map(fun allow=>match ObjectActions.approval_action snapshot s task id allow with
    |Some action=>match ObjectActions.command action with
     |Some command=>[declared key(if allow then Roles.PrimaryButton else Roles.Button)
       (Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]
     |None=>[]end|None=>[]end)[false;true] else [] in
 Node key "approval" status Roles.Approval Region
  ([region key "approval-heading" "" Roles.Section
     [group_title key(Read.operation_tool operation);information key "approval-status" Information.Description status];
    region key "approval-details" "" Roles.Section
     (approval_arguments key operation ++
      (match Read.operation_directory operation with
       |Some directory=>[read_only key "directory" "Default working directory" directory]|None=>[]end) ++
      if human then [] else [read_only key "reviewer" "Reviewer model"
       (value_or "Reviewer observation unavailable"(Read.operation_reviewer operation))])]
   ++ [region key "approval-actions" "Approval decision" Roles.Toolbar
       (decisions++operation_cancel_control snapshot s task key id)])%list.
Definition approvals snapshot s task parent operations :=
 match Read.pending_approvals operations with []=>[]|pending=>[page_region parent Composition.ApprovalDecisions Composition.DockPosition
  [region parent "approval-queue" "Approvals"Roles.ApprovalQueue(map(approval_node snapshot s task parent)pending)]]end.
Definition reader_disclosures task s :=State.disclosures(SessionNavigation.reader_for s task).
Definition reading_actions := AuditReading.ReadingActions Input.SetDisclosure Input.Interactive Input.RetainedOutput.
Definition operation_caption operation := match Read.operation_status operation with
 |"running"=>"Running"
 |"awaiting_approval"=>"Waiting for approval"
 |"approved_waiting_to_run"=>"Approved, waiting to run"
 |"result_pending"=>"Processing the result"
 |other=>other end.
Definition operation_node snapshot s task parent operation :=
 let id:=Read.operation_id operation in
 let key:=part parent("operation/"++show_natural id)in
 region key "operation"(Read.operation_tool operation)Roles.Activity
    ([information key "tool" Information.FieldLabel(Read.operation_tool operation);
      information key "status" Information.Description(operation_caption operation)]++
     operation_cancel_control snapshot s task key id).
Definition operation_controls snapshot s task parent operations :=
 let running:=filter (fun op=>negb(String.eqb "approval_pending"(Read.operation_stage op))) operations in
 match running with []=>[]|_=>[region parent "active-operations" "Tool activity"Roles.Activity
  (map(operation_node snapshot s task parent)running)]end.
Definition worktree_feedback {A} snapshot task parent:list(node A):=match Read.task_workspace task snapshot with
|None=>[]|Some value=>match Read.worktree_status value with
 |"creating"|"creating_archived"|"archiving"=>[information parent "worktree/status" Information.Status(Read.worktree_caption value)]
 |"create_failed"|"archive_failed"=>[region parent "worktree/error" "Workspace" Roles.Alert
   [read_only (part parent "worktree/error") "message" "Workspace"(String.concat ": "[Read.worktree_caption value;Read.worktree_message value])]]
 |_=>[]end end.
Definition directory_details parent identity label path : node Input.input :=
 let key:=part parent identity in
 region key "directory-path-entry" "" Roles.Content
   [Node key "directory-path" (label++" · "++UX.directory_basename path) Roles.Content ContentDisclosure
     [Node (part key "path") "directory-path-value" "" Roles.Content (Fact path) []];
    declared key Roles.Button(secondary "copy-path" ("复制"++label++"路径")(Input.CopyPath path))].
Definition worktree_details snapshot s task parent:=match Read.task_workspace task snapshot with
|None=>[]|Some value=>List.app
 [read_only parent "worktree/status" "工作区状态"(Read.worktree_caption value);
  directory_details parent "worktree/source" "源仓库"(Read.worktree_source value)]
 (List.app
  (match Read.worktree_root value with None=>[]|Some root=>
   let roots:=value_or [] (option_map (fun context=>Domain.workspace_roots(Read.context_workspace context))
     (Read.task_context task snapshot)) in
   if existsb (String.eqb root) roots then [] else [directory_details parent "worktree/root" "托管工作区" root] end)
 (List.app(if String.eqb(Read.worktree_message value)""then[]else[read_only parent "worktree/error" "工作区"(Read.worktree_message value)])
  (match ObjectActions.worktree_retry_action snapshot s task with
   |Some action=>match ObjectActions.command action with
    |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]
   |None=>[]end|None=>[]end)))end.
Definition show_side_control parent task : node Input.input :=
 declared parent Roles.Button(secondary "side/show" "Open side conversation"
   (Input.ShowSide task(part parent "side/show"))).
Definition task_side_controls snapshot s task parent:=match ObjectActions.return_action snapshot s task with
|None=>match filter (fun entry=>match Read.task_side_parent snapshot (task_id entry) with
         |Some source=>N.eqb source task|None=>false end) (value_or[](Read.tasks snapshot)) with
       |[child]=>[show_side_control parent (task_id child)]|_=>[]end
|Some action=>List.app
 (match ObjectActions.command action with
  |Some command=>[declared parent Roles.Button(Control(ObjectActions.action_key action)(ObjectActions.action_label action)Secondary(Input.Command command)(approval_availability action))]|None=>[]end)
 [show_side_control parent task]end.
Definition discarded_unfinished_notice s task parent:=
 let count:=Documents.discarded_count task(State.document_retention s)in
 if N.eqb count 0 then [] else
 let key:=part parent "discarded-unfinished" in
 [region parent "discarded-unfinished" "未完成回复" Roles.Alert
  [information key "discarded-unfinished-count" Information.Description
    ("已有 "++show_natural count++" 条未完成回复因会话容量限制被移除。");
   declared key Roles.Button(secondary "clear-discarded-unfinished" "清除此提示"(Input.ClearDiscarded task))]].
Definition task_details_label := "任务详情".
Definition task_details_control s task parent :=
 let expanded:=existsb(fun layer=>match State.layer_panel layer with
  |State.InformationPanel(State.TaskDetails actual)=>N.eqb task actual|_=>false end)
  (State.layers(State.navigation_state s))in
 Node(part parent "details")"details" task_details_label Roles.Button
  (PanelToggle expanded(secondary "details" task_details_label
    (Input.OpenInformation(State.TaskDetails task)(part parent "details"))))[].
Definition run_control snapshot s (task:Read.task) parent key :=
 match ObjectActions.resolve snapshot s (TaskActions(Read.task_id task)) key with
 |Some action=>match ObjectActions.command action with
  |Some command=>let control:=Control key (ObjectActions.action_label action) Secondary
    (Input.Command command)(approval_availability action)in
   (* Keep the action eligible for automatic admission while concealing an
      interrupt that cannot yet be used. A submitted interrupt remains visible. *)
   [if String.eqb key "interrupt" then match ObjectActions.action_status action with
    |ObjectActions.Available|ObjectActions.InFlight=>declared parent Roles.Button control
    |_=>Node(part parent key)"interrupt-unavailable"(control_label control) Roles.Button (Activate control)[]end
    else declared parent Roles.Button control]
  |None=>[]end
 |None=>[]end.
Definition task_run_controls snapshot s (task:Read.task) parent :=
 let status:=Read.task_status task in
 let working:=Read.task_working task && negb(String.eqb status "archived") in
 let paused:=String.eqb status "frozen" in
 ((if String.eqb status "active" then []
   else[information parent "run-status" Information.Status(Read.task_caption task)])++
 (if paused then run_control snapshot s task parent "unfreeze" else [])++
 (if working then run_control snapshot s task parent "interrupt" else []))%list.
Definition task_details_controls s task parent (hidden : bool) :=
 if hidden then [] else [task_details_control s task parent].
Definition task_actions_with_details snapshot s task parent hide_details :=
 let id:=task_id task in
 page_region parent Composition.TaskActions Composition.HeadingPosition
  (task_run_controls snapshot s task parent++
   task_details_controls s id parent hide_details++[Collections.more parent(TaskActions id)]++
   task_side_controls snapshot s id parent).
Definition task_has_composer s task :=negb(String.eqb(task_status task)"archived")||
 match Draft.find_draft(Message(task_id task))(State.drafts(State.authoring_state s))with Some _=>true|None=>false end.
Definition task_composer snapshot s view parent task :=
 let owner:=Message(task_id task)in
 if task_has_composer s task then match Editors.composer_view snapshot s owner(NavigationIdentity.task_view_key view(editor_key owner))with
 |Some composer=>Some(page_region parent Composition.ComposerInput Composition.DockPosition[composer])
 |None=>None end else None.
Definition conversation_composer snapshot s view parent :=
 bind(find_task(NavigationIdentity.task_view_task view)snapshot)(task_composer snapshot s view parent).
Definition fork_history_control view :=
 let action:=ObjectActions.task_fork_action(NavigationIdentity.task_view_task view)in
 match ObjectActions.action_operation action with
 |ObjectActions.Editor owner=>let key:="fork-current-history" in
  let parent:=NavigationIdentity.task_view_scope view in
  [declared parent Roles.Button(Control key (ObjectActions.action_label action) Secondary
    (Input.OpenEditor owner(part parent key))(approval_availability action))]
 |_=>[]end.
Definition search_return_controls s view parent :=
 match view,State.search_return(SessionNavigation.search_state s)with
 |PrimaryTask _,Some _=>[declared parent Roles.Button
      (secondary "return-to-search" "返回搜索结果" Input.ReturnToHistorySearch)]
 |_,_=>[]end.
Definition task_title_region snapshot task parent : node Input.input :=
 page_region parent Composition.ConversationTitle Composition.HeadingPosition
   (title parent(task_title task)::worktree_feedback snapshot(task_id task)parent).
Definition task_header snapshot s view parent task hide_details :=
 page_region parent Composition.ConversationHeader Composition.HeadingPosition
   (search_return_controls s view parent ++
    [task_title_region snapshot task parent;task_actions_with_details snapshot s task parent hide_details]).
Definition task_timeline snapshot s view parent task operations :=
 let id:=task_id task in
 let history:=AuditReading.timeline reading_actions(document_context snapshot s)(State.document_retention s)
   (State.interactive_state s)view(reader_disclosures id s)in
 let tail:=if Read.task_working task then [] else
   match history with []=>[]|_=>fork_history_control view end in
 let timeline:=List.app history(List.app(operation_controls snapshot s id parent operations)tail)in
 let timeline:=match timeline with []=>
   [information parent "conversation-empty" Information.Description "Messages and task activity will appear here."]
  |_=>timeline end in
 page_region parent Composition.TimelineContent Composition.BodyPosition
   (discarded_unfinished_notice s id parent ++
    [Node(NavigationIdentity.task_view_key view "timeline")"timeline" "Conversation"Roles.Timeline
      (ReadingTimeline view(State.reader_generation(SessionNavigation.reader_for s id)))timeline;
     information parent "reading-initial-status" Information.Status "正在加载对话…"] ++
    if SessionNavigation.return_latest s id then
    [page_region parent Composition.LatestAction Composition.BodyPosition
      [declared parent Roles.Button(secondary "latest" "Return to latest"(Input.FollowLatest id))]]else[]).
Definition task_contents snapshot s view parent task hide_details :=
 let id:=task_id task in
 let operations:=value_or[](Read.task_operations id snapshot)in
 ((match view with PrimaryTask _=>[task_header snapshot s view parent task hide_details]|SideTask _=>[]end) ++
 [task_timeline snapshot s view parent task operations] ++
 approvals snapshot s id parent operations ++
 match task_composer snapshot s view parent task with Some composer=>[composer]|None=>[]end)%list.
Definition conversation_page_with_details snapshot s view parent hide_details :=
 match find_task(NavigationIdentity.task_view_task view)snapshot with
 |None=>[page_region parent Composition.UnavailableMessage Composition.BodyPosition
   [region parent "conversation-unavailable" "" Roles.Section
     ([title parent "Conversation unavailable";
      information parent "conversation-unavailable-message" Information.Description "This task no longer exists."]++
       search_return_controls s view parent)]]
 |Some task=>[Node(part parent "conversation")"conversation" ""Roles.Section(PageContext(Some view))
  (task_contents snapshot s view parent task hide_details)]end.
Definition conversation_page snapshot s view parent := conversation_page_with_details snapshot s view parent false.
Definition history_scope (project:bool) selected choices parent :=
 Node(part parent(if project then"history/project"else"history/work"))"history-scope"(if project then"项目"else"工作组")Roles.Field
  (HistorySearchScope project selected choices(fun value=>
   selected<-(match value with JString ""=>Some None|JString value=>option_map(@Some N)(parse_natural value)|_=>Identity.decode_id value end);;
   Some(Input.ChooseHistoryScope project selected))) [].
Definition history_result_text parent name query width text : node Input.input :=
 let folded:=Search.lower text in
 let meaning:=
   match Utf8.chunks text with
   | Some chunks=>if negb (Nat.eqb width 0) && Search.contains query folded then
      let offset:=Search.match_offset query folded 0 in
      let rest:=skipn offset chunks in
      HistoryMatch (Utf8.render_chunks (firstn offset chunks))
        (Utf8.render_chunks (firstn width rest)) (Utf8.render_chunks (skipn width rest))
     else ReadOnly text
   | None=>ReadOnly text
   end in
 Node (part parent name) name "" Roles.Content meaning [].
Definition history_result_button parent label input children : node Input.input :=
 Node (part parent "open") "open" label Roles.Button
   (Activate (secondary "open" label input)) children.
Definition history_hit_task hit :=
 match hit with
 |HistoryObservation.TitleMatch task|HistoryObservation.MessageMatch task _=>task end.
(* Moving the current hit's group to the front retains the first hit's
   position, while prepending the hit preserves the order within its group. *)
Definition history_result_groups hits : list (Read.task * list HistoryObservation.history_hit) :=
 fold_right (fun hit groups=>
   let task:=history_hit_task hit in
   let '(same,others):=List.partition
     (fun group=>N.eqb (Read.task_id task) (Read.task_id (fst group))) groups in
   (task,hit::flat_map snd same)::others) [] hits.
Definition history_message_result parent query width id title hit :=
 let index:=HistoryObservation.hit_message hit in
 let key:=part parent("hit/"++show_natural id++"/"++show_natural index)in
 let speaker:=match HistoryObservation.hit_speaker hit with
  |Domain.UserSpeaker=>"用户"|Domain.AssistantSpeaker=>"助手" end in
 let excerpt:=match HistoryObservation.hit_preview hit with
   |Some text=>history_result_text key "result-excerpt" query width text
   |None=>Node (part key "result-excerpt") "result-excerpt" "" Roles.Content
      (ReadOnly "在消息原文中找到匹配") []
   end in
 history_result_button key (title++" · "++speaker) (Input.OpenHistoryResult id(Some index)(part key "open"))
  [Node (part key "result-speaker") "result-speaker" "" Roles.Content (ReadOnly speaker) []; excerpt].
Definition history_conversation_result parent query width
  (group:Read.task * list HistoryObservation.history_hit) :=
 let '(task,hits):=group in
 let id:=Read.task_id task in
 let title:=Read.task_title task in
 let key:=part parent("conversation/"++show_natural id)in
 let title_key:=part parent("hit/"++show_natural id++"/title")in
 let title_node:=if existsb (fun hit=>match hit with HistoryObservation.TitleMatch _=>true|_=>false end) hits then
   history_result_button title_key title (Input.OpenHistoryResult id None(part title_key "open"))
     [history_result_text title_key "result-title" query width title]
  else information key "result-title" Information.GroupTitle title in
 let messages:=flat_map (fun hit=>match hit with
   |HistoryObservation.TitleMatch _=>[]
   |HistoryObservation.MessageMatch _ message=>[history_message_result parent query width id title message]
   end) hits in
 region key "result" "" Roles.Card (title_node::messages).
Definition history_page snapshot s parent :=
 let search:=SessionNavigation.search_state s in
 let page:=State.search_result search in
 let results_parent:=match page with None=>parent|Some result=>
   part parent("search-page/"++show_natural(State.search_page_ticket result))end in
 let pending:=State.pending_search s in
 let availability input:=if pending then Busy "正在搜索…" else
   domain_availability(Selvedge.Browser.Session.Authoring.input_availability snapshot s input)in
 let submit:=observe_control availability(primary "history/submit" "搜索"(Input.SubmitHistorySearch 0))in
 let project_choices:=Fields.ChoiceValue "" "全部"::map(fun p=>Fields.ChoiceValue(show_natural(project_id p))(project_name p))(value_or[](projects snapshot))in
 let work_choices:=Fields.ChoiceValue "" "全部"::map(fun w=>Fields.ChoiceValue(show_natural(work_id w))(work_name w))(value_or[](works snapshot))in
 [browse_heading parent
   (page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "搜索对话"]) [];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [Node(part parent "history/query")"history-query" "标题或消息关键词"Roles.Field
     (HistorySearchQuery(State.keyword search)(fun value=>option_map Input.WriteHistoryQuery(as_string value))submit)[];
    history_scope true(State.project_filter search)project_choices parent;
    history_scope false(State.work_filter search)work_choices parent;
    declared parent Roles.PrimaryButton submit];
  page_region parent Composition.HistoryResults Composition.BodyPosition
   (if pending then[information parent "searching" Information.Status "正在搜索…"]else
    match page with
   |None=>[]
   |Some result=>match HistoryObservation.search_result(State.search_reply result)with
    |inr result=>
     let after:=HistoryObservation.page_after result in
     let query:=Search.lower(Search.trim(State.keyword search))in
     let width:=value_or 0 (Utf8.scalar_count query) in
     let filtered:=match State.project_filter search,State.work_filter search with None,None=>false|_,_=>true end in
     ((match HistoryObservation.hits result with
       |[]=>[region parent "history-empty" "" Roles.Content
         [information parent "history-empty-status" Information.Status "没有匹配结果";
          information parent "history-empty-next" Information.Description
            (if filtered then "试试其他关键词，或将筛选改为「全部」。" else "试试其他关键词。")]]
       |hits=>map (history_conversation_result results_parent query width) (history_result_groups hits) end)++
      (if N.eqb after 0 then[]else
        [declared parent Roles.Button(observe_control availability
          (secondary "history/previous" "上一页"(Input.SubmitHistorySearch(N.sub after 20))))])++
      match HistoryObservation.next_after result with
      |Some next=>[declared parent Roles.Button(observe_control availability(secondary "history/more" "更多结果"(Input.SubmitHistorySearch next)))]|None=>[]end)%list
    |inl reason=>[information parent "search-error" Information.Status
       ("未能完成搜索，请重试。 "++reason)]end end)].
Definition shared_page snapshot s work parent :=
 match find_work work snapshot with
 |None=>missing parent "This Work no longer exists"
 |Some work=>[browse_heading parent
   (page_region parent Composition.SharedTitle Composition.HeadingPosition [title parent "共享 UI"])
   [information parent "work-name" Information.Description (work_name work)];
   page_region parent Composition.SharedContent Composition.BodyPosition
    (let contents:=AuditReading.shared_ui Input.Interactive(document_context snapshot s)(State.document_retention s)(State.interactive_state s)in
     match contents with []=>[read_only parent "shared-empty" "共享 UI 尚未创建" "请让智能体创建共享 UI。"]|_=>contents end)]end.
Definition page_contents snapshot s pending parent hide_details :=match pending with
|Some message=>creating_conversation_page parent message
|None=>match State.location(State.navigation_state s)with
|Start|GraphConversation _ _=>creation_page snapshot s parent
|Conversation task=>conversation_page_with_details snapshot s(PrimaryTask task)parent hide_details
|Projects=>Collections.projects_page snapshot s parent
|ProjectHome id=>match find_project id snapshot with Some project=>Collections.project_page snapshot s parent project|None=>missing parent "This project no longer exists"end
|Board=>Collections.board_page snapshot s parent
|Graphs=>Collections.graphs_page snapshot s parent|HistorySearch=>history_page snapshot s parent
|SharedUI work task=>shared_page snapshot s work parent end end.
Definition page_kind_with snapshot s (pending:option Draft.text) :=match pending with
|Some _=>Composition.Conversation false false
|None=>match State.location(State.navigation_state s)with
|Start|GraphConversation _ _=>Composition.Creation true
|Conversation task=>match find_task task snapshot with
 |None=>Composition.Unavailable
 |Some value=>Composition.Conversation(task_has_composer s value)
   (match Read.pending_approvals(value_or[](Read.task_operations(task_id value)snapshot))with []=>false|_=>true end)end
|Projects=>Composition.ProjectCollection
|ProjectHome id=>match find_project id snapshot with Some _=>Composition.ProjectOverview|None=>Composition.Unavailable end
|Board=>Composition.TaskBoard|Graphs=>Composition.TaskGraphCollection
|HistorySearch=>Composition.HistorySearchCollection
|SharedUI work _=>match find_work work snapshot with Some _=>Composition.SharedInterface|None=>Composition.Unavailable end end end.
Definition page_kind snapshot s :=page_kind_with snapshot s (SessionNavigation.creating_conversation s).
Definition main_with_details snapshot s hide_details :=
 let pending:=SessionNavigation.creating_conversation s in
 Node "/main" "main" "Main content"Roles.Main(PageBody(page_kind_with snapshot s pending))
  (page_contents snapshot s pending "/main" hide_details).
