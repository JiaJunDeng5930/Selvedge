From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition maximum_message_depth : nat := 8.
Definition maximum_message_nodes : nat := 64.
Definition maximum_rule_actions : nat := 8.

Definition output_fields := [Field "kind" (KEnum "output" [])].
Definition literal_fields := [Field "kind" (KEnum "literal" []);Field "value" KText].
Definition existing_node_fields := [Field "key" KText;Field "task_id" KNatural].
Definition node_settings_field := OmittableField "settings" KJson.
Definition spawn_node_fields := [Field "key" KText;OmittableField "profile" KText;
 OmittableField "reasoning" KText;OmittableField "message" KText;node_settings_field].

(** The recursive declaration is shared by public schemas and the typed parser. *)
Fixpoint message_declaration (depth : nat) : ArgumentDeclaration.t := match depth with
 | O => ArgumentDeclaration.Reject
 | S remaining => ArgumentDeclaration.Union [ArgumentDeclaration.of_schema output_fields;
   ArgumentDeclaration.of_schema literal_fields;
   ArgumentDeclaration.Object [("kind",true,ArgumentDeclaration.of_kind (KEnum "concat" []));
     ("parts",true,ArgumentDeclaration.Array (message_declaration remaining))]] end.
Definition action_declaration := ArgumentDeclaration.Object [
 ("target",true,ArgumentDeclaration.text);("message",true,message_declaration maximum_message_depth)].
Definition rule_declaration := ArgumentDeclaration.Object [
 ("key",true,ArgumentDeclaration.text);("source",true,ArgumentDeclaration.text);
 ("actions",true,ArgumentDeclaration.BoundedArray 0 (N.of_nat maximum_rule_actions) action_declaration)].
