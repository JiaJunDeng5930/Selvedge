From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain State Codec Tasks CommandExecution.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Work Worktree.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_graphs (world_features value).
Definition lookup (id:N) (value:world) := match registry_at id (registry value) with Some graph=>graph | None=>None end.
Definition store (id:N) (graph:Selvedge.Features.Domain.task_graph) (value:world) :=
 Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_graphs (if N.eqb id (N.of_nat (List.length (registry value))) then registry value++[Some graph] else replace id (Some graph) (registry value)) (world_features value)) value.
Definition resolve (key:string) (nodes:list Selvedge.Features.Domain.resolved_node) := option_map Selvedge.Features.Domain.node_task (find (fun node=>String.eqb key (Selvedge.Features.Domain.node_key node)) nodes).
Definition maximum_message_depth : nat := 8.
Definition maximum_message_nodes : nat := 64.
Definition maximum_rule_actions : nat := 8.
Fixpoint parse_message (depth:nat) (source:json) :option Selvedge.Features.Domain.graph_message := match depth with O=>None | S rest=>
 match string_field "kind" source with
 | Some "output"=>if Worktree.shape [Field "kind" KText] source then Some Selvedge.Features.Domain.GraphOutput else None
 | Some "literal"=>if Worktree.shape [Field "kind" KText;Field "value" KText] source then option_map Selvedge.Features.Domain.GraphLiteral (string_field "value" source) else None
 | Some "concat"=>if Worktree.shape [Field "kind" KText;Field "parts" (KArray KJson)] source then
 match array_field "parts" source with Some parts=>if Nat.leb (List.length parts) maximum_message_nodes then option_map Selvedge.Features.Domain.GraphConcat (traverse (parse_message rest) parts) else None | None=>None end else None
 | _=>None end end.
Fixpoint message_size (message:Selvedge.Features.Domain.graph_message) :nat := match message with
 | Selvedge.Features.Domain.GraphOutput|Selvedge.Features.Domain.GraphLiteral _=>1 | Selvedge.Features.Domain.GraphConcat parts=>S (fold_right (fun part total=>message_size part+total)%nat 0%nat parts) end.
Definition parse_action (source:json) :option Selvedge.Features.Domain.graph_action :=
 if Worktree.shape [Field "target" KText;Field "message" KJson] source then match string_field "target" source,field "message" source with
 | Some target,Some input=>match parse_message maximum_message_depth input with Some message=>if Nat.leb (message_size message) maximum_message_nodes then Some (Selvedge.Features.Domain.GraphAction target message) else None | None=>None end | _,_=>None end else None.
Definition parse_rule (source:json) :option Selvedge.Features.Domain.graph_rule :=
 if Worktree.shape [Field "key" KText;Field "source" KText;Field "actions" (KArray KJson)] source then
 match string_field "key" source,string_field "source" source,array_field "actions" source with
 | Some key,Some source,Some actions=>if Nat.leb (List.length actions) maximum_rule_actions then option_map (Selvedge.Features.Domain.GraphRule key source) (traverse parse_action actions) else None | _,_,_=>None end else None.
Definition parse_node (source:json) :option Selvedge.Features.Domain.graph_node := match natural_field "task_id" source with
 | Some id=>if Worktree.shape [Field "key" KText;Field "task_id" KNatural] source then option_map (fun key=>Selvedge.Features.Domain.ExistingNode key id) (string_field "key" source) else None
 | None=>if Worktree.shape [Field "key" KText;Field "profile" (KOptional KText);Field "reasoning" (KOptional KText);Field "message" (KOptional KText);Field "settings" (KOptional KJson)] source then
 match string_field "key" source with Some key=>Some (Selvedge.Features.Domain.SpawnNode key (text_default "profile" source "") (text_default "reasoning" source "default") [TextPart (text_default "message" source "")] (match field "settings" source with Some settings=>settings | None=>JObject [] end)) | None=>None end else None end.
Definition node_key (node:Selvedge.Features.Domain.graph_node) := match node with Selvedge.Features.Domain.ExistingNode key _|Selvedge.Features.Domain.SpawnNode key _ _ _ _=>key end.
Definition unique (keys:list string) := forallb nonempty keys && Schema.unique_names keys.
Fixpoint message_depth (depth:nat) (message:Selvedge.Features.Domain.graph_message) :bool :=
 match depth with O=>false | S remaining=>match message with
 | Selvedge.Features.Domain.GraphOutput|Selvedge.Features.Domain.GraphLiteral _=>true
 | Selvedge.Features.Domain.GraphConcat parts=>forallb (message_depth remaining) parts
 end end.
