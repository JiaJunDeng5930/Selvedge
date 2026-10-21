From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Interaction Require Import Scene Graphics.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Vocabulary Registry Types State Sources Expand Plot.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope nat_scope.
Definition scene:=Selvedge.Interaction.Scene.scene Types.input.
Definition text key value:scene:=Selvedge.Interaction.Scene.Content Selvedge.Interaction.Scene.CText key[("value",JString value)][].
Definition group key props children:scene:=Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CGroup key props None children.
Definition button key label action disabled:scene:=Selvedge.Interaction.Scene.ActionButton key[("label",JString label)]action disabled[].
Definition layout p:=if String.eqb p.(description).(component_tag)"row-layout"then "row"else
 if String.eqb p.(description).(component_tag)"grid"then "grid"else "column".
Definition common event_id p:=
 [("layout",JString(layout p));("columns",match property "columns"p with Some v=>v|None=>JNull end);
  ("gap",match property "gap"p with Some(JString s)=>JString s|_=>JString "md"end);
  ("tone",match property "tone"p with Some(JString s)=>JString s|_=>JString "neutral"end);
  ("attrs",JObject[("data-owner",JString event_id.(event_owner).(owner_key));
   ("data-layout",JString p.(description).(component_tag))])].
(* Native Markdown paints its content separately. Keep common appearance on the
   component enclosure, with the same path for plain text and badges. *)
Definition leaf kind event_id p props:scene:=
 let key:=Types.event_key event_id in
 group key(common event_id p)
  [Selvedge.Interaction.Scene.Content kind(key++"/@content")%string props[]].
Definition node_properties (value:scene):list(string*json):=match value with
 |Selvedge.Interaction.Scene.GraphicView _ props _
 |Selvedge.Interaction.Scene.Container _ _ props _ _
 |Selvedge.Interaction.Scene.Content _ _ props _
 |Selvedge.Interaction.Scene.ActionButton _ props _ _ _
 |Selvedge.Interaction.Scene.FormView _ props _ _
 |Selvedge.Interaction.Scene.FieldView _ _ _ _ props _ _ _
 |Selvedge.Interaction.Scene.FieldWithFiles _ _ _ props _ _ _ _=>props end.
(** Motion decorates every component's real scene, including text/Markdown leaves.
    Keep its existing keys/actions and propagate an enclosing resource's declared
    pause to the decoration rather than restarting an independent animation. *)
Definition with_motion event_id p (value:scene):scene:=
 let key:=Types.event_key event_id in
 let motion:=match property "motion"p with Some(JString name)=>name|_=>"none"end in
 let transition:=match property "transition"p with Some(JString name)=>name|_=>"none"end in
 if String.eqb motion "none" && String.eqb transition "none"then value else
 let attrs:=[("data-interactive-motion",JString motion);("data-interactive-transition",JString transition)]++
   match field "attrs"(JObject(node_properties value))with
   |Some source=>match field "data-motion-paused"source with
      |Some paused=>[("data-motion-paused",paused)]|None=>[]end
   |None=>[]end in
 group(key++"/@motion")%string
  [("layout",JString(if String.eqb motion "spin"then "motion-wrapper"else "column"));
   ("tone",match property "tone"p with Some tone=>tone|None=>JString "neutral"end);
   ("attrs",JObject attrs)]
  ((if String.eqb motion "spin"then
    [Selvedge.Interaction.Scene.Content Selvedge.Interaction.Scene.CIcon(key++"/@motion-glyph")%string
      [("icon",JString "spinner");("attrs",JObject[("data-interactive-motion-glyph",JString "");("aria-hidden",JString "true")])][]]
    else[])++[value]).
Definition label_text p:=property_text "label"p.
Definition field_kind l:=match l.(local_shape)with
 |Numeric true _ _ _=>KInteger|Numeric false _ _ _=>KDecimal|Boolean=>KBool|Local.Text _=>KText|Enumeration first rest=>KEnum first rest end.
