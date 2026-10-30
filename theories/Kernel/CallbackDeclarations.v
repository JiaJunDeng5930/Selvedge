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
(** A branch stores only its data. The constructor owns the result marker, so
    a successful callback cannot contain a failure marker or a failure-only
    payload. The same branch description admits external callbacks. *)
Definition status (kind : callback_kind) : option (string * bool) := match kind with
 | Approval | Hook | AfterHook => None
 | Tool | ChatgptExec | Compaction _ => Some ("error",false)
 | _ => Some ("ok",true) end.
Definition payload (kind : callback_kind) (ok : bool) := match kind with
 | TaskTitle => [Field (if ok then "title" else "message") KText]
 | BoardText => if ok then [Field "title" KText;Field "description" KText] else [Field "message" KText]
 | Approval | Hook | AfterHook => [Field "outcome" KJson]
 | Context => if ok then [Field "observations" (KArray KJson)] else [Field "message" KText]
 | Reasoning => if ok then [Field "effort" KText;Field "generations" KNatural] else [Field "message" KText]
 | Model => if ok then [Field "items" (KArray KJson)] else [Field "message" KText;failure_kind]
 | Tool => [Field "value" (KOptional KJson)]
 | ChatgptExec => [Field "value" KJson]
 | Compaction _ => [Field "result" KJson]
 | Worktree created =>
   if created then if ok then [Field "root" KText;Field "workspace" KJson;Field "guidance" KJson]
     else [Field "root" (KOptional KText);Field "message" KText]
   else if ok then [Field "outcome" KJson] else [Field "message" KText]
 end.
Definition wire_payload kind ok := match status kind with
 | Some (name,_) => Field name KBool :: payload kind ok
 | None => payload kind ok end.
Definition declaration kind ok := ModelDeclarations.effect (callback_text kind) (coordinates kind ++ wire_payload kind ok) None.
Definition full_schema kind ok := Field "kind" KText :: ModelDeclarations.payload_fields (declaration kind ok).
Fixpoint append_fields (first second : schema) : fields first -> fields second -> fields (first ++ second) :=
 match first as first return fields first -> fields second -> fields (first ++ second) with
 | [] => fun _ values => values
 | field :: rest => fun first second => FCons (head first) (append_fields rest _ (tail first) second) end.
Fixpoint split_fields (first second : schema) : fields (first ++ second) -> fields first * fields second :=
 match first as first return fields (first ++ second) -> fields first * fields second with
 | [] => fun values => (FNil,values)
 | field :: rest => fun values => let '(prefix,suffix) := split_fields rest second (tail values) in
   (FCons (head values) prefix,suffix) end.
Definition mark kind ok : fields (payload kind ok) -> fields (wire_payload kind ok) :=
 match status kind as marker return fields (payload kind ok) ->
   fields (match marker with Some (name,_) => Field name KBool :: payload kind ok | None => payload kind ok end) with
 | Some (name,success) => fun values => FCons (field:=Field name KBool) (Bool.eqb ok success) values
 | None => fun values => values end.
Definition unmark kind ok : fields (wire_payload kind ok) -> fields (payload kind ok) :=
 match status kind as marker return
   fields (match marker with Some (name,_) => Field name KBool :: payload kind ok | None => payload kind ok end) -> fields (payload kind ok) with
 | Some (name,_) => fun values => @tail (Field name KBool) (payload kind ok) values
 | None => fun values => values end.
Definition encode kind ok (address : fields (coordinates kind)) (values : fields (payload kind ok)) :=
 ModelDeclarations.encode (declaration kind ok) (append_fields _ _ address (mark kind ok values)).
Definition full_fields kind ok (address : fields (coordinates kind)) (values : fields (payload kind ok)) :=
 FCons (field:=Field "kind" KText) (callback_text kind)
   (append_fields _ _ address (mark kind ok values)).
Definition read_status kind source := match status kind with
 | Some (name,success) => option_map (fun flag => Bool.eqb flag success) (bool_field name source)
 | None => Some true end.
Definition response kind := { ok : bool & (fields (coordinates kind) * fields (payload kind ok))%type }.
Definition decode kind source : option (response kind) :=
 match read_status kind source with
 | None => None
 | Some ok => if ModelDeclarations.matches (declaration kind ok) source then
   option_map (fun values =>
     let '(address,values) := split_fields (coordinates kind) (wire_payload kind ok) (tail values) in
     existT _ ok (address,unmark kind ok values))
     (Schema.decode (full_schema kind ok) source)
   else None
 end.