Definition valid_message (message:Selvedge.Features.Domain.graph_message) :=
 message_depth maximum_message_depth message && Nat.leb (message_size message) maximum_message_nodes.
Definition valid_declaration (name:string) (nodes:list Selvedge.Features.Domain.graph_node) (rules:list Selvedge.Features.Domain.graph_rule) :=
 let keys:=map node_key nodes in nonempty name && Utf8.well_formed name && Nat.leb (List.length nodes) 32 && Nat.leb (List.length rules) 32 && unique keys && unique (map Selvedge.Features.Domain.rule_key rules) &&
 forallb (fun rule=>existsb (String.eqb (Selvedge.Features.Domain.rule_source rule)) keys &&
 Nat.leb (List.length (Selvedge.Features.Domain.rule_actions rule)) maximum_rule_actions &&
 forallb (fun action=>existsb (String.eqb (Selvedge.Features.Domain.action_target action)) keys &&
   valid_message (Selvedge.Features.Domain.action_message action)) (Selvedge.Features.Domain.rule_actions rule)) rules.
Record declaration := Declaration { declaration_name:string;
 declaration_nodes:list Selvedge.Features.Domain.graph_node;
 declaration_rules:list Selvedge.Features.Domain.graph_rule }.
Definition admissible (value:declaration) :=
 valid_declaration (declaration_name value) (declaration_nodes value) (declaration_rules value)=true.
Definition checked_declaration := { value:declaration | admissible value }.
Definition construct (value:declaration) :option checked_declaration.
Proof.
 destruct (valid_declaration (declaration_name value) (declaration_nodes value)
   (declaration_rules value)) eqn:checked.
 - exact (Some (exist _ value checked)).
 - exact None.
Defined.
(** Arrangements compose declarations; admission checks their combined keys,
    references and bounds. No new execution case is required for a new graph. *)
Definition compose (name:string) (left right:declaration) :=
 Declaration name (declaration_nodes left++declaration_nodes right)
   (declaration_rules left++declaration_rules right).
Definition paired (name:string) (tests implementation:Selvedge.Features.Domain.graph_node)
 (rule:string) (message:Selvedge.Features.Domain.graph_message) :=
 Declaration name [tests;implementation]
 [Selvedge.Features.Domain.GraphRule rule (node_key tests)
   [Selvedge.Features.Domain.GraphAction (node_key implementation) message]].
Definition work_valid (owner:option N) (value:world) := match owner with None=>true | Some id=>match Work.lookup id value with Some _=>true | None=>false end end.
Definition task_in_work (owner:option N) (id:N) (value:world) := match owner with None=>true | Some expected=>match Work.task_owner id value with Some actual=>N.eqb expected actual | None=>false end end.
Inductive births := Born (value:world) (nodes:list Selvedge.Features.Domain.resolved_node) (effects:list Selvedge.Kernel.State.effect) | BirthFailed (reply:json).
Definition birth (owner:option N) (caller:option N) (node:Selvedge.Features.Domain.graph_node) (progress:births) :births := match progress with
 | BirthFailed failure=>BirthFailed failure | Born value previous effects=>match node with
 | Selvedge.Features.Domain.ExistingNode key id=>match Selvedge.Kernel.State.find_task id value with None=>BirthFailed (Selvedge.Kernel.State.failure "task_not_found" "A referenced graph task does not exist") | Some _=>
 if task_in_work owner id value then Born value (previous++[Selvedge.Features.Domain.ResolvedNode key id]) effects else BirthFailed (Selvedge.Kernel.State.failure "task_graph_work_mismatch" "Every existing Task in a Work graph must already belong to that Work") end
 | Selvedge.Features.Domain.SpawnNode key profile effort contents settings=>
 let created:=Worktree.create_in_work owner (fun current=>Worktree.create_selected profile (Some effort) contents (Some settings) false caller None current) value in
 if bool_default "ok" (decision_reply created) false then Born (decision_world created) (previous++[Selvedge.Features.Domain.ResolvedNode key (Selvedge.Kernel.State.next_task value)]) (effects++decision_effects created)
 else BirthFailed (decision_reply created) end end.
