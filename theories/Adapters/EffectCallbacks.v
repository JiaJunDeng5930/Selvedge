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
Definition unreserved (reserved : list string) (fields : list (string * json)) :=
  filter (fun pair => negb (existsb (String.eqb (fst pair)) reserved)) fields.
Definition extend (fields : list (string * json)) (result : json) :=
  JObject (fields ++ unreserved (map (@fst string json) fields) (object_fields result)).
Definition diagnostic_contract (kind : ModelDeclarations.callback_kind) :=
  match kind with
  | Approval => BoundedDiagnostic.Contract 2048 true
  | TaskTitle | BoardText | ChatgptExec | Context | Compaction _ | Worktree _ |
      Reasoning | Hook | AfterHook | Model | Tool => BoundedDiagnostic.Contract 4096 false
  end.
Definition diagnostic (kind : ModelDeclarations.callback_kind) (message : string) :=
  BoundedDiagnostic.make (diagnostic_contract kind) message.
Definition worktree_reply (created : bool) (effect result : json) (message : string) :=
 let ok := boolean_field result "ok" in
 if created then if ok then CallbackDeclarations.encode (Worktree true) true effect
   [!Some (JBool true);Some (get result "root");Some (get result "workspace");Some (get result "guidance")!]
   else CallbackDeclarations.encode (Worktree true) false effect [!Some (JBool false);Some (get result "root");Some (JString message)!]
 else if ok then CallbackDeclarations.encode (Worktree false) true effect [!Some (JBool true);Some
   (if Json.is_null (get result "outcome") then JObject [("kind",JString "archived_at");("root",get result "root")] else get result "outcome")!]
 else CallbackDeclarations.encode (Worktree false) false effect [!Some (JBool false);Some (JString message)!].
Definition completed (effect result : json) : option json :=
 let encoded kind values := CallbackDeclarations.encode kind true effect values in
 let extended kind values := extend (object_fields (encoded kind values)) result in
 match callback_kind_of (str effect "kind") with
 | Some TaskTitle => Some (encoded TaskTitle [!Some (JBool true);Some (get result "title")!])
 | Some ChatgptExec => Some (extended ChatgptExec [!None;None!])
 | Some BoardText => Some (extended BoardText [!Some (JBool true);None;None!])
 | Some Approval => Some (encoded Approval [!Some result!])
 | Some Hook => Some (encoded Hook [!Some result!])
 | Some AfterHook => Some (encoded AfterHook [!Some result!])
 | Some Context => Some (encoded Context [!Some (JBool true);Some (get result "observations");None!])
 | Some (Compaction done) => Some (encoded (Compaction done) [!Some result;Some (JBool false)!])
 | Some (Worktree created) => Some (worktree_reply created effect result (diagnostic (Worktree created) (str result "message")))
 | Some Reasoning => Some (extended Reasoning [!Some (JBool true);None;None;None!])
 | Some Model => Some (encoded Model [!Some (JBool true);Some result;None;None!])
 | Some Tool => Some (extended Tool [!None;None!])
 | None => None end.
Definition error_value (message : string) := JObject [("error",JObject
 [("code",JString "external_execution_failed");("message",JString message)])].
Definition failure_outcome (message : string) := JObject [("decision",JString "failed");("reason",JString message)].
Definition failure_payload (kind : callback_kind) (message : string) (context_limit : bool)
 : Schema.tuple (CallbackDeclarations.raw_schema (CallbackDeclarations.payload kind false)) := match kind as kind return Schema.tuple (CallbackDeclarations.raw_schema (CallbackDeclarations.payload kind false)) with
 | TaskTitle | BoardText => [!Some (JBool false);Some (JString message)!]
 | Approval | Hook | AfterHook => [!Some (failure_outcome message)!]
 | Context => [!Some (JBool false);None;Some (JString message)!]
 | Reasoning => [!Some (JBool false);None;None;Some (JString message)!]
 | Model => [!Some (JBool false);None;Some (JString message);if context_limit then Some (JString "context_limit") else None!]
 | Tool | ChatgptExec => [!Some (JBool true);Some (error_value message)!]
 | Compaction _ => [!Some (JObject [("message",JString message)]);Some (JBool true)!]
 | Worktree created => if created as created return Schema.tuple (CallbackDeclarations.raw_schema (CallbackDeclarations.payload (Worktree created) false)) then [!Some (JBool false);Some JNull;Some (JString message)!]
   else [!Some (JBool false);Some (JString message)!] end.
Definition failed (effect : json) (original : string) (context_limit : bool) : json :=
 match callback_kind_of (str effect "kind") with
 | Some kind => CallbackDeclarations.encode kind false effect (failure_payload kind (diagnostic kind original) context_limit)
 | None => type_error "The effect has no completion callback" end.
Definition completion (source : json) :=
  match completed (get source "effect") (get source "result") with
  | Some value => success value
  | None => type_error "Completion contains invalid UTF-8 text"
  end.
Definition failure (source : json) :=
  let original := match as_string (get source "message") with
    | Some value => value | None => "External execution failed" end in
  match callback_kind_of (str (get source "effect") "kind") with
 | None => type_error "The effect has no completion callback"
 | Some _ => success (failed (get source "effect") original (boolean_field source "context_limit"))
 end.
