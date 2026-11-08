From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require Domain BoardFilter.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input ObjectActions.
From Selvedge.Browser.Session Require State Authoring.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection Navigation.
From Selvedge.Browser.Presentation Require Roles Information Composition.
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
   [read_only parent "guidance" "Project guidance"(value_or "No project guidance"(project_instructions project))];
  page_region parent Composition.ProjectTasks Composition.BodyPosition
   (match Projection.project_members snapshot id with
    |Some values=>map(task_entry_tree(State.location(State.navigation_state s))parent)(forest values)
    |None=>[read_only parent "tasks-unavailable" "Tasks" "Task observations unavailable"]end)].
Definition elapsed_label seconds:=
 if N.ltb seconds 60 then "刚刚"else if N.ltb seconds 3600 then show_natural(N.div seconds 60)++"分钟前"
 else if N.ltb seconds 86400 then show_natural(N.div seconds 3600)++"小时前"else show_natural(N.div seconds 86400)++"天前".
Definition card_face snapshot s value :=
 CardFace (Read.card_id value)(Read.card_identifier value)(Read.card_title value)(Read.card_description value)
  (Read.card_priority value)(Read.card_pinned value)(Read.card_activity_label(Read.card_activity value))
  (Read.card_project_label snapshot(Read.card_project value))(Read.card_labels value)
  (Read.card_owner_label snapshot(Read.card_owner value))
  (match State.now s with Some now=>elapsed_label(BoardFilter.elapsed now(Read.card_updated value))|None=>"更新时间待观测"end).
Definition card_destinations snapshot s board_parent candidates value :=
 match State.now s with
 |Some now=>
  let id:=Read.card_id value in
  let entry position:=
   let stage:=BoardDomain.stage_name(CardDecisions.position_stage position) in
   let before:=CardDecisions.position_target position in
   let label:=match position with
    |CardDecisions.EndOfStage stage=>BoardDomain.stage_label stage
    |CardDecisions.BeforeCard _ _ title=>String.append "Move before " title end in
   let action:=Input.CardPlaced id (Read.card_revision value) now stage before in
   let target:=match before with None=>part board_parent stage
    |Some id=>part(part board_parent stage)(String.append "card/"(show_natural id))end in
   Placement target(Control(String.append "move/" target)label Secondary action
    (if State.pending_placement id s then Busy "This task movement is pending"else
     domain_availability(Authoring.input_availability snapshot s action)))in
  List.app(map entry(CardDecisions.move_positions_from_cards candidates id))
    (if Read.card_archived value then[]else match ObjectActions.resolve snapshot s(CardActions id)"archive"with
     |None=>[]|Some descriptor=>match ObjectActions.command descriptor with
      |None=>[]|Some command=>[Placement(part board_parent "archive-destination")
        (Control "archive" "归档任务"Secondary(Input.Command command)(domain_availability(Authoring.command_availability snapshot s command)))]end end)
 |None=>[]end.
Definition card_node snapshot s board_parent candidates parent value :=
 let id:=Read.card_id value in
 let key:=part parent("card/"++show_natural id)in
 let face:=card_face snapshot s value in
 let title:=Read.card_title value in
 Node key "card" title Roles.Card(CardContent face)
   [Node(part key "movement")"movement"("Move "++title)Roles.Content(MovableCard face(card_destinations snapshot s board_parent candidates value))[];
    declared key Roles.Button(secondary "open"("打开 "++title)(Input.OpenInformation(State.CardDetails id)(part key "open")));
    more key(CardActions id)].
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
   [declared parent Roles.Button(secondary "working"("正在运行的任务 "++show_natural(value_or 0%N(count_working snapshot)))(Input.BoardTab "working"))];
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
   (match Projection.visible_cards snapshot s with
    |None=>[read_only parent "pending" "Board" "Waiting for current board observations"]
    |Some cards=>let candidates:=value_or[](Read.board_cards snapshot)in
     map(fun stage=>let key:=part parent(BoardDomain.stage_name stage)in
      let entries:=filter(fun card=>String.eqb(BoardDomain.stage_name(Read.card_stage card))(BoardDomain.stage_name stage))cards in
      Node key "board-lane"(BoardDomain.stage_label stage)Roles.Section
        (BoardLane(BoardDomain.stage_name stage)(N.of_nat(List.length entries)))
        (group_title key(BoardDomain.stage_label stage)::
         declared key Roles.Button(secondary "card/new" "新建任务"(Input.NewCard stage(part key "card/new")))::
         map(card_node snapshot s parent candidates key)(Read.display_cards entries)))BoardDomain.stages end)].
