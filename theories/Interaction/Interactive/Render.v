From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Interaction Require Import Codec Graphics CodeSource CodeBlock DocumentPublication.
From Selvedge.Interaction.Presentation Require Import Surface Roles Model Information.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Vocabulary Registry Types State Sources Expand Plot Presentation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope nat_scope.
Local Infix "+++" := String.append (at level 60, right associativity).
Module S := Selvedge.Interaction.Presentation.Surface.
Module R := Selvedge.Interaction.Presentation.Roles.
Module M := Selvedge.Interaction.Presentation.Model.
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
Definition component_caption event_id p : list scene :=
  let label := property_text "label" p in
  match p.(description).(component_role) with
  | Field | Action | TextLeaf | MarkdownLeaf | Column => []
  | _ => if String.eqb label "" then [] else
      [text (Types.event_key event_id+++"/@label") label] end.
Definition component_node event_id p binding children : scene :=
 S.Node (Types.event_key event_id) ("interactive-markdown/"+++p.(description).(component_tag))
  (property_text "label" p)
  (match binding with FieldLink _ _=>R.Field|ActionLink _ _=>R.Button|_=>R.Content end)
  (S.InteractiveNode (IP.Component event_id p binding)) (component_caption event_id p++children).
Definition synthetic event_id part tag attrs children : scene :=
 let event_id:=Event event_id.(event_owner) (event_id.(path)+++"/@"+++part) event_id.(occurrence) in
 match Vocabulary.component tag with
 |Some spec=>match Vocabulary.component_values spec (("id",JString part)::attrs) with
   |Some values=>component_node event_id (Properties spec values) (Passive true) children
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

Theorem unformatted_number_preserves_its_text source :
 formatted_value (JNumber source) "" = source.
Proof. reflexivity. Qed.
Definition feedback_text path b := match State.feedback_at path b with
 |Some (FeedbackEntry _ (Waiting _ _ _))|Some (FeedbackEntry _ (CopyingDefinition _))=>"Pending"
 |_=>"" end.
Definition field_scene identity event_id p binding local (active:bool) : scene :=
 let tag:=p.(description).(component_tag) in
 let display:=if String.eqb tag "slider"||String.eqb tag "checkbox"||String.eqb tag "select"
   then Local.canonical local else JString local.(Local.raw) in
 let editor:=IP.Editor (IP.Component event_id p binding) local.(Local.local_shape) local.(Local.validation) display (Some local.(Local.raw)) active
   (if active then Some (fun value=>Some (ValueChanged event_id value)) else None) in
 S.Node (Types.event_key event_id+++"/@input") "interactive-markdown/edit" (property_text "label" p)
  R.Field (S.InteractiveEdit identity event_id.(path) editor)
  (match local.(validation) with
   |Some reason=>[S.Node (Types.event_key event_id+++"/@input/validation")
     "interactive-markdown/validation" reason R.Alert (S.InformationText Information.Status) []]
   |None=>[] end).
Definition table_columns children := fold_right (fun node rest=>match node with
 |Mounted _ p _ _=>if match p.(description).(component_role) with Column=>true|_=>false end then p::rest else rest
 |_=>rest end) [] children.
Definition find_column id columns := find (fun p=>String.eqb (property_text "id" p) id) columns.
Definition table_order rows columns path b budget := match State.view_at path false b with
 |TableView (Some column) descending _=>match find_column column columns with
   |Some p=>Expression.sort_metered (property_text "field" p) descending rows budget
   |None=>(Error "Saved sort column is currently hidden",budget) end
 |_ =>(Good rows,budget) end.
Definition table_page path b := match State.view_at path false b with TableView _ _ page=>page|_=>0 end.
Definition cell_value p row :=
 formatted_value (get_path (property_text "field" p) row) (property_text "format" p).
Definition table_column event_id b (sortable active:bool) p : IP.table_column Types.input :=
 let id:=property_text "id" p in
 IP.TableColumn id (property_text "label" p)
  (if sortable then Some (ViewChanged event_id (SortColumn id)) else None) active
  (match State.view_at event_id.(path) false b with
   |TableView (Some current) descending _=>if String.eqb current id then Some descending else None|_=>None end).