Definition field_metadata p l:=
 let tag:=p.(description).(component_tag)in
 let numeric:=match l.(local_shape)with Numeric _ _ _ _=>true|_=>false end in
 let ranges:=match l.(local_shape)with
 |Numeric _ lo hi step=>
  [("type",JString(if String.eqb tag "slider"then "range"else "text"));("step",decimal_json step)]++
  (match lo with Some d=>[("min",decimal_json d)]|None=>[]end)++(match hi with Some d=>[("max",decimal_json d)]|None=>[]end)
 |_=>[("type",JString "text")]end in
 [("label",JString(label_text p));("value_kind",JString(if String.eqb tag "checkbox"then "boolean"else if String.eqb tag "slider"then "decimal"else "string"));
  ("multiline",JBool(String.eqb tag "textarea"));("checked",match canonical l with JBool b=>JBool b|_=>JBool false end);
  ("invalid",JBool(match l.(validation)with Some _=>true|None=>false end));
  ("help",match l.(validation)with Some reason=>JString reason|None=>JString ""end);
  ("options",match l.(local_shape)with Enumeration first rest=>JArray(map JString(first::rest))|_=>JArray[]end);
  ("attrs",JObject ranges)].
Definition field_scene event_id p l active:scene:=
 let key:=Types.event_key event_id in
 let tag:=p.(description).(component_tag)in
 let spec:=Schema.Field "value"(field_kind l)in
 let display:=if String.eqb tag "slider"||String.eqb tag "checkbox"||String.eqb tag "select"then canonical l else JString l.(raw)in
 let props:list(Selvedge.Interaction.Scene.property Types.input):=Selvedge.Interaction.Scene.Specification spec::Selvedge.Interaction.Scene.Data Selvedge.Interaction.Scene.Value display::[]in
 Selvedge.Interaction.Scene.FieldView(if String.eqb tag "checkbox"then Selvedge.Interaction.Scene.CheckboxField else if String.eqb tag "select"then Selvedge.Interaction.Scene.SelectField else Selvedge.Interaction.Scene.InputField)
 key spec(Selvedge.Interaction.Scene.input_value props)(("disabled",JBool(negb active))::field_metadata p l)
 (if active then Some(Selvedge.Interaction.Scene.InteractiveValueInjection,ValueChanged event_id JNull)else None)[][].
Definition scalar_text v:=match v with JString s|JNumber s=>s|JBool value=>if value then "true"else "false"|_=>""end.
Definition metric p:=match property "value"p with
 |Some(JNumber _ as n)=>match decimal_value n with
   |Some d=>match formatted d(match property "format"p with Some(JString s)=>s|_=>"number"end)with Good s=>s|Error e=>e end
   |None=>"Invalid number"end
 |Some v=>scalar_text v|None=>""end.
Definition feedback_text path b:=match State.feedback_at path b with
 |Some(FeedbackEntry _(Waiting _ _ _))=>"Pending"
 |Some(FeedbackEntry _(CopyingDefinition _))=>"Pending"
 |Some(FeedbackEntry _(Answered _ _ message))=>message|None=>""end.
Definition table_columns children:=fold_right(fun e acc=>match e with Mounted _ p _ _=>if match p.(description).(component_role)with Column=>true|_=>false end then p::acc else acc|_=>acc end)[]children.
Definition find_column id columns:=find(fun p=>String.eqb(property_text "id"p)id)columns.
Definition table_order rows columns path b budget :=
 match State.view_at path false b with
 |TableView(Some column)descending _=>match find_column column columns with
   |Some p=>Expression.sort_metered(property_text "field"p)descending rows budget
   |None=>(Error "Saved sort column is currently hidden",budget)end
 |_ => (Good rows,budget)end.
Definition table_page path b:=match State.view_at path false b with TableView _ _ page=>page|_=>0 end.
Definition column_label p:=property_text "label"p.
Definition cell_value p row:=let value:=get_path(property_text "field"p)row in
 match value,property "format"p with
 |JNumber _,Some(JString style)=>match decimal_value value with Some d=>match formatted d style with Good s=>s|Error e=>e end|_=>"Invalid number"end
 |_,_=>scalar_text value end.
Definition table_header event_id (active sortable:bool) columns:scene:=
 Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CRow((Types.event_key event_id++"/@header")%string)[]None
 (map(fun p=>let key:=(Types.event_key event_id++"/@column/"++property_text "id"p)%string in
 Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell key[]None
 [if sortable then button(key++"/@sort")%string(column_label p)
    (if active then Some(ViewChanged event_id(SortColumn(property_text "id"p)))else None)(negb active)
  else text(key++"/@label")%string(column_label p)])columns).
Fixpoint table_rows event_id columns index rows:list scene:=
 match rows with []=>[]|row::rest=>
 let key:=(Types.event_key event_id++"/@row/"++show_nat index)%string in
 Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CRow key[]None
 (map(fun p=>Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell(key++"/"++property_text "id"p)%string[]None[text(key++"/"++property_text "id"p++"/@value")%string(cell_value p row)])columns)::
 table_rows event_id columns(S index)rest end.
