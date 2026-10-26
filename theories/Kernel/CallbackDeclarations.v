From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition operation_identity := Field "operation_id" KNatural.
Definition failure_kind := Field "failure_kind" (KOptional (KEnum "context_limit" [])).
Definition coordinates (kind : callback_kind) := match kind with
 | ChatgptExec => [operation_identity]
 | BoardText => [Field "card_id" KNatural;Field "ticket" KNatural]
 | Worktree _ => ModelDeclarations.task_only
 | AfterHook => ModelDeclarations.identity ++ [operation_identity]
 | _ => ModelDeclarations.identity end.
Definition outcome_values (kind : callback_kind) := match kind with
 | Context => [OmittableField "observations" (KArray KJson)]
 | Reasoning => [OmittableField "effort" KText;OmittableField "generations" KNatural]
 | _ => [] end.
Definition outcome_diagnostic := OmittableField "message" KText.
Definition payload (kind : callback_kind) (ok : bool) := match kind with
 | TaskTitle => [Field "ok" KBool;Field (if ok then "title" else "message") KText]
 | BoardText => Field "ok" KBool :: (if ok then [Field "title" KText;Field "description" KText] else [Field "message" KText])
 | Approval | Hook | AfterHook => [Field "outcome" KJson]
 | Context | Reasoning => [Field "ok" KBool] ++ outcome_values kind ++ [outcome_diagnostic]
 | Model => [Field "ok" KBool;Field "items" (KOptional (KArray KJson));Field "message" (KOptional KText);failure_kind]
 | Tool => [Field "error" KBool;Field "value" (KOptional KJson)]
 | ChatgptExec => [Field "error" KBool;Field "value" KJson]
 | Compaction _ => [Field "result" KJson;Field "error" KBool]
 | Worktree created => Field "ok" KBool ::
   if created then if ok then [Field "root" KText;Field "workspace" KJson;Field "guidance" KJson]
     else [Field "root" (KOptional KText);Field "message" KText]
   else if ok then [Field "outcome" KJson] else [Field "message" KText]
 end.
Definition declaration kind ok := ModelDeclarations.effect (callback_text kind) (coordinates kind ++ payload kind ok) None.
Definition full_schema kind ok := Field "kind" KText :: ModelDeclarations.payload_fields (declaration kind ok).
Fixpoint append_fields (first second : schema) : fields first -> fields second -> fields (first ++ second) :=
 match first as first return fields first -> fields second -> fields (first ++ second) with
 | [] => fun _ values => values
 | field :: rest => fun first second => FCons (head first) (append_fields rest _ (tail first) second) end.
Definition encode kind ok (address : fields (coordinates kind)) (values : fields (payload kind ok)) :=
 ModelDeclarations.encode (declaration kind ok) (append_fields _ _ address values).
