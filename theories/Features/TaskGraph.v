From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain State Codec Conversation Tasks CommandExecution.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Work Worktree TaskGraphDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_graphs (world_features value).
Definition lookup (id:N) (value:world) := match registry_at id (registry value) with Some graph=>graph | None=>None end.
Definition store (id:N) (graph:Selvedge.Features.Domain.task_graph) (value:world) :=
 Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_graphs (if N.eqb id (N.of_nat (List.length (registry value))) then registry value++[Some graph] else replace id (Some graph) (registry value)) (world_features value)) value.
Definition resolve (key:string) (nodes:list Selvedge.Features.Domain.resolved_node) := option_map Selvedge.Features.Domain.node_task (find (fun node=>String.eqb key (Selvedge.Features.Domain.node_key node)) nodes).
Definition maximum_message_depth := TaskGraphDeclarations.maximum_message_depth.
Definition maximum_message_nodes := TaskGraphDeclarations.maximum_message_nodes.
Definition maximum_rule_actions := TaskGraphDeclarations.maximum_rule_actions.
Fixpoint parse_message (depth:nat) (source:json) :option Selvedge.Features.Domain.graph_message := match depth with O=>None | S rest=>
 match Schema.decode TaskGraphDeclarations.output_fields source with Some _=>Some Selvedge.Features.Domain.GraphOutput | None=>
 match Schema.decode TaskGraphDeclarations.literal_fields source with Some values=>Some (Selvedge.Features.Domain.GraphLiteral (Schema.head (Schema.tail values))) | None=>
 match Schema.decode TaskGraphDeclarations.concat_fields source with Some values=>
 let parts:=Schema.head (Schema.tail values) in
 if Nat.leb (List.length parts) maximum_message_nodes then
 option_map Selvedge.Features.Domain.GraphConcat (traverse (parse_message rest) parts) else None
 | None=>None end end end end.
Fixpoint message_size (message:Selvedge.Features.Domain.graph_message) :nat := match message with
 | Selvedge.Features.Domain.GraphOutput|Selvedge.Features.Domain.GraphLiteral _=>1 | Selvedge.Features.Domain.GraphConcat parts=>S (fold_right (fun part total=>message_size part+total)%nat 0%nat parts) end.
Definition parse_action (source:json) :option Selvedge.Features.Domain.graph_action :=
 match Schema.decode TaskGraphDeclarations.action_fields source with
 | Some values=>match parse_message maximum_message_depth (Schema.head (Schema.tail values)) with
 | Some message=>if Nat.leb (message_size message) maximum_message_nodes then
   Some (Selvedge.Features.Domain.GraphAction (Schema.head values) message) else None
 | None=>None end | None=>None end.
Definition parse_rule (source:json) :option Selvedge.Features.Domain.graph_rule :=
 match Schema.decode TaskGraphDeclarations.rule_fields source with
 | Some values=>let actions:=Schema.head (Schema.tail (Schema.tail values)) in
 if Nat.leb (List.length actions) maximum_rule_actions then
 option_map (Selvedge.Features.Domain.GraphRule (Schema.head values) (Schema.head (Schema.tail values)))
   (traverse parse_action actions) else None
 | None=>None end.
Definition parse_node (source:json) :option Selvedge.Features.Domain.graph_node :=
 match Schema.decode TaskGraphDeclarations.existing_node_fields source with
 | Some values=>Some (Selvedge.Features.Domain.ExistingNode (Schema.head values) (Schema.head (Schema.tail values)))
 | None=>match Schema.decode TaskGraphDeclarations.spawn_node_fields source with
 | Some values=>let profile:=Schema.head (Schema.tail values) in
 let reasoning:=Schema.head (Schema.tail (Schema.tail values)) in
 let message:=Schema.head (Schema.tail (Schema.tail (Schema.tail values))) in
 (* A supplied JSON null must still reach ordinary Task settings admission;
    only an omitted settings field supplies the empty settings object. *)
 let settings:=match field (Schema.field_name TaskGraphDeclarations.node_settings_field) source with
   Some value=>value|None=>JObject [] end in
 Some (Selvedge.Features.Domain.SpawnNode (Schema.head values)
   (match profile with Some value=>value|None=>"" end)
   (match reasoning with Some value=>value|None=>"default" end)
   [TextPart (match message with Some value=>value|None=>"" end)]
   settings)
 | None=>None end end.
