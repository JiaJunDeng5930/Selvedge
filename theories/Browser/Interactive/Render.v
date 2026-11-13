From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction Require Import CodeSource.
From Selvedge.Browser Require Import CodeBlock DocumentPublication.
From Selvedge.Browser.Scene Require Import Surface.
From Selvedge.Browser.Presentation Require Import Roles.
From Selvedge.Browser.Scene Require Import Model.
From Selvedge.Browser.Presentation Require Import Information.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Vocabulary Registry Types State Sources Expand Plot Presentation.
From Selvedge.Interaction.Interactive Require Runtime.
From Selvedge.Programming Require Import Outcome.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope nat_scope.
Local Infix "+++" := String.append (at level 60, right associativity).
Module S := Selvedge.Browser.Scene.Surface.
Module R := Selvedge.Browser.Presentation.Roles.
Module M := Selvedge.Browser.Scene.Model.
Module IP := Selvedge.Interaction.Interactive.Presentation.
Definition scene := S.node Types.input.
Definition text key value : scene := S.Node key "interactive-markdown/text" "" R.Content (S.Fact value) [].
Definition diagnostic_node key path reason : scene :=
 if String.prefix "@feedback/" path || String.eqb path "@storage" then
  S.Node key "interactive-markdown/status" reason R.Content (S.InformationText Information.Status) []
 else S.Node key "interactive-markdown/diagnostic" "交互内容错误" R.Alert (S.Fact(path+++": "+++reason)) [].
Definition region key children : scene := S.Node key "interactive-markdown/region" "" R.Content S.Region children.
Definition button key label action (active:bool) : scene :=
 S.Node key "interactive-markdown/control" label R.Button
  (S.Activate (M.Control key label M.Secondary action
    (if active then M.Available else M.Unavailable "Control is not available"))) [].
Definition optional_caption key label : list scene :=
 if String.eqb label "" then [] else [text (key+++"/@label") label].
Definition component_caption event_id p : list scene :=
  match p.(description).(component_role) with
  | Field | Action | TextLeaf | MarkdownLeaf | MetricLeaf | Table | Column | Chart => []
  | _ => optional_caption (Types.event_key event_id) (property_text "label" p) end.
Definition component_has_tag tag (node:scene) :=
 match S.node_meaning node with
 |S.InteractiveNode c=>String.eqb tag (component_tag (description (IP.component_properties c)))
 |_=>false end.
Definition metric_comparison_card (node:scene) :=
 component_has_tag "card" node &&
 match S.node_children node with
 |[metric]=>component_has_tag "metric" metric
 |[caption;metric]=>component_has_tag "metric" metric &&
  match S.node_meaning caption with S.Fact _=>true|_=>false end
 |_=>false end.
Definition compact_summary_card (node:scene) :=
 component_has_tag "card" node &&
 match S.node_children node with
 |[caption;status;metric;action]=>
  (match S.node_meaning caption with S.Fact _=>true|_=>false end) &&
  component_has_tag "badge" status && component_has_tag "metric" metric && component_has_tag "button" action
 |_=>false end.
Definition with_children (node:scene) children : scene :=
 S.Node (S.node_key node) (S.semantic_key node) (S.node_label node)
   (S.node_role node) (S.node_meaning node) children.
Definition comparison_card (node:scene) : scene :=
 match S.node_children node with
 |[caption;metric]=>with_children node [metric;caption]
 |_=>node end.
Definition summary_metric_label (node:scene) :=
 match S.node_children node with [ _; _; metric; _ ]=>S.node_label metric|_=>""end.
Definition summary_heading (children:list scene) :=
 match children with
 |first::others=>match others with
   |[]=>None
   |_=>let label:=summary_metric_label first in
     if negb (String.eqb label "") && forallb (fun card=>String.eqb label (summary_metric_label card)) others
     then Some label else None end
 |[]=>None end.
