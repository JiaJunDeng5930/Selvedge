From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import ModelDeclarations Commands.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Definition call (_operation : string) (_source : json) := success (JObject [
 ("results",ModelResultDeclarations.schema_json);
 ("effects",JArray (map ModelDeclarations.variant_json ModelDeclarations.effects));
 ("audio",JArray (map ModelDeclarations.variant_json ModelDeclarations.audio_admission));
 ("commands",JArray (map (fun declaration => JObject [("name",JString (command_name (Commands.declared_schema declaration)));
   ("owner",JString (Commands.owner_name declaration.(Commands.declared_owner)));
   ("fields",ModelDeclarations.fields_json (command_fields (Commands.declared_schema declaration)))]) Commands.command_declarations))]).
