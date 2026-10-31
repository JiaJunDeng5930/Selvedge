From Selvedge.Programming Require Callback Variant.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson BoundedDiagnostic.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition addressed (effect : json) : option { kind : Callback.callback_kind & fields (Callback.coordinates kind) } :=
 match DeclarationRegistry.lookup (TextJson.render_json (JString (str effect "kind"))) ModelDeclarations.registered_effects with
 | Some declaration =>
   match Variant.callback_name declaration as callback return
     SchemaProjection.program (Variant.payload_fields declaration) (Variant.callback_coordinates callback) ->
     option { kind : Callback.callback_kind & fields (Callback.coordinates kind) } with
   | Some kind => fun projection => option_map (fun address => existT _ kind address)
       (SchemaProjection.read projection (object_fields effect))
   | None => fun _ => None end (Variant.callback_projection declaration)
 | None => None end.
Definition completed (effect result : json) : option json :=
 match addressed effect with
 | Some (existT _ kind address) => match Callback.observed_result kind result with
   | Some (existT _ ok values) => Some (Callback.encode kind ok address values)
   | None => None end
 | None => None end.
Definition failed (effect : json) (original : string) (context_limit : bool) : option json :=
 match addressed effect with
 | Some (existT _ kind address) => Some (Callback.encode kind false address
     (Callback.failure_payload kind (Callback.diagnostic kind original) context_limit))
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
