From Selvedge.Kernel Require Import ModelDeclarations.
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
Definition base (kind : string) (effect : json) : list (string * json) :=
  [("kind",JString kind);("task_id",get effect "task_id");("ticket",get effect "ticket")].
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
  JObject ([("kind",JString (if created then "worktree_created" else "worktree_archived"));
    ("task_id",get effect "task_id");("ok",JBool ok)] ++
    if created then
      [("root",get result "root")] ++
        if ok then [("workspace",get result "workspace");("guidance",get result "guidance")]
        else [("message",JString message)]
    else if ok then [("outcome",if Json.is_null (get result "outcome")
      then JObject [("kind",JString "archived_at");("root",get result "root")]
      else get result "outcome")] else [("message",JString message)]).
Definition completed (effect result : json) : option json :=
  match callback_kind_of (str effect "kind") with
  | Some TaskTitle => Some (JObject (base "task_title" effect ++ [("ok",JBool true);("title",get result "title")]))
  | Some ChatgptExec => Some (extend [("kind",JString "chatgpt_result");("operation_id",get effect "operation_id")] result)
  | Some BoardText => Some (extend [("kind",JString "board_text");("card_id",get effect "card_id");
      ("ticket",get effect "ticket");("ok",JBool true)] result)
  | Some Approval => Some (JObject (base "approval" effect ++ [("outcome",result)]))
  | Some Hook => Some (JObject (base "hook" effect ++ [("outcome",result)]))
  | Some AfterHook => Some (JObject (base "after_hook" effect ++ [("operation_id",get effect "operation_id");("outcome",result)]))
  | Some Context => Some (JObject (base "context_observed" effect ++ [("ok",JBool true);("observations",get result "observations")]))
  | Some (Compaction done) => Some (JObject (base (if done then "compaction_completed" else "compaction_measured") effect ++ [("result",result);("error",JBool false)]))
  | Some (Worktree created) =>
    Some (worktree_reply created effect result (diagnostic (Worktree created) (str result "message")))
  | Some Reasoning => Some (extend (base "reasoning" effect ++ [("ok",JBool true)]) result)
  | Some Model => Some (JObject (base "model" effect ++ [("ok",JBool true);("items",result)]))
  | Some Tool => Some (extend (base "tool" effect) result)
  | None => None
  end.
Definition error_value (message : string) := JObject [("error",JObject
  [("code",JString "external_execution_failed");("message",JString message)])].
Definition failed_outcome (kind : string) (effect : json) (message : string) :=
  JObject (base kind effect ++ [("outcome",JObject [("decision",JString "failed");("reason",JString message)])]).
Definition failed (effect : json) (original : string) (context_limit : bool) : json :=
  let message := match callback_kind_of (str effect "kind") with
    | Some kind => diagnostic kind original | None => BoundedDiagnostic.fallback end in
  match callback_kind_of (str effect "kind") with
  | Some TaskTitle => JObject (base "task_title" effect ++ [("ok",JBool false);("message",JString message)])
  | Some ChatgptExec => JObject [("kind",JString "chatgpt_result");("operation_id",get effect "operation_id");
      ("error",JBool true);("value",error_value message)]
  | Some BoardText => JObject [("kind",JString "board_text");("card_id",get effect "card_id");
      ("ticket",get effect "ticket");("ok",JBool false);("message",JString message)]
  | Some Context => JObject (base "context_observed" effect ++ [("ok",JBool false);("message",JString message)])
  | Some (Compaction done) => JObject (base (if done then "compaction_completed" else "compaction_measured") effect ++
      [("result",JObject [("message",JString message)]);("error",JBool true)])
  | Some (Worktree created) => worktree_reply created effect (JObject [("ok",JBool false);("root",JNull)]) message
  | Some Reasoning => JObject (base "reasoning" effect ++ [("ok",JBool false);("message",JString message)])
  | Some Hook => failed_outcome "hook" effect message
  | Some Approval => failed_outcome "approval" effect message
  | Some AfterHook => set (failed_outcome "after_hook" effect message) "operation_id" (get effect "operation_id")
  | Some Model => JObject (optional context_limit "failure_kind" (JString "context_limit") ++ base "model" effect ++
      [("ok",JBool false);("message",JString message)])
  | Some Tool => JObject (base "tool" effect ++ [("error",JBool true);("value",error_value message)])
  | None => type_error "The effect has no completion callback"
  end.
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