Definition invalid_declaration (value:world) :=
 Selvedge.Kernel.State.reject "invalid_task_graph" "Task graph names and keys must be nonempty and unique, every reference must resolve, and declaration bounds must hold" value.
Definition install (id:N) (owner:option N) (checked:checked_declaration) (caller:option N) (original:world) :=
 if work_valid owner original then
 let declaration:=proj1_sig checked in
 match fold_left (fun progress node=>birth owner caller node progress) (declaration_nodes declaration) (Born original [] []) with
 | BirthFailed reply=>Selvedge.Kernel.State.Decision original reply []
 | Born value resolved effects=>let graph:=Selvedge.Features.Domain.TaskGraph (declaration_name declaration) resolved (declaration_rules declaration) [] in let installed:=store id graph value in
 let owned:=match owner with None=>installed | Some owner=>Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_graph_owners ((id,owner)::filter (fun entry=>negb (N.eqb id (fst entry))) (Selvedge.Features.Domain.feature_graph_owners (world_features installed))) (world_features installed)) installed end in
 Selvedge.Kernel.State.accept (Observation.graph_json id graph) owned effects end
 else invalid_declaration original.
Definition declare (id:N) (owner:option N) (name:string) (node_sources rule_sources:list json) (caller:option N) (value:world) :=
 match traverse parse_node node_sources,traverse parse_rule rule_sources with Some nodes,Some rules=>
 match construct (Declaration name nodes rules) with
 | Some checked=>install id owner checked caller value
 | None=>invalid_declaration value end
 | _,_=>Selvedge.Kernel.State.reject "invalid_task_graph" "Invalid Task graph declaration fields" value end.
Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_list_task_graphs _=>Some (Selvedge.Kernel.State.success (JObject [("graphs",JArray (Observation.present_values Observation.graph_json (registry value)))]))
 | Selvedge.Generated.Commands.Cmd_read_task_graph p=>Some (match lookup (Selvedge.Generated.Commands.read_task_graph_graph_id p) value with Some graph=>Selvedge.Kernel.State.success (Observation.graph_json (Selvedge.Generated.Commands.read_task_graph_graph_id p) graph) | None=>Selvedge.Kernel.State.failure "task_graph_not_found" "The Task graph does not exist" end) | _=>None end.
Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_create_task_graph p=>Some (if Nat.ltb (List.length (filter (fun graph=>match graph with Some _=>true | None=>false end) (registry value))) 32 then declare (N.of_nat (List.length (registry value))) (Selvedge.Generated.Commands.create_task_graph_work_id p) (Selvedge.Generated.Commands.create_task_graph_name p) (Selvedge.Generated.Commands.create_task_graph_nodes p) (Selvedge.Generated.Commands.create_task_graph_rules p) caller value else Selvedge.Kernel.State.reject "task_graph_capacity" "At most 32 live Task graphs may be installed" value)
 | Selvedge.Generated.Commands.Cmd_update_task_graph p=>Some (let id:=Selvedge.Generated.Commands.update_task_graph_graph_id p in match lookup id value with None=>Selvedge.Kernel.State.reject "task_graph_not_found" "The Task graph does not exist" value | Some _=>declare id (Selvedge.Features.Domain.association id (Selvedge.Features.Domain.feature_graph_owners (world_features value))) (Selvedge.Generated.Commands.update_task_graph_name p) (Selvedge.Generated.Commands.update_task_graph_nodes p) (Selvedge.Generated.Commands.update_task_graph_rules p) caller value end)
 | Selvedge.Generated.Commands.Cmd_delete_task_graph p=>Some (let id:=Selvedge.Generated.Commands.delete_task_graph_graph_id p in match lookup id value with None=>Selvedge.Kernel.State.reject "task_graph_not_found" "The Task graph does not exist" value | Some _=>
 let features:=world_features value in Selvedge.Kernel.State.accept (JObject [("graph_id",number id)]) (Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_graph_owners (filter (fun entry=>negb (N.eqb id (fst entry))) (Selvedge.Features.Domain.feature_graph_owners features)) (Selvedge.Features.State.with_graphs (replace id None (registry value)) features)) value) [] end)
 | _=>None end.
