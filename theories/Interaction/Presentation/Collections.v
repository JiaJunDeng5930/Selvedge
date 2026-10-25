From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require Domain BoardFilter BoardParameters.
From Selvedge.Interaction Require ModelSelection.
From Selvedge.Interaction.Experience Require Observation.
From Selvedge.Interaction Require Import Codec Identity Input ObjectActions.
From Selvedge.Interaction.Session Require State Observation Authoring.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Projection Navigation.
From Selvedge.Interaction.Presentation Require Roles Information Composition.
Import ListNotations.
Open Scope string_scope.
Module BoardDomain := Selvedge.Features.Domain.
Definition more parent subject :=declared parent Roles.Button
 (secondary "more" "More actions"(Input.OpenObjectActions subject(part parent "more"))).
Definition projects_page snapshot s parent :=
 [page_region parent Composition.CollectionTitle Composition.HeadingPosition [title parent "Projects"];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [declared parent Roles.PrimaryButton(primary "project/new" "New project"(Input.OpenEditor(Identity.Project None)(part parent "project/new")))];
  page_region parent Composition.ProjectEntries Composition.BodyPosition
   (match projects snapshot,tasks snapshot with
   |Some [],_=>[read_only parent "empty" "" "Create a project to group tasks and choose default working folders."]
   |Some projects,Some tasks=>map(Navigation.project_entry snapshot s(State.location(State.navigation_state s))parent tasks)projects
   |_,_=>[read_only parent "unavailable" "Projects" "Project observations unavailable"]end)].
