From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Interaction.Interactive Require Import Decimal Expression Syntax Local Sources Vocabulary Registry Types State.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Record properties:=Properties{description:component_spec;values:fields(full_schema description)}.
Definition properties_json p:=Schema.encode(full_schema p.(description))p.(values).
Definition property name p:=field name(properties_json p).
Definition property_text name p:=match string_field name(properties_json p)with Some s=>s|None=>""end.
Definition property_bool fallback name p:=match bool_field name(properties_json p)with Some b=>b|None=>fallback end.
Definition property_array name p:=match array_field name(properties_json p)with Some xs=>xs|None=>[]end.
Inductive gate:=Disabled|Enabled|Busy(ticket:N).
Inductive binding:=Passive(active:bool)|FieldLink(state_id:string)(enabled:bool)|ActionLink(value:action)(availability:gate).
Inductive expanded:=Mounted(event_id:event)(props:properties)(binding:binding)(children:list expanded)|Message(key:string)(reason:string).
Definition key_value j:=match j with
 |JString s=>if String.eqb s ""then None else Some("s:"++TextJson.quote s)
 |JNumber _=>match decimal_value j with Some d=>if Decimal.integral d then Some("n:"++Decimal.text d)else None|None=>None end
 |_=>None end.
Definition collection_keys path xs:=Sources.traverse(fun x=>from_option "Collection key must be a nonempty string or integer"(key_value(get_path path x)))xs.
Definition collection_valid path xs:=valid_field_path path&&match collection_keys path xs with Good keys=>Schema.unique_names keys|_=>false end.
Definition binding_id := Syntax.valid_binding.
Definition variable_free {A}(name:string)(env:list(string*A)):= binding_id name&&negb(existsb(fun kv=>String.eqb name(fst kv))env).
Definition field_matches tag shape:=
 match tag,shape with
 |"slider",Numeric _ (Some _) (Some _) _|"number-input",Numeric _ _ _ _|"text-input",Local.Text _|"textarea",Local.Text _|"checkbox",Boolean|"select",Enumeration _ _=>true
 |_,_=>false end.
Definition parse_action p locals:outcome action:=
 let props:=properties_json p in
 match property_text "action"p with
 |"set"=>let target:=property_text "target"p in
   l <-? from_option "Action target is not a root state"(find_local target locals);;
   value <-? from_option "set requires value"(field "value"props);;
   _ <-? from_option "set value violates the target schema"(Local.assign l value);;Good(Assign target value)
 |"reset"=>Good ResetAll
 |"draft"=>text <-? from_option "draft requires message"(string_field "message"props);;
   if String.eqb text ""then Error "draft message is empty"else Good(Draft text)
 |"submit"=>text <-? from_option "submit requires message"(string_field "message"props);;
   if String.eqb text ""then Error "submit message is empty"else Good(Submit text)
 |"copy"=>text <-? from_option "copy requires string value"(string_field "value"props);;Good(Copy text)
 |"openUrl"=>url <-? from_option "openUrl requires url"(string_field "url"props);;
   if String.eqb url ""then Error "openUrl url is empty"else Good(Navigate url)
 |_=>Error "Unknown authored action"end.
Definition local_action a:=match a with Assign _ _|ResetAll=>true|_=>false end.
Definition external_allowed b prepared environment:=
 b.(external)&&b.(fence_closed)&&b.(syntax).(sealed)&&
 (match b.(block_ending)with Complete=>true|_=>false end)&&negb prepared.(fatal)&&
 (match b.(syntax).(syntax_error)with None=>true|Some _=>false end)&&
 (match bool_field "connected"environment with Some true=>true|_=>false end)&&
 (match bool_field "display_lagged"environment with Some false=>true|_=>false end)&&
 forallb(fun kv=>ready_fresh(snd kv))prepared.(Registry.sources).
Definition binding_for (who:owner) path p b prepared environment enabled:=
 match p.(description).(component_role)with
 |Field=>let id:=property_text "bind"p in
   l <-? from_option "Field binding is not a root state"(find_local id prepared.(prepared_locals));;
   if field_matches p.(description).(component_tag)l.(local_shape)then Good(FieldLink id enabled)else Error "Field and state types differ"
 |Action=>a <-? parse_action p prepared.(prepared_locals);;
   let allowed:=enabled&&(local_action a||external_allowed b prepared environment)in
   Good(ActionLink a(if allowed then match State.pending path b with Some ticket=>Busy ticket|None=>Enabled end else Disabled))
 |_=>Good(Passive enabled)end.
Definition graph_endpoints p:=let nodes:=property_array "nodes"p in let edges:=property_array "edges"p in
 forallb(fun edge=>match string_field "sourceIdentity"edge,string_field "targetIdentity"edge with
 |Some source,Some target=>existsb(fun node=>match string_field "identity"node with Some id=>String.eqb source id|_=>false end)nodes&&
  existsb(fun node=>match string_field "identity"node with Some id=>String.eqb target id|_=>false end)nodes
 |_,_=>false end)edges.
Definition graph_identities items:=forallb(fun item=>match string_field "identity"item with
 |Some id=>negb(String.eqb id "")|None=>false end)items.
