From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson JsonObjects.
From Selvedge.Adapters Require Import Common ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive provider_output := ToolCall (id name : string) (arguments : json)
  | ContextItem (value markdown_fences : json).
Definition encode_output index value := match value with
  | ToolCall id name arguments => JObject [("type",JString "call"); ("id",JString id);
      ("name",JString name); ("arguments",arguments)]
  | ContextItem item markdown_fences => JObject [("part",number index); ("type",JString "context");
      ("value",item);("markdown_fences",markdown_fences)] end.
Definition message_part part := is_object part &&
  ((String.eqb (str part "type") "output_text" && is_text (get part "text")) ||
   (String.eqb (str part "type") "refusal" && is_text (get part "refusal"))).
Definition fence_observation_valid observation := is_object observation &&
 is_text (get observation "raw_info") && is_text (get observation "fence_kind") &&
 Json.is_bool (get observation "info_complete").
Definition empty_observations observations := is_array observations && Nat.eqb (List.length (items observations)) 0.
Definition parse_output (profile item markdown_fences : json) : outcome provider_output :=
  if negb (is_object item) then reject "Provider returned an invalid output item"
  else if String.eqb (str item "type") "function_call" then
    if negb (empty_observations markdown_fences) then reject "Tool output cannot carry Markdown fence observations"
    else if account profile && negb (JsonObjects.equivalent (get item "namespace") (JString local_tool_namespace))
      then reject "ChatGPT returned a function call outside the local tool namespace"
    else if nonempty (get item "call_id") && nonempty (get item "name") && is_text (get item "arguments") then
      (* DEFENSE: Provider function arguments are external JSON text, including
         duplicate object members; they must be parsed before tool dispatch. *)
      match TextJson.parse_json (str item "arguments") with
      | Some (JObject fields) => Accepted (ToolCall (str item "call_id") (str item "name") (JObject fields))
      | Some _ => reject "Function arguments must be a JSON object"
      | None => reject "Invalid JSON function arguments" end
    else reject "Provider returned a malformed function call"
  else if String.eqb (str item "type") "message" then
    if String.eqb (str item "role") "assistant" && is_array (get item "content") &&
       forallb message_part (items (get item "content")) && is_array markdown_fences &&
       forallb fence_observation_valid (items markdown_fences) then Accepted (ContextItem item markdown_fences)
    else reject "Provider returned an unsupported assistant message"
  else if existsb (String.eqb (str item "type")) ["reasoning";"compaction"] then
    if empty_observations markdown_fences then Accepted (ContextItem item markdown_fences)
    else reject "Non-message provider output cannot carry Markdown fence observations"
  else reject ("Unsupported provider output type: " ++ display_field item "type").
Fixpoint valid_coordinates (previous : option N) values := match values with
  | [] => true | value :: rest => match natural value with None => false | Some index =>
    canonical_natural value && match previous with None => true | Some old => old <? index end &&
      valid_coordinates (Some index) rest end end.
Definition coordinates_valid values count := match values with [] => true
  | _ => Nat.eqb (List.length values) count && valid_coordinates None values end.
Fixpoint output_items profile values observations coordinates index : outcome (list json) :=
  match values,observations with
  | [],[] => Accepted []
  | value :: rest,markdown_fences :: fence_rest =>
    let coordinate := match coordinates with [] => index | first :: _ => nat_value first end in
    bind (parse_output profile value markdown_fences) (fun parsed =>
      bind (output_items profile rest fence_rest (tl coordinates) (index + 1))
        (fun tail => Accepted (encode_output coordinate parsed :: tail)))
  | _,_ => reject "Provider output and Markdown fence observations are misaligned"
  end.
Definition output source :=
  if is_array (get source "output") && is_array (get source "markdown_observations") &&
    coordinates_valid (items (get source "output_indices"))
    (List.length (items (get source "output")))
  then render_outcome JArray (output_items (get source "profile") (items (get source "output"))
    (items (get source "markdown_observations")) (items (get source "output_indices")) 0)
  else err "Completed response requires output and Markdown fence observations".

