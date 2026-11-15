From Selvedge.Kernel Require Commands.
From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Programming Require Graphics.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require Domain BoardFilter.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Interaction Require World.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Interaction.Submission Require GraphAuthoring.
From Selvedge.Interaction.Interactive Require Presentation.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input ObjectActions.
From Selvedge.Browser.Session Require State Authoring Services.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection Navigation.
From Selvedge.Browser.Presentation Require Editors Roles Information Composition TaskGraphCanvas.
Import ListNotations.
Open Scope string_scope.
Module BoardDomain := Selvedge.Features.Domain.
Definition more parent subject :=declared parent Roles.Button
 (secondary "more" (ObjectActions.menu_label subject)(Input.OpenObjectActions subject(part parent "more"))).
Definition browse_heading {A} parent leading (trailing : list (node A)) :=
 region parent "workspace-browse-heading" "" Roles.Section (leading :: trailing).
Definition projects_page snapshot s parent :=
 let project_list:=projects snapshot in
 let create:=declared parent Roles.PrimaryButton(primary "project/new" "新建项目"(Input.OpenEditor(Identity.Project None)(part parent "project/new")))in
 [browse_heading parent
   (page_region parent Composition.CollectionTitle Composition.HeadingPosition
     [title parent "项目";
      information parent "project-purpose" Information.Description "项目归类对话，并提供默认工作目录和指引。"])
   (match project_list with Some []=>[]|_=>[page_region parent Composition.CollectionActions Composition.HeadingPosition [create]]end);
  page_region parent Composition.ProjectEntries Composition.BodyPosition
   (match project_list,tasks snapshot with
   |Some [],_=>[region parent "project/empty" "" Roles.Section
      [information parent "project/empty-description" Information.Description "还没有项目。";create]]
   |Some values,Some tasks=>map(Navigation.project_entry snapshot s(State.location(State.navigation_state s))parent tasks)values
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
  (Read.card_priority value)(Read.card_pinned value)(Read.card_activity_label snapshot value)
  (Read.card_project_label snapshot(Read.card_project value))(Read.card_labels value)
  (match Read.card_owner value with BoardDomain.Unassigned=>""|owner=>Read.card_owner_label snapshot owner end)
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
Definition card_conversation snapshot parent value activity :=
 let identity:="card/conversation" in
 match Read.card_task value with
 |None=>if Read.card_archived value then [] else
   [declared parent Roles.Button(secondary identity "关联对话"
     (Input.OpenCardDecision(Read.card_id value)CardDecisions.LinkCard(part parent identity)))]
 |Some task=>
   let open_conversation availability description:=
    Node(part parent identity)identity "打开对话" Roles.Button
      (Activate(Control identity "打开对话" Secondary (Input.Navigate(Conversation task)) availability))
      description in
   match Read.find_task task snapshot with
   |Some _=>[open_conversation Available (if String.eqb activity "" then [] else
      [information (part parent identity) "card/conversation-activity" Information.Description activity])]
   (* DEFENSE: A linked conversation can be absent from the current observation. *)
   |None=>[open_conversation(Unavailable "关联的对话不可用") []]
   end
 end.
Definition card_node snapshot s board_parent candidates parent value :=
 let id:=Read.card_id value in
 let key:=part parent("card/"++show_natural id)in
 let action_parent:=part board_parent("card/"++show_natural id)in
 let face:=card_face snapshot s value in
 let title:=Read.card_title value in
 let status:=Model.card_status face in
 (* Card enrichment takes precedence over linked execution in BoardFacts.activity. *)
 let activity:=match Read.card_task value,Read.card_generation value with
  |Some _,Read.Idle=>("",status)
  |_,_=>(status,"")end in
 let card_activity:=fst activity in
 Node key "card" title Roles.Card(CardContent face)
   ([Node(part key "movement")"movement"("Move "++title)Roles.Content(MovableCard face(card_destinations snapshot s board_parent candidates value))[];
     declared key Roles.Button(secondary "open"("打开 "++title)(Input.OpenInformation(State.CardDetails id)(part key "open")));
     declared action_parent Roles.Button(secondary "more" "卡片操作"(Input.OpenObjectActions(CardActions id)(part action_parent "more")))] ++
     (if String.eqb card_activity "" then [] else
       [information key "card/activity" Information.Description card_activity]) ++
     card_conversation snapshot key value(snd activity))%list.
Definition board_group {A} parent key grouping (children:list(node A)):=Node(part parent key)key ""Roles.Toolbar(BoardGroup grouping)children.
Definition board_toolbar snapshot s parent :=
 let selection:=State.board_selection s in
 let tab key label:=Node(part parent("view/"++key))(if String.eqb key "working" then "board/working" else "board/view")label Roles.Button
   (Choice SingleChoice(String.eqb key(BoardFilter.tab_name(BoardFilter.filter_tab selection)))""
     (secondary("view/"++key)label(Input.BoardTab key)))[] in
 let working:="仅执行中"++match bind(State.now s)(count_working snapshot selection)with
   |Some count=>" · "++show_natural count|None=>""end in
 [board_group parent "view-choices" ViewChoices
   [tab "all" "全部卡片";tab "assigned" "分配给我";tab "unassigned" "未分配";
    tab "working" working;
    declared parent Roles.Button(secondary "filters" "筛选卡片"(Input.OpenBoard State.BoardFilters(part parent "filters")))];
  board_group parent "search-area" SearchArea
   [Node(part parent "search")"board-search" "搜索卡片"Roles.Field
     (BoardSearch selection(fun value=>option_map Input.BoardQuery(as_string value)))[]];
  board_group parent "secondary-actions" SecondaryActions
   [declared parent Roles.Button(secondary "settings" "看板设置"(Input.OpenBoard State.BoardSettings(part parent "settings")));
    Node(part parent "archive-destination")"board/archive" "归档卡片"Roles.Section
     (CardArchive(N.of_nat(List.length(value_or[](archived_cards snapshot)))))
     [declared(part parent "archive-destination")Roles.Button(secondary "open" "归档卡片"(Input.OpenBoard State.ArchivedCards(part(part parent "archive-destination")"open")))]]].
Definition board_page snapshot s parent :=
 let cards:=Projection.visible_cards snapshot s in
 let empty:list(node Input.input):=match cards,BoardFilter.filter_tab(State.board_selection s)with
  |Some [],BoardFilter.Working=>[information parent "board/working-empty" Information.Status "没有正在执行的卡片"]
  |_,_=>[]end in
 ([browse_heading parent
   (page_region parent Composition.BoardTitle Composition.HeadingPosition
     [title parent "卡片看板";
      information parent "board-scope" Information.Description "卡片可以关联已有对话，也可以交给模型启动新对话。"])
   [board_group parent "primary-action" PrimaryAction
     [declared parent Roles.PrimaryButton(primary "card/new" "新建卡片"(Input.NewCard BoardDomain.Backlog(part parent "card/new")))]];
  page_region parent Composition.BoardControls Composition.HeadingPosition(board_toolbar snapshot s parent)] ++ empty ++
 [page_region parent Composition.BoardStages Composition.BodyPosition
   (match cards with
    |None=>[information parent "pending" Information.Description "正在加载看板。"]
    |Some cards=>let candidates:=value_or[](Read.board_cards snapshot)in
     map(fun stage=>let key:=part parent(BoardDomain.stage_name stage)in
      let entries:=filter(fun card=>String.eqb(BoardDomain.stage_name(Read.card_stage card))(BoardDomain.stage_name stage))cards in
      Node key "board-lane"(BoardDomain.stage_label stage)Roles.Section
        (BoardLane(BoardDomain.stage_name stage)(N.of_nat(List.length entries)))
        (group_title key(BoardDomain.stage_label stage)::
         declared key Roles.Button(secondary "card/new" ("新建卡片 · "++BoardDomain.stage_label stage)(Input.NewCard stage(part key "card/new")))::
         map(card_node snapshot s parent candidates key)(Read.display_cards entries)))BoardDomain.stages end)])%list.
Definition graph_endpoint_label graph name :=
 match Read.graph_endpoint graph name with
 |Some task=>String.concat ""[name;"（对话 #";show_natural task;"）"]
 |None=>String.append name "（不可用）"end.
Definition graph_rule_nodes {A} parent graph:list(node A):=map(fun rule=>let key:=part parent(String.append "rule/"(Read.rule_key rule))in
 region parent(String.append "rule/"(Read.rule_key rule))(Read.rule_key rule)Roles.Section
  (information key "rule-name" Information.FieldLabel (Read.rule_key rule)::map(fun '(ordinal,action)=>read_only key(show_natural(N.of_nat ordinal))"发送规则"
    (String.concat ""[graph_endpoint_label graph(rule_source rule);" → ";graph_endpoint_label graph(Read.action_target action);": ";
     TextJson.render_json(Read.action_message action)]))
   (combine(seq 0(List.length(Read.rule_actions rule)))(Read.rule_actions rule))))
  (graph_rules graph).
Definition graph_receipt_nodes {A} parent graph:list(node A):=map(fun '(ordinal,receipt)=>
 read_only parent(String.append "receipt/"(show_natural(N.of_nat ordinal)))"最近发送结果"
  (String.concat ""["对话 #";show_natural(receipt_source receipt);" → 对话 #";show_natural(receipt_target receipt);
   " (";receipt_rule receipt;"): ";match receipt_reply receipt with JString value=>value|reply=>TextJson.render_json reply end]))
 (combine(seq 0(List.length(graph_receipts graph)))(graph_receipts graph)).
Definition graph_placement parent name label role place children : node Input.input :=
  Node (part parent name) name label role (InteractivePlacement place) children.

Definition graph_task_card snapshot parent placed :=
  let entry := TaskGraphCanvas.entry placed in
  let task := Read.node_task entry in
  let key := part parent (String.append "node/" (Read.node_key entry)) in
  let label := String.concat "" [Read.node_key entry; " · 对话 #"; show_natural task] in
  let placement := Presentation.GraphNode Presentation.RootFontScale
    (TaskGraphCanvas.left placed) (TaskGraphCanvas.top placed)
    (Z.to_N TaskGraphCanvas.node_width) (Z.to_N TaskGraphCanvas.node_height) false in
  Node key "task-graph/node" label Roles.Section (InteractivePlacement placement)
    (match find_task task snapshot with
     | Some entry =>
         let title := task_title entry in
         let project := match task_project entry with
           | Some id => value_or ("项目 #" ++ show_natural id)
               (option_map project_name (find_project id snapshot))
           | None => "未归入项目"
           end in
         let open_key := part key "open" in
         [Node open_key "task-graph/open" title Roles.Button
           (Activate (secondary "open" title (Input.Navigate (Conversation task))))
           [information open_key "task-graph/title" Information.OptionLabel title;
            information open_key "task-graph/project" Information.Description project]]
     | None => [read_only key "status" label "对话不可用"]
     end).

Definition graph_canvas snapshot parent graph :=
  let layout := TaskGraphCanvas.arrange (A:=Input.input) graph in
  let drawing := TaskGraphCanvas.edges layout in
  let viewport := part parent "task-graph/viewport" in
  let canvas := part viewport "task-graph/canvas" in
  let edges := part canvas "edges" in
  graph_placement parent "task-graph/viewport" "任务图画布" Roles.Section
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
  ([region key "task-graph/actions" "任务图操作" Roles.Toolbar
    [group_title key (graph_name value);
     declared key Roles.Button(secondary "edit" Editors.graph_edit_label (Input.OpenEditor(graph_editor(Some id)(State.active_work(State.navigation_state s)))(part key "edit")));
     more key(GraphActions id)]] ++
   (match graph_nodes value with
    | [] => [read_only key "nodes" "" "此任务图还没有对话。"]
    | _ => [information key "task-graph/direction" Information.Description
              "来源对话的回复沿箭头传给接收对话。";
            graph_canvas snapshot key value]
    end) ++
   [region key "task-graph/rules" "发送规则" Roles.Section
      (group_title (part key "task-graph/rules") "发送规则" :: graph_rule_nodes key value);
    region key "task-graph/receipts" "最近发送结果" Roles.Section
      (group_title (part key "task-graph/receipts") "最近发送结果" :: graph_receipt_nodes key value)])%list.
Definition workflow_field key value := value_or "" (string_field key value).
Definition workflow_list key value := value_or [] (array_field key value).
Definition workflow_scope selected value := match selected with
 | None => true | Some id => match natural_field "work_id" value with Some work => N.eqb work id | None => false end end.
Definition same_workflow_canvas first second :=
 forallb (fun key => Json.equal (value_or JNull (field key first)) (value_or JNull (field key second)))
   ["workflow_id";"nodes";"connections"].
Definition active_workflow_path path := match bool_field "active" path with
 | Some active => active | None => false end.
Definition workflow_instance_label id := "实例 #" ++ show_natural id.
Definition inspect_instance parent key label id :=
 secondary key label (Input.OpenInformation (State.WorkflowInstanceDetails id) (part parent key)).
Definition instance_color (id:N) :=
 String.concat "" ["hsl(";show_natural (N.modulo (id * 137) 360); " 72% 49%)"].
Definition workflow_markers snapshot definition node parent : Surface.node Input.input :=
 let markers : list (Surface.node Input.input) := flat_map (fun instance =>
  if match field "definition" instance with Some graph => same_workflow_canvas graph definition | None => false end then
   let active := filter (fun path => String.eqb node (workflow_field "node" path) &&
     active_workflow_path path) (workflow_list "paths" instance) in
   match active, natural_field "instance_id" instance with
   | _ :: _, Some id =>
     let details := String.concat "、" (map (fun path =>
       "#" ++ show_natural (value_or 0%N (natural_field "task_id" path))) active) in
     let key := "instance/" ++ show_natural id in
     let label := workflow_instance_label id ++ " · 对话 " ++ details in
     let control := inspect_instance parent key label id in
     let marker := part parent key in
     [Node marker "workflow-instance-marker" label Roles.Button (Activate control)
       [Node (part marker "dot") "workflow-instance-dot" "" Roles.Decorative
         (ReadOnly (instance_color id)) []]]
   | _, _ => [] end else []) (workflow_list "workflow_instances" snapshot) in
 region parent "workflow-instance-markers" "" Roles.Section markers.
Definition workflow_canvas snapshot parent compact definition :=
 let nodes := map (fun value => Read.GraphNode (workflow_field "key" value) 0%N) (workflow_list "nodes" definition) in
 let routes := map (fun edge => (workflow_field "source" edge, workflow_field "target" edge))
   (workflow_list "connections" definition) in
 let geometry := TaskGraphCanvas.workflow_geometry compact in
 let layout := TaskGraphCanvas.arrange_flow (A:=Input.input) geometry true nodes routes in
 let drawing := TaskGraphCanvas.edges layout in
 let viewport := part parent "task-graph/viewport" in
 let canvas := part viewport "task-graph/canvas" in
 let edges := part canvas "edges" in
 region parent "task-graph/viewport" "工作流图" Roles.Section
 [graph_placement viewport "task-graph/canvas" "" Roles.Content
  (Presentation.GraphCanvas Presentation.RootFontScale (Npos (Graphics.width drawing)) (Npos (Graphics.height drawing)))
  (graph_placement canvas "edges" "" Roles.Content Presentation.GraphEdges
   [Node (part edges "drawing") "task-graph/edges" "" Roles.Content (Graphic drawing) []] ::
   map (fun placed =>
     let name := Read.node_key (TaskGraphCanvas.entry placed) in
     let key := part canvas ("node/" ++ name) in
     let kind := value_or "" (option_map (workflow_field "kind")
       (find (fun n => String.eqb name (workflow_field "key" n)) (workflow_list "nodes" definition))) in
     let caption := match kind with "entrance"=>"入口"|"exit"=>"出口"|_=>"任务"end in
     Node key "workflow-node" name Roles.Section
      (InteractivePlacement (Presentation.GraphNode Presentation.RootFontScale
        (TaskGraphCanvas.left placed) (TaskGraphCanvas.top placed)
        (Z.to_N (TaskGraphCanvas.card_width geometry)) (Z.to_N (TaskGraphCanvas.card_height geometry)) false))
      [Node (part key "workflow-node-name") "workflow-node-name" name Roles.Content ContentDisclosure [];
       information key ("workflow-node-kind/" ++ kind) Information.Description caption;
       workflow_markers snapshot definition name key])
   (TaskGraphCanvas.nodes layout))].
Definition workflow_instance_summary parent value :=
 let id := value_or 0%N (natural_field "instance_id" value) in
 let key := "instance/" ++ show_natural id in
 declared parent Roles.Button
   (inspect_instance parent key (workflow_instance_label id ++ " · " ++ Read.workflow_instance_status value) id).
Definition workflow_instances snapshot id :=
 filter (fun value => match natural_field "workflow_id" value with
   | Some origin => N.eqb id origin | None => false end) (workflow_list "workflow_instances" snapshot).
Definition workflow_history snapshot parent id :=
 match rev (workflow_instances snapshot id) with
 |[]=>[information parent "empty" Information.Description "还没有运行记录。"]
 |runs=>map (fun run=>
   let index:=show_natural (value_or 0%N (natural_field "instance_id" run)) in
   let key:=part parent ("run/"++index) in
   region parent ("run/"++index) "" Roles.Section
    [workflow_instance_summary key run;
     information key "workflow-run-entrance" Information.Description ("入口 · "++workflow_field "entrance" run);
     information key "workflow-run-message" Information.Description (workflow_field "message_preview" run)]) runs
 end.
Definition workflow_instance_details snapshot parent value :=
 let workflow := value_or "" (bind (field "definition" value) (string_field "name")) in
 let task_ids := nodup N.eq_dec (flat_map (fun occurrence =>
   match natural_field "task_id" occurrence with Some task=>[task]|None=>[]end) (workflow_list "tasks" value)) in
 let links := map (fun task =>
   let text := value_or ("对话 #" ++ show_natural task)%string (option_map task_title (find_task task snapshot)) in
   let key := "task/" ++ show_natural task in
   declared parent Roles.Button (secondary key text (Input.InspectWorkflowTask task (part parent key)))) task_ids in
 let results := flat_map (fun path =>
   let suffix := show_natural (value_or 0%N (natural_field "path_id" path)) in
   let node := workflow_field "node" path in
   let route := match string_field "source" path with
     | Some source => String.concat "" [source; " → "; node] | None => node end in
   let label := String.concat "" ["路径 #"; suffix; " · "; route] in
   match string_field "result" path, string_field "reason" path with
   | Some output, _ =>
     let result := part parent ("exit/" ++ suffix) in
     [Node result "workflow-exit-result" ("出口结果 · " ++ label) Roles.Section
       ContentDisclosure [read_only result "workflow-exit-output" "出口结果" output]]
   | _, Some reason => [read_only parent ("failure/" ++ suffix) ("阻塞原因 · " ++ label) reason]
   | _, _ => [] end) (workflow_list "paths" value) in
 ([read_only parent "workflow-name" "工作流" workflow;
   information parent "instance-status" Information.Status (Read.workflow_instance_status value)] ++ links ++ results)%list.
Definition workflow_section_key definition :=
 "workflow/" ++ show_natural (value_or 0%N (natural_field "workflow_id" definition)).
Definition workflow_controls parent definition :=
 let id := value_or 0%N (natural_field "workflow_id" definition) in
 let section := workflow_section_key definition in
 let key := part parent section in
 Node key section "" Roles.Toolbar Region
  [declared key Roles.Button (secondary "edit-workflow" "编辑工作流"
     (Input.OpenEditor (Identity.WorkflowDefinition (Some id) None) (part key "edit-workflow")));
   declared key Roles.Button (secondary "start-workflow" "启动工作流"
     (Input.OpenEditor (Identity.WorkflowStart id) (part key "start-workflow")));
   declared key Roles.Button (secondary "workflow-history" "运行记录"
     (Input.OpenInformation (State.WorkflowHistory id) (part key "workflow-history")))].
Definition workflow_section snapshot parent compact definition :=
 let id := value_or 0%N (natural_field "workflow_id" definition) in
 let section := workflow_section_key definition in
 let key := part parent section in
 let runs := workflow_instances snapshot id in
 let active_runs := filter (fun instance => existsb active_workflow_path (workflow_list "paths" instance)) runs in
 let archived_definitions := fold_right (fun instance collected => match field "definition" instance with
   | Some graph => if same_workflow_canvas graph definition || existsb (same_workflow_canvas graph) collected
     then collected else graph :: collected
   | None => collected end) [] active_runs in
 region parent section (workflow_field "name" definition) Roles.Section
  ([group_title key (workflow_field "name" definition);
    workflow_canvas snapshot key compact definition] ++
   map (fun '(index, graph) =>
     let version := ("saved/" ++ show_natural (N.of_nat index))%string in
     let name := ("运行中的历史版本 " ++ show_natural (N.of_nat index) ++ " · " ++ workflow_field "name" graph)%string in
     region key version name Roles.Section
       [group_title (part key version) name; workflow_canvas snapshot (part key version) compact graph])
     (combine (seq 1 (List.length archived_definitions)) archived_definitions))%list.
Definition ticket_workflow_controls snapshot s parent (card : Read.card) :=
 let id := Read.card_id card in
 let link := Read.ticket_workflow snapshot id in
 let card_args := [("card_id",number id);("revision",number (Read.card_revision card))] in
 let command key caption op fields :=
   match Selvedge.Programming.Schema.decode_command Selvedge.Kernel.Commands.command_specs
     (JObject (("op",JString op) :: fields)) with
   | Some command =>
     let pending := State.pending_command command s in
     let connected := Services.connected (State.service_state s) in
     let request := Input.RequestCommand command in
     let progress := if State.checking_command command s then "正在检查入口切换…" else "正在提交…" in
     let control := if pending then Control key progress Secondary request (Busy progress)
       else if negb connected then Control key caption Secondary request (Unavailable "正在重新连接服务…")
       else match Authoring.command_assessment_failure snapshot s command with
       | Some _ => Control key ("重新检查 · " ++ caption) Secondary (Input.RetryCommandAssessment command) Available
       | None => Control key caption Secondary request
           (value_or Available (option_map domain_availability (Authoring.direct_command_admission snapshot s command))) end in
     [declared parent Roles.Button control]
   | None => [] end in
 let configured : list (node Input.input) := match link with
   | None => []
   | Some value =>
      let workflow := bind (natural_field "workflow_id" value)
        (fun workflow => World.find_world "workflows" "workflow_id" workflow snapshot) in
      let selection := String.concat "" [value_or "" (bind workflow (string_field "name")); " · "; workflow_field "entrance" value] in
      [read_only parent "workflow-entrance" "当前工作流入口" selection] end in
 let options := flat_map (fun graph =>
   let workflow := value_or 0%N (natural_field "workflow_id" graph) in
   flat_map (fun node =>
     if String.eqb (workflow_field "kind" node) "entrance" then
       let entrance := workflow_field "key" node in
       let selected := match link with
         | Some value => match natural_field "workflow_id" value with
           | Some previous => N.eqb previous workflow && String.eqb entrance (workflow_field "entrance" value)
           | None => false end
         | None => false end in
       if selected then [] else command ("workflow-choice/" ++ show_natural workflow ++ "/" ++ entrance)
         (String.concat "" ["选择 ";workflow_field "name" graph; " · ";entrance])
         "configure_ticket_workflow" ([("workflow_id",number workflow);("entrance",JString entrance)] ++ card_args)%list
     else []) (workflow_list "nodes" graph)) (workflow_list "workflows" snapshot) in
 match Read.card_task card, Read.card_archived card with
 | None, false => (configured, options)
 | _, _ => (configured, []) end.
Definition relay_creation work parent :=
 declared parent Roles.Button (secondary "graph/new" Editors.graph_creation_label
   (Input.OpenEditor (graph_editor None work) (part parent "graph/new"))).
Definition relay_contents snapshot s parent :=
 let work:=State.active_work(State.navigation_state s) in
 let create:=relay_creation work parent in
 match scoped_graphs work snapshot with
 |Some []=>[region parent "task-graph/empty" "" Roles.Section
    [group_title (part parent "empty-relay-heading") "暂无对话转发";
     information parent "task-graph/empty-description" Information.Description "把来源对话的新回复发送到接收对话。";
     region parent "task-graph/empty-route" "转发方向" Roles.Section
     [Node (part parent "graph/empty-source") "task-graph/empty-endpoint" "" Roles.Content (ReadOnly GraphAuthoring.source_endpoint_label) [];
      Node (part parent "graph/empty-direction") "task-graph/empty-direction" "" Roles.Decorative (Fact "→") [];
      Node (part parent "graph/empty-target") "task-graph/empty-endpoint" "" Roles.Content (ReadOnly GraphAuthoring.target_endpoint_label) []];
     create]]
 |Some entries=>create :: map (graph_node snapshot s parent) entries
 |None=>[read_only parent "unavailable" task_graphs_label "对话转发暂不可用。"]end.
Definition graphs_page snapshot s parent compact :=
 let work:=State.active_work(State.navigation_state s) in
 let definitions:=rev (filter (workflow_scope work) (workflow_list "workflows" snapshot)) in
 let create_workflow:=declared parent Roles.PrimaryButton
   (primary "workflow/new" "创建工作流"
     (Input.OpenEditor (Identity.WorkflowDefinition None work) (part parent "workflow/new"))) in
 let relay:=declared parent Roles.Button
   (secondary "conversation-relays" "对话转发" (Input.OpenInformation State.ConversationRelays (part parent "conversation-relays"))) in
 [browse_heading parent
   (page_region parent Composition.CollectionTitle Composition.HeadingPosition[title parent task_graphs_label])
   [page_region parent Composition.CollectionActions Composition.HeadingPosition
     (create_workflow :: match definitions with []=>[]|_=>[relay]end)];
  page_region parent Composition.TaskGraphEntries Composition.BodyPosition
   (match definitions with
    |[]=>relay_contents snapshot s parent
    |_=>let key := part parent ("workflow-workspace/" ++ value_or "all" (option_map show_natural work)) in
       let controls := part key "workflow-actions" in
       [Node key "workflow-workspace" "工作流画布" Roles.Section
         (WorkflowWorkspace (map (fun definition => (workflow_section_key definition, workflow_field "name" definition)) definitions))
         (Node controls "workflow-actions" "" Roles.Content Region (map (workflow_controls controls) definitions) ::
          map (workflow_section snapshot key compact) definitions)]
    end)].