Definition graph_endpoint_label graph name :=
 match Read.graph_endpoint graph name with
 |Some task=>String.concat ""[name;" (Task #";show_natural task;")"]
 |None=>String.append name " (unavailable)"end.
Definition graph_rule_nodes {A} parent graph:list(node A):=map(fun rule=>let key:=part parent(String.append "rule/"(Read.rule_key rule))in
 region parent(String.append "rule/"(Read.rule_key rule))(Read.rule_key rule)Roles.Section
  (group_title key(Read.rule_key rule)::map(fun '(ordinal,action)=>read_only key(show_natural(N.of_nat ordinal))"Output delivery"
    (String.concat ""[graph_endpoint_label graph(rule_source rule);" → ";graph_endpoint_label graph(Read.action_target action);": ";
     TextJson.render_json(Read.action_message action)]))
   (combine(seq 0(List.length(Read.rule_actions rule)))(Read.rule_actions rule))))
  (graph_rules graph).
Definition graph_receipt_nodes {A} parent graph:list(node A):=map(fun '(ordinal,receipt)=>
 read_only parent(String.append "receipt/"(show_natural(N.of_nat ordinal)))"Last delivery result"
  (String.concat ""["Task #";show_natural(receipt_source receipt);" → Task #";show_natural(receipt_target receipt);
   " (";receipt_rule receipt;"): ";match receipt_reply receipt with JString value=>value|reply=>TextJson.render_json reply end]))
 (combine(seq 0(List.length(graph_receipts graph)))(graph_receipts graph)).
Definition graph_node snapshot s parent value :=
 let id:=graph_id value in
 let key:=part parent("graph/"++show_natural id)in
 region parent("graph/"++show_natural id)(graph_name value)Roles.Card
  ([group_title key(graph_name value);
    declared key Roles.Button(secondary "edit" "Edit task graph"(Input.OpenEditor(graph_editor(Some id)(State.active_work(State.navigation_state s)))(part key "edit")));
    more key(GraphActions id)]++
   [region key "nodes" "Tasks"Roles.Section
    (group_title(part key "nodes")"Tasks"::map(fun entry=>
      let task:=node_task entry in
      let node_key:=part key(String.append "node/"(Read.node_key entry))in
      Node node_key "task-graph/node" ""Roles.Section(ObjectGroup(Selvedge.Interaction.Experience.Model.TaskObject task))
       (group_title node_key(String.concat ""[Read.node_key entry;" · Task #";show_natural task])::
        match find_task task snapshot with
        |Some task=>[Navigation.task_entry_tree(State.location(State.navigation_state s))node_key(TaskTree task [])]
        |None=>[read_only node_key "status" "Task status" "Unavailable"]end))(graph_nodes value));
    region key "rules" "Output rules"Roles.Section(graph_rule_nodes key value);
    region key "receipts" "Last delivery results"Roles.Section(graph_receipt_nodes key value)])%list.
Definition graphs_page snapshot s parent :=
 [page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "Task graphs"];
  page_region parent Composition.CollectionActions Composition.HeadingPosition
   [declared parent Roles.PrimaryButton(primary "graph/new" "New task graph"(Input.OpenEditor(graph_editor None(State.active_work(State.navigation_state s)))(part parent "graph/new")))];
  page_region parent Composition.TaskGraphEntries Composition.BodyPosition
   (match scoped_graphs(State.active_work(State.navigation_state s))snapshot with
    |Some entries=>map(graph_node snapshot s parent)entries
    |None=>[read_only parent "unavailable" "Task graphs" "Task graph observations unavailable"]end)].
