From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Programming Require Graphics.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require Domain BoardFilter.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Interaction.Interactive Require Presentation.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input ObjectActions.
From Selvedge.Browser.Session Require State Authoring.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection Navigation.
From Selvedge.Browser.Presentation Require Roles Information Composition TaskGraphCanvas.
Import ListNotations.
Open Scope string_scope.
Module BoardDomain := Selvedge.Features.Domain.
Definition more parent subject :=declared parent Roles.Button
 (secondary "more" "More actions"(Input.OpenObjectActions subject(part parent "more"))).
Definition browse_heading {A} parent leading (trailing : list (node A)) :=
 region parent "workspace-browse-heading" "" Roles.Section (leading :: trailing).
Definition projects_page snapshot s parent :=
 [browse_heading parent
   (page_region parent Composition.CollectionTitle Composition.HeadingPosition
     [title parent "项目";
      information parent "project-purpose" Information.Description "项目归类对话，并提供默认工作目录和指引。"])
   [page_region parent Composition.CollectionActions Composition.HeadingPosition
     [declared parent Roles.PrimaryButton(primary "project/new" "新建项目"(Input.OpenEditor(Identity.Project None)(part parent "project/new")))]];
  page_region parent Composition.ProjectEntries Composition.BodyPosition
   (match projects snapshot,tasks snapshot with
   |Some [],_=>[information parent "empty" Information.Description "还没有项目。"]
   |Some projects,Some tasks=>map(Navigation.project_entry snapshot s(State.location(State.navigation_state s))parent tasks)projects
   |_,_=>[information parent "unavailable" Information.Description "项目列表不可用。"]end)].
Definition project_page snapshot s parent project :=
 let id:=project_id project in
 [browse_heading parent
   (page_region parent Composition.ProjectTitle Composition.HeadingPosition [title parent(project_name project)])
   [page_region parent Composition.ProjectActions Composition.HeadingPosition
     [declared parent Roles.Button(secondary "new-task" "在项目中开始对话"(Input.BeginTask(Some id)));
      declared parent Roles.Button(secondary "more" "项目操作"(Input.OpenObjectActions(ProjectActions id)(part parent "more")))]];
  page_region parent Composition.DefaultWorkspace Composition.BodyPosition
   [read_only parent "workspace-roots" "默认工作目录"(String.concat "
"(Domain.workspace_roots(project_workspace project)));
    read_only parent "workspace-primary" "主目录"(value_or ""(Domain.workspace_primary(project_workspace project)))];
  page_region parent Composition.ProjectGuidance Composition.BodyPosition
   [read_only parent "guidance" "项目指引"(value_or "尚未设置"(project_instructions project))];
  page_region parent Composition.ProjectTasks Composition.BodyPosition
   (information parent "project/conversations" Information.GroupTitle "项目中的对话" ::
    match Projection.project_members snapshot id with
    |Some []=>[information parent "tasks-empty" Information.Description "这个项目还没有对话。"]
    |Some values=>map(task_entry_tree(State.location(State.navigation_state s))(State.collapsed_tasks s)parent)(forest values)
    |None=>[information parent "tasks-unavailable" Information.Description "对话列表不可用。"]end)].
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
        (Control "archive" "归档卡片"Secondary(Input.Command command)(domain_availability(Authoring.command_availability snapshot s command)))]end end)
 |None=>[]end.
Definition card_conversation snapshot parent value :=
 let identity:="card/conversation" in
 match Read.card_task value with
 |None=>if Read.card_archived value then [] else
   [declared parent Roles.Button(secondary identity "关联对话"
     (Input.OpenCardDecision(Read.card_id value)CardDecisions.LinkCard(part parent identity)))]
 |Some task=>
   let availability:=match Read.find_task task snapshot with
   |Some _=>Available
   (* DEFENSE: A linked conversation can be absent from the current observation. *)
   |None=>Unavailable "关联的对话不可用"
   end in
   [declared parent Roles.Button(Control identity "打开对话" Secondary (Input.Navigate(Conversation task)) availability)]
 end.
Definition card_node snapshot s board_parent candidates parent value :=
 let id:=Read.card_id value in
 let key:=part parent("card/"++show_natural id)in
 let action_parent:=part board_parent("card/"++show_natural id)in
 let face:=card_face snapshot s value in
 let title:=Read.card_title value in
 Node key "card" title Roles.Card(CardContent face)
   ([Node(part key "movement")"movement"("Move "++title)Roles.Content(MovableCard face(card_destinations snapshot s board_parent candidates value))[];
     declared key Roles.Button(secondary "open"("打开 "++title)(Input.OpenInformation(State.CardDetails id)(part key "open")));
     declared action_parent Roles.Button(secondary "more" "卡片操作"(Input.OpenObjectActions(CardActions id)(part action_parent "more")))] ++
     card_conversation snapshot key value)%list.