Definition concise_selection (title:string) (selected:bool) (node:scene) : scene :=
 match S.node_meaning node, S.node_children node with
 |S.InteractiveNode component,face::feedback=>
   match IP.component_binding component,S.node_meaning face with
   |ActionLink (Assign _ _) _,S.Activate control=>
     let accessible:=M.control_label control+++" · "+++title in
     let key:=S.node_key face in
     let mark:=S.Node (key+++"/@choice-mark")
       (if selected then "interactive-markdown/summary-choice-selected" else "interactive-markdown/summary-choice")
       "" R.Decorative (S.Fact (if selected then "☑" else "☐")) [] in
     with_children node (S.Node key (S.semantic_key face) accessible (S.node_role face)
       (S.Activate (M.Control (M.control_identity control) accessible (M.control_prominence control)
         (M.control_input control) (M.control_availability control))) [mark]::feedback)
   |_,_=>node end
 |_,_=>node end.
Definition summary_assignment (node:scene) :=
 match S.node_children node with
 |[_;_;_;action]=>match S.node_meaning action with
   |S.InteractiveNode component=>match IP.component_binding component with
     |ActionLink (Assign target value) _=>Some (target,value)|_=>None end
   |_=>None end
 |_=>None end.
(** A row choice writes that row's collection key to the same state as every
    other row. Other assignments keep their authored button faces. *)
Definition summary_selection locals p (children:list scene) : option (list bool) :=
 match children with
 |first::_::_=>match summary_assignment first,collection_keys (property_text "key" p) (property_array "items" p) with
   |Some (target,_),Good keys=>match find_local target locals with
     |Some local=>let current:=key_value (Local.canonical local) in
       if Nat.eqb (List.length keys) (List.length children) then
       match traverse (fun pair=>
         let '(row,key):=pair in
         match summary_assignment row with
         |Some (other,value)=>match key_value value with
           |Some assigned=>if String.eqb target other && String.eqb key assigned then
             Good (match current with Some value=>String.eqb value key|None=>false end)
             else Error "Not a row choice"
           |None=>Error "Not a row choice" end
         |None=>Error "Not a row choice" end) (combine children keys) with
       |Good selected=>Some selected|Error _=>None end else None
     |None=>None end
   |_,_=>None end
 |_=>None end.
Definition compact_summary (shared:option string) (selected:option bool) (node:scene) : scene :=
 match S.node_children node with
 |[caption;status;metric;action]=>
   let metric:=match shared with
     |Some _=>with_children metric (filter (fun child=>
       negb (String.eqb (S.semantic_key child) "interactive-markdown/metric-label")) (S.node_children metric))
     |None=>metric end in
   with_children node
     (match selected with
      |Some value=>[concise_selection (S.node_label node) value action;caption;status;metric]
      |None=>[caption;status;metric;action]
      end)
 |_=>node end.
Definition field_binding (tag:string) (node:scene) :=
 if component_has_tag tag node then
   match S.node_meaning node with
   |S.InteractiveNode component=>match IP.component_binding component with FieldLink id _=>Some id|_=>None end
   |_=>None end
 else None.
Definition range_number_group (range number:scene) : scene :=
 let key:=S.node_key range+++"/@range-number" in
 let heading:=S.node_label range in let detail:=S.node_label number in
 S.Node key "interactive-markdown/range-number" "" R.Content S.Region
  ([S.Node (key+++"/@heading") "interactive-markdown/range-number-heading" heading
    R.Content (S.InformationText Information.FieldLabel) [];range;number]++
   if String.eqb heading detail || String.eqb detail "" then [] else
   [S.Node (key+++"/@detail") "interactive-markdown/range-number-detail" detail
     R.Content (S.InformationText Information.Description) []]).
Fixpoint group_range_numbers (children:list scene) : list scene :=
 match children with
 |range::rest=>match rest with
   |number::remaining=>
     match field_binding "slider" range,field_binding "number-input" number with
     |Some first,Some second=>if String.eqb first second then range_number_group range number::group_range_numbers remaining
       else range::group_range_numbers rest
     |_,_=>range::group_range_numbers rest end
   |[]=>[range] end
 |[]=>[] end.
