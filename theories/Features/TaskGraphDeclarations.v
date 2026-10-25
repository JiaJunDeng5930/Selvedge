From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
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
Definition node_settings_field := OmittableField "settings" KJson.
Definition spawn_node_fields := [Field "key" KText;OmittableField "profile" KText;
 OmittableField "reasoning" KText;OmittableField "message" KText;node_settings_field].
Definition action_message_field := Field "message" KJson.
Definition action_fields := [Field "target" KText;action_message_field].
Definition rule_actions_field := Field "actions" (KArray KJson).
Definition rule_fields := [Field "key" KText;Field "source" KText;rule_actions_field].
