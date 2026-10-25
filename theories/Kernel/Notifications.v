From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import HookRules Numbers Domain Codec State Observation Inputs Delivery.
From Selvedge.Kernel Require ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition subscribers (kind : string) (plugins : list json) :=
 fold_right (fun plugin rest =>
  if existsb (fun event => match event with JString event => String.eqb kind event | _ => false end)
    (array_default "events" plugin)
  then value_or_null "reference" plugin :: rest else rest) [] plugins.
Definition event (kind : string) (owner cursor : option N) (payload : json) (plugins : list json) : list json :=
 let recipients := subscribers kind plugins in
 match recipients with [] => [] | _ =>
 let included := Nat.leb (String.length (TextJson.render_json payload)) 16384 in
 [JObject [("type",JString kind);("task_id",optional_number owner);("cursor",optional_number cursor);
  ("payload",if included then payload else JNull);("payload_omitted",JBool (negb included));
  ("recipients",JArray recipients)]] end.
Definition task_event (id : N) (value : task) (kind : string) (cursor : option N) (payload : json) :=
 event kind (Some id) cursor payload (contract_plugins (task_contract value)).
Definition requested_call (identity : string) (history : list message) :=
 fold_left (fun previous message => match message with
 | FunctionCall invocation => if String.eqb identity (call_id invocation) then call_json invocation else previous
 | _ => previous end) history JNull.
Definition authorized_call (identity : string) (history : list message) :=
 fold_left (fun previous message => match message with
 | FunctionCall invocation => if String.eqb identity (call_id invocation) then call_json invocation else previous
 | HookReceipt _ invocation _ outcome =>
   if String.eqb identity (call_id invocation) then match HookRules.parse_hook outcome with
   | Some outcome => match HookRules.before_apply invocation outcome with
     | HookRules.Proceed updated => call_json updated
     | HookRules.Refuse _ _ => JNull end
   | None => JNull end else previous
 | _ => previous end) history JNull.
Definition settled (id : N) (value : task) (cursor : N) (identity : string) (result : json) (error : bool)
 (seen : list string) :=
 if existsb (String.eqb identity) seen || existsb (fun operation => String.eqb identity (call_id (operation_call operation))) (task_operations value)
 then [] else task_event id value "tool_completed" (Some cursor)
  (JObject [("call_id",JString identity);("requested",requested_call identity (task_history value));
   ("authorized",authorized_call identity (task_history value));("value",result);("error",JBool error)]).
Definition history_event (id : N) (value : task) (index : N) (message : message) (seen : list string) :=
 let cursor := N.succ index in
 match message with
 | FunctionCall invocation => (seen,task_event id value "tool_requested" (Some cursor) (call_json invocation))
 | FunctionOutput identity result error =>
   (identity :: seen,settled id value cursor identity result error seen)
 | OperationResult _ invocation result error =>
   (call_id invocation :: seen,settled id value cursor (call_id invocation) result error seen)
 | HookReceipt owner _ _ _ | AfterReceipt owner _ _ _ =>
   (seen,if N.eqb id owner then task_event id value "hook_completed" (Some cursor) (public_message_json id message) else [])
 | ForkReceipt owner invocation branch =>
   (seen,if N.eqb owner id then task_event id value "tool_completed" (Some cursor)
    (JObject [("call_id",JString (call_id invocation));("value",number branch);("error",JBool false);("origin",JString "fork_return")]) else [])
 | _ => (seen,[]) end.
Fixpoint fork_birth_index (id : N) (history : list message) : option nat :=
 match history with
 | [] => None
 | entry :: rest =>
   if match entry with ForkReceipt owner _ _ => N.eqb owner id | _ => false end
   then Some O else option_map S (fork_birth_index id rest)
 end.
Definition task_events (before : world) (id : N) (value : task) (after : world) :=
 let previous := find_task id before in
 let lifecycle := match previous with
 | None => task_event id value "task_created" None (task_summary id value (world_features after))
 | Some previous => if Json.equal (task_summary id previous (world_features before)) (task_summary id value (world_features after))
   then [] else task_event id value "task_changed" None (task_summary id value (world_features after)) end in
 let start := match previous with
 | Some previous => N.of_nat (List.length (task_history previous))
 | None => match fork_birth_index id (task_history value) with
   | Some index => N.of_nat index | None => task_side_cursor value end
 end in
 let records := rev (Selvedge.Foundation.Registry.indexed (fun index message => (index,message)) start (skipn (N.to_nat start) (task_history value))) in
 let '(_,notices) := fold_left (fun state entry => let '(seen,events) := state in let '(index,message) := entry in
   let '(seen,added) := history_event id value index message seen in (seen,added ++ events)) records ([],[]) in
 lifecycle ++ notices.
Definition model_outcome_json (outcome : model_outcome) := match outcome with
 | ModelSuccess items => JObject [("ok",JBool true);("items",number (N.of_nat (List.length items)))]
 | ModelFailure reason => JObject [("ok",JBool false);("error",JString reason)]
 | ModelContextLimit => JObject [("ok",JBool false);("error",JString "context_limit")] end.
Definition input_events (source : option input) (before after : world) := match source with
 | Some (ModelCompleted id ticket outcome) => match find_task id before with
   | Some value => match task_activity value with
     | AskingModel expected _ _ => if N.eqb expected ticket then task_event id value "model_completed" None
       (JObject [("ticket",number ticket);("kind",JString "model");("outcome",model_outcome_json outcome)]) else []
     | _ => [] end | None => [] end
 | Some Recover => event "recovered" None None JNull (environment_plugins (world_environment after))
 | Some (Configure _) => event "configured" None None (JArray (environment_plugins (world_environment after))) (environment_plugins (world_environment after))
 | _ => [] end.
Definition effect_events (after : world) (output : effect) :=
 let emit id kind payload := match find_task id after with Some value => task_event id value kind None payload | None => [] end in
 match output with
 | RequestModel request =>
   let id := ModelRequest.owner request in
   let ticket := ModelRequest.ticket request in
   let model := ModelRequest.model (ModelRequest.selection request) in
   emit id "model_started"
   (JObject [("ticket",number ticket);("kind",JString "model");("model",model_json model)])
 | ExecuteTool id ticket _ tool invocation _ _ => emit id "tool_dispatched"
   (JObject [("ticket",number ticket);("tool",tool_json tool);("call",call_json invocation)])
 | _ => [] end.
Definition batch (source : option input) (before : world) (result : decision) :=
 let after := decision_world result in
 input_events source before after ++
  concat (Selvedge.Foundation.Registry.indexed (fun id task => task_events before id task after) 0 (world_tasks after)) ++
  flat_map (effect_events after) (decision_effects result).
Definition enriched_envelope (durable : bool) (result : decision) (notices : list json) :=
 Observation.envelope_with_effects durable (decision_reply result)
   (map (Observation.effect_json (decision_world result)) (decision_effects result) ++
     [JObject [(ModelDeclarations.tag_field ModelDeclarations.plugin_events,ModelDeclarations.tag_value ModelDeclarations.plugin_events);("events",JArray notices)]]).
(** Only the final public receipt can contain notifications. The admission flag
    records global rollback independently of a business reply's success flag. *)
Definition envelope (durable admitted : bool) (source : option input) (before : world) (result : decision) :=
 let base := Observation.envelope durable result in
 if durable && admitted then
 match batch source before result with
 | [] => base
 | notices => let enriched := enriched_envelope durable result notices in
   if Delivery.fits_json enriched then enriched else base
 end else base.