Definition node_key (node:Selvedge.Features.Domain.graph_node) := match node with Selvedge.Features.Domain.ExistingNode key _|Selvedge.Features.Domain.SpawnNode key _ _ _ _=>key end.
Definition identifier_nonempty (key:string) := negb (String.eqb key "").
Definition unique (keys:list string) := forallb identifier_nonempty keys && Schema.unique_names keys.
Fixpoint message_depth (depth:nat) (message:Selvedge.Features.Domain.graph_message) :bool :=
 match depth with O=>false | S remaining=>match message with
 | Selvedge.Features.Domain.GraphOutput|Selvedge.Features.Domain.GraphLiteral _=>true
 | Selvedge.Features.Domain.GraphConcat parts=>forallb (message_depth remaining) parts
 end end.
Definition valid_message (message:Selvedge.Features.Domain.graph_message) :=
 message_depth maximum_message_depth message && Nat.leb (message_size message) maximum_message_nodes.
Definition valid_declaration (name:string) (nodes:list Selvedge.Features.Domain.graph_node) (rules:list Selvedge.Features.Domain.graph_rule) :=
 let keys:=map node_key nodes in identifier_nonempty name && Utf8.well_formed name && Nat.leb (List.length nodes) 32 && Nat.leb (List.length rules) 32 && unique keys && unique (map Selvedge.Features.Domain.rule_key rules) &&
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
(* Cache ordinary start outcomes against the original world. Native authority
   observes successful starts before domain failures are projected. *)
Inductive cached_node := CachedExisting (key:string) (id:N)
 | CachedSpawn (key:string) (settings:json) (start:Tasks.start_resolution).
Definition cache_node (caller:option N) (original:world) (node:Selvedge.Features.Domain.graph_node) :=
 match node with
 | Selvedge.Features.Domain.ExistingNode key id=>CachedExisting key id
 | Selvedge.Features.Domain.SpawnNode key profile effort contents settings=>
   CachedSpawn key settings (CommandExecution.resolve_context_start
     (Worktree.creation_entry Worktree.GraphTaskCreation caller)
     profile (Some effort) contents (Some settings) false caller original) end.
Definition cached_allowed (caller:option N) (original:world) (node:cached_node) :=
 match node with CachedExisting _ _=>true
 | CachedSpawn _ settings cached=>Worktree.start_allowed (Some settings) caller original cached end.
Inductive node_plan (original:world) (owner:option N) :=
 | ExistingPlan (key:string) (id:N) (task:task)
     (observed:find_task id original=Some task) (membership:task_in_work owner id original=true)
 | SpawnPlan (key:string) (plan:Worktree.planned_start original).
Arguments ExistingPlan {original owner}.
Arguments SpawnPlan {original owner}.
Inductive node_resolution (original:world) (owner:option N) :=
 | NodeResolved (plan:node_plan original owner) | NodeRefused (reply:json).
Arguments NodeResolved {original owner}.
Arguments NodeRefused {original owner}.
Definition prepare_node (owner:option N) (caller:option N) (original:world)
 (cached:cached_node) :node_resolution original owner.
Proof.
 destruct cached as [key id|key settings cached].
 - destruct (find_task id original) as [task|] eqn:observed.
   + destruct (task_in_work owner id original) eqn:membership.
     * exact (NodeResolved (ExistingPlan key id task observed membership)).
     * exact (NodeRefused (failure "task_graph_work_mismatch"
         "Every existing Task in a Work graph must already belong to that Work")).
   + exact (NodeRefused (failure "task_not_found" "A referenced graph task does not exist")).
 - destruct cached as [cause|start].
   + exact (NodeRefused (failure (Tasks.failure_code (Worktree.creation_entry Worktree.GraphTaskCreation caller) cause)
       (Tasks.failure_message cause))).
   + destruct (Worktree.prepare_resolved Worktree.GraphTaskCreation None None start original) as [plan|reply].
     * exact (NodeResolved (SpawnPlan key plan)).
     * exact (NodeRefused reply).
Defined.
Inductive nodes_resolution (original:world) (owner:option N) :=
 | NodesResolved (plans:list (node_plan original owner)) | NodesRefused (reply:json).
Arguments NodesResolved {original owner}.
Arguments NodesRefused {original owner}.
Fixpoint prepare_nodes (owner:option N) (caller:option N) (original:world)
 (cached:list cached_node) :nodes_resolution original owner := match cached with
 | []=>NodesResolved []
 | node::rest=>match prepare_node owner caller original node with
   | NodeRefused reply=>NodesRefused reply
   | NodeResolved plan=>match prepare_nodes owner caller original rest with
     | NodesRefused reply=>NodesRefused reply | NodesResolved plans=>NodesResolved (plan::plans) end end end.