Definition component_node event_id p binding children locals : scene :=
 let tag:=p.(description).(component_tag) in
 let compact:=String.eqb tag "each" &&
  (match children with []=>false|_=>forallb compact_summary_card children end) in
 let comparison:=String.eqb tag "row-layout" &&
   (match children with _::_::_=>forallb metric_comparison_card children|_=>false end) in
 let presentation:=if compact then "compact-card-list"
  else if comparison then "metric-comparison" else tag in
 let children:=if compact then
   let shared:=summary_heading children in
   (match shared with None=>[]|Some label=>
     [S.Node (Types.event_key event_id+++"/@metric-heading") "interactive-markdown/summary-metric-heading"
       label R.Content (S.InformationText Information.Description) []]end)++
   (match summary_selection locals p children with
   |Some selected=>map (fun row=>compact_summary shared (Some (snd row)) (fst row)) (combine children selected)
   |None=>map (compact_summary shared None) children end)
  else if comparison then map comparison_card children
  else if String.eqb tag "stack" || String.eqb tag "card" then group_range_numbers children else children in
 S.Node (Types.event_key event_id) ("interactive-markdown/"+++presentation)
  (property_text "label" p)
  (match binding with FieldLink _ _=>R.Field|ActionLink _ _=>R.Button|_=>R.Content end)
  (S.InteractiveNode (IP.Component event_id p binding)) (component_caption event_id p++children).
Definition synthetic event_id part tag attrs children : scene :=
 let event_id:=Event event_id.(event_owner) (event_id.(path)+++"/@"+++part) event_id.(occurrence) in
 match Vocabulary.component tag with
 |Some spec=>match Vocabulary.component_values spec (("id",JString part)::attrs) with
   |Some values=>component_node event_id (Properties spec values) (Passive true) children []
   |None=>region (Types.event_key event_id) children end
 |None=>region (Types.event_key event_id) children end.
Definition toolbar event_id part children : scene :=
 S.Node (Types.event_key event_id+++"/@"+++part) "interactive-markdown/toolbar" "" R.Toolbar S.Region children.
Definition scalar_text value := match value with JString s|JNumber s=>s|JBool b=>if b then "true" else "false"|_=>"" end.
Definition formatted_value value style := match value with
 |JNumber source=>if String.eqb style "" then source else
   match decimal_value value with
   |Some d=>match formatted d style with Good s=>s|Error e=>"显示错误："+++e end
   |None=>"显示错误：Invalid number" end
 |_=>scalar_text value end.
Definition metric p := match property "value" p with
 |Some value=>formatted_value value (property_text "format" p)|None=>"" end.
Definition render_metric key p : list scene :=
 let part name value := S.Node (key+++"/@"+++name) ("interactive-markdown/metric-"+++name)
   "" R.Content (S.Fact value) [] in
 let label:=property_text "label" p in
 (if String.eqb label "" then [] else [part "label" label])++[part "value" (metric p)].

Theorem unformatted_number_preserves_its_text source :
 formatted_value (JNumber source) "" = source.
Proof. reflexivity. Qed.
Definition feedback_text path b := match State.feedback_at path b with
 |Some (FeedbackEntry _ (Waiting _ _ _))|Some (FeedbackEntry _ (CopyingDefinition _))=>"Pending"
 |Some (FeedbackEntry _ (Answered _ _ message))=>message
 |_=>"" end.
Definition field_scene identity event_id p binding local (active:bool) : scene :=
 let tag:=p.(description).(component_tag) in
 let display:=if String.eqb tag "slider"||String.eqb tag "checkbox"||String.eqb tag "select"
   then Local.canonical local else JString local.(Local.raw) in
 let editor:=IP.Editor (IP.Component event_id p binding) local.(Local.local_shape) local.(Local.validation) display (Some local.(Local.raw)) active
   (if active then Some (fun value=>Some (ValueChanged event_id value)) else None) in
 S.Node (Types.event_key event_id+++"/@input") (Types.event_key event_id) (property_text "label" p)
  R.Field (S.InteractiveEdit identity event_id.(path) editor)
  (match local.(validation) with
   |Some reason=>[S.Node (Types.event_key event_id+++"/@input/validation")
     "interactive-markdown/validation" reason R.Alert (S.InformationText Information.Status) []]
   |None=>[] end).
Definition table_columns children := fold_right (fun node rest=>match node with
 |Mounted _ p _ _=>if match p.(description).(component_role) with Column=>true|_=>false end then p::rest else rest
 |_=>rest end) [] children.
