From Selvedge.Kernel Require Import ModelDeclarations CallbackDeclarations.
From Selvedge.Foundation Require Import Schema.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson BoundedDiagnostic.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition callback_kind_of (kind : string) :=
 match find (fun declaration => Json.equal declaration.(ModelDeclarations.tag_value) (JString kind)) ModelDeclarations.effects with
 | Some declaration => declaration.(ModelDeclarations.callback_name)
 | None => None end.
Definition diagnostic_contract (kind : ModelDeclarations.callback_kind) :=
  match kind with
  | Approval => BoundedDiagnostic.Contract 2048 true
  | TaskTitle | BoardText | ChatgptExec | Context | Compaction _ | Worktree _ |
      Reasoning | Hook | AfterHook | Model | Tool => BoundedDiagnostic.Contract 4096 false
  end.
Definition diagnostic (kind : ModelDeclarations.callback_kind) (message : string) :=
  BoundedDiagnostic.make (diagnostic_contract kind) message.
Definition reply_fields kind := { ok : bool & fields (CallbackDeclarations.payload kind ok) }.
Definition observed_payload kind ok members : option (reply_fields kind) :=
 option_map (fun values => existT _ ok values) (decode_fields (CallbackDeclarations.payload kind ok) members).
Definition observed_result (kind : callback_kind) (result : json) : option (reply_fields kind) :=
 let members := object_fields result in
 match kind as kind return option (reply_fields kind) with
 | TaskTitle => observed_payload TaskTitle true (("ok",JBool true) :: members)
| BoardText => observed_payload BoardText true (("ok",JBool true) :: members)
| Context => observed_payload Context true (("ok",JBool true) :: members)
| Reasoning => observed_payload Reasoning true (("ok",JBool true) :: members)
 | Tool => observed_payload Tool true members
 | ChatgptExec => observed_payload ChatgptExec true members
 | Approval => Some (existT _ true (Schema.of_tuple (CallbackDeclarations.payload Approval true) [!result!]))
| Hook => Some (existT _ true (Schema.of_tuple (CallbackDeclarations.payload Hook true) [!result!]))
| AfterHook => Some (existT _ true (Schema.of_tuple (CallbackDeclarations.payload AfterHook true) [!result!]))
 | Compaction done => Some (existT _ true (Schema.of_tuple (CallbackDeclarations.payload (Compaction done) true) [!result;false!]))
 | Model => option_map (fun items => existT _ true
     (Schema.of_tuple (CallbackDeclarations.payload Model true) [!true;Some items;None;None!])) (as_array result)
 | Worktree created =>
   match bool_field "ok" result with
   | None => None
   | Some true => if created as created return option (reply_fields (Worktree created))
     then observed_payload (Worktree true) true members
     else option_map (fun outcome => existT _ true
       (Schema.of_tuple (CallbackDeclarations.payload (Worktree false) true) [!true;outcome!]))
       (match Json.field "outcome" result with
        | Some outcome => Some outcome
        (* Cloud workspace receipts carry their archived root; local receipts
           already distinguish an archived root from a released reservation. *)
        | None => option_map (fun root => JObject [("kind",JString "archived_at");("root",JString root)])
            (string_field "root" result) end)
   | Some false => if created as created return option (reply_fields (Worktree created)) then
       option_map (fun values : fields (CallbackDeclarations.payload (Worktree true) false) => existT _ false
         (Schema.of_tuple (CallbackDeclarations.payload (Worktree true) false)
           [!false;Schema.head (Schema.tail values);diagnostic (Worktree true) (Schema.head (Schema.tail (Schema.tail values)))!]))
         (decode_fields (CallbackDeclarations.payload (Worktree true) false) members)
     else option_map (fun values : fields (CallbackDeclarations.payload (Worktree false) false) => existT _ false
         (Schema.of_tuple (CallbackDeclarations.payload (Worktree false) false)
           [!false;diagnostic (Worktree false) (Schema.head (Schema.tail values))!]))
         (decode_fields (CallbackDeclarations.payload (Worktree false) false) members)
   end
 end.
Definition completed (effect result : json) : option json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => match decode_fields (CallbackDeclarations.coordinates kind) (object_fields effect), observed_result kind result with
   | Some address,Some (existT _ ok values) => Some (CallbackDeclarations.encode kind ok address values)
   | _,_ => None end
 | None => None end.
Definition error_value (message : string) := JObject [("error",JObject
 [("code",JString "external_execution_failed");("message",JString message)])].
Definition failure_outcome (message : string) := JObject [("decision",JString "failed");("reason",JString message)].
Definition failure_payload (kind : callback_kind) (message : string) (context_limit : bool)
 : fields (CallbackDeclarations.payload kind false) := Schema.of_tuple _
 (match kind as kind return Schema.tuple (CallbackDeclarations.payload kind false) with
 | TaskTitle | BoardText => [!false;message!]
 | Approval | Hook | AfterHook => [!failure_outcome message!]
 | Context => [!false;None;Some message!]
 | Reasoning => [!false;None;None;Some message!]
 | Model => [!false;None;Some message;if context_limit then Some (exist _ "context_limit" (or_introl eq_refl)) else None!]
 | Tool => [!true;Some (error_value message)!]
 | ChatgptExec => [!true;error_value message!]
 | Compaction _ => [!JObject [("message",JString message)];true!]
 | Worktree created => if created as created return Schema.tuple (CallbackDeclarations.payload (Worktree created) false)
     then [!false;None;message!] else [!false;message!] end).
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