Record births := Born { born_world:world; born_nodes:list Selvedge.Features.Domain.resolved_node;
 born_effects:list Selvedge.Kernel.State.effect }.
Definition birth {original:world} {owner:option N} (plan:node_plan original owner) (progress:births) :births :=
 let value:=born_world progress in let previous:=born_nodes progress in let effects:=born_effects progress in
 match plan with
 | ExistingPlan key id _ _ _=>Born value (previous++[Selvedge.Features.Domain.ResolvedNode key id]) effects
 | SpawnPlan key plan=>
   let created:=Worktree.consume_planned_start plan value in
   let fresh:=next_task value in
   let owned:=match owner with None=>decision_world created
     | Some owner=>Work.own_birth owner fresh (decision_world created) end in
   Born owned (previous++[Selvedge.Features.Domain.ResolvedNode key fresh]) (effects++decision_effects created) end.
Definition invalid_declaration (value:world) :=
 reject "invalid_task_graph" "Task graph names and keys must be nonempty and unique, every reference must resolve, and declaration bounds must hold" value.
Definition install_cached (id:N) (owner:option N) (checked:checked_declaration)
 (caller:option N) (cached:list cached_node) (original:world) :=
 match prepare_nodes owner caller original cached with
 | NodesRefused reply=>Decision original reply []
 | NodesResolved plans=>
 match fold_left (fun progress plan=>birth plan progress) plans (Born original [] []) with
 | Born value resolved effects=>
   let graph:=Selvedge.Features.Domain.TaskGraph (declaration_name (proj1_sig checked)) resolved
     (declaration_rules (proj1_sig checked)) [] in
   let installed:=store id graph value in
   let owned:=match owner with None=>installed
     | Some owner=>with_features (Selvedge.Features.State.with_graph_owners
       ((id,owner)::filter (fun entry=>negb (N.eqb id (fst entry)))
         (Selvedge.Features.Domain.feature_graph_owners (world_features installed)))
       (world_features installed)) installed end in
   accept (Observation.graph_json id graph) owned effects end end.
Definition install (id:N) (owner:option N) (checked:checked_declaration) (caller:option N) (original:world) :=
 if work_valid owner original then
 install_cached id owner checked caller (map (cache_node caller original) (declaration_nodes (proj1_sig checked))) original
 else reject "work_not_found" "The Work does not exist." original.
Definition graph_capacity (value:world) :=
 Nat.ltb (List.length (filter (fun graph=>match graph with Some _=>true | None=>false end) (registry value))) 32.
Definition declare (creating:bool) (id:N) (owner:option N) (name:string)
 (node_sources rule_sources:list json) (caller:option N) (value:world) :=
 match traverse parse_node node_sources,traverse parse_rule rule_sources with
 | Some nodes,Some rules=>
   let cached:=map (cache_node caller value) nodes in
   if forallb (cached_allowed caller value) cached then
     if work_valid owner value then
       if negb creating || graph_capacity value then
         match construct (Declaration name nodes rules) with
         | Some checked=>install_cached id owner checked caller cached value
         | None=>invalid_declaration value end
       else reject "invalid_task_graph" "At most 32 live Task graphs may be installed" value
     else reject "work_not_found" "The Work does not exist." value
   else Tasks.refuse_start Tasks.NativeFeatureCreation Tasks.AuthorityExpansion value
 | _,_=>reject "invalid_task_graph" "Invalid Task graph declaration fields" value end.
Definition handle_list_task_graphs (payload:Selvedge.Generated.Commands.list_task_graphs_payload) (caller:option N) (value:world) :json :=
 Selvedge.Kernel.State.success (JObject [("graphs",JArray (Observation.present_values Observation.graph_json (registry value)))]).
Definition handle_read_task_graph (payload:Selvedge.Generated.Commands.read_task_graph_payload) (caller:option N) (value:world) :json :=
 match lookup (Selvedge.Generated.Commands.read_task_graph_graph_id payload) value with Some graph=>Selvedge.Kernel.State.success (Observation.graph_json (Selvedge.Generated.Commands.read_task_graph_graph_id payload) graph) | None=>Selvedge.Kernel.State.failure "task_graph_not_found" "The Task graph does not exist" end.
Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_list_task_graphs payload=>Some (handle_list_task_graphs payload _caller value)
 | Selvedge.Generated.Commands.Cmd_read_task_graph p=>Some (handle_read_task_graph p _caller value)
 | _=>None end.
