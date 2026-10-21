From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction.Interactive Require Import Expression.
Import ListNotations.
Open Scope string_scope.
Record request := Request { source_name:string; graph_id:N }.
Definition number_id j :=match j with JNumber s|JString s=>parse_natural s|_=>None end.
Definition id_text j :=option_map show_natural(number_id j).
Definition required name j:=from_option("Missing resource field: "++name)(field name j).
Definition required_array name j:=from_option("Missing resource list: "++name)(array_field name j).
Definition required_text name j:=from_option("Missing resource text: "++name)(string_field name j).
Fixpoint traverse{A B}(f:A->outcome B)(xs:list A):outcome(list B):=
 match xs with []=>Good[]|x::xs=>y <-? f x;;ys <-? traverse f xs;;Good(y::ys)end.
Definition find_id name id xs:=find(fun x=>match field name x with
 | Some j=>match number_id j with Some n=>N.eqb id n|None=>false end|None=>false end)xs.
Definition operation_projection operation:outcome json:=
 id <-? required "operation_id"operation;;id <-? from_option "Invalid operation id"(id_text id);;
 name <-? required_text "tool"operation;;stage <-? required_text "stage"operation;;
 awaiting <-? from_option "Missing operation awaitingHuman fact"(bool_field "awaitingHuman"operation);;
 Good(JObject[("id",JString id);("name",JString name);("stage",JString stage);("awaitingHuman",JBool awaiting)]).
Definition task_projection task : outcome json:=
 id <-? required "id"task;;id <-? from_option "Invalid task id"(id_text id);;
 title <-? required_text "title"task;;control <-? required_text "control"task;;phase <-? required_text "phase"task;;
 working <-? from_option "Missing authoritative working fact"(bool_field "working"task);;
 awaiting <-? from_option "Missing authoritative awaitingHuman fact"(bool_field "awaitingHuman"task);;
 label <-? required_text "statusLabel"task;;messages <-? required "pendingMessages"task;;raw_operations <-? required_array "operations"task;;operations <-? traverse operation_projection raw_operations;;
 Good(JObject[("id",JString id);("title",JString title);("control",JString control);("phase",JString phase);
 ("working",JBool working);("awaitingHuman",JBool awaiting);("pendingMessages",messages);("operations",JArray operations);("statusLabel",JString label)]).
Definition node_projection graph tasks node : outcome json:=
 key <-? required_text "key"node;;taskid <-? required "task_id"node;;taskid <-? from_option "Invalid graph task id"(number_id taskid);;
 task <-? match find_id "id"taskid tasks with Some task=>task_projection task|None=>Good JNull end;;
 let identity:=render_json(JArray[JString(show_natural graph);JString key;JString(show_natural taskid)])in
 Good(JObject[("identity",JString identity);("key",JString key);("taskId",JString(show_natural taskid));("task",task)]).
Definition node_identity key nodes :=
 match find(fun node=>match string_field "key"node with Some id=>String.eqb id key|None=>false end)nodes with
 | Some node=>string_field "identity"node|None=>None end.
Definition edge_projection graph nodes source rule ordinal action : outcome json:=
 target <-? required_text "target"action;;
 source_identity <-? from_option "Graph edge source is absent"(node_identity source nodes);;
 target_identity <-? from_option "Graph edge target is absent"(node_identity target nodes);;
 kind <-? required "message"action;;kind <-? required_text "kind"kind;;
 let identity:=render_json(JArray[JString(show_natural graph);JString rule;JString(show_nat ordinal);JString source_identity;JString target_identity])in
 Good(JObject[("identity",JString identity);("ruleKey",JString rule);("sourceIdentity",JString source_identity);
 ("targetIdentity",JString target_identity);("actionKind",JString kind)]).
Fixpoint action_edges graph nodes source rule ordinal actions:=
 match actions with []=>Good[]|action::rest=>
 edge <-? edge_projection graph nodes source rule ordinal action;;
 edges <-? action_edges graph nodes source rule(S ordinal)rest;;Good(edge::edges)end.
Definition rule_edges graph nodes rule:=
 source <-? required_text "source"rule;;key <-? required_text "key"rule;;actions <-? required_array "actions"rule;;action_edges graph nodes source key 0 actions.
Definition graph_projection graph_id graph world : outcome json:=
 name <-? required_text "name"graph;;raw_nodes <-? required_array "nodes"graph;;tasks <-? required_array "tasks"world;;
 nodes <-? traverse(node_projection graph_id tasks)raw_nodes;;rules <-? required_array "rules"graph;;
 edges <-? traverse(rule_edges graph_id nodes)rules;;
 Good(JObject[("id",JString(show_natural graph_id));("name",JString name);("nodes",JArray nodes);("edges",JArray(List.concat edges))]).
Definition handle status fresh sequence value:=JObject[("status",JString status);("fresh",JBool fresh);("sequence",JString sequence);("value",value)].
Definition refresh(req:request)(environment previous:json):json:=
 match bool_field "revoked"environment with
 | Some true=>handle "forbidden"false ""JNull
 | _=>match bool_field "connected"environment with
   | Some false=>match string_field "status"previous,field "value"previous,string_field "sequence"previous with
     | Some "ready",Some value,Some sequence=>handle "ready"false sequence value
     | _,_,_=>handle "loading"false ""JNull end
   | Some true=>match field "world"environment with
     | Some world=>match array_field "graphs"world with
       | Some graphs=>match field "sequence"world with
       | Some sequence=>match id_text sequence with
         | Some sequence=>match find_id "graph_id"req.(graph_id)graphs with
         | None=>handle "missing"true sequence JNull
         | Some graph=>match graph_projection req.(graph_id)graph world with
           | Good value=>handle "ready"true sequence value
           | Error reason=>JObject[("status",JString "error");("fresh",JBool false);("sequence",JString sequence);("value",JNull);("error",JString reason)]end end
       | None=>handle "loading"false ""JNull end
       | None=>handle "loading"false ""JNull end
       | None=>handle "loading"false ""JNull end
     | None=>handle "loading"false ""JNull end
   | None=>handle "loading"false ""JNull end end.
Definition ready_fresh j:=match string_field "status"j,bool_field "fresh"j with Some "ready",Some true=>true|_,_=>false end.