Definition graph_selection_target p:=match property "select"p with Some(JString id)=>if String.eqb id ""then None else Some id|_=>None end.
Definition graph_selection_valid locals p:=match property "select"p with
 |Some(JString id)=>if String.eqb id ""then true else match Local.find_local id locals with
   |Some local=>match local.(Local.local_shape)with Local.Text _=>true|_=>false end
   |None=>false end
 |None|Some JNull=>true|Some _=>false end.
Definition required_label_valid p:=forallb(fun field=>
 if String.eqb field.(field_name)"label"then match field.(field_kind)with
 |KText=>negb(String.eqb(property_text "label"p)"")|_=>true end else true)p.(description).(component_fields).
Definition extra_valid p children:=required_label_valid p&&
 match p.(description).(component_role)with
 |MetricLeaf=>match property "value"p with Some v=>scalar v|None=>false end
 |Layout=>if String.eqb p.(description).(component_tag)"grid"then
   match property "columns"p with Some v=>match as_small Bounds.grid_columns v with Some n=>0<?n|None=>false end|_=>false end else true
 |Repeat=>collection_valid(property_text "key"p)(property_array "items"p)
 |Table=>collection_valid(property_text "row-key"p)(property_array "rows"p)&&
   (0<?List.length children)&&(List.length children<=?Bounds.table_columns)&&forallb(fun e=>match e with Element "column"_ []_=>true|_=>false end)children
 |Chart=>collection_valid(property_text "row-key"p)(property_array "data"p)
 |Graph=>collection_valid "identity"(property_array "nodes"p)&&collection_valid "identity"(property_array "edges"p)&&
   graph_identities(property_array "nodes"p)&&graph_identities(property_array "edges"p)&&
   (List.length(property_array "nodes"p)<=?Bounds.graph_nodes)&&(List.length(property_array "edges"p)<=?Bounds.graph_edges)&&graph_endpoints p&&
   (match children with []|[Element "node-template"_ _ _]=>true|_=>false end)
 |Column=>negb(String.eqb(property_text "field"p)"")
 |Task=>match property "task"p with
   |Some JNull=>true
   |Some task=>match bool_field "working"task,bool_field "awaitingHuman"task,string_field "statusLabel"task,string_field "phase"task with
     |Some _,Some _,Some _,Some _=>true|_,_,_,_=>false end
   |None=>false end
 |_=>true end.
Record context:=Context{parent_path:string;environment:list(string*outcome json);enabled:bool;parent_role:option role}.
Record allocation_state:=Allocation{new_mounts:list(string*N);next_occurrence:N;node_count:nat;remaining:nat}.
Definition consume budget a:=Allocation a.(new_mounts)a.(next_occurrence)a.(node_count)budget.
Definition allocate who path previous a:=
 let occurrence:=match find(fun kv=>String.eqb path(fst kv))previous with Some(_,n)=>n|None=>a.(next_occurrence)end in
 let next:=match find(fun kv=>String.eqb path(fst kv))previous with Some _=>a.(next_occurrence)|None=>N.succ a.(next_occurrence)end in
 (Event who path occurrence,Allocation((path,occurrence)::a.(new_mounts))next(S a.(node_count))a.(remaining)).
Definition message path reason a:=([Message path reason],Allocation a.(new_mounts)a.(next_occurrence)(S a.(node_count))a.(remaining)).
Definition template_attributes (name variable:string):=
 [Attribute "id"(Value(JString "task"))"";
  Attribute "label"(Access(Reference variable)(Value(JString "key")))"";
  Attribute "task"(Access(Reference variable)(Value(JString "task")))""].
Fixpoint expand_nodes(fuel:nat)(b:block)(prepared:prepared)(external_env:json)(ctx:context)(nodes:list element)(allocation:allocation_state):list expanded*allocation_state:=
 match fuel,nodes with
 |_,[]=>([],allocation)
 |O,_=>message ctx.(parent_path)"Expansion work limit"allocation
 |S k,node::rest=>
   if (Bounds.expanded_components<=?allocation.(node_count))||Nat.eqb allocation.(remaining)0 then message ctx.(parent_path)"Expanded node or shared evaluation budget exceeded"allocation else
   let '(first,allocation):=expand_node k b prepared external_env ctx node allocation in
   let '(rest,allocation):=expand_nodes k b prepared external_env ctx rest allocation in(List.app first rest,allocation)
 end
