From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import SchemaJson.
From Selvedge.Programming Require Import JsonSchema Arguments.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Kernel Require Import Domain Codec Commands ToolArguments Pagination ContentDeclarations.
From Selvedge.Kernel Require CommandDeclarations.
From Selvedge.Kernel Require Import ChatgptArguments ChatgptProtocol.
From Selvedge.Features Require Import Titles BoardParameters.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import TaskGraphDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Record command_binding := CommandBinding {
 binding_tool : string;
 binding_command : string;
 binding_caller_field : option string;
 binding_description : string
}.
Definition shared_command_binding (name : string) :=
 CommandBinding name name None (Commands.command_description name).
Definition bindings := [
 CommandBinding "choose_workflow_connection" "choose_workflow_connection" None
   "Choose one of the outgoing connection keys supplied for the current workflow delivery. Call this before giving your final answer. The final answer is forwarded over the selected connection.";
  CommandBinding "create_task" "create" None "Create an independent task with a configured model. Settings obey the caller's workspace and permission bounds. Set monitor to true to receive its future commentary and final answers automatically.";
  CommandBinding "fork_task" "fork" (Some "task_id") "Fork this task within every ancestor's descendant limit. The caller receives 0 and each child receives its one-based branch number. Supply no messages or exactly one message per child. Set monitor to true to receive each child's future commentary and final answers automatically.";
  CommandBinding "monitor_task" "monitor_task" None "Receive this task's future commentary and final answers automatically in your history. Monitoring lasts across turns until you cancel it or either task is archived.";
  CommandBinding "unmonitor_task" "unmonitor_task" None "Stop receiving new messages from this task. Messages already received stay in your history.";
  CommandBinding "search_history" "search_history" None "Search committed user and assistant messages by literal keyword or phrase (ASCII case-insensitive). Restrict to a project or Work, or both. Message matches include a zero-based message_index; use read_task with after=message_index to read the original message. Set include_titles to also find conversations by their current title.";
 CommandBinding "read_task" "read" None "Read a task's identity, lifecycle, available controls and a bounded page of its original history.";
 CommandBinding "read_current_task" "read" (Some "task_id") "Read this task's identity, lifecycle and Work ownership.";
  CommandBinding "send_message_to_task" "send" None "Commit a user message to another task, or queue it while that task is busy or frozen.";
 CommandBinding "archive_task" "archive" None "Permanently archive a task and cancel its work.";
  CommandBinding "cancel_operation" "cancel_operation" (Some "task_id") "Cancel one live operation without cancelling the task or unrelated work. Use its operation_id from a running status or read_task. Cancellation cannot undo effects already performed.";
 shared_command_binding "create_task_graph";
 shared_command_binding "update_task_graph";
 shared_command_binding "delete_task_graph";
 shared_command_binding "list_task_graphs";
 shared_command_binding "read_task_graph";
 shared_command_binding "create_work";
 shared_command_binding "rename_work";
 shared_command_binding "create_work_task";
 shared_command_binding "list_works";
 shared_command_binding "read_work";
 shared_command_binding "read_work_ui";
 shared_command_binding "apply_work_ui_patch"
].
Definition binding_schema (binding : command_binding) (specification : command_spec) :=
 if String.eqb (binding_tool binding) "read_current_task" then [] else
 match binding_caller_field binding with
 | None => command_fields specification
 | Some name => if String.eqb (binding_command binding) "cancel_operation" then
   map (fun field => if String.eqb name (field_name field) then Field name (KOptional KNatural) else field) (command_fields specification)
   else filter (fun field => negb (String.eqb name (field_name field))) (command_fields specification)
 end.
Definition model_field (binding : command_binding) (argument : argument_spec) :=
 let argument := Arguments.omittable_nonnull argument in
 if (String.eqb (binding_command binding) "create" || String.eqb (binding_command binding) "send") &&
    String.eqb (argument_name argument) "message" then Arguments.with_scalar KText true argument else
 if String.eqb (binding_command binding) "fork" && String.eqb (argument_name argument) "messages"
 then Arguments.with_scalar (KArray KText) false argument else argument.