Definition render_table event_id p b children active ordered:scene:=
 let key:=Types.event_key event_id in let columns:=table_columns children in
 match ordered with
 |Error reason=>text(key++"/@error")%string reason
 |Good rows=>let page:=Nat.min(table_page event_id.(path)b)((List.length rows-1)/Bounds.table_page)in let start:=(page*Bounds.table_page)%nat in
 let visible:=firstn Bounds.table_page(skipn start rows)in
 group key(common event_id p)
 ([text(key++"/@count")%string(label_text p++" / "++show_nat(List.length rows)++" rows")%string;
   Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CTable(key++"/@table")%string[]None
     (table_header event_id active(property_bool false "sortable"p)columns::table_rows event_id columns start visible)]++
 (if Nat.eqb(List.length visible)0 then[text(key++"/@empty")%string "No rows on this page"]else[])++
 (if Nat.ltb Bounds.table_page(List.length rows)then
 [group(key++"/@pages")%string[("layout",JString "row")]
  [button(key++"/@previous")%string "Previous"(if active&&Nat.ltb 0 page then Some(ViewChanged event_id(Page(Nat.pred page)))else None)(negb(active&&Nat.ltb 0 page));
   text(key++"/@page")%string(show_nat(S page));
   button(key++"/@next")%string "Next"(if active&&Nat.ltb(start+Bounds.table_page)(List.length rows)then Some(ViewChanged event_id(Page(S page)))else None)(negb(active&&Nat.ltb(start+Bounds.table_page)(List.length rows)))]]else[]))
 end.
Definition render_chart event_id p:scene:=
 let key:=Types.event_key event_id in
 match Plot.chart p with
 |Error reason=>text(key++"/@error")%string reason
 |Good plot=>let rows:=property_array "data"p in
 let x:=property_text "x"p in let y:=property_text "y"p in
 group key(common event_id p)
 [text(key++"/@label")%string(label_text p);
  text(key++"/@axes")%string(Plot.axis_label p "x"++" / "++Plot.axis_label p "y")%string;
  group(key++"/@viewport")%string[("layout",JString "chart-viewport")]
   [group(key++"/@canvas")%string[("layout",JString "graph-canvas");
      ("width",JNumber(show_natural(Npos(Graphics.width plot))));("height",JNumber(show_natural(Npos(Graphics.height plot))))]
    [Selvedge.Interaction.Scene.GraphicView(key++"/@plot")%string[("label",JString(label_text p))]plot]];
  text(key++"/@count")%string(show_nat(List.length rows)++" rows / plotted "++show_nat(List.length(Plot.chart_rows p)))%string;
  Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CTable(key++"/@data")%string[]None
   (Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CRow(key++"/@headers")%string[]None
     [Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell(key++"/@x")%string[]None[text(key++"/@xlabel")%string(Plot.axis_label p "x")];
      Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell(key++"/@y")%string[]None[text(key++"/@ylabel")%string(Plot.axis_label p "y")]]::
    map(fun row=>let index:=match key_value(get_path(property_text "row-key"p)row)with Some s=>s|None=>""end in
      Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CRow(key++"/@row/"++index)%string[]None
       [Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell(key++"/@x/"++index)%string[]None[text(key++"/@xv/"++index)%string(scalar_text(get_path x row))];
        Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CCell(key++"/@y/"++index)%string[]None[text(key++"/@yv/"++index)%string(scalar_text(get_path y row))]])(Plot.chart_rows p))]
 end.
Definition expanded_path node:=match node with Mounted event_id _ _ _=>event_id.(path)|Message path _=>path end.
Definition graph_identity node:=match string_field "identity"node with Some id=>id|None=>""end.
Definition graph_task_status node:=match field "task"node with
 |Some task=>match string_field "title"task,string_field "statusLabel"task,string_field "phase"task with
   |Some title,Some status,Some phase=>(title++" · "++status++" · "++phase)%string
   |_,_,_=>"Task unavailable"end
 |None=>"Task unavailable"end.