Definition table_order rows path b budget := match State.view_at path false b with
 |TableView (Some field) descending _=>Expression.sort_metered field descending rows budget
 |_ =>(Good rows,budget) end.
Definition table_page path b := match State.view_at path false b with TableView _ _ page=>page|_=>0 end.
Definition numeric_value value := match value with JNumber _=>true|_=>false end.
Definition cell_value p row :=
 let value:=get_path (property_text "field" p) row in
 IP.TableCell (formatted_value value (property_text "format" p)) (numeric_value value).
Definition numeric_column p rows :=
 let values:=map (get_path (property_text "field" p)) rows in
 existsb numeric_value values &&
 forallb (fun value=>match value with JNull=>true|_=>numeric_value value end) values.
Definition table_column event_id b (sortable active:bool) rows p : IP.table_column Types.input :=
 let id:=property_text "id" p in
 IP.TableColumn id (property_text "label" p)
  (if sortable then Some (ViewChanged event_id (SortColumn id)) else None) active
  (match State.view_at event_id.(path) false b with
   |TableView (Some current) descending _=>if String.eqb current(property_text "field" p)then Some descending else None|_=>None end)
  (numeric_column p rows).
Definition render_table event_id p b children active ordered : list scene :=
 let key:=Types.event_key event_id in let columns:=table_columns children in
 let caption:=property_text "label" p in
 match ordered with
 |Error reason=>optional_caption key caption++[text (key+++"/@error") reason]
 |Good rows=>let row_count:=List.length rows in
 let last_page:=Bounds.last_table_page_index row_count in
 let page:=Nat.min (table_page event_id.(path) b) last_page in
 let start:=(page*Bounds.table_page)%nat in let visible:=firstn Bounds.table_page (skipn start rows) in
 let summary label := S.Node (key+++"/@page") "interactive-markdown/table-summary"
   label R.Content (S.InformationText Information.Description) [] in
 let count_text:="共 "+++show_nat row_count+++" 行" in
 [S.Node (key+++"/@table") "interactive-markdown/table" caption R.Content
   (S.InteractiveTable (IP.DataTable caption
     (map (table_column event_id b (property_bool false "sortable" p) active visible) columns)
     (map (fun row=>IP.TableRow(TextJson.render_json(get_path(property_text "row-key" p)row))
       (map (fun column=>cell_value column row) columns)) visible))) []]++
 (if Nat.eqb row_count 0 then [summary "暂无数据"]
  else if Nat.eqb last_page 0 then [summary count_text]
  else [toolbar event_id "pages"
  [button (key+++"/@previous") "上一页" (ViewChanged event_id (Page (Nat.pred page))) (active&&Nat.ltb 0 page);
   summary ("第 "+++show_nat (S page)+++" / "+++show_nat (S last_page)+++" 页，"+++count_text);
   button (key+++"/@next") "下一页" (ViewChanged event_id (Page (S page))) (active&&Nat.ltb page last_page)]])
 end.
Definition placement key position children : scene :=
 S.Node key "interactive-markdown/placement" "" R.Content (S.InteractivePlacement position) children.
Definition chart_summary_table event_id p : scene :=
  S.Node (Types.event_key event_id+++"/@data") "interactive-markdown/chart-data" "图表数据" R.Content
    (S.Table "图表数据"
      [Plot.x_title p; Plot.y_title p]
      (map (fun row => [scalar_text (get_path (property_text "x" p) row);
                        scalar_text (get_path (property_text "y" p) row)]) (Plot.chart_rows p))) [].
Definition chart_heading key p : list scene :=
 let label:=property_text "label" p in
 if String.eqb label "" then [] else
   [S.Node (key+++"/@label") "interactive-markdown/chart-title" "" R.Content (S.Fact label) []].
Definition chart_disclosure event_id p : scene :=
 let key:=Types.event_key event_id in
 S.Node (key+++"/@data-disclosure") "interactive-markdown/chart-disclosure" "查看数据" R.Content
   S.ContentDisclosure
   [S.Node (key+++"/@data-region") "interactive-markdown/chart-data-region" "" R.Content
     S.Region [chart_summary_table event_id p]].