Definition natural_bounds (argument : argument_spec) :=
 match argument_type_of argument with
 | Scalar KNatural => Arguments.with_bounds (0,JsonSchema.maximum_natural) argument
 | _ => argument end.
Definition binding_arguments (max_fork : N) (binding : command_binding) (specification : command_spec) :=
 map (fun field =>
   let argument := Selvedge.Kernel.CommandDeclarations.refine_argument false (binding_command binding)
     (Commands.command_argument (binding_command binding) field) in
   let argument := model_field binding argument in
   if String.eqb (binding_command binding) "fork" && String.eqb (field_name field) "child_count"
   then Arguments.with_bounds (1,max_fork) argument else natural_bounds argument)
   (filter (fun field => negb ((String.eqb (binding_command binding) "create" ||
     String.eqb (binding_command binding) "send") && String.eqb (field_name field) "images"))
     (binding_schema binding specification)).
Definition binding_entry (max_fork : N) (binding : command_binding) : list tool :=
 if Commands.task_command_allowed (binding_command binding) then
 match find (fun command => String.eqb (binding_command binding) (command_name command)) Selvedge.Kernel.Commands.command_specs with
 | None => []
  | Some specification => [Tool (binding_tool binding) (binding_description binding)
     (NativeToolSource (binding_arguments max_fork binding specification)
       (JObject [("kind", JString "Command"); ("command", JString (binding_command binding))]))]
 end else [].
Definition primitive_kind (value : native_tool) := match value with
 | Bash => "Process" | ReadProcess => "ProcessRead" | WriteProcess => "ProcessWrite" | ReadImage => "ReadImage" end.
Definition primitive_entry (value : native_tool) :=
 Tool (ToolArguments.tool_name value)
  (match value with
   | Bash => "Run Bash in this task's primary workspace root, or / for an empty workspace. Independent calls run concurrently. Running or awaiting_approval is not completion; results arrive automatically. Use read_process on demand for incremental output and write_process for input; do not poll automatically. Pipe mode is the default; select pty for interactive terminal programs. Full Access runs commands unrestricted; other modes obey the task sandbox by default. To request one command outside that sandbox, set sandbox_permissions to require_escalated and explain the concrete need in justification before executing it. Failure may leave partial effects; there is no automatic unrestricted retry. Descendants are terminated on exit. Nonzero exits are errors. Output retains bounded latest content and marks omitted characters. Runtime is unlimited unless timeout_ms is supplied."
   | ReadProcess => "Read available incremental output from this task's Bash operation while running or after completion. Use next_cursor from the previous read. Output is bounded and explicitly marks discarded content. Call on demand; do not poll automatically."
   | WriteProcess => "Write input to this task's running Bash operation. Pipe mode supports eof to close stdin. PTY mode accepts terminal keys as control characters and escape sequences, and paired cols/rows to resize; eof is unavailable."
   | ReadImage => (String.append "Read a local PNG, JPEG, GIF or WebP image in this task's sandbox and return visual content to the model. Relative paths use the task workspace. Images are snapshotted before use; maximum bytes: " (String.append (Numbers.show_natural Images.image_byte_limit) ". detail defaults to auto.")) end)
   (NativeToolSource (ToolArguments.argument_specs value)
     (JObject [("kind", JString (primitive_kind value))])).
Definition discover_schema := [Field "query" (KOptional KText); Field "names" (KOptional (KArray KText));
 Field "offset" (KOptional KNatural); Field "limit" (KOptional KNatural)].
Definition discover_arguments := map (fun field =>
 let argument := Arguments.omittable_nonnull (Arguments.from_field field) in
 let argument := Arguments.with_description
   (match field_name field with
    | "query" => "Case-insensitive keywords matched against tool names and descriptions."
    | "names" => "Exact tool names; bypasses query, offset and limit. Unknown names are returned in missing."
    | "offset" => "Zero-based directory page offset; defaults to 0."
    | "limit" => "Directory page size from 1 to 20; defaults to 5."
    | _ => "" end) argument in
 if String.eqb (field_name field) "limit" then Arguments.with_bounds (1,20) argument else
 if String.eqb (field_name field) "offset" then Arguments.with_bounds (0,JsonSchema.maximum_natural) argument else argument)
 discover_schema.