Definition graph_item event_id p b expanded rendered (active:bool) index node:scene:=
 let id:=graph_identity node in let key:=(Types.event_key event_id++"/@node/"++TextJson.quote id)%string in
 let '(zoom,x,y,fit,_):=Plot.graph_view event_id.(path)b in let '(x,y):=Plot.position index zoom fit x y in
 let prefix:=(event_id.(path)++"/@item/s:"++TextJson.quote id++"/")%string in
 let children:=map snd(filter(fun pair=>String.prefix prefix(expanded_path(fst pair)))(combine expanded rendered))in
 group key[("layout",JString "graph-node");("label",JString(graph_task_status node));
   ("x",JNumber(show_integer x));("y",JNumber(show_integer y));("width",JNumber(show_integer(Plot.graph_width zoom)));("height",JNumber(show_integer(Plot.graph_height zoom)));
   ("attrs",JObject[("aria-current",JString(if String.eqb(Plot.selected p event_id.(path)b)id then "true"else "false"))])]
  (button(key++"/@select")%string "Select node"(if active then Some(ViewChanged event_id(SelectNode id))else None)(negb active)::children).
Definition render_graph event_id p b expanded rendered (active:bool):scene:=
 let key:=Types.event_key event_id in let nodes:=property_array "nodes"p in
 let selected:=Plot.selected p event_id.(path)b in
 let selection_exists:=existsb(fun node=>String.eqb(graph_identity node)selected)nodes in
 let '(zoom,x,y,fit,_):=Plot.graph_view event_id.(path)b in
 let '(width,height):=Plot.graph_extent(List.length nodes)zoom fit x y in
 group key(common event_id p)
 ([text(key++"/@label")%string(label_text p);
   group(key++"/@controls")%string[("layout",JString "row")]
    [button(key++"/@zoom-in")%string "+"(if active then Some(ViewChanged event_id ZoomIn)else None)(negb active);
     button(key++"/@zoom-out")%string "−"(if active then Some(ViewChanged event_id ZoomOut)else None)(negb active);
     button(key++"/@fit")%string "Fit width"(if active then Some(ViewChanged event_id Fit)else None)(negb active);
     button(key++"/@left")%string "←"(if active then Some(ViewChanged event_id(Pan "-40" "0"))else None)(negb active);
     button(key++"/@right")%string "→"(if active then Some(ViewChanged event_id(Pan "40" "0"))else None)(negb active);
     button(key++"/@up")%string "↑"(if active then Some(ViewChanged event_id(Pan "0" "-40"))else None)(negb active);
     button(key++"/@down")%string "↓"(if active then Some(ViewChanged event_id(Pan "0" "40"))else None)(negb active)];
   group(key++"/@viewport")%string[("layout",JString "graph-viewport")]
    [group(key++"/@canvas")%string[("layout",JString "graph-canvas");
      ("width",JNumber(show_integer width));("height",JNumber(show_integer height))]
      (group(key++"/@edges")%string[("layout",JString "graph-edges")]
        [Selvedge.Interaction.Scene.GraphicView(key++"/@plot")%string[("label",JString "Graph connections")](Plot.graph event_id p b)]::
       map(fun indexed=>graph_item event_id p b expanded rendered active(fst indexed)(snd indexed))(combine(seq 0(List.length nodes))nodes))]]++
  (if negb(String.eqb selected "")&&negb selection_exists then[text(key++"/@removed")%string "原节点已移除"]else[])++
  (if Nat.eqb(List.length nodes)0 then[text(key++"/@empty")%string "No graph nodes"]else[])++
  [Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CList(key++"/@nodes")%string[("label",JString "Graph node states")]None
   (map(fun node=>let id:=graph_identity node in let key:=(key++"/@accessible/"++TextJson.quote id)%string in
     group key[("layout",JString "row")]
      [button(key++"/@select")%string(match string_field "key"node with Some name=>name|None=>id end)
        (if active then Some(ViewChanged event_id(SelectNode id))else None)(negb active);
       text(key++"/@state")%string(graph_task_status node)])nodes);
   Selvedge.Interaction.Scene.Container Selvedge.Interaction.Scene.CList(key++"/@connections")%string[("label",JString "Connection rules")]None
    (map(fun edge=>let id:=graph_identity edge in text(key++"/@edge/"++TextJson.quote id)%string
      (property_text "label"p++" / "++match string_field "ruleKey"edge,string_field "sourceIdentity"edge,string_field "targetIdentity"edge,string_field "actionKind"edge with
       |Some rule,Some source,Some target,Some action=>(rule++": "++source++" → "++target++" ("++action++")")%string
       |_,_,_,_=>id end))%string(property_array "edges"p))]).
