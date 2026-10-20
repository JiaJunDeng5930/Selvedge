From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive callback_kind :=
| TaskTitle | ChatgptExec | BoardText | Approval | Hook | AfterHook
| Context | Compaction (completed : bool) | Worktree (created : bool) | Reasoning | Model | Tool.
Definition callback_kind_of (kind : string) :=
  if String.eqb kind "task_title" then TaskTitle
  else if String.eqb kind "chatgpt_exec" then ChatgptExec
  else if String.eqb kind "board_text" then BoardText
  else if String.eqb kind "approval" then Approval
  else if String.eqb kind "hook" then Hook
  else if String.eqb kind "after_hook" then AfterHook
  else if String.eqb kind "observe_context" then Context
  else if String.eqb kind "context_scope" || String.eqb kind "context_measure" then Compaction false
  else if String.eqb kind "context_compaction" then Compaction true
  else if String.eqb kind "worktree_create" then Worktree true
  else if String.eqb kind "worktree_archive" then Worktree false
  else if String.eqb kind "reasoning" then Reasoning
  else if String.eqb kind "model" then Model
  else Tool.
Definition base (kind : string) (effect : json) : list (string * json) :=
  [("kind",JString kind);("task_id",get effect "task_id");("ticket",get effect "ticket")].
Definition unreserved (reserved : list string) (fields : list (string * json)) :=
  filter (fun pair => negb (existsb (String.eqb (fst pair)) reserved)) fields.
Definition extend (fields : list (string * json)) (result : json) :=
  JObject (fields ++ unreserved (map (@fst string json) fields) (object_fields result)).
Definition worktree_reply (created : bool) (effect result : json) (message : string) :=
  let ok := boolean_field result "ok" in
  JObject ([("kind",JString (if created then "worktree_created" else "worktree_archived"));
    ("task_id",get effect "task_id");("ok",JBool ok)] ++
    if created then
      [("root",get result "root")] ++
        if ok then [("workspace",get result "workspace");("guidance",get result "guidance")]
        else [("message",JString message)]
    else if ok then [("root",get result "root")] else [("message",JString message)]).
Definition completed (effect result : json) : option json :=
  match callback_kind_of (str effect "kind") with
  | TaskTitle => Some (JObject (base "task_title" effect ++ [("ok",JBool true);("title",get result "title")]))
  | ChatgptExec => Some (extend [("kind",JString "chatgpt_result");("operation_id",get effect "operation_id")] result)
  | BoardText => Some (extend [("kind",JString "board_text");("card_id",get effect "card_id");
      ("ticket",get effect "ticket");("ok",JBool true)] result)
  | Approval => Some (JObject (base "approval" effect ++ [("outcome",result)]))
  | Hook => Some (JObject (base "hook" effect ++ [("outcome",result)]))
  | AfterHook => Some (JObject (base "after_hook" effect ++ [("operation_id",get effect "operation_id");("outcome",result)]))
  | Context => Some (JObject (base "context_observed" effect ++ [("ok",JBool true);("observations",get result "observations")]))
  | Compaction done => Some (JObject (base (if done then "compaction_completed" else "compaction_measured") effect ++ [("result",result);("error",JBool false)]))
  | Worktree created =>
    match Utf8.take 1024%nat (str result "message") with
    | Some message => Some (worktree_reply created effect result message)
    | None => None
    end
  | Reasoning => Some (extend (base "reasoning" effect ++ [("ok",JBool true)]) result)
  | Model => Some (JObject (base "model" effect ++ [("ok",JBool true);("items",result)]))
  | Tool => Some (extend (base "tool" effect) result)
  end.
Definition error_value (message : string) := JObject [("error",JObject
  [("code",JString "external_execution_failed");("message",JString message)])].
Definition failed_outcome (kind : string) (effect : json) (message : string) :=
  JObject (base kind effect ++ [("outcome",JObject [("decision",JString "failed");("reason",JString message)])]).
Definition failed (effect : json) (message short_message : string) (context_limit : bool) : json :=
  match callback_kind_of (str effect "kind") with
  | TaskTitle => JObject (base "task_title" effect ++ [("ok",JBool false);("message",JString short_message)])
  | ChatgptExec => JObject [("kind",JString "chatgpt_result");("operation_id",get effect "operation_id");
      ("error",JBool true);("value",error_value message)]
  | BoardText => JObject [("kind",JString "board_text");("card_id",get effect "card_id");
      ("ticket",get effect "ticket");("ok",JBool false);("message",JString message)]
  | Context => JObject (base "context_observed" effect ++ [("ok",JBool false);("message",JString message)])
  | Compaction done => JObject (base (if done then "compaction_completed" else "compaction_measured") effect ++
      [("result",JObject [("message",JString message)]);("error",JBool true)])
  | Worktree created => worktree_reply created effect (JObject [("ok",JBool false);("root",JNull)]) message
  | Reasoning => JObject (base "reasoning" effect ++ [("ok",JBool false);("message",JString message)])
  | Hook => failed_outcome "hook" effect message
  | Approval => failed_outcome "approval" effect short_message
  | AfterHook => set (failed_outcome "after_hook" effect message) "operation_id" (get effect "operation_id")
  | Model => JObject (optional context_limit "failure_kind" (JString "context_limit") ++ base "model" effect ++
      [("ok",JBool false);("message",JString message)])
  | Tool => JObject (base "tool" effect ++ [("error",JBool true);("value",error_value message)])
  end.
Definition completion (source : json) :=
  match completed (get source "effect") (get source "result") with
  | Some value => success value
  | None => type_error "Completion contains invalid UTF-8 text"
  end.
Definition failure (source : json) :=
  let original := match as_string (get source "message") with
    | Some value => value | None => "External execution failed" end in
  (* DEFENSE: External error messages may contain invalid UTF-8 and may exceed durable message bounds. *)
  match Utf8.chunks original with
  | None => type_error "External execution failure contains invalid UTF-8 text"
  | Some chunks => success (failed (get source "effect")
      (Utf8.render_chunks (firstn 1024%nat chunks)) (Utf8.render_chunks (firstn 400%nat chunks))
      (boolean_field source "context_limit"))
  end.
