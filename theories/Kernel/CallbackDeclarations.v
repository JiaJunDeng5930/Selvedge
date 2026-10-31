From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Selvedge.Foundation Require Import ModelWire BoundedDiagnostic.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Kernel Require Import ApprovalProtocol.
From Selvedge.Kernel Require Guidance WorkspacePath.
From Selvedge.Programming Require Import Callback.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition identity := [Field "task_id" KNatural;Field "ticket" KNatural].
Definition task_only := [Field "task_id" KNatural].
Definition operation_identity := Field "operation_id" KNatural.
Definition standard_diagnostic := Diagnostic (text_constraints 4096 true false)
 (exist _ BoundedDiagnostic.fallback eq_refl).
Definition approval_diagnostic := Diagnostic ApprovalProtocol.justification_constraints
 (exist _ BoundedDiagnostic.fallback eq_refl).
Definition success_or_message (fields : list F.property) := fun ok : bool => if ok then fields
 else [F.required "message" (diagnostic_type standard_diagnostic)].
Definition message_failure fields (message : diagnostic_admitted standard_diagnostic) (_ : bool)
 : F.values (success_or_message fields false) := (message,tt).
Definition title_fields (ok : bool) := [F.required (if ok then "title" else "message")
 (D.Text (text_constraints 4096 (negb ok) false))].
Definition TaskTitle := declare "task_title" identity (Marked "ok" true title_fields) standard_diagnostic
 (observe_fields _ true) (fun message _ => (message,tt)).
Definition BoardText := declare "board_text" [Field "card_id" KNatural;Field "ticket" KNatural]
 (Marked "ok" true (success_or_message [F.required "title" (text 4096 true);F.required "description" (text 100000 true)]))
 standard_diagnostic (observe_fields _ true) (message_failure _).
Definition Context := declare "context_observed" identity
 (Marked "ok" true (success_or_message [F.required "observations" (D.Array D.Any)]))
 standard_diagnostic (observe_fields _ true) (message_failure _).
Definition Reasoning := declare "reasoning" identity
 (Marked "ok" true (success_or_message [F.required "effort" (text 64 false);F.required "generations" (D.Value KNatural)]))
 standard_diagnostic (observe_fields _ true) (message_failure _).

Definition reason decision declaration := D.Object
 [F.required "decision" (D.Const (JString decision));F.required "reason" declaration].
Definition reason_fields decision declaration (value : D.denote declaration) :=
 F.construct [F.required "decision" (D.Const (JString decision));F.required "reason" declaration] (tt,(value,tt)).
Definition hook_schema := D.Union
 [D.Object [F.required "decision" (D.Const (JString "allow"))];
  D.Object [F.required "decision" (D.Const (JString "rewrite"));F.required "arguments" D.RawObject];
  reason "deny" (diagnostic_type standard_diagnostic);reason "failed" (diagnostic_type standard_diagnostic)].
Definition after_schema := D.Union
 [D.Object [F.required "decision" (D.Const (JString "allow"))];
  D.Object [F.required "decision" (D.Const (JString "rewrite"));F.required "value" D.Any];
  reason "deny" (diagnostic_type standard_diagnostic);reason "failed" (diagnostic_type standard_diagnostic)].
Definition approval_schema := ApprovalProtocol.callback_declaration.
Definition Approval := declare "approval" identity (Unmarked [F.required "outcome" approval_schema]) approval_diagnostic
 (observe_wrapped _ _) (fun message _ => (inr (inr (inl (reason_fields "failed" _ message))),tt)).
Definition Hook := declare "hook" identity (Unmarked [F.required "outcome" hook_schema]) standard_diagnostic
 (observe_wrapped _ _) (fun message _ => (inr (inr (inr (inl (reason_fields "failed" _ message)))),tt)).
Definition AfterHook := declare "after_hook" (identity ++ [operation_identity]) (Unmarked [F.required "outcome" after_schema])
 standard_diagnostic (observe_wrapped _ _) (fun message _ => (inr (inr (inr (inl (reason_fields "failed" _ message)))),tt)).