Fixpoint expand (message:Selvedge.Features.Domain.graph_message) (output:string) :string := match message with
 | Selvedge.Features.Domain.GraphOutput=>output | Selvedge.Features.Domain.GraphLiteral text=>text | Selvedge.Features.Domain.GraphConcat parts=>fold_right (fun part rest=>String.append (expand part output) rest) "" parts end.
Definition same_origin (a b:output_origin) := N.eqb (origin_producer a) (origin_producer b) && N.eqb (origin_operation a) (origin_operation b) && N.eqb (origin_part a) (origin_part b) &&
 match origin_mode a,origin_mode b with PlainOutput,PlainOutput|InteractiveOutput,InteractiveOutput=>true | _,_=>false end.
Definition seen_origin (origin:output_origin) (task:task) := existsb (fun message=>match message with AssistantMessage existing _=>same_origin origin existing | _=>false end) (task_history task).
Definition new_outputs (before:world) (id:N) (task:task) :=
 let added:=skipn (match Selvedge.Kernel.State.find_task id before with Some previous=>List.length (task_history previous) | None=>0%nat end) (task_history task) in
 if existsb (fun message=>match message with FunctionCall _=>true | _=>false end) added then [] else
 fold_right (fun message rest=>match message with
 | AssistantMessage origin text=>if N.eqb id (origin_producer origin) && negb (String.eqb text "") &&
 (match origin_mode origin with PlainOutput=>true | _=>false end) &&
 negb (match Selvedge.Kernel.State.find_task id before with Some previous=>seen_origin origin previous | None=>false end) then text::rest else rest | _=>rest end) [] added.
Record delivery := Delivery { delivery_graph:N;delivery_rule:string;delivery_target:N;delivery_text:string }.
Definition pending_rule (source graph:N) (nodes:list Selvedge.Features.Domain.resolved_node) (rule:Selvedge.Features.Domain.graph_rule) (output:string) :=
 match resolve (Selvedge.Features.Domain.rule_source rule) nodes with Some expected=>if N.eqb source expected then fold_right
 (fun action rest=>match resolve (Selvedge.Features.Domain.action_target action) nodes with Some target=>Delivery graph (Selvedge.Features.Domain.rule_key rule) target (expand (Selvedge.Features.Domain.action_message action) output)::rest | None=>rest end) [] (Selvedge.Features.Domain.rule_actions rule) else [] | None=>[] end.
Definition pending_deliveries (source:N) (output:string) (value:world) := flat_map (fun pair=>match snd pair with None=>[] | Some graph=>
 flat_map (fun rule=>pending_rule source (fst pair) (Selvedge.Features.Domain.graph_nodes graph) rule output) (Selvedge.Features.Domain.graph_rules graph) end) (indexed (fun id graph=>(id,graph)) 0 (registry value)).
Definition record_receipt (graph:N) (receipt:Selvedge.Features.Domain.graph_receipt) (value:world) := match lookup graph value with None=>value | Some graph_value=>
 let combined:=Selvedge.Features.Domain.graph_receipts graph_value++[receipt] in
 store graph (Selvedge.Features.Domain.TaskGraph (Selvedge.Features.Domain.graph_name graph_value) (Selvedge.Features.Domain.graph_nodes graph_value) (Selvedge.Features.Domain.graph_rules graph_value) (skipn (List.length combined-256) combined)) value end.
Definition send_delivery (source:N) (item:delivery) (result:decision) :=
 let sent:=Tasks.send (delivery_target item) [TextPart (delivery_text item)] (decision_world result) in
 Selvedge.Kernel.State.Decision (record_receipt (delivery_graph item) (Selvedge.Features.Domain.GraphReceipt source (delivery_rule item) (delivery_target item) (decision_reply sent)) (decision_world sent))
 (decision_reply result) (decision_effects result++decision_effects sent).
Definition react_output (source:N) (output:string) (result:decision) :=
 fold_left (fun progress item=>send_delivery source item progress) (pending_deliveries source output (decision_world result)) result.
Definition after_transition (before:world) (result:decision) :=
 fold_left (fun progress pair=>fold_left (fun current output=>react_output (fst pair) output current)
 (new_outputs before (fst pair) (snd pair)) progress)
 (indexed (fun id task=>(id,task)) 0 (world_tasks (decision_world result))) result.