with expand_node(fuel:nat)(b:block)(prepared:prepared)(external_env:json)(ctx:context)(node:element)(allocation:allocation_state):list expanded*allocation_state:=
 match fuel with O=>message ctx.(parent_path)"Expansion depth limit"allocation|S k=>
 match node with Element tag attrs children _=>
 let path:=ctx.(parent_path)++"/"++match lexical_id attrs with Some id=>id|None=>"@invalid"end in
 match component tag with
 |None=>message path("Unknown component: "++tag)allocation
 |Some spec=>
   let '(result,budget):=evaluate_attributes allocation.(remaining)ctx.(environment)attrs in
   let allocation:=consume budget allocation in
   match result with
   |Error reason=>message path reason allocation
   |Good props=>match component_values spec props with
     |None=>message path("Invalid component properties: "++tag)allocation
     |Some values=>let props:=Properties spec values in
       if String.eqb tag "graph-view"&&negb(graph_selection_valid prepared.(prepared_locals) props)
       then message path "Graph selection must bind a root string state" allocation else
       if negb(property_bool true "visible"props)||
          (match spec.(component_role)with Condition=>negb(property_bool false "test"props)|_=>false end)then([],allocation)else
       if negb spec.(container)&&negb(Nat.eqb(List.length children)0)then message path "Leaf component cannot contain children"allocation else
       if negb(extra_valid props children)then message path "Invalid component data or child structure"allocation else
       let active:=ctx.(enabled)&&property_bool true "enabled"props in
       match binding_for b.(block_owner)path props b prepared external_env active with
       |Error reason=>message path reason allocation
       |Good binding=>
         let '(event_id,allocation):=allocate b.(block_owner)path b.(mounts)allocation in
         let ctx':=Context path ctx.(environment)active(Some spec.(component_role))in
         match spec.(component_role)with
         |Condition=>if property_bool false "test"props then
             let '(children,allocation):=expand_nodes k b prepared external_env ctx' children allocation in([Mounted event_id props binding children],allocation)
           else([],allocation)
         |Repeat=>let variable:=property_text "item"props in
           if variable_free variable ctx.(environment)then
             let '(children,allocation):=expand_items k b prepared external_env ctx' variable(property_text "key"props)(property_array "items"props)children allocation in
             ([Mounted event_id props binding children],allocation)
           else message path "Template variable shadows an existing binding"allocation
         |Resource=>let name:=property_text "source"props in let variable:=property_text "let"props in
           if variable_free variable ctx.(environment)then
             match lookup name prepared.(Registry.sources)with
             |Some handle=>match field "value"handle with
               |Some(JObject _ as value)=>let child_ctx:=Context path(binding_set variable(Good value)ctx.(environment))active(Some Resource)in
                 let '(children,allocation):=expand_nodes k b prepared external_env child_ctx children allocation in([Mounted event_id props binding children],allocation)
               |_=>let status:=match string_field "status"handle with Some s=>s|None=>"error"end in
                   ([Mounted event_id props binding[Message(path++"/@status")("实时视图 / "++status)]],allocation)end
             |None=>message path "Resource-view source is not declared"allocation end
           else message path "Resource variable shadows a binding"allocation
         |Graph=>let '(variable,template):=match children with
           |[Element "node-template"attrs children _]=>
             (match literal_text "item"attrs with Good v=>v|_=>""end,children)
           |_ =>("node",[Element "task-node"(template_attributes "task" "node")[]true])end in
           if variable_free variable ctx.(environment)then
             let '(children,allocation):=expand_items k b prepared external_env ctx' variable "identity"(property_array "nodes"props)template allocation in
             ([Mounted event_id props binding children],allocation)
           else message path "Node template variable shadows a binding"allocation
         |Template=>message path "node-template is only valid directly inside graph-view"allocation
         |Column=>match ctx.(parent_role)with Some Table=>([Mounted event_id props binding []],allocation)|_=>message path "column is only valid directly inside table"allocation end
         |_=>let '(children,allocation):=expand_nodes k b prepared external_env ctx' children allocation in([Mounted event_id props binding children],allocation)
         end
       end
     end
   end
 end end end
with expand_items(fuel:nat)(b:block)(prepared:prepared)(external_env:json)(ctx:context)(variable key:string)(items:list json)(template:list element)(allocation:allocation_state):list expanded*allocation_state:=
 match fuel,items with _,[]=>([],allocation)|O,_=>message ctx.(parent_path)"Repeat expansion budget"allocation
 |S k,item::rest=>match key_value(get_path key item)with
   |None=>message ctx.(parent_path)"Invalid repeated collection key"allocation
   |Some item_key=>let item_ctx:=Context(ctx.(parent_path)++"/@item/"++item_key)(binding_set variable(Good item)ctx.(environment))ctx.(enabled)ctx.(parent_role)in
     let '(first,allocation):=expand_nodes k b prepared external_env item_ctx template allocation in
     let '(rest,allocation):=expand_items k b prepared external_env ctx variable key rest template allocation in(List.app first rest,allocation)
   end end.
Definition expand b prepared environment:=
 expand_nodes 16384 b prepared environment(Context "ui"prepared.(bindings)true None)prepared.(visual)
  (Allocation [] b.(State.next_occurrence)0 prepared.(Registry.remaining)).
Fixpoint find_event(fuel:nat)(event_id:event)(nodes:list expanded):option expanded:=
 match fuel,nodes with _,[]=>None|O,_=>None|S k,node::rest=>match node with
 |Message _ _=>find_event k event_id rest
 |Mounted current _ _ children=>
   if same_owner event_id.(event_owner)current.(event_owner)&&String.eqb event_id.(path)current.(path)&&N.eqb event_id.(occurrence)current.(occurrence)
   then Some node else match find_event k event_id children with Some node=>Some node|None=>find_event k event_id rest end end end.