Definition discover_entry := Tool "discover_tools"
  "Find external MCP and plugin tools by keywords, or load complete definitions with exact names. External function declarations are a lightweight directory, not parameter definitions. Discover an unfamiliar external tool before calling it and copy its parameters from the result. names bypasses query, offset and limit; unknown names are returned in missing. Without query or names, returns a bounded directory page; use offset for later pages. Definitions remain ordinary tool results, so rediscover after compaction if needed."
  (NativeToolSource discover_arguments (JObject [("kind", JString "Discover")])).
Definition wait_name := "wait".
Definition wait_entry := Tool wait_name
 "Suspend this task without a final answer until new input arrives. This call returns 0 on resumption. Input may come from the user, a monitored task, another task, or a pending operation. Call it separately when other calls in the same turn are needed to produce input."
 (NativeToolSource [] (JObject [("kind", JString "Wait")])).
Definition is_wait (definition : tool) :=
 match tool_origin definition with
 | NativeToolSource _ program => String.eqb (text_default "kind" program "") "Wait"
 | _ => false end.
Definition catalog (max_fork : N) := discover_entry :: wait_entry ::
  map primitive_entry [Bash; ReadProcess; WriteProcess; ReadImage] ++ flat_map (binding_entry max_fork) bindings.
Definition find_binding (name : string) := find (fun binding => String.eqb name (binding_tool binding)) bindings.
Definition admit_command (caller : N) (invocation : call) : option Selvedge.Generated.Commands.admitted_command :=
 match find_binding (call_name invocation), call_arguments invocation with
 | Some binding, JObject fields =>
   let fields := match binding_caller_field binding with
    | Some name => match lookup name fields with
      | None => Json.set_field name (Numbers.number caller) fields
      | Some JNull => Json.set_field name (Numbers.number caller) fields
      | Some _ => fields end
    | None => fields end in
   let fields := if String.eqb (binding_tool binding) "read_current_task" then
     Json.set_field "after" (Numbers.number 0) (Json.set_field "limit" (Numbers.number 1) fields)
     else fields in
   Selvedge.Generated.Commands.admit (JObject (("op", JString (binding_command binding)) :: fields))
 | _,_ => None end.
(** Internal specifications may inspect this projection. Dispatch keeps the
    admitted command until it hands the same value to the command interpreter. *)
Definition command (caller : N) (invocation : call) :=
 option_map Selvedge.Generated.Commands.admitted_value (admit_command caller invocation).
Definition primitive (name : string) := find (fun value => String.eqb name (ToolArguments.tool_name value)) [Bash;ReadProcess;WriteProcess;ReadImage].
Definition arguments_valid (definition : tool) (invocation : call) :=
 match tool_origin definition with
 | NativeToolSource parameters _ => match primitive (call_name invocation) with
   | Some primitive => ToolArguments.valid_arguments primitive (call_arguments invocation)
   | None => Arguments.valid parameters (call_arguments invocation) &&
     match find_binding (call_name invocation) with
     | Some _ => true
     | None => String.eqb (call_name invocation) "discover_tools" || String.eqb (call_name invocation) wait_name
     end
   end
 | _ => false
 end.

Definition deferred_parameters := JObject [("type",JString "object");("properties",JObject []);("additionalProperties",JBool true)].
Definition resident (value : json) := String.eqb (text_default "kind" (value_or_null "source" value) "") "native".
Definition discovery_available (values : list json) := existsb (fun value => resident value &&
 String.eqb (text_default "kind" (value_or_null "program" (value_or_null "source" value)) "") "Discover") values.
Definition presentation_catalog (values : list json) :=
 let available := discovery_available values in
 map (fun value => let complete := negb available || resident value in
 JObject [("name",value_or_null "name" value);
  ("description",if complete then value_or_null "description" value else
   JString (String.append
    (match Utf8.take 160 (text_default "description" value "") with Some text => text | None => "" end)
    " [Load parameters by this exact name through the resident discovery tool.]"));
  ("parameters",if complete then value_or_null "parameters" value else deferred_parameters)]) values.
