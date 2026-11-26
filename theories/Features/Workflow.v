From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Utf8.
From Selvedge.Foundation Require DependencyIndex IndexedRegistry ScopedRegistry.
From Selvedge.Kernel Require Import Numbers Domain State Codec Tasks CommandExecution.
From Selvedge.Features Require Import WorkflowTypes TaskGraph TaskGraphDeclarations Work Worktree Board BoardFacts.
From Selvedge.Features Require Domain Observation BoardClock.
Module F := Selvedge.Features.Domain.
From Selvedge.Programming Require CommandResult DecisionComposition CardScope.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.
Module D := Selvedge.Programming.ArgumentDeclaration.

Definition graph := @definition F.graph_message.
Definition edge := @connection F.graph_message.
Definition execution := @instance F.graph_message.
Definition graphs v := F.feature_workflows (world_features v).
Definition instance_registry v := F.feature_instances (world_features v).
Definition instances v := IndexedRegistry.contents (ScopedRegistry.rows (instance_registry v)).
Definition active_instances v := ScopedRegistry.selected_entries (instance_registry v).
Definition lookup_graph id v := match registry_at id (graphs v) with Some g => g | None => None end.
Definition lookup_instance id v := IndexedRegistry.lookup id (ScopedRegistry.rows (instance_registry v)).
Definition store_graphs graphs v :=
 with_features (set F.feature_workflows (fun _ => graphs) (world_features v)) v.
Definition store_instances entries v :=
 with_features (set F.feature_instances (fun _ => entries) (world_features v)) v.
Definition store_instance id entry v := store_instances (ScopedRegistry.put id entry (instance_registry v)) v.
Definition ticket_setting := BoardFacts.workflow_setting.
Definition current_instance := BoardFacts.workflow_instance_id.
Definition lookup_node key (g : graph) := find (fun n => String.eqb key (WorkflowTypes.node_key n)) (workflow_nodes g).
Definition outgoing (g : graph) key := filter (fun e => String.eqb key (connection_source e)) (workflow_connections g).
Definition entrance g key := match lookup_node key g with Some (Node _ Entrance) => true | _ => false end.
Definition unique (names : list string) :=
 Nat.eqb (List.length names) (List.length (nodup String.string_dec names)).
Definition bounded_key key := match D.decode identifier (JString key) with Some _ => true | None => false end.
Definition outgoing_allowed n :=
 match node_behavior n with Exit => false | _ => true end.
Definition node_model_selected n :=
 match node_behavior n with
 | TaskNode (CreateTask profile _ _ _) => Codec.nonempty profile
 | _ => true end.
Definition valid_graph (g : graph) v :=
 bounded_key (workflow_name g) &&
 N.leb (N.of_nat (List.length (workflow_nodes g))) 128 &&
 N.leb (N.of_nat (List.length (workflow_connections g))) 256 &&
 existsb (fun n => match node_behavior n with Entrance => true | _ => false end) (workflow_nodes g) &&
 existsb (fun n => match node_behavior n with Exit => true | _ => false end) (workflow_nodes g) &&
 unique (map WorkflowTypes.node_key (workflow_nodes g)) && unique (map connection_key (workflow_connections g)) &&
 forallb (fun n => bounded_key (WorkflowTypes.node_key n) &&
   match node_behavior n with
   | Entrance => negb (Nat.eqb (List.length (outgoing g (WorkflowTypes.node_key n))) 0)
   | Exit => true
   | TaskNode (ExistingTask id) =>
      match find_task id v with
      | Some task => negb (task_archived task) && TaskGraph.task_in_work (workflow_work g) id v
      | None => false end
   | TaskNode (CreateTask _ _ _ _) => node_model_selected n
   end) (workflow_nodes g) &&
 forallb (fun e => bounded_key (connection_key e) &&
   match lookup_node (connection_source e) g, lookup_node (connection_target e) g with
   | Some n, Some _ => outgoing_allowed n && match node_behavior n, outgoing g (WorkflowTypes.node_key n) with
     | TaskNode _, _ :: _ :: _ => Codec.nonempty (connection_description e)
     | _, _ => true end
   | _, _ => false end) (workflow_connections g).
