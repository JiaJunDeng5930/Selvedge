From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec PluginProtocol.
Import ListNotations.
Definition available (catalog : list tool) (value : tool) :=
 existsb (fun current => Json.equal (Codec.tool_json current) (Codec.tool_json value)) catalog.
Definition task_tools (value : task) := contract_tools (task_contract value).
Definition callable (value : task) (environment : environment) :=
 map tool_name (filter (available (environment_tools environment)) (task_tools value)).

Inductive hook_phase := BeforeTool | AfterTool.
Definition hook_field (phase : hook_phase) := match phase with
 | BeforeTool => "before_tool" | AfterTool => "after_tool" end%string.
Definition hook_references (phase : hook_phase) (plugins : list json) :=
 fold_right (fun plugin rest => if bool_default (hook_field phase) plugin false
   then value_or_null "reference" plugin :: rest else rest) [] plugins.
Definition plugin_matches (reference plugin : json) :=
 PluginProtocol.same_reference (value_or_null "reference" plugin) reference.
Definition plugin_present (reference : json) (catalog : list json) :=
 existsb (plugin_matches reference) catalog.
Definition hook_available (phase : hook_phase) (reference : json) (catalog : list json) :=
 existsb (fun plugin => bool_default (hook_field phase) plugin false &&
   plugin_matches reference plugin) catalog.