Definition project_page snapshot s parent project :=
 let id:=project_id project in
 [page_region parent Composition.ProjectTitle Composition.HeadingPosition [title parent(project_name project)];
  page_region parent Composition.ProjectActions Composition.HeadingPosition
   [declared parent Roles.Button(secondary "new-task" "New task"(Input.BeginTask(Some id)));
    declared parent Roles.Button(secondary "edit" "Edit project"(Input.OpenEditor(Identity.Project(Some id))(part parent "edit")));more parent(ProjectActions id)];
  page_region parent Composition.DefaultWorkspace Composition.BodyPosition
   [read_only parent "workspace-roots" "Default workspace"(String.concat "
"(Domain.workspace_roots(project_workspace project)));
    read_only parent "workspace-primary" "Primary directory"(value_or ""(Domain.workspace_primary(project_workspace project)))];
  page_region parent Composition.ProjectGuidance Composition.BodyPosition
   [read_only parent "guidance" "Project guidance"(match project_guidance project with
    |JNull=>"No project guidance"|value=>text "instructions" value end)];
  page_region parent Composition.ProjectTasks Composition.BodyPosition
   (match tasks snapshot with
    |Some values=>map(task_entry_tree(State.location(State.navigation_state s))parent)(forest(project_tasks(Some id)values))
    |None=>[read_only parent "tasks-unavailable" "Tasks" "Task observations unavailable"]end)].
Definition elapsed_label seconds:=
 if N.ltb seconds 60 then "刚刚"else if N.ltb seconds 3600 then show_natural(N.div seconds 60)++"分钟前"
 else if N.ltb seconds 86400 then show_natural(N.div seconds 3600)++"小时前"else show_natural(N.div seconds 86400)++"天前".
Definition card_activity_label name:=value_or "未开始"
 (option_map snd(find(fun entry=>String.eqb name(fst entry))
 [("generating","生成中");("draft_failed","生成失败");("queued","排队中");("working","工作中");
  ("evaluating","评估推理等级");("compacting","整理上下文");("awaiting_approval","等待授权");
  ("completed","已完成");("failed","运行失败");("interrupted","已中断");("paused","已暂停");("archived","会话已归档")])).
Definition card_owner_label snapshot owner:=match BoardParameters.owner owner with
|Some BoardDomain.Unassigned=>"未分配"|Some BoardDomain.Self=>"我"
|Some(BoardDomain.ProfileOwner key)=>match ModelSelection.observed_profile snapshot key with
 |Some profile=>Selvedge.Interaction.Experience.Observation.profile_label profile|None=>"模型 "++key++" 不可用"end
|Some(BoardDomain.AgentOwner id)=>match find(fun agent=>match natural_field "agent_id" agent with Some actual=>N.eqb id actual|None=>false end)(value_or[](board_agents snapshot))with
 |Some agent=>text "name" agent|None=>"智能体 #"++show_natural id++" 不可用"end
|None=>"负责人不可用"end.
Definition card_face snapshot s id value :=
 priority<-BoardParameters.priority(text "priority" value);;
 Some(CardFace id(text "identifier" value)(text "title" value)(text "description" value)
  priority(flag "pinned" value)
  (card_activity_label(text "activity" value))
  (match Numbers.parse_natural(text "project" value)with Some id=>match find_project id snapshot with Some project=>project_name project|None=>"项目 #"++show_natural id++" 不可用"end|None=>""end)
  (value_or[](bind(array_field "labels" value)Selvedge.Kernel.Codec.strings))(card_owner_label snapshot(text "assignee" value))
  (match State.now s,Numbers.parse_natural(text "updated_at" value)with Some now,Some updated=>elapsed_label(BoardFilter.elapsed now updated)|_,_=>"更新时间待观测"end)).
Definition card_destinations snapshot s board_parent value :=
 match natural_field "card_id" value,natural_field "revision" value,State.now s with
 |Some id,Some revision,Some now=>
  let entry stage before label:=
   let action:=Input.CardPlaced id revision now stage before in
   let target:=match before with None=>part board_parent stage
    |Some id=>part(part board_parent stage)(String.append "card/"(show_natural id))end in
   Placement target(Control(String.append "move/" target)label Secondary action
    (if State.pending_placement id s then Busy "This task movement is pending"else
     domain_availability(Authoring.input_availability snapshot s action)))in
  List.app(map(fun stage=>entry(BoardDomain.stage_name stage)None(BoardDomain.stage_label stage))BoardDomain.stages)
   (List.app(flat_map(fun other=>match natural_field "card_id" other with
    |Some target=>if negb(N.eqb id target)&&negb(flag "archived" other)then
      [entry(text "status" other)(Some target)(String.append "Move before "(text "title" other))]else[]|None=>[]end)
     (value_or[](board_cards snapshot)))
    (if flag "archived" value then[]else match ObjectActions.resolve snapshot s(CardActions id)"archive"with
     |None=>[]|Some descriptor=>match ObjectActions.command descriptor with
      |None=>[]|Some command=>[Placement(part board_parent "archive-destination")
        (Control "archive" "归档任务"Secondary(Input.Command command)(domain_availability(Authoring.command_availability snapshot s command)))]end end))
 |_,_,_=>[]end.
Definition card_node snapshot s board_parent parent value :=match natural_field "card_id" value with
|None=>read_only parent "invalid-card" "Card unavailable" "Card identity unavailable"
|Some id=>let key:=part parent("card/"++show_natural id)in
 match card_face snapshot s id value with
 |None=>read_only key "invalid-card" "Card unavailable" "Card priority observation unavailable"
 |Some face=>Node key "card"(text "title" value)Roles.Card(CardContent face)
   [Node(part key "movement")"movement"("Move "++text "title" value)Roles.Content(MovableCard face(card_destinations snapshot s board_parent value))[];
    declared key Roles.Button(secondary "open"("打开 "++text "title" value)(Input.OpenInformation(State.CardDetails id)(part key "open")));
    more key(CardActions id)]end end.
Definition board_group {A} parent key grouping (children:list(node A)):=Node(part parent key)key ""Roles.Toolbar(BoardGroup grouping)children.
Definition board_toolbar snapshot s parent :=
 let selection:=State.board_selection s in
 [board_group parent "view-choices" ViewChoices
   (map(fun '(key,label)=>Node(part parent("view/"++key))"board/view"label Roles.Button
     (Choice SingleChoice(String.eqb key(BoardFilter.tab_name(BoardFilter.filter_tab selection)))""
       (secondary("view/"++key)label(Input.BoardTab key)))[])
      [("all","全部任务");("assigned","分配给我");("unassigned","未分配")]);
  board_group parent "search-area" SearchArea
   [Node(part parent "search")"board-search" "搜索任务"Roles.Field
     (BoardSearch selection(fun value=>option_map Input.BoardQuery(as_string value)))[]];
  board_group parent "work-status" WorkStatus
   [declared parent Roles.Button(secondary "working"("正在运行的任务 "++show_natural(count_working snapshot))(Input.BoardTab "working"))];
  board_group parent "secondary-actions" SecondaryActions
   [declared parent Roles.Button(secondary "filters" "筛选任务"(Input.OpenBoard State.BoardFilters(part parent "filters")));
    declared parent Roles.Button(secondary "settings" "看板设置"(Input.OpenBoard State.BoardSettings(part parent "settings")));
    Node(part parent "archive-destination")"board/archive" "归档任务"Roles.Section
     (CardArchive(N.of_nat(List.length(value_or[](archived_cards snapshot)))))
     [declared(part parent "archive-destination")Roles.Button(secondary "open" "归档任务"(Input.OpenBoard State.ArchivedCards(part(part parent "archive-destination")"open")))]];
  board_group parent "primary-action" PrimaryAction
   [declared parent Roles.PrimaryButton(primary "card/new" "新建任务"(Input.NewCard BoardDomain.Backlog(part parent "card/new")))]]
 .
Definition board_page snapshot s parent :=
 [page_region parent Composition.BoardTitle Composition.HeadingPosition[title parent "任务看板"];
  page_region parent Composition.BoardControls Composition.HeadingPosition(board_toolbar snapshot s parent);
  page_region parent Composition.BoardStages Composition.BodyPosition
   (match visible_cards snapshot s with
    |None=>[read_only parent "pending" "Board" "Waiting for current board observations"]
    |Some cards=>map(fun stage=>let key:=part parent(BoardDomain.stage_name stage)in
      let entries:=filter(fun card=>String.eqb(text "status" card)(BoardDomain.stage_name stage))cards in
      Node key "board-lane"(BoardDomain.stage_label stage)Roles.Section
        (BoardLane(BoardDomain.stage_name stage)(N.of_nat(List.length entries)))
        (group_title key(BoardDomain.stage_label stage)::
         declared key Roles.Button(secondary "card/new" "新建任务"(Input.NewCard stage(part key "card/new")))::
         map(card_node snapshot s parent key)(BoardFilter.display_cards entries)))BoardDomain.stages end)].
Definition agent_node parent value :=match natural_field "agent_id" value with
|None=>read_only parent "unavailable" "Agent" "Agent observation unavailable"
|Some id=>let key:=part parent("agent/"++show_natural id)in
 region parent("agent/"++show_natural id)(text "name" value)Roles.Card
  [group_title key(text "name" value);read_only key "instructions" "Instructions"(text "instructions" value);
   read_only key "model" "Model"(text "profile" value);
   read_only key "reasoning" "Reasoning"(text "reasoning" value);
   read_only key "concurrency" "Concurrency"(match natural_field "concurrency" value with Some count=>show_natural count|None=>"Unavailable"end);
   read_only key "active" "Active tasks"(match natural_field "active" value with Some count=>show_natural count|None=>"Unavailable"end);
   declared key Roles.Button(secondary "edit" "Edit agent"(Input.OpenEditor(Agent(Some id))(part key "edit")));more key(AgentActions id)]end.
Definition agents_page snapshot (s:State.state) parent :=
 [page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "Agents"];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [declared parent Roles.PrimaryButton(primary "agent/new" "New agent"(Input.OpenEditor(Agent None)(part parent "agent/new")))];
  page_region parent Composition.AgentEntries Composition.BodyPosition
   (match board_agents snapshot with Some entries=>map(agent_node parent)entries
    |None=>[read_only parent "unavailable" "Agents" "Agent observations unavailable"]end)].