Fixpoint traverse {A B} (f : A -> option B) (items : list A) : option (list B) :=
 match items with [] => Some [] | item :: rest =>
 match f item, traverse f rest with Some x, Some xs => Some (x :: xs) | _, _ => None end end.
Definition parse_settings source :=
 match field "settings" source with
 | None => Some Codec.empty_settings_request
 | Some raw => option_map (Codec.settings_request_of_values true) (D.decode (Codec.settings_declaration true) raw)
 end.
Definition parse_node source :=
 match string_field "key" source, string_field "kind" source with
 | Some key, Some "entrance" => Some (Node key Entrance)
 | Some key, Some "exit" => Some (Node key Exit)
 | Some key, Some "task" => match natural_field "task_id" source, string_field "profile" source with
   | Some task, None => Some (Node key (TaskNode (ExistingTask task)))
   | None, Some profile => match parse_settings source, string_field "creation" source with
     | Some settings, Some "once" => Some (Node key (TaskNode (CreateTask profile settings (field "settings" source) false)))
     | Some settings, Some "each" => Some (Node key (TaskNode (CreateTask profile settings (field "settings" source) true)))
     | _, _ => None end
   | _, _ => None end
 | _, _ => None end.
Definition node_model_missing source :=
 match parse_node source with
 | Some node => negb (node_model_selected node)
 | None => false end.
Definition parse_edge source : option edge :=
 match string_field "key" source, string_field "source" source, string_field "target" source with
 | Some key, Some from, Some target =>
   let description := match string_field "description" source with Some text => text | None => "" end in
   let message := match field "message" source with
      | None => Some F.GraphOutput
      | Some raw => option_map (TaskGraph.message_of_fields maximum_message_depth)
                      (D.decode (message_declaration maximum_message_depth) raw)
      end in
   option_map (Connection key from target description) message
 | _, _, _ => None end.
Definition save_graph id owner name nodes edges v :=
 match traverse parse_node nodes, traverse parse_edge edges with
 | Some nodes, Some edges =>
   let g := DefinitionOf owner name nodes edges in
   if valid_graph g v &&
      (match owner with None => true | Some work => match Work.lookup work v with Some _ => true | None => false end end)
   then let updated := match id with
       | None => graphs v ++ [Some g]
       | Some id => replace id (Some g) (graphs v) end in
     let key := match id with Some id => id | None => N.of_nat (List.length (graphs v)) end in
     accept (JObject [("workflow_id", number key)]) (store_graphs updated v) []
   else match find (fun e => match lookup_node (connection_source e) g with
     | Some n => negb (outgoing_allowed n) | None => false end) edges with
   | Some edge => reject "invalid_workflow_exit_source"
     ("连线「" ++ connection_key edge ++ "」的来源是出口。请选择入口或任务作为来源节点。") v
   | None => reject "invalid_workflow"
     "请检查工作流名称、工作组、节点和连线名称、出入口及分支说明。节点和连线名称必须各自唯一。" v
   end
 | _, _ => reject "invalid_workflow" "Invalid workflow node or connection declaration." v end.

Definition arrived p := match path_value p with Arrived _ _ _ => true | _ => false end.
Definition complete (i : execution) :=
 negb (Nat.eqb (List.length (instance_paths i)) 0) && forallb arrived (instance_paths i).
Definition failed (i : execution) :=
 existsb (fun p => match path_value p with Blocked _ _ => true | _ => false end) (instance_paths i).
Definition status i := if complete i then "completed" else if failed i then "blocked" else "running".
Definition replace_path id state (i : execution) :=
 set instance_paths (map (fun p => if N.eqb id (path_id p) then Path id state else p)) i.
Definition replace_with_paths id (next : list WorkflowTypes.delivery) (i : execution) :=
 let start := instance_next_path i in
 let added := indexed (fun id input => Path id (Pending input)) start next in
 set instance_next_path (fun _ => start + N.of_nat (List.length next))
   (set instance_paths
     (flat_map (fun p => if N.eqb id (path_id p) then added else [p])) i).

Definition text_content (contents : content) :=
 String.concat "" (flat_map (fun piece => match piece with TextPart s => [s] | _ => [] end) contents).
