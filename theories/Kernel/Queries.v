From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers Domain Codec Commands Context State Observation NativeTools Limits Search Pagination.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Definition default_n (value : option N) (fallback : N) := match value with Some value => value | None => fallback end.
Definition read_task (id after limit : N) (value : world) :=
 match find_task id value with
 | None => State.failure "task_not_found" "The target task does not exist"
 | Some task =>
   let length := N.of_nat (List.length (task_history task)) in
   if N.leb 1 limit && N.leb limit Pagination.history_limit && N.leb after length then
   State.success (JObject [("task", task_summary id task (world_features value));
    ("after", number after); ("cursor", number length); ("has_more", JBool (N.ltb (after+limit)%N length));
    ("messages", JArray (map (message_json id) (firstn (N.to_nat limit) (skipn (N.to_nat after) (task_history task)))))])
   else State.failure "invalid_page" "History requires a valid cursor and a page size of 1..100"
 end.
Definition describe := JObject [
 ("commands", JArray (map (fun command => JObject [("name", JString (command_name command));
 ("description", JString (command_name command)); ("schema", NativeTools.schema_json (Field "op" KText :: command_fields command))]) Selvedge.Kernel.Commands.command_specs));
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
 fold_right (fun item rest => match item with Some item => item :: rest | None => rest end) []
  (indexed (fun id project => if project_deleted project then None else Some (project_json id project)) 0 (world_projects value)).
Definition answer (command : Selvedge.Generated.Commands.command) (value : world) : option json :=
 match command with
 | Selvedge.Generated.Commands.Cmd_describe _ => Some (State.success describe)
 | Selvedge.Generated.Commands.Cmd_list _ => Some (list_tasks value)
 | Selvedge.Generated.Commands.Cmd_read request => Some (read_task (Selvedge.Generated.Commands.read_task_id request) (default_n (Selvedge.Generated.Commands.read_after request) 0) (default_n (Selvedge.Generated.Commands.read_limit request) Pagination.history_limit) value)
 | Selvedge.Generated.Commands.Cmd_search_history request => Some (Search.search (Selvedge.Generated.Commands.search_history_query request) (Selvedge.Generated.Commands.search_history_project_id request) (Selvedge.Generated.Commands.search_history_work_id request)
   (default_n (Selvedge.Generated.Commands.search_history_after request) 0) (default_n (Selvedge.Generated.Commands.search_history_limit request) Search.default_limit) value)
 | Selvedge.Generated.Commands.Cmd_list_projects _ => Some (State.success (JObject [("projects",JArray (projects_json value))]))
 | Selvedge.Generated.Commands.Cmd_read_project request => Some (read_project (Selvedge.Generated.Commands.read_project_project_id request) value)
 | _ => None
 end.