Definition render_chart event_id p : list scene :=
 let key:=Types.event_key event_id in
 let count:=List.length (property_array "data" p) in
 chart_heading key p++
 (if Nat.eqb count 0 then [text (key+++"/@empty") "暂无数据"] else
 (match Plot.chart p with
 |Error reason=>[S.Node (key+++"/@error") "interactive-markdown/status" reason R.Content
   (S.InformationText Information.Status) []]
 |Good drawing=>
 [S.Node (key+++"/@viewport") "interactive-markdown/chart-viewport" "图表区域" R.Content
    (S.InteractivePlacement IP.ChartViewport)
    [S.Node (key+++"/@plot") "interactive-markdown/chart"
     (Plot.y_title p+++" / "+++Plot.x_title p+++"；显示 "+++
      show_nat (List.length (Plot.chart_rows p))+++" / "+++show_nat count+++" 行")
     R.Content (S.Graphic drawing) []]]
 end)++[chart_disclosure event_id p]++
 (if Nat.ltb Bounds.chart_points count then
   [text (key+++"/@truncation") ("共 "+++show_nat count+++" 行，图中显示前 "+++show_nat Bounds.chart_points+++" 行。")]
  else [])).
Definition expanded_path node := match node with Mounted event_id _ _ _=>event_id.(path)|Message path _=>path end.
Definition graph_identity node := match string_field "identity" node with Some id=>id|None=>"" end.
Definition graph_task_status node :=
 (* DEFENSE: A retained graph node can outlive its Task; the live snapshot then
    omits the corresponding task/status metadata. *)
 let task:=match field "task" node with Some task=>task|None=>JNull end in
 let text name:=match string_field name task with Some value=>value|None=>"" end in
 text "title"+++" · "+++
 (match string_field "statusLabel" task with Some value=>value|None=>"任务不存在" end)+++" · "+++text "phase".
Definition graph_item event_id p b expanded rendered active index node : scene :=
 let id:=graph_identity node in let key:=Types.event_key event_id+++"/@node/"+++TextJson.quote id in
 let '(zoom,x,y,fit,_):=Plot.graph_view event_id.(path) b in
 let '(x,y):=Plot.position index zoom fit x y in
 let prefix:=event_id.(path)+++"/@item/s:"+++TextJson.quote id+++"/" in
 let children:=map snd (filter (fun pair=>String.prefix prefix (expanded_path (fst pair))) (combine expanded rendered)) in
 placement key (IP.GraphNode IP.FixedPixels x y (Z.to_N (Plot.graph_width zoom)) (Z.to_N (Plot.graph_height zoom)) (String.eqb (Plot.selected p event_id.(path) b) id))
  (button (key+++"/@select") "选择节点" (ViewChanged event_id (SelectNode id)) active::children).
Definition graph_control event_id part label command active :=
 button (Types.event_key event_id+++"/@"+++part) label (ViewChanged event_id command) active.