Definition forwarded (g : graph) (node : string) (choice : option string) (contents : content) :=
 let edges := outgoing g node in
 let edges := match choice with None => edges | Some key => filter (fun e => String.eqb key (connection_key e)) edges end in
 map (fun e => WorkflowTypes.Delivery (connection_target e)
   (match connection_message e with
    | F.GraphOutput => contents
    | expression => [TextPart (TaskGraph.expand expression (text_content contents))]
    end) (Some (connection_source e))) edges.
Definition route id input choice contents (i : execution) :=
 match forwarded (instance_definition i) (delivery_node input) choice contents with
 | [] => replace_path id (Blocked input "此节点没有可继续通往出口的连线。") i
 | deliveries => replace_with_paths id deliveries i
 end.
Definition instructions (g : graph) key :=
 match outgoing g key with
 | (first :: second :: tail) =>
   ("Before the final answer, call choose_workflow_connection with exactly one of these connection keys:" ++
   String.concat "" (map (fun e => ("
- " ++ connection_key e ++ ": " ++ connection_description e)%string) (first :: second :: tail)))%string
 | _ => "" end.
Definition delivery_contents g input :=
 match instructions g (delivery_node input) with
 | "" => delivery_content input
 | guidance => TextPart ((guidance ++ "

Workflow input:
")%string) :: delivery_content input
 end.
Definition authorized_task id before :=
 match find_task id before with
 | Some task => match task_lifecycle task with
   | Running Idle [] => match task_queued task with [] => true | _ => false end
   | _ => false end
 | None => false end.
Definition owns_task id (i : execution) :=
 existsb (fun p => match path_value p with Executing _ task _ => N.eqb id task | _ => false end) (instance_paths i).

Definition delivery_task node (creation : task_creation) (i : execution) :=
 match creation with
 | ExistingTask id => Some id
 | CreateTask _ _ _ false => option_map snd (find (fun pair => String.eqb node (fst pair)) (instance_tasks i))
 | _ => None
 end.
Definition awaited_task p :=
 match path_value p with
 | Executing _ task _ | Forwarding _ task _ _ => Some task
 | _ => None
 end.
Definition pending_task (i : execution) p :=
 match path_value p with
 | Pending input =>
   match lookup_node (delivery_node input) (instance_definition i) with
   | Some (Node node (TaskNode creation)) => delivery_task node creation i
   | _ => None end
 | _ => None
 end.
Definition immediately_pending (i : execution) p :=
 match path_value p with
 | Pending _ => match pending_task i p with None => true | Some _ => false end
 | _ => false
 end.
Record dependencies := Dependencies {
 awaiting_instances : DependencyIndex.t N;
 pending_instances : DependencyIndex.t N;
 immediate_instances : IndexedRegistry.Slots.t N
}.
Definition update_dependencies (add : bool) id (i : execution) current :=
 let update key bucket :=
   match key with
   | Some target => let target := IndexedRegistry.key target in
     if add then DependencyIndex.include target id id bucket else DependencyIndex.exclude target id bucket
   | None => bucket
   end in
 let paths := instance_paths i in
 let update_paths select := fold_left (fun bucket p => update (select p) bucket) paths in
 Dependencies (update_paths awaited_task (awaiting_instances current))
   (update_paths (pending_task i) (pending_instances current))
   (let immediate := immediate_instances current in
    if existsb (immediately_pending i) paths then
      if add then IndexedRegistry.Slots.add (IndexedRegistry.key id) id immediate
      else IndexedRegistry.Slots.remove (IndexedRegistry.key id) immediate
    else immediate).
Definition instance_dependencies := DependencyIndex.project
 (Dependencies (IndexedRegistry.Slots.empty _) (IndexedRegistry.Slots.empty _) (IndexedRegistry.Slots.empty _))
 (update_dependencies true) (update_dependencies false).
Definition dependencies_for v := instance_dependencies (ScopedRegistry.rows (instance_registry v)).
Definition task_instances task v :=
 DependencyIndex.members (IndexedRegistry.key task) (awaiting_instances (dependencies_for v)).
Definition task_reserved task v :=
 existsb (fun id => match lookup_instance id v with Some i => owns_task task i | None => false end)
   (task_instances task v).
Definition attempt_send task input i v :=
 if task_reserved task v then None
 else match find_task task v with
 | Some current => if task_archived current then Some (reject "archived" "The workflow Task was archived." v)
                   else if authorized_task task v then Some (Tasks.send task (delivery_contents (instance_definition i) input) v) else None
 | None => Some (reject "task_not_found" "The workflow Task no longer exists." v) end.
Definition create_task profile settings input (i : execution) v :=
 let contents := delivery_contents (instance_definition i) input in
 let settings := match instance_project i with
   | Some project => with_requested_project (Some project) settings
   | None => settings end in
 let selected := CommandExecution.resolve_context_start profile None contents (Some settings) false None v in
 Worktree.consume_owned_start (workflow_work (instance_definition i)) Worktree.GraphTaskCreation
   (Some settings) None None None selected v.
Definition save_path instance_id path_key input (i : execution) (sent : decision) (task : option N) remember :=
 let result := decision_reply sent in
 let next := if bool_default "ok" result false then match task with
   | Some id => Executing input id None
   | None => Blocked input "启动任务后未获得对话标识。" end
   else Blocked input (match field "error" result with
     | Some error => match string_field "code" error with
       | Some "unknown_profile" | Some "invalid_profile" => "所选模型不可用。请为此节点重新选择模型。"
       | _ => match string_field "message" error with Some detail => detail | None => "任务未能接收消息。" end
       end
     | None => "任务未能接收消息。" end) in
 let i := replace_path path_key next i in
 let i := match next with
  | Executing _ id _ => set instance_history (fun history => history ++ [(path_key, delivery_node input, id)]) i
  | _ => i end in
 let i := match next, remember with
  | Executing _ id _, true => set instance_tasks (fun saved => (delivery_node input, id) :: saved) i
  | _, _ => i end in
 DecisionComposition.Update (store_instance instance_id i (decision_world sent)) (decision_effects sent).
Definition service_path instance_id (p : path) : DecisionComposition.step := fun v _ =>
 let unchanged := DecisionComposition.Update v [] in
 match lookup_instance instance_id v with
 | None => unchanged
 | Some i => match find (fun x => N.eqb (path_id x) (path_id p)) (instance_paths i) with
   | Some (Path path_id (Pending input)) =>
     let g := instance_definition i in
     match lookup_node (delivery_node input) g with
     | Some (Node _ Entrance) =>
       DecisionComposition.Update (store_instance instance_id (route path_id input None (delivery_content input) i) v)
         [ContinueScheduling]
     | Some (Node exit Exit) =>
       DecisionComposition.Update (store_instance instance_id
         (replace_path path_id (Arrived exit (delivery_source input) (delivery_content input)) i) v) []
     | Some (Node node (TaskNode creation)) =>
       let saved := delivery_task node creation i in
       match saved, creation with
       | Some id, _ => match attempt_send id input i v with
         | Some sent => save_path instance_id path_id input i sent (Some id) false
         | None => unchanged end
       | None, CreateTask profile settings _ each =>
          let sent := create_task profile settings input i v in
          save_path instance_id path_id input i sent
            (match field "result" (decision_reply sent) with Some r => natural_field "task_id" r | None => None end)
            (negb each)
       | None, ExistingTask _ => unchanged end
     | None => DecisionComposition.Update
        (store_instance instance_id (replace_path path_id (Blocked input "该工作流节点已不可用。") i) v) []
     end
   | _ => unchanged end
 end.

Definition notice := [TextPart "Choose an outgoing connection using choose_workflow_connection before giving the final answer. Then send the final answer again."].
Definition settle_path before instance_id (p : path) : DecisionComposition.step := fun v _ =>
 let unchanged := DecisionComposition.Update v [] in
 match lookup_instance instance_id v, path_value p with
 | Some i, Executing input task choice =>
   let save next := DecisionComposition.Update (store_instance instance_id next v) [] in
   let block detail := save (replace_path (path_id p) (Blocked input detail) i) in
   match find_task task before, find_task task v with
   | Some previous, Some current =>
     let added := skipn (List.length (task_history previous)) (task_history current) in
     match TaskGraph.new_outputs before task current with
     | first :: rest =>
       let answer := [TextPart (String.concat "
" (first :: rest))] in
       match outgoing (instance_definition i) (delivery_node input), choice with
       | _ :: _ :: _, None =>
         let sent := Tasks.send task notice v in
         if bool_default "ok" (decision_reply sent) false
         then DecisionComposition.Update (decision_world sent) (decision_effects sent)
         else block "The Task could not accept a reminder to choose a connection."
       | _, _ =>
         match task_operations current with
         | [] => save (route (path_id p) input choice answer i)
         | _ :: _ => save (replace_path (path_id p) (Forwarding input task choice answer) i)
         end
       end
     | [] =>
       if task_archived current || existsb (fun entry => match entry with FailureMessage _ => true | _ => false end) added
       then block "Task execution failed before it reached the next connection."
       else if existsb (fun entry => match entry with UserMessage _ => true | _ => false end) added
       then block "The current workflow input was replaced before its final answer."
       else match task_activity previous, task_activity current with
         | AskingModel _ _ _, Idle => block "The Task returned no final answer."
         | _, _ => unchanged end
     end
   | _, _ => block "The Task is unavailable."
   end
 | Some i, Forwarding input task choice answer =>
   match find_task task v with
   | Some current => match task_operations current with
     | [] => DecisionComposition.Update
         (store_instance instance_id (route (path_id p) input choice answer i) v) []
     | _ => unchanged end
   | None => unchanged end
 | _, _ => unchanged end.

Definition set_binding {A} id (value : A) (bindings : list (N * A)) :=
 (id, value) :: filter (fun pair => negb (N.eqb id (fst pair))) bindings.
Definition revise_ticket id stage clock c v :=
 Board.put id (Board.revised (Board.with_stage stage (F.card_contents c)) clock c) v.
Definition sync_ticket instance_id (i : execution) v :=
 match instance_card i with
 | Some id => match current_instance id v, CardScope.lookup id v with
   | Some current, Some c =>
     if N.eqb current instance_id && negb (F.card_archived c) then
       let stage := if complete i then F.Completed else if failed i then F.Blocked else F.InProgress in
       if String.eqb (F.stage_name stage) (F.stage_name (F.draft_stage (F.card_contents c))) then v
       else revise_ticket id stage (F.card_updated_at c) c v
     else v
   | _, _ => v end
 | None => v end.
Definition ordered_instances ids :=
 map (fun id => N.pred (N.pos id))
   (ScopedRegistry.Ordered.sort
     (map fst (IndexedRegistry.Slots.elements
       (fold_left (fun selected id => IndexedRegistry.Slots.add (IndexedRegistry.key id) tt selected)
         ids (IndexedRegistry.Slots.empty unit))))).
Definition for_paths ids (eligible : execution -> path -> bool)
 (operation : N -> path -> DecisionComposition.step) : DecisionComposition.step :=
 fun v effects =>
 let selected := flat_map (fun id => match lookup_instance id v with
   | Some i => [(id, filter (eligible i) (instance_paths i))]
   | None => [] end) (ordered_instances ids) in
 DecisionComposition.each selected
   (fun '(id, paths) => DecisionComposition.each paths (operation id)) v effects.
Definition changed_tasks before v := DependencyIndex.changed_ids (task_rows before) (task_rows v).
Definition changed_instances before v := DependencyIndex.changed_ids
 (ScopedRegistry.rows (instance_registry before)) (ScopedRegistry.rows (instance_registry v)).
Definition depends_on tasks target :=
 match target with Some id => existsb (N.eqb id) tasks | None => false end.
Definition settle before : DecisionComposition.step := fun v effects =>
 let tasks := changed_tasks before v in
 for_paths (flat_map (fun id => task_instances id v) tasks)
   (fun _ p => depends_on tasks (awaited_task p)) (settle_path before) v effects.
Definition service before (continue : bool) : DecisionComposition.step := fun v effects =>
 let tasks := changed_tasks before v in
 let dependencies := dependencies_for v in
 let pending := flat_map (fun id =>
   DependencyIndex.members (IndexedRegistry.key id) (pending_instances dependencies)) tasks in
 let changed := changed_instances before v in
 let immediate := if continue then DependencyIndex.values (immediate_instances dependencies) else [] in
 for_paths (pending ++ changed ++ immediate)
   (fun _ p => match path_value p with Pending _ => true | _ => false end) service_path v effects.
Definition synchronize before : DecisionComposition.step :=
 DecisionComposition.world_only (fun v =>
 fold_left (fun current key => match lookup_instance key current with
   | Some i => sync_ticket key i current | None => current end)
   (changed_instances before v) v).
Definition after_transition before continue :=
 DecisionComposition.and_then (settle before)
  (DecisionComposition.and_then (service before continue) (synchronize before)).

Definition launch_result id := JObject [("instance_id", number id)].
Definition start id key contents preview_text ticket project clock browser_launch v :=
 match lookup_graph id v with
 | Some g => if entrance g key && Tasks.content_nonempty contents then
   let instance_id := IndexedRegistry.next (ScopedRegistry.rows (instance_registry v)) in
   let preview := match Utf8.take 96 preview_text with Some text => text | None => "" end in
   let i := Instance id g ticket project key preview (option_map BoardClock.value clock) browser_launch
     [Path 0 (Pending (WorkflowTypes.Delivery key contents None))] [] [] 1 in
   let started := store_instances (ScopedRegistry.append i (instance_registry v)) v in
   accept (launch_result instance_id) started []
   else reject "invalid_workflow_start" "Select an entrance of the workflow and supply a nonempty message." v
 | None => reject "workflow_not_found" "The workflow does not exist." v end.
Definition choose context key v :=
 match context with
 | None => reject "workflow_task_required" "Only the Task executing a workflow delivery can choose its connection." v
 | Some caller =>
   let task := Tasks.native_owner caller in
   match find (fun '(_, i) => owns_task task i)
    (flat_map (fun id => match lookup_instance id v with Some i => [(id,i)] | None => [] end)
      (ordered_instances (task_instances task v))) with
   | Some (id, i) =>
     match find (fun p => match path_value p with Executing _ owner _ => N.eqb task owner | _ => false end) (instance_paths i) with
     | Some (Path path (Executing input owner None)) =>
       match outgoing (instance_definition i) (delivery_node input) with
       | (first :: second :: tail) =>
         if existsb (fun e => String.eqb key (connection_key e)) (first :: second :: tail) then
          accept JNull (store_instance id (replace_path path (Executing input owner (Some key)) i) v) []
         else reject "invalid_workflow_connection" "Choose one of the outgoing connection keys supplied for this delivery." v
       | _ => reject "workflow_choice_not_required" "This Task has no alternative outgoing connections." v end
     | _ => reject "workflow_choice_already_made" "The current delivery already selected a connection." v end
   | None => reject "workflow_delivery_not_found" "This Task is not executing a workflow delivery." v end
 end.
Definition ticket_available (c : F.card) := negb (F.card_archived c) && BoardFacts.enrichment_ready c && BoardFacts.unlinked c.
Definition ticket_running := BoardFacts.workflow_in_progress.
Definition ticket_configure id revision workflow key v :=
 CardScope.with_card id revision v (fun card =>
   match lookup_graph workflow v with
   | Some g => if entrance g key && ticket_available card && negb (ticket_running id v) then
     let updated := with_features (set F.feature_ticket_workflows
       (set_binding id (Invocation workflow key)) (world_features v)) v in
     Board.save id (Board.revised (F.card_contents card) (F.card_updated_at card) card) updated
     else reject "workflow_ticket_unavailable" "Choose a workflow entrance on an available ticket." v
   | None => reject "workflow_not_found" "The workflow does not exist." v end).
Definition ticket_start id revision clock browser_launch v :=
 CardScope.with_card id revision v (fun card =>
  match ticket_setting id v with
  | Some selected =>
    if ticket_available card && negb (ticket_running id v) then
      let draft := F.card_contents card in
      let preview := if String.eqb (F.draft_description draft) "" then F.draft_title draft else F.draft_description draft in
      let launched := start (invocation_graph selected) (invocation_entrance selected)
        (Board.task_contents id draft) preview (Some id) (F.draft_project draft) clock browser_launch v in
      match field "result" (decision_reply launched) with
      | Some result => match natural_field "instance_id" result with
        | Some key =>
          let updated := decision_world launched in
          let updated := with_features (set F.feature_ticket_instances
            (set_binding id key) (world_features updated)) updated in
          accept result (revise_ticket id F.InProgress (BoardClock.observed clock) card updated) (decision_effects launched)
        | None => launched end
      | None => launched end
    else reject "workflow_ticket_unavailable" "Wait for the current work and drafting to settle before starting the ticket." v
  | None => reject "workflow_ticket_not_configured" "Select a workflow definition and entrance first." v end).
Definition node_json n :=
 let fields := match node_behavior n with
   | Entrance => [("kind", JString "entrance")]
   | Exit => [("kind", JString "exit")]
   | TaskNode (ExistingTask id) => [("kind", JString "task"); ("task_id", number id)]
   | TaskNode (CreateTask profile _ settings each) =>
     [("kind", JString "task"); ("profile", JString profile); ("creation", JString (if each then "each" else "once"))] ++
     match settings with Some value => [("settings", value)] | None => [] end
   end in
 JObject (("key", JString (WorkflowTypes.node_key n)) :: fields).
Definition edge_json (e : edge) := JObject [("key", JString (connection_key e));
 ("source", JString (connection_source e)); ("target", JString (connection_target e));
 ("description", JString (connection_description e)); ("message", Observation.graph_message_json (connection_message e))].
Definition graph_json id (g : graph) := JObject [("workflow_id", number id); ("name", JString (workflow_name g));
 ("work_id", match workflow_work g with Some work => number work | None => JNull end);
 ("nodes", JArray (map node_json (workflow_nodes g))); ("connections", JArray (map edge_json (workflow_connections g)))].
Definition task_active id v := match find_task id v with
 | Some task => match task_lifecycle task with Running _ _ => task_busy task | _ => false end
 | None => false end.
Definition path_json v p :=
 let fields := match path_value p with
 | Pending input => [("node", JString (delivery_node input)); ("state", JString "pending")]
 | Executing input id choice =>
    [("node", JString (delivery_node input)); ("state", JString "executing"); ("task_id", number id);
     ("active", JBool (task_active id v)); ("connection", match choice with Some c => JString c | None => JNull end)]
 | Forwarding input id _ _ =>
    [("node", JString (delivery_node input)); ("state", JString "settling"); ("task_id", number id);
     ("active", JBool (task_active id v))]
 | Arrived node source result => [("node", JString node); ("state", JString "exit"); ("result", JString (text_content result));
     ("content", Codec.content_json result)] ++
     match source with Some name => [("source", JString name)] | None => [] end
 | Blocked input reason => [("node", JString (delivery_node input)); ("state", JString "blocked"); ("reason", JString reason)] end in
 JObject (("path_id", number (path_id p)) :: fields).
Definition instance_json v id (i : execution) := JObject [("instance_id", number id);
 ("workflow_id", number (instance_graph i)); ("definition", graph_json (instance_graph i) (instance_definition i));
 ("ticket_id", match instance_card i with Some ticket => number ticket | None => JNull end);
 ("entrance", JString (instance_entrance i)); ("message_preview", JString (instance_message_preview i));
 ("started_at", match instance_started_at i with Some seconds => number seconds | None => JNull end);
 ("browser_launch_receipt", match instance_browser_launch i with
  | Some launch => JObject [("key", JString launch); ("reply", success (launch_result id))]
  | None => JNull end);
 ("state", JString (status i)); ("paths", JArray (map (path_json v) (instance_paths i)));
 ("tasks", JArray (map (fun '(path, node, task) =>
  JObject [("path_id", number path); ("node", JString node); ("task_id", number task)]) (instance_history i)))].
Definition definitions_json v := JArray (flat_map (fun '(id, entry) =>
 match entry with Some g => [graph_json id g] | None => [] end) (indexed (fun id entry => (id, entry)) 0 (graphs v))).
Definition instances_json v := JArray (indexed (instance_json v) 0 (instances v)).
Definition ticket_bindings_json v := JArray (map (fun '(id, invocation) =>
 JObject [("card_id", number id); ("workflow_id", number (invocation_graph invocation));
  ("entrance", JString (invocation_entrance invocation));
  ("instance_id", match current_instance id v with Some instance => number instance | None => JNull end)])
 (F.feature_ticket_workflows (world_features v))).
Definition read_instance id v :=
 match lookup_instance id v with Some i => success (instance_json v id i)
 | None => failure "workflow_instance_not_found" "The workflow instance does not exist." end.