Record completed_item := CompletedItem { completed_index : N; completed_value : json }.
Record response_stream := ResponseStream { output_started : bool; completed_items : list completed_item }.
Definition initial_stream := ResponseStream false [].
Definition decode_completed value := CompletedItem (num value "index") (get value "item").
Definition decode_stream value := ResponseStream (boolean_field value "output_started")
  (map decode_completed (items (get value "completed_items"))).
Definition encode_completed item := JObject [("index",number item.(completed_index)); ("item",item.(completed_value))].
Definition encode_stream state := JObject [("output_started",JBool state.(output_started));
  ("completed_items",JArray (map encode_completed state.(completed_items)))].
Inductive stream_action := Continue | TextDelta (index : N) (value : string)
  | Terminal (output indices : json) | StreamFailure (message : string) (recoverable : bool).
Definition encode_action (state : response_stream) (action : stream_action) := success (JObject
  (("state",encode_stream state) :: match action with
  | Continue => [("action",JString "continue")]
  | TextDelta index value => [("action",JString "delta");("text",JString value);("index",number index)]
  | Terminal output indices => [("action",JString "terminal");("output",output);("output_indices",indices)]
  | StreamFailure message recoverable => [("action",JString "failure");("message",JString message);
      ("recoverable",JBool recoverable)] end)).
Fixpoint insert_completed item values := match values with [] => [item] | first :: rest =>
  if item.(completed_index) <? first.(completed_index) then item :: first :: rest
  else if N.eqb item.(completed_index) first.(completed_index) then item :: rest
  else first :: insert_completed item rest end.
Definition conflict values index value := existsb (fun previous =>
  N.eqb previous.(completed_index) index && negb (JsonObjects.equivalent previous.(completed_value) value)) values.
Definition exposed event state := ResponseStream
  (state.(output_started) || (is_text (get event "type") &&
    (contains_text ".delta" (str event "type") || String.eqb (str event "type") "response.output_item.added")))
  state.(completed_items).
Definition terminal_action event state :=
  let output := get (get event "response") "output" in
  if is_array output && negb (Nat.eqb (List.length (items output)) 0) then Terminal output (JArray [])
  else match state.(completed_items) with [] => Terminal output (JArray [])
    | values => Terminal (JArray (map completed_value values)) (JArray (map (fun v => number v.(completed_index)) values)) end.
Definition step (event : json) (state : response_stream) : response_stream * stream_action :=
  let state := exposed event state in let kind := str event "type" in
  if String.eqb kind "response.output_text.delta" then
    (state, if is_text (get event "delta") && canonical_natural (get event "output_index")
      then TextDelta (num event "output_index") (str event "delta") else Continue)
  else if String.eqb kind "response.output_item.done" then
    if canonical_natural (get event "output_index") && is_object (get event "item") then
      let state := ResponseStream true state.(completed_items) in
      if conflict state.(completed_items) (num event "output_index") (get event "item") then
        (state,StreamFailure "Provider returned conflicting completed output items" false)
      else (ResponseStream true (insert_completed
        (CompletedItem (num event "output_index") (get event "item")) state.(completed_items)),Continue)
    else (state,StreamFailure "Provider returned an invalid completed output item" false)
  else if String.eqb kind "response.completed" then
    (state,if String.eqb (str (get event "response") "status") "completed" then terminal_action event state
      else StreamFailure "Terminal model response is not completed" false)
  else if existsb (String.eqb kind) ["error";"response.failed";"response.incomplete"] then
    (state,StreamFailure ("Model stream ended with " ++ kind)
      (negb state.(output_started) && negb (String.eqb kind "response.incomplete") &&
       String.eqb (str (if String.eqb kind "error" then event else get (get event "response") "error") "code")
         "context_length_exceeded"))
  else (state,Continue).
Definition stream_step source :=
  let '(state,action) := step (get source "event") (decode_stream (get source "state")) in
  encode_action state (if String.eqb (str (get source "effect") "kind") "context_compaction" then
    match action with TextDelta _ _ => Continue | _ => action end else action).
Definition stream_end source := encode_action (decode_stream (get source "state"))
  (StreamFailure "Model stream ended without a completed response" false).
