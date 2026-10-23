From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Sources Vocabulary Types.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Definition declaration:=Vocabulary.is_declaration.
Definition declaration_attributes:=Vocabulary.declaration_attributes.
Definition attrs_known tag attrs:=forallb(fun a=>existsb(String.eqb a.(attribute_name))(declaration_attributes tag))attrs.
Definition binding_set {A}(name:string)(value:A)(env:list(string*A)):=(name,value)::filter(fun kv=>negb(String.eqb name(fst kv)))env.
Fixpoint evaluate_attributes budget environment attributes : outcome(list(string*json))*nat:=
 match attributes with []=>(Good[],budget)|a::rest=>
 match evaluate budget environment a.(attribute_value)with
 | (Error e,remaining_budget)=>(Error e,remaining_budget)
 | (Good value,remaining_budget)=>match evaluate_attributes remaining_budget environment rest with
   |(Error e,remaining_budget)=>(Error e,remaining_budget)|(Good values,remaining_budget)=>(Good((a.(attribute_name),value)::values),remaining_budget)end end end.
Definition literal_text name attrs:=j <-? literal_attr name attrs;;from_option("Text literal required: "++name)(as_string j).
Definition lexical_id attrs:=match literal_text "id"attrs with Good id=>if valid_id id then Some id else None|_=>None end.
Definition literal_bind tag attrs:=match component tag with
 |Some spec=>match spec.(component_role)with Field=>match literal_text "bind"attrs with Good _=>true|_=>false end|_=>true end
 |None=>true end.
Fixpoint structural_scan(fuel:nat)(scope:string)(seen:list string)(nodes:list element):list element*list string*option diagnostic:=
 match fuel,nodes with
 | _,[]=>([],seen,None)
 | O,_=>([],seen,Some(Diagnostic scope "Component structure budget" true))
 | S k,(Element tag attrs children closed)::rest=>
   if declaration tag then([],seen,Some(Diagnostic (scope++"/"++tag) "Declarations are only allowed directly inside ui" true))else
   if negb(literal_bind tag attrs)then([],seen,Some(Diagnostic (scope++"/"++tag) "Input bind must be a literal root state id" true))else
   let template:=String.eqb tag "node-template"in
   let id:=if template then Some ""else lexical_id attrs in
   match id with
   | None=>([],seen,Some(Diagnostic (scope++"/"++tag) "Component id must be a literal valid identifier" true))
   | Some id=>let key:=scope++"/"++id in
     if negb template&&existsb(String.eqb key)seen then([],seen,Some(Diagnostic key "Duplicate component id in lexical scope" true))else
     let seen:=if template then seen else key::seen in
     let child_scope:=if template||String.eqb tag "each"||String.eqb tag "graph-view"then scope++"/template/"++id else scope in
     let '(children,seen,error):=structural_scan k child_scope seen children in
     let node:=Element tag attrs children closed in
     match error with Some _=>([node],seen,error)|None=>
       let '(rest,seen,error):=structural_scan k scope seen rest in(node::rest,seen,error)end
   end end.
Record dataset:=Dataset{dataset_id:string;columns:list string;row_keys:list string;rows:list json}.
Record prepared:=Prepared{
 prepared_locals:list local;bindings:list(string*outcome json);requests:list request;
 sources:list(string*json);datasets:list dataset;visual:list element;diagnostics:list diagnostic;
 remaining:nat;layout_started:bool;fatal:bool;declared:list string;component_names:list string }.
Definition start(previous:list local):prepared:=Prepared [] [] [] [] [] [] [] Bounds.evaluation_steps false false [] [].
Definition with_diagnostic_at path reason stop p:=Prepared p.(prepared_locals)p.(bindings)p.(requests)p.(sources)p.(datasets)p.(visual)
 (List.app p.(diagnostics)[Diagnostic path reason stop])p.(remaining)p.(layout_started)(p.(fatal)||stop) p.(declared)p.(component_names).
Definition with_diagnostic:=with_diagnostic_at "ui".
Definition with_budget budget p:=Prepared p.(prepared_locals)p.(bindings)p.(requests)p.(sources)p.(datasets)p.(visual)p.(diagnostics)
 budget p.(layout_started)p.(fatal)p.(declared)p.(component_names).