Fixpoint render_nodes(fuel:nat)(b:block)(prepared:prepared)(nodes:list expanded)(budget:nat):list scene*nat:=
 match fuel with O=>([text "interactive-limit" "Render node limit"],budget)|S k=>
 let result:=fold_left(fun result node=>let '(reversed,budget):=result in match node with
 |Message key reason=>(text key reason::reversed,budget)
 |Mounted event_id p binding children=>
   let key:=Types.event_key event_id in let '(rendered,budget):=render_nodes k b prepared children budget in
   let '(ordered,budget):=match p.(description).(component_role)with
   |Table=>table_order(property_array "rows"p)(table_columns children)event_id.(path)b budget
   |_ =>(Good [],budget)end in
   let rendered_node:=match p.(description).(component_role),binding with
   |Field,FieldLink id active=>match find_local id b.(locals)with
     |Some l=>field_scene event_id p l active|None=>text key "Field state no longer exists"end
   |Action,ActionLink action availability=>
     let active:=match availability with Enabled=>true|_=>false end in
     group key(common event_id p)
       [button(key++"/@button")%string(label_text p)(if active then Some(ActionClicked event_id)else None)(negb active);
        text(key++"/@feedback")%string(feedback_text event_id.(path)b)]
   |TextLeaf,_=>leaf Selvedge.Interaction.Scene.CText event_id p[("value",JString(label_text p))]
   |MarkdownLeaf,_=>leaf Selvedge.Interaction.Scene.CMarkdown event_id p[("value",JString(property_text "value"p));("complete",JBool true)]
   |MetricLeaf,_=>group key(common event_id p)[text(key++"/@label")%string(label_text p);text(key++"/@value")%string(metric p)]
   |Table,Passive active=>render_table event_id p b children active ordered
   |Chart,_=>render_chart event_id p
   |Graph,Passive active=>render_graph event_id p b children rendered active
   |Column,_=>text key(label_text p)
   |Task,_=>let task:=match property "task"p with Some t=>t|None=>JNull end in
      let status:=match string_field "statusLabel"task with Some s=>s|None=>"Task unavailable"end in
      group key(common event_id p)[text(key++"/@label")%string(label_text p);text(key++"/@status")%string status]
   |Resource,_=>let handle:=match lookup(property_text "source"p)prepared.(Registry.sources)with Some s=>s|None=>JNull end in
      let sequence:=match string_field "sequence"handle with Some s=>s|None=>""end in
      let props:=map(fun '(name,value)=>if String.eqb name "attrs"then
        (name,JObject(("data-motion-paused",JBool(negb(ready_fresh handle)))::match value with JObject attrs=>attrs|_=>[]end))
        else(name,value))(common event_id p)in
      group key props
       (text(key++"/@resource")%string("实时视图 / 上次同步 "++sequence++if ready_fresh handle then ""else " / 上次数据")%string::rendered)
   |_,_=>group key(common event_id p)
      ((if String.eqb(label_text p)""then[]else[text(key++"/@label")%string(label_text p)])++rendered)
   end in (with_motion event_id p rendered_node::reversed,budget) end)nodes([],budget)in
 (rev(fst result),snd result)end.
Definition source_open b:=match State.view_at "@source"false b with SourceView open=>open|_=>false end.
Definition block_scene b prepared nodes budget:scene:=
 let key:=b.(block_owner).(owner_key)in
 group key[("attrs",JObject[("data-owner",JString key);("data-sources-fresh",JBool(forallb(fun kv=>ready_fresh(snd kv))prepared.(Registry.sources)))])]
 (fst(render_nodes 64 b prepared nodes budget)++
  map(fun reason=>text(key++"/@diagnostic/"++reason)%string reason)prepared.(diagnostics)++
  (match b.(syntax).(syntax_error)with Some e=>[text(key++"/@syntax")%string e]|None=>[]end)++
  (match b.(block_ending)with Interrupted=>[text(key++"/@interrupted")%string "生成未完成（仅保留在本次浏览器会话）"]|_=>[]end)++
  (match b.(storage_notice)with Some message=>[text(key++"/@storage")%string message]|None=>[]end)++
  [group(key++"/@source-controls")%string[("layout",JString "row")]
   [button(key++"/@disclose")%string(if source_open b then "Hide source"else "Show source")(Some(SourceDisclosure b.(block_owner)))false;
    button(key++"/@copy")%string "Copy source"(Some(CopyDefinition b.(block_owner)))false]]++
  (if source_open b then[Selvedge.Interaction.Scene.Content Selvedge.Interaction.Scene.CCode(key++"/@source")%string[("value",JString b.(source))][]]else[])).
