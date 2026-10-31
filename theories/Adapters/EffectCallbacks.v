From Selvedge.Kernel Require Import ModelDeclarations CallbackDeclarations.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson BoundedDiagnostic.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition addressed (effect : json) : option { kind : ModelDeclarations.callback_kind & fields (CallbackDeclarations.coordinates kind) } :=
 match DeclarationRegistry.lookup (TextJson.render_json (JString (str effect "kind"))) ModelDeclarations.registered_effects with
 | Some declaration =>
   match ModelDeclarations.callback_name declaration as callback return
     SchemaProjection.program (ModelDeclarations.payload_fields declaration) (ModelDeclarations.callback_coordinates callback) ->
     option { kind : ModelDeclarations.callback_kind & fields (CallbackDeclarations.coordinates kind) } with
   | Some kind => fun projection => option_map (fun address => existT _ kind address)
       (SchemaProjection.read projection (object_fields effect))
   | None => fun _ => None end (ModelDeclarations.callback_projection declaration)
 | None => None end.
Definition completed (effect result : json) : option json :=
 match addressed effect with
 | Some (existT _ kind address) => match CallbackDeclarations.observed_result kind result with
   | Some (existT _ ok values) => Some (CallbackDeclarations.encode kind ok address values)
   | None => None end
 | None => None end.
Definition failed (effect : json) (original : string) (context_limit : bool) : option json :=
 match addressed effect with
 | Some (existT _ kind address) => Some (CallbackDeclarations.encode kind false address
     (CallbackDeclarations.failure_payload kind (CallbackDeclarations.diagnostic kind original) context_limit))
 | None => None end.
Definition completion (source : json) :=
 match completed (get source "effect") (get source "result") with
 | Some value => success value
 (* DEFENSE: Provider results can violate their declared payload shape. The
    service converts a rejected completion into the issued effect's failure. *)
 | None => type_error "Completion does not satisfy its declared callback fields" end.
Definition failure (source : json) :=
 match as_string (get source "message") with
 | Some original => match failed (get source "effect") original (boolean_field source "context_limit") with
   | Some value => success value
   | None => type_error "Failure requires an issued effect with callback coordinates" end
 | None => type_error "Failure requires a diagnostic message" end.