Definition handle_create_task_graph (payload:Selvedge.Generated.Commands.create_task_graph_payload) (caller:option N) (value:world) :decision :=
 declare true (N.of_nat (List.length (registry value))) (Selvedge.Generated.Commands.create_task_graph_work_id payload) (Selvedge.Generated.Commands.create_task_graph_name payload) (Selvedge.Generated.Commands.create_task_graph_nodes payload) (Selvedge.Generated.Commands.create_task_graph_rules payload) caller value.
Definition handle_update_task_graph (payload:Selvedge.Generated.Commands.update_task_graph_payload) (caller:option N) (value:world) :decision :=
 let id:=Selvedge.Generated.Commands.update_task_graph_graph_id payload in match lookup id value with None=>Selvedge.Kernel.State.reject "task_graph_not_found" "The Task graph does not exist" value | Some _=>declare false id (Selvedge.Features.Domain.association id (Selvedge.Features.Domain.feature_graph_owners (world_features value))) (Selvedge.Generated.Commands.update_task_graph_name payload) (Selvedge.Generated.Commands.update_task_graph_nodes payload) (Selvedge.Generated.Commands.update_task_graph_rules payload) caller value end.
Definition handle_delete_task_graph (payload:Selvedge.Generated.Commands.delete_task_graph_payload) (caller:option N) (value:world) :decision :=
 let id:=Selvedge.Generated.Commands.delete_task_graph_graph_id payload in match lookup id value with None=>Selvedge.Kernel.State.reject "task_graph_not_found" "The Task graph does not exist" value | Some _=>
 let features:=world_features value in Selvedge.Kernel.State.accept (JObject [("graph_id",number id)]) (Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_graph_owners (filter (fun entry=>negb (N.eqb id (fst entry))) (Selvedge.Features.Domain.feature_graph_owners features)) (Selvedge.Features.State.with_graphs (replace id None (registry value)) features)) value) [] end.
Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_create_task_graph p=>Some (handle_create_task_graph p caller value)
 | Selvedge.Generated.Commands.Cmd_update_task_graph p=>Some (handle_update_task_graph p caller value)
 | Selvedge.Generated.Commands.Cmd_delete_task_graph p=>Some (handle_delete_task_graph p caller value)
 | _=>None end.
Fixpoint expand (message:Selvedge.Features.Domain.graph_message) (output:string) :string := match message with
 | Selvedge.Features.Domain.GraphOutput=>output | Selvedge.Features.Domain.GraphLiteral text=>text | Selvedge.Features.Domain.GraphConcat parts=>fold_right (fun part rest=>String.append (expand part output) rest) "" parts end.
Definition same_origin (a b:output_origin) := N.eqb (origin_producer a) (origin_producer b) && N.eqb (origin_operation a) (origin_operation b) && N.eqb (origin_part a) (origin_part b) &&
 match origin_mode a,origin_mode b with PlainOutput,PlainOutput|InteractiveOutput,InteractiveOutput=>true | _,_=>false end.
Definition assistant_output (item:message) : option (output_origin * string) :=
 match item with
 | AssistantMessage origin text=>Some (origin,text)
 | ModelContext origin content=>
   if Conversation.provider_assistant_message content
   then Some (origin,Conversation.provider_text content) else None
 | _=>None end.
Definition seen_origin (origin:output_origin) (task:task) := existsb (fun message=>match assistant_output message with Some (existing,_)=>same_origin origin existing | None=>false end) (task_history task).
Definition new_outputs (before:world) (id:N) (task:task) :=
 let added:=skipn (match Selvedge.Kernel.State.find_task id before with Some previous=>List.length (task_history previous) | None=>0%nat end) (task_history task) in
 if existsb (fun message=>match message with FunctionCall _=>true | _=>false end) added then [] else
 fold_right (fun message rest=>match assistant_output message with
 | Some (origin,text)=>if N.eqb id (origin_producer origin) &&
 negb (String.eqb text "") &&
 negb (match Selvedge.Kernel.State.find_task id before with Some previous=>seen_origin origin previous | None=>false end) then text::rest else rest
 | None=>rest end) [] added.
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
