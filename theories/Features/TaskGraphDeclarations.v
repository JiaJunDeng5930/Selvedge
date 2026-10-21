From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema SchemaJson.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition maximum_message_depth : nat := 8.
Definition maximum_message_nodes : nat := 64.
Definition maximum_rule_actions : nat := 8.

Definition output_fields := [Field "kind" (KEnum "output" [])].
Definition literal_fields := [Field "kind" (KEnum "literal" []);Field "value" KText].
Definition message_parts_field := Field "parts" (KArray KJson).
Definition concat_fields := [Field "kind" (KEnum "concat" []);message_parts_field].
Definition existing_node_fields := [Field "key" KText;Field "task_id" KNatural].
Definition node_settings_field := Field "settings" (KOptional KJson).
Definition spawn_node_fields := [Field "key" KText;Field "profile" (KOptional KText);
 Field "reasoning" (KOptional KText);Field "message" (KOptional KText);node_settings_field].
Definition action_message_field := Field "message" KJson.
Definition action_fields := [Field "target" KText;action_message_field].
Definition rule_actions_field := Field "actions" (KArray KJson).
Definition rule_fields := [Field "key" KText;Field "source" KText;rule_actions_field].

(** Schema supplies field identity, type and requiredness to both parsers and
    documentation. Nested descriptions refine only the opaque JSON fields. *)
Definition declared_schema (declaration:Schema.schema) (nested:list (string*json)) :=
 JObject (Json.set_field "properties" (JObject (map (fun specification=>
 (field_name specification,match Json.lookup (field_name specification) nested with
 | Some description=>description
 | None=>JObject (SchemaJson.present_schema (field_kind specification)) end)) declaration))
 (SchemaJson.omittable_fields declaration)).
Definition array_schema (items:json) := [("type",JString "array");("items",items)].

(** The native fragment has no recursive references. Inline the same depth
    budget as parsing. The closed empty object at the cutoff preserves a last
    empty concat; actual depth and total-node admission remain runtime rules,
    including rejection of any nonempty expression beyond that cutoff. *)
Fixpoint message_schema (depth:nat) :json := match depth with
 | O=>SchemaJson.object_schema [] []
 | S remaining=>JObject [("anyOf",JArray [
   declared_schema output_fields [];
   declared_schema literal_fields [];
   declared_schema concat_fields [(field_name message_parts_field,JObject (array_schema (message_schema remaining)))]] )]
 end.
Definition node_schema (settings:json) := JObject [("anyOf",JArray [
 declared_schema existing_node_fields [];
 declared_schema spawn_node_fields [(field_name node_settings_field,settings)]])].
Definition action_schema := declared_schema action_fields
 [(field_name action_message_field,message_schema maximum_message_depth)].
Definition rule_schema := declared_schema rule_fields
 [(field_name rule_actions_field,JObject (array_schema action_schema))].

Definition native_argument_fields (settings:json) (command:string) :=
 if String.eqb command "create_task_graph" || String.eqb command "update_task_graph"
 then [("nodes",array_schema (node_schema settings));("rules",array_schema rule_schema)]
 else [].
