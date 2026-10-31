From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers Domain Codec Commands Context State Observation NativeTools Limits Search Pagination.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Definition default_n (value : option N) (fallback : N) := match value with Some value => value | None => fallback end.
Definition read_task (id after : N) (size : Pagination.size Pagination.history_limit) (value : world) :=
 let limit := proj1_sig size in
 match find_task id value with
 | None => State.failure "task_not_found" "The target task does not exist"
 | Some task =>
   let length := N.of_nat (List.length (task_history task)) in
   if N.leb after length then
   State.success (JObject [("task", task_summary id task (world_features value));
    ("after", number after); ("cursor", number length); ("has_more", JBool (N.ltb (after+limit)%N length));
    ("messages", JArray (map (public_message_json id) (firstn (N.to_nat limit) (skipn (N.to_nat after) (task_history task)))))])
   else State.failure "invalid_page" "History cursor exceeds the current history"
 end.
Definition describe := JObject [
 ("commands", JArray (map (fun command => let name := wire_name (Selvedge.Kernel.Commands.declared_wire command) in
 JObject [("name", JString name);
 ("description", JString (match Selvedge.Kernel.Commands.command_description name with
   | Some description => description | None => "" end));
 ("schema", CommandDeclarations.command_schema command)]) Selvedge.Kernel.Commands.command_declarations));
 ("limits", Limits.boundary_limits); ("plugins", JObject [("protocolVersion", JString "selvedge-plugin-2");
  ("max_plugins", number Limits.plugin_limit); ("events", JArray (map JString Limits.plugin_events))])].
Definition list_tasks (value : world) := State.success (JObject [
 ("tasks", JArray (indexed (fun id task => task_summary id task (world_features value)) 0 (world_tasks value)));
 ("profiles", JArray (map profile_json (environment_profiles (world_environment value))));
 ("tools", JArray (map tool_json (environment_tools (world_environment value))));
 ("plugins", JArray (environment_plugins (world_environment value)));
 ("compaction",Selvedge.Features.CompactionCodec.state_json (Features.Domain.feature_compaction (world_features value)));
 ("max_fork", number (environment_max_fork (world_environment value)));
 ("max_descendants", number (environment_max_descendants (world_environment value))) ]).
Definition read_project (id : N) (value : world) :=
 match registry_at id (world_projects value) with
 | Some project => if project_deleted project then State.failure "project_not_found" "The project does not exist"
   else State.success (project_json id project)
 | None => State.failure "project_not_found" "The project does not exist" end.
Definition projects_json (value : world) :=
 Observation.projects_json (world_projects value) (world_tasks value).
Definition handle_describe (_payload : Selvedge.Generated.Commands.describe_payload)
 (_caller : option N) (value : world) : json :=
 State.success describe.

Definition handle_list (_payload : Selvedge.Generated.Commands.list_payload)
 (_caller : option N) (value : world) : json :=
 list_tasks value.

Definition handle_read (request : Selvedge.Generated.Commands.read_payload)
 (_caller : option N) (value : world) : json :=
 read_task (Selvedge.Generated.Commands.read_task_id request) (default_n (Selvedge.Generated.Commands.read_after request) 0) (Pagination.selected (Selvedge.Generated.Commands.read_limit_admitted request) Pagination.history_default) value.

Definition handle_search_history (request : Selvedge.Generated.Commands.search_history_payload)
 (_caller : option N) (value : world) : json :=
 Search.search (Selvedge.Generated.Commands.search_history_query request) (Selvedge.Generated.Commands.search_history_project_id request) (Selvedge.Generated.Commands.search_history_work_id request)
   (default_n (Selvedge.Generated.Commands.search_history_after request) 0) (Pagination.selected (Selvedge.Generated.Commands.search_history_limit_admitted request) Pagination.default_search_size) value.

Definition handle_list_projects (_payload : Selvedge.Generated.Commands.list_projects_payload)
 (_caller : option N) (value : world) : json :=
 State.success (JArray (projects_json value)).

Definition handle_read_project (request : Selvedge.Generated.Commands.read_project_payload)
 (_caller : option N) (value : world) : json :=
 read_project (Selvedge.Generated.Commands.read_project_project_id request) value.
