From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson.
From Selvedge.Kernel Require Import Domain Codec Commands ToolArguments.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition kind_json := SchemaJson.kind_schema.
Definition schema_json := SchemaJson.schema_json.
Record command_binding := CommandBinding {
 binding_tool : string;
 binding_command : string;
 binding_caller_field : option string;
 binding_description : string
}.
Definition bindings := [
 CommandBinding "create_task" "create" None "Create an independent task with the caller's execution limits.";
 CommandBinding "fork_task" "fork" (Some "task_id") "Fork this task within every ancestor's descendant limit.";
 CommandBinding "search_history" "search_history" None "Search committed user and assistant conversation text.";
 CommandBinding "read_task" "read" None "Read a bounded page of a task's original history.";
 CommandBinding "read_current_task" "read" (Some "task_id") "Read this task's identity, lifecycle and Work ownership.";
 CommandBinding "send_message_to_task" "send" None "Commit or queue a message to another task.";
 CommandBinding "archive_task" "archive" None "Permanently archive a task and cancel its work.";
 CommandBinding "cancel_operation" "cancel_operation" (Some "task_id") "Cancel one live operation without cancelling unrelated work.";
 CommandBinding "create_task_graph" "create_task_graph" None "Create a task graph from declared output handlers.";
 CommandBinding "update_task_graph" "update_task_graph" None "Replace a graph's future output handlers atomically.";
 CommandBinding "delete_task_graph" "delete_task_graph" None "Remove a graph without archiving its tasks.";
 CommandBinding "list_task_graphs" "list_task_graphs" None "List installed task graphs.";
 CommandBinding "read_task_graph" "read_task_graph" None "Read a graph and its delivery receipts.";
 CommandBinding "create_work" "create_work" None "Create a continuing undertaking.";
 CommandBinding "rename_work" "rename_work" None "Rename a Work.";
 CommandBinding "create_work_task" "create_work_task" None "Create a task owned by a Work.";
 CommandBinding "list_works" "list_works" None "List Works.";
 CommandBinding "read_work" "read_work" None "Read a Work and its tasks and graphs.";
 CommandBinding "read_work_ui" "read_work_ui" None "Read the calling task's persistent shared Work UI source.";
 CommandBinding "apply_work_ui_patch" "apply_work_ui_patch" None "Apply an exact-context revision-bound patch to this Work's shared UI."
].
Definition binding_schema (binding : command_binding) (specification : command_spec) :=
 match binding_caller_field binding with
 | None => command_fields specification
 | Some name => if String.eqb (binding_command binding) "cancel_operation" then
   map (fun field => if String.eqb name (field_name field) then Field name (KOptional KNatural) else field) (command_fields specification)
   else filter (fun field => negb (String.eqb name (field_name field))) (command_fields specification)
 end.
Definition binding_entry (binding : command_binding) : list tool :=
 match find (fun command => String.eqb (binding_command binding) (command_name command)) Selvedge.Kernel.Commands.command_specs with
 | None => []
 | Some specification => [Tool (binding_tool binding) (binding_description binding)
    (schema_json (binding_schema binding specification))
    (JObject [("kind", JString "native"); ("program", JObject [("kind", JString "Command"); ("command", JString (binding_command binding))])])]
 end.
Definition primitive_kind (value : native_tool) := match value with
 | Bash => "Process" | ReadProcess => "ProcessRead" | WriteProcess => "ProcessWrite" | ReadImage => "ReadImage" end.
Definition primitive_entry (value : native_tool) :=
 Tool (ToolArguments.tool_name value)
  (match value with
  | Bash => "Run Bash in this task's sandbox. Completion is asynchronous; do not poll automatically."
  | ReadProcess => "Read incremental output from this task's Bash operation on demand."
  | WriteProcess => "Write to this task's running Bash operation."
  | ReadImage => "Read a sandboxed immutable image asset as visual model input." end)
  (ToolArguments.json_schema value)
  (JObject [("kind", JString "native"); ("program", JObject [("kind", JString (primitive_kind value))])]).
Definition discover_schema := [Field "query" (KOptional KText); Field "names" (KOptional (KArray KText));
 Field "offset" (KOptional KNatural); Field "limit" (KOptional KNatural)].
Definition discover_entry := Tool "discover_tools"
 "Find external MCP and plugin tools by keywords, or load exact names to obtain their complete parameter definitions."
 (schema_json discover_schema) (JObject [("kind", JString "native"); ("program", JObject [("kind", JString "Discover")])]).
Definition catalog := discover_entry ::
 map primitive_entry [Bash; ReadProcess; WriteProcess; ReadImage] ++ flat_map binding_entry bindings.
Definition find_binding (name : string) := find (fun binding => String.eqb name (binding_tool binding)) bindings.
Definition command (caller : N) (invocation : call) : option Selvedge.Generated.Commands.command :=
 match find_binding (call_name invocation), call_arguments invocation with
 | Some binding, JObject fields =>
   let fields := match binding_caller_field binding with
    | Some name => match lookup name fields with
      | None => Json.set_field name (Numbers.number caller) fields
      | Some JNull => Json.set_field name (Numbers.number caller) fields
      | Some _ => fields end
    | None => fields end in
   Selvedge.Generated.Commands.decode (JObject (("op", JString (binding_command binding)) :: fields))
 | _,_ => None end.
Definition primitive (name : string) := find (fun value => String.eqb name (ToolArguments.tool_name value)) [Bash;ReadProcess;WriteProcess;ReadImage].
Definition arguments_valid (invocation : call) :=
 match primitive (call_name invocation) with
 | Some primitive => ToolArguments.valid_arguments primitive (call_arguments invocation)
 | None => match find_binding (call_name invocation) with
   | Some binding => match find (fun command => String.eqb (binding_command binding) (command_name command)) Selvedge.Kernel.Commands.command_specs with
     | Some specification => match Schema.decode (binding_schema binding specification) (call_arguments invocation) with Some _ => true | None => false end
     | None => false end
   | None => match Schema.decode discover_schema (call_arguments invocation) with
     | Some values => String.eqb (call_name invocation) "discover_tools" &&
       (match head (tail (tail (tail values))) with None => true | Some limit => ((1 <=? limit) && (limit <=? 20))%N end) &&
       (match head (tail (tail values)) with None => true | Some offset => (offset <=? 4294967295)%N end)
     | None => false end
   end
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
