From Selvedge.Kernel Require Import ModelDeclarations CallbackDeclarations.
From Selvedge.Foundation Require Import Schema DeclarationFields.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson BoundedDiagnostic.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition callback_kind_of (kind : string) :=
 match DeclarationRegistry.lookup (TextJson.render_json (JString kind)) ModelDeclarations.registered_effects with
 | Some declaration => declaration.(ModelDeclarations.callback_name)
 | None => None end.
Definition completed (effect result : json) : option json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => match decode_fields (CallbackDeclarations.coordinates kind) (object_fields effect), CallbackDeclarations.observed_result kind result with
   | Some address,Some (existT _ ok values) => Some (CallbackDeclarations.encode kind ok address values)
   | _,_ => None end
 | None => None end.
Definition failed (effect : json) (original : string) (context_limit : bool) : option json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => option_map (fun address => CallbackDeclarations.encode kind false address
     (CallbackDeclarations.failure_payload kind (CallbackDeclarations.diagnostic kind original) context_limit))
     (decode_fields (CallbackDeclarations.coordinates kind) (object_fields effect))
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