Definition error_fields message := [("error",JObject
 [("code",JString "external_execution_failed");("message",JString message)])].
Definition error_value message := JObject (error_fields message).
Definition observe_error body source := match bool_field "error" source with
 | Some error => observe_fields body (negb error) source | None => None end.
Definition Tool := declare "tool" identity
 (Marked "error" false (fun _ => [F.optional "value" D.Any])) standard_diagnostic (observe_error _)
 (fun message _ => (Some (error_value (proj1_sig message)),tt)).
Definition ChatgptExec := declare "chatgpt_result" [operation_identity]
 (Marked "error" false (wrapped "value" D.RawObject)) standard_diagnostic (observe_error _)
 (fun message _ => (error_fields (proj1_sig message),tt)).
Definition compaction_fields (ok : bool) := [F.required "result" (if ok then D.RawObject else
 D.Object [F.required "message" (diagnostic_type standard_diagnostic)])].
Definition Compaction (completed : bool) := declare (if completed then "compaction_completed" else "compaction_measured")
 identity (Marked "error" false compaction_fields) standard_diagnostic
 (fun source => option_map (fun value => existT _ true (value,tt)) (D.decode D.RawObject source))
 (fun message _ => (F.construct [F.required "message" (diagnostic_type standard_diagnostic)] (message,tt),tt)).
Definition model_fields (ok : bool) := if ok then [F.required "items" ModelWire.items] else
 [F.required "message" (diagnostic_type standard_diagnostic);F.optional "failure_kind" (D.Const (JString "context_limit"))].
Definition Model := declare "model" identity (Marked "ok" true model_fields) standard_diagnostic
 (fun source => option_map (fun items => existT _ true (items,tt)) (ModelWire.decode_items source))
 (fun message context_limit => (message,(if context_limit then Some tt else None,tt))).

Definition created_workspace := D.Object
 [F.required "roots" (D.BoundedArray 0 32 WorkspacePath.declaration);F.required "primary_root" WorkspacePath.declaration].
Definition worktree_created_fields (ok : bool) := if ok then
 [F.required "root" WorkspacePath.declaration;F.required "workspace" created_workspace;F.required "guidance" Guidance.declaration]
 else [F.optional "root" D.text;F.required "message" (diagnostic_type standard_diagnostic)].
Definition observe_created source : option (replies worktree_created_fields) := match bool_field "ok" source with
 | Some true => observe_fields _ true source
 | Some false => match F.observe [F.optional "root" D.text;F.required "message" (D.Value KText)] source with
   | Some values => Some (existT _ false (fst values,(normalize_diagnostic standard_diagnostic (fst (snd values)),tt)))
   | None => None end
 | None => None end.
Definition WorktreeCreated := declare "worktree_created" task_only (Marked "ok" true worktree_created_fields)
 standard_diagnostic observe_created (fun message _ => (None,(message,tt))).
Definition worktree_archived_fields := success_or_message [F.required "outcome" D.Any].
Definition observe_archived source : option (replies worktree_archived_fields) := match bool_field "ok" source with
 | Some true => option_map (fun outcome => existT _ true (outcome,tt))
   (match Json.field "outcome" source with
    | Some outcome => Some outcome
    (* Cloud receipts identify the archived root; local receipts also distinguish
       releasing a reservation from archiving a checkout. *)
    | None => option_map (fun root => JObject [("kind",JString "archived_at");("root",JString root)])
        (string_field "root" source) end)
 | Some false => option_map (fun message => existT _ false (normalize_diagnostic standard_diagnostic message,tt))
     (string_field "message" source)
 | None => None end.
Definition WorktreeArchived := declare "worktree_archived" task_only (Marked "ok" true worktree_archived_fields)
 standard_diagnostic observe_archived (message_failure _).
Definition Worktree (created : bool) := if created then WorktreeCreated else WorktreeArchived.