Definition declare_binding id value p:=Prepared p.(prepared_locals)(binding_set id value p.(bindings))p.(requests)p.(sources)p.(datasets)
 p.(visual)p.(diagnostics)p.(remaining)p.(layout_started)p.(fatal)(id::p.(declared))p.(component_names).
Definition add_local l p:=
 let p:=declare_binding l.(local_id)(Good(canonical l))p in
 Prepared(List.app p.(prepared_locals)[l])p.(bindings)p.(requests)p.(sources)p.(datasets)p.(visual)p.(diagnostics)p.(remaining)p.(layout_started)p.(fatal)p.(declared)p.(component_names).
Definition add_source req value p:=
 let p:=declare_binding req.(source_name)(Good value)p in
 Prepared p.(prepared_locals)p.(bindings)(List.app p.(requests)[req])((req.(source_name),value)::p.(sources))p.(datasets)p.(visual)p.(diagnostics)p.(remaining)p.(layout_started)p.(fatal)p.(declared)p.(component_names).
Definition add_dataset ds p:=
 let p:=declare_binding ds.(dataset_id)(Good(JArray ds.(rows)))p in
 Prepared p.(prepared_locals)p.(bindings)p.(requests)p.(sources)(ds::p.(datasets))p.(visual)p.(diagnostics)p.(remaining)p.(layout_started)p.(fatal)p.(declared)p.(component_names).
Definition graph_literal value:=
 match value with
 | JString s=>if (String.length s<=?Bounds.identifier_length)&&negb(String.eqb s "")then
   match parse_natural s with Some n=>if String.eqb(show_natural n)s then Some n else None|None=>None end else None
 | JNumber _=>match decimal_value value with Some d=>if Decimal.integral d&&Z.leb 0(Decimal.units d)
   then Some(Z.to_N(Z.quot(Decimal.units d)Decimal.scale))else None|None=>None end
 | _=>None end.
Definition parse_source id attrs:=
 kind <-? literal_text "kind"attrs;;mode <-? literal_text "mode"attrs;;graph <-? literal_attr "graph-id"attrs;;
 graph <-? from_option "graph-id must be a nonnegative integer or canonical 64-digit string"(graph_literal graph);;
 if String.eqb kind "task-graph"&&String.eqb mode "live"then Good(Request id graph)else Error "Unsupported source kind or mode".
Definition parse_dataset id attrs:=
 j <-? literal_attr "columns"attrs;;xs <-? from_option "Dataset columns must be a string list"(as_array j);;
 names <-? from_option "Dataset columns must be strings"(Schema.decode_list as_string xs);;
 if negb(Nat.eqb(List.length names)0)&&(List.length names<=?Bounds.record_fields)&&Schema.unique_names names&&forallb(fun s=>negb(String.eqb s ""))names
 then Good(Dataset id names [][])else Error "Dataset columns must be unique and nonempty".
Definition dataset_row attrs p:outcome prepared:=
 id <-? literal_text "dataset"attrs;;key <-? literal_text "key"attrs;;value <-? literal_attr "value"attrs;;
 ds <-? from_option "Unknown dataset"(find(fun ds=>String.eqb id ds.(dataset_id))p.(datasets));;
 fs <-? from_option "Dataset row must be a literal record"(as_object value);;
 if negb(String.eqb key "")&&negb(existsb(String.eqb key)ds.(row_keys))&&
    (List.length ds.(rows)<?Bounds.collection_items)&&Nat.eqb(List.length fs)(List.length ds.(columns))&&
    forallb(fun name=>match lookup name fs with Some _=>true|None=>false end)ds.(columns)then
 let next:=Dataset id ds.(columns)(key::ds.(row_keys))(List.app ds.(rows)[value])in
 let budget:=value_cost 33 value in
 remaining <-? spend p.(remaining)budget;;
 Good(Prepared p.(prepared_locals)(binding_set id(Good(JArray next.(rows)))p.(bindings))p.(requests)p.(sources)
 (map(fun ds=>if String.eqb id ds.(dataset_id)then next else ds)p.(datasets))p.(visual)p.(diagnostics)remaining p.(layout_started)p.(fatal)p.(declared)p.(component_names))
 else Error "Invalid or duplicate dataset row".