Definition graph_endpoint graph name:=
 match find(fun entry=>String.eqb name(text "key" entry))(Selvedge.Interaction.Codec.items "nodes" graph)with
 |Some entry=>match natural_field "task_id" entry with Some task=>String.concat ""[name;" (Task #";show_natural task;")"]|None=>String.append name " (unavailable)"end
 |None=>String.append name " (unavailable)"end.
Definition graph_rule_nodes {A} parent graph:list(node A):=map(fun rule=>let key:=part parent(String.append "rule/"(text "key" rule))in
 region parent(String.append "rule/"(text "key" rule))(text "key" rule)Roles.Section
  (group_title key(text "key" rule)::map(fun '(ordinal,action)=>read_only key(show_natural(N.of_nat ordinal))"Output delivery"
    (String.concat ""[graph_endpoint graph(text "source" rule);" → ";graph_endpoint graph(text "target" action);": ";
     match field "message" action with Some message=>TextJson.render_json message|None=>"Unavailable message"end]))
   (combine(seq 0(List.length(Selvedge.Interaction.Codec.items "actions" rule)))(Selvedge.Interaction.Codec.items "actions" rule))))
  (Selvedge.Interaction.Codec.items "rules" graph).
Definition graph_receipt_nodes {A} parent graph:list(node A):=map(fun '(ordinal,receipt)=>
 read_only parent(String.append "receipt/"(show_natural(N.of_nat ordinal)))"Last delivery result"
  (String.concat ""["Task #";match natural_field "source" receipt with Some source=>show_natural source|None=>"Unavailable"end;
   " → Task #";match natural_field "target" receipt with Some target=>show_natural target|None=>"Unavailable"end;
   " (";text "rule" receipt;"): ";match field "reply" receipt with Some(JString value)=>value|Some reply=>TextJson.render_json reply|None=>"Unavailable reply"end]))
 (combine(seq 0(List.length(Selvedge.Interaction.Codec.items "receipts" graph)))(Selvedge.Interaction.Codec.items "receipts" graph)).
