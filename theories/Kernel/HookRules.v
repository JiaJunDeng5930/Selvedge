From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Domain Codec State Inputs.
Import ListNotations.
Open Scope string_scope.

Definition parse_reason_decision (decision : string) (source : json) :=
 match Schema.decode [Field "decision" (KEnum decision []);Field "reason" KText] source with
 | Some values => let reason := head (tail values) in
   if Utf8.well_formed reason && Nat.leb (String.length reason) 4096 then Some reason else None
 | None => None end.
Definition parse_hook (source : json) : option hook_outcome :=
 match string_field "decision" source with
 | Some "allow" => match Schema.decode [Field "decision" (KEnum "allow" [])] source with Some _ => Some HookAllow | _ => None end
 | Some "rewrite" => match Schema.decode [Field "decision" (KEnum "rewrite" []);Field "arguments" KJson] source with
   | Some fields => match head (tail fields) with JObject arguments => Some (HookRewrite arguments) | _ => None end
   | _ => None end
 | Some "deny" => option_map HookDeny (parse_reason_decision "deny" source)
 | Some "failed" => option_map HookFailure (parse_reason_decision "failed" source)
 | _ => None end.
Definition parse_after (source : json) : option after_outcome :=
 match string_field "decision" source with
 | Some "allow" => match Schema.decode [Field "decision" (KEnum "allow" [])] source with Some _ => Some KeepResult | _ => None end
 | Some "rewrite" => match Schema.decode [Field "decision" (KEnum "rewrite" []);Field "value" KJson] source with
   | Some fields => Some (RewriteResult (head (tail fields))) | _ => None end
 | Some "deny" => option_map DenyResult (parse_reason_decision "deny" source)
 | Some "failed" => option_map AfterFailure (parse_reason_decision "failed" source)
 | _ => None end.
Inductive before_action := Proceed (invocation : call) | Refuse (code reason : string).
Definition before_apply (invocation : call) (outcome : hook_outcome) := match outcome with
 | HookAllow => Proceed invocation
 | HookRewrite arguments => Proceed (Call (call_id invocation) (call_name invocation) (JObject arguments) (call_origin invocation))
 | HookDeny reason => Refuse "hook_denied" reason
 | HookFailure reason => Refuse "hook_failed" reason end.
Inductive after_action := ContinueResult (result : json) | RefuseResult (code reason : string).
Definition after_apply (result : json) (outcome : after_outcome) := match outcome with
 | KeepResult => ContinueResult result
 | RewriteResult replacement => ContinueResult replacement
 | DenyResult reason => RefuseResult "after_hook_denied" reason
 | AfterFailure reason => RefuseResult "after_hook_failed" reason end.