Definition board_group {A} parent key grouping (children:list(node A)):=Node(part parent key)key ""Roles.Toolbar(BoardGroup grouping)children.
Definition board_toolbar snapshot s parent :=
 let selection:=State.board_selection s in
 let tab key label:=Node(part parent("view/"++key))"board/view"label Roles.Button
   (Choice SingleChoice(String.eqb key(BoardFilter.tab_name(BoardFilter.filter_tab selection)))""
     (secondary("view/"++key)label(Input.BoardTab key)))[] in
 let working:="执行中的卡片"++match bind(State.now s)(count_working snapshot selection)with
   |Some count=>" "++show_natural count|None=>""end in
 [board_group parent "view-choices" ViewChoices
   [tab "all" "全部卡片";tab "assigned" "分配给我";tab "unassigned" "未分配";tab "working" working];
  board_group parent "search-area" SearchArea
   [Node(part parent "search")"board-search" "搜索卡片"Roles.Field
     (BoardSearch selection(fun value=>option_map Input.BoardQuery(as_string value)))[]];
  board_group parent "secondary-actions" SecondaryActions
   [declared parent Roles.Button(secondary "filters" "筛选卡片"(Input.OpenBoard State.BoardFilters(part parent "filters")));
    declared parent Roles.Button(secondary "settings" "看板设置"(Input.OpenBoard State.BoardSettings(part parent "settings")));
    Node(part parent "archive-destination")"board/archive" "归档卡片"Roles.Section
     (CardArchive(N.of_nat(List.length(value_or[](archived_cards snapshot)))))
     [declared(part parent "archive-destination")Roles.Button(secondary "open" "归档卡片"(Input.OpenBoard State.ArchivedCards(part(part parent "archive-destination")"open")))]]].
Definition board_page snapshot s parent :=
 [browse_heading parent
   (page_region parent Composition.BoardTitle Composition.HeadingPosition
     [title parent "卡片看板";
      information parent "board-scope" Information.Description "卡片可以关联已有对话，也可以交给模型启动新对话。"])
   [board_group parent "primary-action" PrimaryAction
     [declared parent Roles.PrimaryButton(primary "card/new" "新建卡片"(Input.NewCard BoardDomain.Backlog(part parent "card/new")))]];
  page_region parent Composition.BoardControls Composition.HeadingPosition(board_toolbar snapshot s parent);
  page_region parent Composition.BoardStages Composition.BodyPosition
   (match Projection.visible_cards snapshot s with
    |None=>[information parent "pending" Information.Description "正在加载看板。"]
    |Some cards=>let candidates:=value_or[](Read.board_cards snapshot)in
     map(fun stage=>let key:=part parent(BoardDomain.stage_name stage)in
      let entries:=filter(fun card=>String.eqb(BoardDomain.stage_name(Read.card_stage card))(BoardDomain.stage_name stage))cards in
      Node key "board-lane"(BoardDomain.stage_label stage)Roles.Section
        (BoardLane(BoardDomain.stage_name stage)(N.of_nat(List.length entries)))
        (group_title key(BoardDomain.stage_label stage)::
         declared key Roles.Button(secondary "card/new" ("新建卡片 · "++BoardDomain.stage_label stage)(Input.NewCard stage(part key "card/new")))::
         map(card_node snapshot s parent candidates key)(Read.display_cards entries)))BoardDomain.stages end)].
Definition graph_endpoint_label graph name :=
 match Read.graph_endpoint graph name with
 |Some task=>String.concat ""[name;" (Task #";show_natural task;")"]
 |None=>String.append name " (unavailable)"end.
Definition graph_rule_nodes {A} parent graph:list(node A):=map(fun rule=>let key:=part parent(String.append "rule/"(Read.rule_key rule))in
 region parent(String.append "rule/"(Read.rule_key rule))(Read.rule_key rule)Roles.Section
  (information key "rule-name" Information.FieldLabel (Read.rule_key rule)::map(fun '(ordinal,action)=>read_only key(show_natural(N.of_nat ordinal))"Output delivery"
    (String.concat ""[graph_endpoint_label graph(rule_source rule);" → ";graph_endpoint_label graph(Read.action_target action);": ";
     TextJson.render_json(Read.action_message action)]))
   (combine(seq 0(List.length(Read.rule_actions rule)))(Read.rule_actions rule))))
  (graph_rules graph).