Definition render_graph event_id p b expanded rendered active : list scene :=
 let key:=Types.event_key event_id in let nodes:=property_array "nodes" p in
 let selected:=Plot.selected p event_id.(path) b in
 let '(zoom,x,y,fit,_):=Plot.graph_view event_id.(path) b in
 let '(width,height):=Plot.graph_extent (List.length nodes) zoom fit x y in
 [toolbar event_id "controls"
  [graph_control event_id "zoom-in" "放大" ZoomIn active;
   graph_control event_id "zoom-out" "缩小" ZoomOut active;
   graph_control event_id "fit" "适应宽度" Fit active;
   graph_control event_id "left" "左移" (Pan "-40" "0") active;
   graph_control event_id "right" "右移" (Pan "40" "0") active;
   graph_control event_id "up" "上移" (Pan "0" "-40") active;
   graph_control event_id "down" "下移" (Pan "0" "40") active];
  placement (key+++"/@viewport") IP.GraphViewport
   [placement (key+++"/@canvas") (IP.GraphCanvas IP.FixedPixels (Z.to_N width) (Z.to_N height))
    (placement (key+++"/@edges") IP.GraphEdges
      [S.Node (key+++"/@plot") "interactive-markdown/connections" "Graph connections" R.Content (S.Graphic (Plot.graph event_id p b)) []]::
     map (fun indexed=>graph_item event_id p b expanded rendered active (fst indexed) (snd indexed)) (combine (seq 0 (List.length nodes)) nodes))]]++
 (if negb (String.eqb selected "")&&negb (existsb (fun node=>String.eqb (graph_identity node) selected) nodes)
   then [text (key+++"/@removed") "原节点已移除"] else [])++
 (if Nat.eqb (List.length nodes) 0 then [text (key+++"/@empty") "暂无数据"] else [])++
 [S.Node (key+++"/@nodes") "interactive-markdown/graph-nodes" "图节点状态" R.Content S.SummaryList
  (map (fun node=>let id:=graph_identity node in let key:=key+++"/@accessible/"+++TextJson.quote id in
   region key [button (key+++"/@select") (match string_field "key" node with Some name=>name|None=>id end) (ViewChanged event_id (SelectNode id)) active;
    text (key+++"/@state") (graph_task_status node)]) nodes);
  S.Node (key+++"/@connections") "interactive-markdown/graph-connections" "连接规则" R.Content S.SummaryList
   (map (fun edge=>let id:=graph_identity edge in
   text (key+++"/@edge/"+++TextJson.quote id)
    (match string_field "ruleKey" edge,string_field "sourceIdentity" edge,string_field "targetIdentity" edge,string_field "actionKind" edge with
     |Some rule,Some source,Some target,Some action=>rule+++": "+++source+++" → "+++target+++" ("+++action+++")"|_,_,_,_=>id end)) (property_array "edges" p))].
Fixpoint grid_rows fuel event_id p index columns nodes : list scene := match fuel,nodes with
 |O,_|_,[]=>[]
 |S fuel,_=>synthetic event_id ("grid-row/"+++show_nat index) "row-layout"
    (match property "gap" p with Some (JString gap)=>[("gap",JString gap)]|_=>[] end)
    (firstn columns nodes)::
   grid_rows fuel event_id p (S index) columns (skipn columns nodes) end.
Fixpoint render_nodes (fuel:nat) identity (b:block) (prepared:prepared) (nodes:list expanded) budget : list scene*nat :=
 match fuel with
 |O=>([diagnostic_node "interactive-limit" "ui" "Render node limit"],budget)
 |S k=>let result:=fold_left (fun result node=>let '(reversed,budget):=result in
   match node with
   |Message key reason=>(diagnostic_node key key reason::reversed,budget)
   |Mounted event_id p binding children=>
    let key:=Types.event_key event_id in
    let '(rendered,budget):=render_nodes k identity b prepared children budget in
    let '(ordered,budget):=match p.(description).(component_role) with
     |Table=>table_order (property_array "rows" p) event_id.(path) b budget
     |_ =>(Good [],budget) end in
    let content:=match p.(description).(component_role),binding with
     |Field,FieldLink id active=>match find_local id b.(locals) with
       |Some local=>[field_scene identity event_id p binding local active]|None=>[text (key+++"/@missing") "Field state no longer exists"] end
     |Action,ActionLink action availability=>
       let '(role,prominence):=match action with Submit _=>(R.PrimaryButton,M.Primary)|_=>(R.Button,M.Secondary)end in
       S.Node (key+++"/@button") key (property_text "label" p) role
        (S.Activate(M.Control (key+++"/@button") (property_text "label" p) prominence (ActionClicked event_id)
          (match availability with Enabled=>M.Available|Busy _=>M.Busy "This action is pending"|Disabled=>M.Unavailable "Control is not available" end))) []::
        (let notice:=feedback_text event_id.(path) b in if String.eqb notice ""then[]else
         [diagnostic_node (key+++"/@feedback") ("@feedback/"+++event_id.(path)) notice])
     |TextLeaf,_=>[text (key+++"/@text") (property_text "label" p)]
     |MarkdownLeaf,_=>[S.Node (key+++"/@markdown") "interactive-markdown/markdown" "" R.Content (S.EmbeddedMarkdown (property_text "value" p)) []]
     |MetricLeaf,_=>render_metric key p
     |Table,Passive active=>render_table event_id p b children active ordered
     |Chart,_=>render_chart event_id p
     |Graph,Passive active=>render_graph event_id p b children rendered active
     |Column,_=>[]
     |Task,_=>let task:=match property "task" p with Some task=>task|None=>JNull end in
       [text (key+++"/@task") (match task with JNull=>"任务不存在"|_=>(match string_field "title" task with Some value=>value|None=>"" end)+++" · "+++(match string_field "statusLabel" task with Some value=>value|None=>"" end)+++" · "+++(match string_field "phase" task with Some value=>value|None=>"" end)+++
         (match bool_field "awaitingHuman" task with Some true=>" · 等待人工审批"|_=>"" end) end)]
     |Resource,_=>let handle:=match lookup (property_text "source" p) prepared.(Registry.sources) with Some source=>source|None=>JNull end in
       (if ready_fresh handle then [] else [S.Node (key+++"/@stale") "interactive-markdown/stale" "连接已断开，显示上次同步状态" R.Content (S.InformationText Information.Status) []])++rendered
     |_,_=>if String.eqb p.(description).(component_tag) "grid" then
       grid_rows (List.length rendered) event_id p 0
        (match property "columns" p with Some value=>match natural value with Some columns=>N.to_nat columns|None=>2 end|None=>2 end) rendered
       else rendered end in
    (component_node event_id p binding content b.(locals)::reversed,budget)
   end) nodes ([],budget) in (rev (fst result),snd result)
 end.
