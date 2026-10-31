From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Kernel Require CallbackDeclarations.
From Selvedge.Kernel Require Import Domain Codec State Inputs.
Import ListNotations.
Open Scope string_scope.

Definition hook_from_fields (value : ArgumentDeclaration.denote CallbackDeclarations.hook_schema) : hook_outcome :=
 match value with
 | inl _ => HookAllow
 | inr (inl rewrite) => HookRewrite (fst (snd (proj1_sig rewrite)))
 | inr (inr (inl reason)) => HookDeny (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr (inl reason))) => HookFailure (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr (inr impossible))) => match impossible with end end.
Definition after_from_fields (value : ArgumentDeclaration.denote CallbackDeclarations.after_schema) : after_outcome :=
 match value with
 | inl _ => KeepResult
 | inr (inl rewrite) => RewriteResult (fst (snd (proj1_sig rewrite)))
 | inr (inr (inl reason)) => DenyResult (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr (inl reason))) => AfterFailure (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr (inr impossible))) => match impossible with end end.
Definition parse_hook source := option_map hook_from_fields
 (ArgumentDeclaration.decode CallbackDeclarations.hook_schema source).
Definition parse_after source := option_map after_from_fields
 (ArgumentDeclaration.decode CallbackDeclarations.after_schema source).
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