Definition graph_node snapshot s parent value :=match natural_field "graph_id" value with
|None=>read_only parent "unavailable" "Task graph" "Task graph observation unavailable"
|Some id=>let key:=part parent("graph/"++show_natural id)in
 region parent("graph/"++show_natural id)(text "name" value)Roles.Card
  ([group_title key(text "name" value);
    declared key Roles.Button(secondary "edit" "Edit task graph"(Input.OpenEditor(graph_editor(Some id)(State.active_work(State.navigation_state s)))(part key "edit")));
    more key(GraphActions id)]++
   [region key "nodes" "Tasks"Roles.Section
    (group_title(part key "nodes")"Tasks"::flat_map(fun entry=>match natural_field "task_id" entry with
     |None=>[]|Some task=>let node_key:=part key(String.append "node/"(text "key" entry))in
      [Node node_key "task-graph/node" ""Roles.Section(ObjectGroup(Selvedge.Interaction.Experience.Model.TaskObject task))
       (group_title node_key(String.concat ""[text "key" entry;" · Task #";show_natural task])::
        match find_task task snapshot with
        |Some task=>[Navigation.task_entry_tree(State.location(State.navigation_state s))node_key(TaskTree task [])]
        |None=>[read_only node_key "status" "Task status" "Unavailable"]end)]end)(Selvedge.Interaction.Codec.items "nodes" value));
    region key "rules" "Output rules"Roles.Section(graph_rule_nodes key value);
    region key "receipts" "Last delivery results"Roles.Section(graph_receipt_nodes key value)])%list end.
Definition graphs_page snapshot s parent :=
 [page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "Task graphs"];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [declared parent Roles.PrimaryButton(primary "graph/new" "New task graph"(Input.OpenEditor(graph_editor None(State.active_work(State.navigation_state s)))(part parent "graph/new")))];
  page_region parent Composition.TaskGraphEntries Composition.BodyPosition(map(graph_node snapshot s parent)(scoped_graphs(State.active_work(State.navigation_state s))snapshot))].