Definition source_open b := match State.view_at "@source" false b with SourceView open=>open|_=>false end.
Definition presentation_cost p (children:list expanded) :=
  match p.(description).(component_role) with
  | Table => 16 + (2 + 2 * Nat.min Bounds.table_page (List.length (property_array "rows" p))) * List.length children
  | Chart => 36 + Nat.min Bounds.chart_points (List.length (property_array "data" p))
  | Graph => 34 + 4 * List.length (property_array "nodes" p) + List.length (property_array "edges" p)
  | _ => if String.eqb p.(description).(component_tag) "grid" then 1 + List.length children else 1 end.
Fixpoint expansion_cost (fuel : nat) (nodes : list expanded) : nat :=
  match fuel with
  | O => if Nat.eqb (List.length nodes) 0 then 0 else S Bounds.expanded_components
  | S remaining => fold_right (fun node cost => match node with
      | Message _ _ => S cost
      | Mounted _ p _ children => presentation_cost p children + expansion_cost remaining children + cost end) 0 nodes
  end.
Fixpoint action_feedback_paths (fuel:nat) b (nodes:list expanded) : list string :=
 match fuel with
 |O=>[]
 |S remaining=>flat_map (fun node=>match node with
   |Mounted event_id p binding children=>
      (match p.(description).(component_role),binding with
       |Action,ActionLink _ _=>if String.eqb (feedback_text event_id.(path) b) "" then [] else [event_id.(path)]
       |_,_=>[] end)++action_feedback_paths remaining b children
   |Message _ _=>[] end) nodes
 end.
Definition feedback_diagnostics b inline :list diagnostic:=
 flat_map(fun feedback=>match feedback.(feedback_transaction)with
  |Answered _ _ message=>if String.eqb message ""||existsb(String.eqb feedback.(feedback_path))inline then[]else
    [Diagnostic(if String.eqb feedback.(feedback_path) "@storage"then "@storage"
       else "@feedback/"+++feedback.(feedback_path))message false]
  |_=>[]end)b.(feedbacks).
Definition content_diagnostics b prepared inline:=
 feedback_diagnostics b inline++
 (match b.(syntax).(syntax_error)with Some reason=>[Diagnostic "ui" reason true]|None=>[]end)++
 prepared.(diagnostics)++
 (match b.(storage_notice)with Some reason=>[Diagnostic "@storage" reason false]|None=>[]end).
Definition diagnostic_nodes identity issues:=
 map(fun indexed=>let '(index,issue):=indexed in
  diagnostic_node(CodeSource.key identity+++"/@diagnostic/"+++show_natural(N.of_nat index))
    issue.(diagnostic_path)issue.(diagnostic_message))
  (combine(seq 0(List.length issues))issues).