Definition declare_one previous old_sources environment tag attrs p:=
 let path:=match lexical_id attrs with Some id=>id|None=>tag end in
 if negb(attrs_known tag attrs) then with_diagnostic_at path "Unknown declaration attribute"true p else
 if negb(forallb(fun a=>if String.eqb tag "derive"&&String.eqb a.(attribute_name)"value"then true else is_literal 33 a.(attribute_value))attrs)then with_diagnostic_at path "Declaration attributes must be literal"true p else
 if String.eqb tag "row"then match dataset_row attrs p with Good p=>p|Error e=>with_diagnostic_at path e false p end else
 if Bounds.declarations<=?List.length p.(declared)then with_diagnostic_at path "Declaration count limit"true p else
 if p.(layout_started)then with_diagnostic_at path "Declarations must precede visual children"true p else
 match lexical_id attrs with
 | None=>with_diagnostic_at path "Declaration requires a valid literal id"true p
 | Some id=>if negb(valid_binding id)then with_diagnostic_at path "Declaration id must be an expression identifier"true p else
 if existsb(String.eqb id)p.(declared)then with_diagnostic_at path "Duplicate declaration id"true p else
 if String.eqb tag "state"then match Local.from_attributes attrs with
   | Good l=>add_local(Local.reuse previous l)p|Error e=>with_diagnostic_at path e true p end
 else if String.eqb tag "derive"then
   match attr "value"attrs with
   | None=>with_diagnostic_at path "derive requires value"true p
   | Some a=>let '(value,remaining_budget):=evaluate p.(remaining)p.(bindings)a.(attribute_value)in
     let p:=declare_binding id value(with_budget remaining_budget p)in
     match value with Good _=>p|Error e=>with_diagnostic_at id e false p end end
 else if String.eqb tag "source"then match parse_source id attrs with
   | Good req=>let previous:=match lookup id old_sources with Some v=>v|None=>JNull end in
      add_source req(Sources.refresh req environment previous)p
   | Error e=>with_diagnostic_at path e true p end
 else if String.eqb tag "dataset"then match parse_dataset id attrs with Good ds=>add_dataset ds p|Error e=>with_diagnostic_at path e true p end
 else with_diagnostic_at path "Unknown declaration"true p end.
Fixpoint prepare_children fuel previous old_sources environment children p:=
 match fuel,children with
 | _,[]=>p|O,_=>with_diagnostic "Definition work budget"true p
 | S k,(Element tag attrs children closed)::rest=>
   if p.(fatal)then p else
   if declaration tag then
     if negb closed||negb(Nat.eqb(List.length children)0)then with_diagnostic "Declarations must be self-closing"true p else
     prepare_children k previous old_sources environment rest(declare_one previous old_sources environment tag attrs p)
   else
     let '(nodes,names,error):=structural_scan 4096 ""p.(component_names)[Element tag attrs children closed]in
     let p:=Prepared p.(prepared_locals)p.(bindings)p.(requests)p.(sources)p.(datasets)(List.app p.(visual)nodes)p.(diagnostics)
       p.(remaining)true p.(fatal)p.(declared)names in
     match error with Some e=>with_diagnostic_at e.(diagnostic_path)e.(diagnostic_message)e.(diagnostic_fatal)p|None=>prepare_children k previous old_sources environment rest p end
 end.
Definition prepare syntax previous old_sources environment:=
 match Syntax.roots syntax with
 | Element "ui"attrs children _::rest=>
   match lexical_id attrs with
   | None=>with_diagnostic "ui requires one valid literal id"true(start previous)
   | Some _=>if forallb(fun a=>String.eqb a.(attribute_name)"id")attrs then
       let p:=prepare_children 2048 previous old_sources environment children(start previous)in
       if Nat.eqb(List.length rest)0 then p else with_diagnostic "Exactly one ui root is allowed"true p
     else with_diagnostic "Unknown ui attribute"true(start previous)end
 | []=>if syntax.(sealed)then with_diagnostic "The document ended without a ui root"true(start previous)else start previous
 | _=>with_diagnostic "Exactly one ui root is required"true(start previous)end.