Definition graph_receipt_nodes {A} parent graph:list(node A):=map(fun '(ordinal,receipt)=>
 read_only parent(String.append "receipt/"(show_natural(N.of_nat ordinal)))"Last delivery result"
  (String.concat ""["Task #";show_natural(receipt_source receipt);" → Task #";show_natural(receipt_target receipt);
   " (";receipt_rule receipt;"): ";match receipt_reply receipt with JString value=>value|reply=>TextJson.render_json reply end]))
 (combine(seq 0(List.length(graph_receipts graph)))(graph_receipts graph)).
Definition graph_placement parent name label role place children : node Input.input :=
  Node (part parent name) name label role (InteractivePlacement place) children.

Definition graph_task_card snapshot parent placed :=
  let entry := TaskGraphCanvas.entry placed in
  let task := Read.node_task entry in
  let key := part parent (String.append "node/" (Read.node_key entry)) in
  let label := String.concat "" [Read.node_key entry; " · Task #"; show_natural task] in
  let placement := Presentation.GraphNode Presentation.RootFontScale
    (TaskGraphCanvas.left placed) (TaskGraphCanvas.top placed)
    (Z.to_N TaskGraphCanvas.node_width) (Z.to_N TaskGraphCanvas.node_height) false in
  Node key "task-graph/node" label Roles.Section (InteractivePlacement placement)
    (match find_task task snapshot with
     | Some entry =>
         let title := task_title entry in
         let project := match task_project entry with
           | Some id => value_or ("Project #" ++ show_natural id)
               (option_map project_name (find_project id snapshot))
           | None => "No project"
           end in
         let open_key := part key "open" in
         [Node open_key "task-graph/open" title Roles.Button
           (Activate (secondary "open" title (Input.Navigate (Conversation task))))
           [information open_key "task-graph/title" Information.OptionLabel title;
            information open_key "task-graph/project" Information.Description project]]
     | None => [read_only key "status" label "Task unavailable"]
     end).

Definition graph_canvas snapshot parent graph :=
  let layout := TaskGraphCanvas.arrange (A:=Input.input) graph in
  let drawing := TaskGraphCanvas.edges layout in
  let viewport := part parent "task-graph/viewport" in
  let canvas := part viewport "task-graph/canvas" in
  let edges := part canvas "edges" in
  graph_placement parent "task-graph/viewport" "Task graph canvas" Roles.Section
    Presentation.GraphViewport
    [graph_placement viewport "task-graph/canvas" "" Roles.Content
      (Presentation.GraphCanvas Presentation.RootFontScale (Npos (Graphics.width drawing)) (Npos (Graphics.height drawing)))
      (graph_placement canvas "edges" "" Roles.Content Presentation.GraphEdges
        [Node (part edges "drawing") "task-graph/edges" "" Roles.Content (Graphic drawing) []] ::
        map (graph_task_card snapshot canvas) (TaskGraphCanvas.nodes layout))].

Definition graph_node snapshot s parent value :=
 let id:=graph_id value in
 let key:=part parent("graph/"++show_natural id)in
 Node key "task-graph/group" (graph_name value) Roles.Section Region
  ([region key "task-graph/actions" "Task graph actions" Roles.Toolbar
    [group_title key (graph_name value);
     declared key Roles.Button(secondary "edit" "Edit task graph"(Input.OpenEditor(graph_editor(Some id)(State.active_work(State.navigation_state s)))(part key "edit")));
     more key(GraphActions id)]] ++
   (match graph_nodes value with
    | [] => [read_only key "nodes" "" "No tasks in this graph."]
    | _ => [information key "task-graph/direction" Information.Description
              "Arrows show how output from a source conversation is delivered to a target conversation.";
            graph_canvas snapshot key value]
    end) ++
   [region key "task-graph/rules" "Output rules" Roles.Section
      (group_title (part key "task-graph/rules") "Output rules" :: graph_rule_nodes key value);
    region key "task-graph/receipts" "Last delivery results" Roles.Section
      (group_title (part key "task-graph/receipts") "Last delivery results" :: graph_receipt_nodes key value)])%list.
Definition graphs_page snapshot s parent :=
 [browse_heading parent
   (page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent "Task graphs"])
   [page_region parent Composition.CollectionActions Composition.HeadingPosition
     [declared parent Roles.PrimaryButton(primary "graph/new" "New task graph"(Input.OpenEditor(graph_editor None(State.active_work(State.navigation_state s)))(part parent "graph/new")))]];
  page_region parent Composition.TaskGraphEntries Composition.BodyPosition
   (match scoped_graphs(State.active_work(State.navigation_state s))snapshot with
    |Some []=>[read_only parent "empty" "" "Create a task graph to route output between conversations."]
    |Some entries=>map(graph_node snapshot s parent)entries
    |None=>[read_only parent "unavailable" "Task graphs" "Task graph observations unavailable"]end)].
