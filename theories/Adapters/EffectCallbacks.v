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
 match find (fun declaration => Json.equal declaration.(ModelDeclarations.tag_value) (JString kind)) ModelDeclarations.effects with
 | Some declaration => declaration.(ModelDeclarations.callback_name)
 | None => None end.
Definition diagnostic_fallback kind : D.text_value (diagnostic_format kind).
Proof. refine (exist _ BoundedDiagnostic.fallback _); destruct kind; reflexivity. Defined.
Definition diagnostic kind message := BoundedDiagnostic.make
 (diagnostic_constraints kind) (diagnostic_fallback kind) message.
Definition diagnostic_value kind (value : D.text_value (diagnostic_format kind)) :=
 D.encode_text (diagnostic_format kind) value.
Definition reply_fields kind := { ok : bool & F.values (CallbackDeclarations.payload kind ok) }.
Definition observed_payload kind ok members : option (reply_fields kind) :=
 option_map (fun values => existT _ ok values) (F.observe (CallbackDeclarations.payload kind ok) (JObject members)).
Definition observed_result (kind : callback_kind) (result : json) : option (reply_fields kind) :=
 let members := object_fields result in
 match kind as kind return option (reply_fields kind) with
 | TaskTitle => observed_payload TaskTitle true members
 | BoardText => observed_payload BoardText true members
 | Context => observed_payload Context true members
 | Reasoning => observed_payload Reasoning true members
 | Tool => match bool_field "error" result with
   | Some error => observed_payload Tool (negb error) members | None => None end
 | ChatgptExec => match bool_field "error" result with
   | Some error => observed_payload ChatgptExec (negb error) members | None => None end
 | Approval => option_map (fun parsed => existT _ true (parsed,tt)) (D.decode approval_schema result)
 | Hook => option_map (fun parsed => existT _ true (parsed,tt)) (D.decode hook_schema result)
 | AfterHook => option_map (fun parsed => existT _ true (parsed,tt)) (D.decode after_schema result)
 | Compaction done => option_map (fun parsed => existT _ true (parsed,tt)) (D.decode D.RawObject result)
 | Model => option_map (fun items => existT _ true (items,tt)) (as_array result)
 | Worktree created =>
   match bool_field "ok" result with
   | None => None
   | Some true => if created as created return option (reply_fields (Worktree created))
     then observed_payload (Worktree true) true members
     else option_map (fun outcome => existT _ true (outcome,tt))
       (match Json.field "outcome" result with
        | Some outcome => Some outcome
        (* Cloud workspace receipts carry their archived root; local receipts
           distinguish an archived root from a released reservation. *)
        | None => option_map (fun root => JObject [("kind",JString "archived_at");("root",JString root)])
            (string_field "root" result) end)
   | Some false => if created as created return option (reply_fields (Worktree created)) then
       match F.observe [F.optional "root" D.text;F.required "message" (D.Value KText)] result with
       | Some values => Some (existT _ false (fst values,(diagnostic (Worktree true) (fst (snd values)),tt)))
       | None => None end
     else option_map (fun message => existT _ false (diagnostic (Worktree false) message,tt)) (string_field "message" result)
   end
 end.
Definition completed (effect result : json) : option json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => match decode_fields (CallbackDeclarations.coordinates kind) (object_fields effect), observed_result kind result with
   | Some address,Some (existT _ ok values) => Some (CallbackDeclarations.encode kind ok address values)
   | _,_ => None end
 | None => None end.
Definition error_fields (message : string) := [("error",JObject
 [("code",JString "external_execution_failed");("message",JString message)])].
Definition error_value message := JObject (error_fields message).
Definition failure_payload (kind : callback_kind) (message : D.text_value (diagnostic_format kind)) (context_limit : bool)
 : F.values (CallbackDeclarations.payload kind false) :=
 match kind as kind return D.text_value (diagnostic_format kind) -> F.values (CallbackDeclarations.payload kind false) with
 | TaskTitle | BoardText | Context | Reasoning => fun message => (message,tt)
 | Approval => fun message => (inr (inr (inl (exist _ (tt,(message,tt)) eq_refl))),tt)
 | Hook | AfterHook => fun message => (inr (inr (inr (inl (exist _ (tt,(message,tt)) eq_refl)))),tt)
 | Model => fun message => (message,(if context_limit then Some tt else None,tt))
 | Tool => fun message => (Some (error_value (diagnostic_value Tool message)),tt)
 | ChatgptExec => fun message => (error_fields (diagnostic_value ChatgptExec message),tt)
 | Compaction _ => fun message => (exist _ (message,tt) eq_refl,tt)
 | Worktree created => if created as created return D.text_value (diagnostic_format (Worktree created)) ->
     F.values (CallbackDeclarations.payload (Worktree created) false)
   then fun message => (None,(message,tt)) else fun message => (message,tt)
 end message.
Definition failed (effect : json) (original : string) (context_limit : bool) : option json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => option_map (fun address => CallbackDeclarations.encode kind false address
     (failure_payload kind (diagnostic kind original) context_limit))
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
