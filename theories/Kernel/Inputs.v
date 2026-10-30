From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Export ApprovalProtocol.
From Selvedge.Kernel Require Import Numbers Domain ContextTypes Reasoning.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Inductive model_outcome := ModelSuccess (items : list model_item)
 | ModelFailure (message : string) | ModelContextLimit.
Inductive hook_outcome := HookAllow | HookRewrite (arguments : list (string * json))
 | HookDeny (reason : string) | HookFailure (reason : string).
Inductive after_outcome := KeepResult | RewriteResult (value : json)
 | DenyResult (reason : string) | AfterFailure (reason : string).
Definition hook_json (value : hook_outcome) := match value with
 | HookAllow => JObject [("decision",JString "allow")]
 | HookRewrite arguments => JObject [("decision",JString "rewrite");("arguments",JObject arguments)]
 | HookDeny reason => JObject [("decision",JString "deny");("reason",JString reason)]
 | HookFailure reason => JObject [("decision",JString "failed");("reason",JString reason)] end.
Definition after_json (value : after_outcome) := match value with
 | KeepResult => JObject [("decision",JString "allow")]
 | RewriteResult result => JObject [("decision",JString "rewrite");("value",result)]
 | DenyResult reason => JObject [("decision",JString "deny");("reason",JString reason)]
 | AfterFailure reason => JObject [("decision",JString "failed");("reason",JString reason)] end.
Inductive input :=
| UserCommand (command : Selvedge.Generated.Commands.command)
| Configure (environment : environment)
| ContextCompleted (task_id ticket : N) (observations : option (list context_observation)) (diagnostic : string)
| ModelCompleted (task_id ticket : N) (outcome : model_outcome)
| ReasoningCompleted (task_id ticket : N) (outcome : Reasoning.outcome)
| ToolCompleted (task_id ticket : N) (value : json) (error : bool)
| HookCompleted (task_id ticket : N) (outcome : hook_outcome)
| AfterCompleted (task_id operation_id ticket : N) (outcome : after_outcome)
| ApprovalCompleted (task_id ticket : N) (outcome : approval_outcome)
| Recover
| Continue.