Definition render_table event_id p b children active ordered : list scene :=
 let key:=Types.event_key event_id in let columns:=table_columns children in
 match ordered with
 |Error reason=>[text (key+++"/@error") reason]
 |Good rows=>let page:=Nat.min (table_page event_id.(path) b) ((List.length rows-1)/Bounds.table_page) in
 let start:=(page*Bounds.table_page)%nat in let visible:=firstn Bounds.table_page (skipn start rows) in
 [S.Node (key+++"/@table") "interactive-markdown/table" (property_text "label" p) R.Content
   (S.InteractiveTable (IP.DataTable (property_text "label" p)
     (map (table_column event_id b (property_bool false "sortable" p) active) columns)
     (map (fun row=>map (fun column=>cell_value column row) columns) visible))) []]++
 (if Nat.eqb (List.length visible) 0 then [text (key+++"/@empty") "暂无数据"] else [])++
 [toolbar event_id "pages"
  [button (key+++"/@previous") "上一页" (ViewChanged event_id (Page (Nat.pred page))) (active&&Nat.ltb 0 page);
   text (key+++"/@page") ("第 "+++show_nat (S page)+++" / "+++show_nat (Nat.max 1 ((List.length rows+99)/100))+++" 页，共 "+++show_nat (List.length rows)+++" 行");
   button (key+++"/@next") "下一页" (ViewChanged event_id (Page (S page))) (active&&Nat.ltb (start+Bounds.table_page) (List.length rows))]]
 end.
Definition placement key position children : scene :=
 S.Node key "interactive-markdown/placement" "" R.Content (S.InteractivePlacement position) children.
Definition chart_summary_table event_id p : scene :=
  let x_label := property_text "x-label" p in let y_label := property_text "y-label" p in
  S.Node (Types.event_key event_id+++"/@data") "interactive-markdown/chart-data" "图表数据" R.Content
    (S.Table "图表数据"
      [if String.eqb x_label "" then property_text "x" p else x_label;
       if String.eqb y_label "" then property_text "y" p else y_label]
      (map (fun row => [scalar_text (get_path (property_text "x" p) row);
                        scalar_text (get_path (property_text "y" p) row)]) (Plot.chart_rows p))) [].
Definition chart_summary event_id p :list scene :=
 let key:=Types.event_key event_id in
 let all_rows:=property_array "data" p in let count:=List.length all_rows in
 let rows:=Plot.chart_rows p in
 let x_label:=property_text "x-label" p in let y_label:=property_text "y-label" p in
 (if String.eqb x_label "" && String.eqb y_label "" then [] else
  [text (key+++"/@axes") (x_label+++" / "+++y_label)])++
 (if Nat.ltb Bounds.chart_points count then
  [text (key+++"/@truncation") ("共 "+++show_nat count+++" 行，图中显示前 "+++show_nat Bounds.chart_points+++" 行。")] else [])++
 (if Nat.eqb count 0 then [text (key+++"/@empty") "暂无数据"] else [])++
 [chart_summary_table event_id p].
Definition render_chart event_id p : list scene :=
 let key:=Types.event_key event_id in
 match Plot.chart p with
 |Error reason=>[text (key+++"/@error") reason]
 |Good drawing=>
 [placement (key+++"/@viewport") IP.ChartViewport
   [placement (key+++"/@canvas") (IP.GraphCanvas (Npos (Graphics.width drawing)) (Npos (Graphics.height drawing)))
    [S.Node (key+++"/@plot") "interactive-markdown/chart"
     ("图表；显示 "+++show_nat (List.length (Plot.chart_rows p))+++" / "+++
      show_nat (List.length (property_array "data" p))+++" 行；数值见下方数据")
     R.Content (S.Graphic drawing) []]]]
 end++chart_summary event_id p.
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
 placement key (IP.GraphNode x y (Z.to_N (Plot.graph_width zoom)) (Z.to_N (Plot.graph_height zoom)) (String.eqb (Plot.selected p event_id.(path) b) id))
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
   [placement (key+++"/@canvas") (IP.GraphCanvas (Z.to_N width) (Z.to_N height))
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
    [("gap",match property "gap" p with Some value=>value|None=>JString "md" end)] (firstn columns nodes)::
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
     |Table=>table_order (property_array "rows" p) (table_columns children) event_id.(path) b budget
     |_ =>(Good [],budget) end in
    let content:=match p.(description).(component_role),binding with
     |Field,FieldLink id active=>match find_local id b.(locals) with
       |Some local=>[field_scene identity event_id p binding local active]|None=>[text (key+++"/@missing") "Field state no longer exists"] end
     |Action,ActionLink action availability=>
       button (key+++"/@button") (property_text "label" p) (ActionClicked event_id) (match availability with Enabled=>true|_=>false end)::
        (let notice:=feedback_text event_id.(path) b in if String.eqb notice ""then[]else
         [diagnostic_node (key+++"/@feedback") ("@feedback/"+++event_id.(path)) notice])
     |TextLeaf,_=>[text (key+++"/@text") (property_text "label" p)]
     |MarkdownLeaf,_=>[S.Node (key+++"/@markdown") "interactive-markdown/markdown" "" R.Content (S.EmbeddedMarkdown (property_text "value" p)) []]
     |MetricLeaf,_=>[text (key+++"/@value") (metric p)]
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
    (component_node event_id p binding content::reversed,budget)
   end) nodes ([],budget) in (rev (fst result),snd result)
 end.
