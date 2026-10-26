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
Definition payload (kind : callback_kind) (ok : bool) := match kind with
 | TaskTitle => [Field "ok" KBool;Field (if ok then "title" else "message") KText]
 | BoardText => Field "ok" KBool :: (if ok then [Field "title" KText;Field "description" KText] else [Field "message" KText])
 | Approval | Hook | AfterHook => [Field "outcome" KJson]
 | Context => [Field "ok" KBool;Field "observations" (KOptional (KArray KJson));Field "message" (KOptional KText)]
 | Reasoning => [Field "ok" KBool;Field "effort" (KOptional KText);Field "generations" (KOptional KNatural);Field "message" (KOptional KText)]
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
(** The external adapter echoes raw coordinates and result values. Presence and
    field order still come from the same declaration used for typed admission. *)
Definition raw_field (field : field_spec) := OmittableField (field_name field) KJson.
Definition raw_schema (description : schema) := map raw_field description.
Definition raw_variant (description : variant) := Variant (tag_field description) (tag_value description)
 (raw_schema (ModelDeclarations.payload_fields description)) [] None.
Fixpoint raw_source (description : schema) (source : json) : fields (raw_schema description) :=
 match description as description return fields (raw_schema description) with [] => FNil | field :: rest =>
 FCons (field:=raw_field field) (Some (match Json.field (field_name field) source with Some value => value | None => JNull end)) (raw_source rest source) end.
Fixpoint append_raw (first second : schema) : fields (raw_schema first) -> fields (raw_schema second) -> fields (raw_schema (first ++ second)) :=
 match first as first return fields (raw_schema first) -> fields (raw_schema second) -> fields (raw_schema (first ++ second)) with
 | [] => fun _ values => values
 | field :: rest => fun first second => FCons (field:=raw_field field) (head first) (append_raw rest _ (tail first) second) end.
Definition raw_values kind ok source (values : Schema.tuple (raw_schema (payload kind ok))) :=
 append_raw (coordinates kind) (payload kind ok) (raw_source (coordinates kind) source) (Schema.of_tuple _ values).
Definition move_first (field : field_spec) (source : json) := match source with
 | JObject members => match lookup (field_name field) members with
   | Some value => JObject (set_field (field_name field) value members) | None => source end
 | _ => source end.
Definition encode kind ok source values :=
 let wire := ModelDeclarations.encode (raw_variant (declaration kind ok)) (raw_values kind ok source values) in
 if ok then wire else match kind with AfterHook => move_first operation_identity wire
 | Model => move_first failure_kind wire | _ => wire end.