Definition presentation_diagnostics b prepared nodes :=
 let inline:=match b.(feedbacks) with []=>[]|_=>action_feedback_paths 64 b nodes end in
 let remaining:=content_diagnostics b prepared inline in
 (List.length inline + List.length remaining,remaining).
Definition admitted_content identity b prepared nodes budget :=
  let '(diagnostics,issues):=presentation_diagnostics b prepared nodes in
  if Nat.leb (expansion_cost 64 nodes + diagnostics) Bounds.expanded_components
  then fst (render_nodes 64 identity b prepared nodes budget)++diagnostic_nodes identity issues
  else [diagnostic_node (CodeSource.key identity+++"/@presentation-limit") "ui" "交互界面展开超过 4096 个节点；局部输入已保留，请查看源码。"].
Definition split_final_reset (nodes : list scene) : list scene * list scene :=
 match rev_append nodes [] with
 | last :: before =>
   match S.node_meaning last with
   | S.InteractiveNode component =>
     match IP.component_binding component with
     | ActionLink ResetAll _ => (rev_append before [], [last])
     | _ => (nodes, [])
     end
   | _ => (nodes, [])
   end
 | [] => ([], [])
 end.
Definition split_footer_reset (nodes : list scene) : list scene * list scene :=
 match nodes with
 | [stack] =>
   if component_has_tag "stack" stack then
     let '(body, footer):=split_final_reset (S.node_children stack) in
     ([with_children stack body],footer)
   else split_final_reset nodes
 | _=>split_final_reset nodes
 end.
Definition source_disclosure key b : scene :=
 let key:=key+++"/@disclose" in
 let expanded:=source_open b in
 let label:=if expanded then "收起源码" else "展开源码" in
 S.Node key "interactive-markdown/source-disclosure" label R.Button
   (S.PanelToggle expanded (M.Control key label M.Secondary (SourceDisclosure b.(block_owner)) M.Available)) [].
Definition content identity b prepared nodes budget : list scene :=
 let key:=CodeSource.key identity in
 let '(body,footer):=split_footer_reset (admitted_content identity b prepared nodes budget) in
 body++
 (match b.(block_ending) with Interrupted=>[text (key+++"/@interrupted") "生成未完成（仅保留在本次浏览器会话）"]|_=>[] end)++
 [S.Node (key+++"/@source-controls") "interactive-markdown/source-controls" "" R.Toolbar S.Region
  (footer++[source_disclosure key b])].
Definition fence identity b prepared nodes budget : scene :=
 S.Node (CodeSource.key identity+++"/@interactive") "interactive-markdown/fence" "" R.Content
  (S.InteractiveRegion (DocumentPublication.interactive identity (source_open b))) (content identity b prepared nodes budget).
Definition shared identity b prepared nodes budget : scene :=
 S.Node (CodeSource.key identity+++"/@shared") "interactive-markdown/shared" "" R.Content S.Region
  (content identity b prepared nodes budget++
   if source_open b then [S.Node (CodeSource.key identity+++"/@source") "interactive-markdown/source" "Source" R.CodeBlock
     (S.CodeFacts (CodeBlock.CodePresentation identity b.(source) false CodeBlock.Idle)) []] else []).

(** Rendering requires the source established by document publication. An opaque
    interactive owner is not evidence of a message, viewer, or source identity. *)
Definition fence_for identity b environment :=
 let prepared:=Runtime.prepared b environment in
 let b:=State.with_sources prepared.(Registry.sources) (State.with_locals prepared.(prepared_locals) b) in
 let '(nodes,allocation):=Expand.expand b prepared environment in
 fence identity b prepared nodes allocation.(Expand.remaining).
Definition shared_for identity b environment :=
 let prepared:=Runtime.prepared b environment in
 let b:=State.with_sources prepared.(Registry.sources) (State.with_locals prepared.(prepared_locals) b) in
 let '(nodes,allocation):=Expand.expand b prepared environment in
 shared identity b prepared nodes allocation.(Expand.remaining).