Definition source_open b := match State.view_at "@source" false b with SourceView open=>open|_=>false end.
Definition presentation_cost p (children:list expanded) :=
  match p.(description).(component_role) with
  | Table => 16 + (2 + 2 * Nat.min Bounds.table_page (List.length (property_array "rows" p))) * List.length children
  | Chart => 8 + Nat.min Bounds.chart_points (List.length (property_array "data" p))
  | Graph => 34 + 4 * List.length (property_array "nodes" p) + List.length (property_array "edges" p)
  | _ => if String.eqb p.(description).(component_tag) "grid" then 1 + List.length children else 1 end.
Fixpoint expansion_cost (fuel : nat) (nodes : list expanded) : nat :=
  match fuel with
  | O => if Nat.eqb (List.length nodes) 0 then 0 else S Bounds.expanded_components
  | S remaining => fold_right (fun node cost => match node with
      | Message _ _ => S cost
      | Mounted _ p _ children => presentation_cost p children + expansion_cost remaining children + cost end) 0 nodes
  end.
Definition feedback_diagnostics b :list diagnostic:=
 flat_map(fun feedback=>match feedback.(feedback_transaction)with
  |Answered _ _ message=>if String.eqb message ""then[]else
    [Diagnostic(if String.eqb feedback.(feedback_path) "@storage"then "@storage"
       else "@feedback/"+++feedback.(feedback_path))message false]
  |_=>[]end)b.(feedbacks).
Definition content_diagnostics b prepared:=
 feedback_diagnostics b++
 (match b.(syntax).(syntax_error)with Some reason=>[Diagnostic "ui" reason true]|None=>[]end)++
 prepared.(diagnostics)++
 (match b.(storage_notice)with Some reason=>[Diagnostic "@storage" reason false]|None=>[]end).
Definition diagnostic_nodes identity issues:=
 map(fun indexed=>let '(index,issue):=indexed in
  diagnostic_node(CodeSource.key identity+++"/@diagnostic/"+++show_natural(N.of_nat index))
    issue.(diagnostic_path)issue.(diagnostic_message))
  (combine(seq 0(List.length issues))issues).
Definition admitted_content identity b prepared nodes budget :=
  let issues:=content_diagnostics b prepared in
  if Nat.leb (expansion_cost 64 nodes + List.length issues) Bounds.expanded_components
  then fst (render_nodes 64 identity b prepared nodes budget)++diagnostic_nodes identity issues
  else [diagnostic_node (CodeSource.key identity+++"/@presentation-limit") "ui" "交互界面展开超过 4096 个节点；局部输入已保留，请查看源码。"].
Definition content identity b prepared nodes budget : list scene :=
 let key:=CodeSource.key identity in
 admitted_content identity b prepared nodes budget++
 (match b.(block_ending) with Interrupted=>[text (key+++"/@interrupted") "生成未完成（仅保留在本次浏览器会话）"]|_=>[] end)++
 [S.Node (key+++"/@source-controls") "interactive-markdown/source-controls" "" R.Toolbar S.Region
  [button (key+++"/@disclose") (if source_open b then "收起源码" else "展开源码") (SourceDisclosure b.(block_owner)) true]].
Definition fence identity b prepared nodes budget : scene :=
 S.Node (CodeSource.key identity+++"/@interactive") "interactive-markdown/fence" "" R.Content
  (S.InteractiveRegion (DocumentPublication.interactive identity (source_open b))) (content identity b prepared nodes budget).
Definition shared identity b prepared nodes budget : scene :=
 S.Node (CodeSource.key identity+++"/@shared") "interactive-markdown/shared" "" R.Content S.Region
  (content identity b prepared nodes budget++
   if source_open b then [S.Node (CodeSource.key identity+++"/@source") "interactive-markdown/source" "Source" R.CodeBlock
     (S.CodeFacts (CodeBlock.CodePresentation identity b.(source) false CodeBlock.Idle)) []] else []).
