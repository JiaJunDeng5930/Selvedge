From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema DeclarationFields.
From Selvedge.Foundation Require ArgumentDeclaration.
From Selvedge.Kernel Require Import ModelDeclarations ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition operation_identity := Field "operation_id" KNatural.
Definition coordinates (kind : callback_kind) := match kind with
 | ChatgptExec => [operation_identity]
 | BoardText => [Field "card_id" KNatural;Field "ticket" KNatural]
 | Worktree _ => ModelDeclarations.task_only
 | AfterHook => ModelDeclarations.identity ++ [operation_identity]
 | _ => ModelDeclarations.identity end.
Definition text_constraints bytes no_nul nonblank :=
 D.TextConstraints 0 D.maximum_natural bytes no_nul nonblank false None.
Definition text bytes no_nul := D.Text (text_constraints bytes no_nul false).
Definition diagnostic_constraints kind := match kind with
 | Approval => ApprovalProtocol.justification_constraints
 | _ => text_constraints 4096 true false end.
Definition diagnostic_format kind := D.ConstrainedText (diagnostic_constraints kind).
Definition diagnostic_text kind := D.Textual (diagnostic_format kind).
Definition reason decision declaration := D.Object
 [F.required "decision" (D.Const (JString decision));F.required "reason" declaration].
Definition hook_schema := D.Union
 [D.Object [F.required "decision" (D.Const (JString "allow"))];
  D.Object [F.required "decision" (D.Const (JString "rewrite"));F.required "arguments" D.RawObject];
  reason "deny" (diagnostic_text Hook);reason "failed" (diagnostic_text Hook)].
Definition after_schema := D.Union
 [D.Object [F.required "decision" (D.Const (JString "allow"))];
  D.Object [F.required "decision" (D.Const (JString "rewrite"));F.required "value" D.Any];
  reason "deny" (diagnostic_text AfterHook);reason "failed" (diagnostic_text AfterHook)].
Definition created_workspace := D.Object
 [F.required "roots" (D.Array D.text);F.required "primary_root" D.text].
Definition approval_schema := D.Union
 [reason "allow" ApprovalProtocol.justification_declaration;
  reason "deny" ApprovalProtocol.justification_declaration;
  reason "failed" ApprovalProtocol.justification_declaration].

(** The branch carries the constraints used by the public decoder. Its fixed
    marker and field names are supplied by the declaration. *)
Definition status (kind : callback_kind) : option (string * bool) := match kind with
 | Approval | Hook | AfterHook => None
 | Tool | ChatgptExec | Compaction _ => Some ("error",false)
 | _ => Some ("ok",true) end.
Definition payload (kind : callback_kind) (ok : bool) := match kind with
 | TaskTitle => [F.required (if ok then "title" else "message")
     (D.Text (if ok then text_constraints 4096 false false else diagnostic_constraints TaskTitle))]
 | BoardText => if ok then [F.required "title" (text 4096 true);F.required "description" (text 100000 true)]
   else [F.required "message" (diagnostic_text BoardText)]
 | Approval => [F.required "outcome" approval_schema]
 | Hook => [F.required "outcome" hook_schema]
 | AfterHook => [F.required "outcome" after_schema]
 | Context => if ok then [F.required "observations" (D.Array D.Any)] else [F.required "message" (diagnostic_text Context)]
 | Reasoning => if ok then [F.required "effort" (text 64 false);F.required "generations" (D.Value KNatural)]
   else [F.required "message" (diagnostic_text Reasoning)]
 | Model => if ok then [F.required "items" (D.Array D.Any)]
   else [F.required "message" (diagnostic_text Model);F.optional "failure_kind" (D.Const (JString "context_limit"))]
 | Tool => [F.optional "value" D.Any]
 | ChatgptExec => [F.required "value" D.RawObject]
 | Compaction _ => [F.required "result" (if ok then D.RawObject else
     D.Object [F.required "message" (diagnostic_text (Compaction false))])]
 | Worktree created =>
   if created then if ok then [F.required "root" D.text;F.required "workspace" created_workspace;F.required "guidance" D.Any]
     else [F.optional "root" D.text;F.required "message" (diagnostic_text (Worktree true))]
   else if ok then [F.required "outcome" D.Any] else [F.required "message" (diagnostic_text (Worktree false))]
 end.
Definition wire_payload kind ok := match status kind with
 | Some (name,success) => F.required name (D.Const (JBool (Bool.eqb ok success))) :: payload kind ok
 | None => payload kind ok end.
Definition full_properties kind ok := F.required "kind" (D.Const (JString (callback_text kind))) ::
 F.schema_properties (coordinates kind) ++ wire_payload kind ok.
Definition full_schema kind ok := D.Object (full_properties kind ok).
Definition mark kind ok : F.values (payload kind ok) -> F.values (wire_payload kind ok) :=
 match status kind as marker return F.values (payload kind ok) ->
   F.values (match marker with Some (name,success) =>
     F.required name (D.Const (JBool (Bool.eqb ok success))) :: payload kind ok | None => payload kind ok end) with
 | Some (name,success) => fun values => (tt,values)
 | None => fun values => values end.
Definition unmark kind ok : F.values (wire_payload kind ok) -> F.values (payload kind ok) :=
 match status kind as marker return F.values (match marker with Some (name,success) =>
     F.required name (D.Const (JBool (Bool.eqb ok success))) :: payload kind ok | None => payload kind ok end) ->
   F.values (payload kind ok) with
 | Some (name,success) => fun values => snd values
 | None => fun values => values end.
Definition full_fields kind ok (address : Schema.fields (coordinates kind)) (values : F.values (payload kind ok))
 : D.denote (full_schema kind ok).
Proof.
 refine (exist _ (tt,F.append _ _ (F.from_schema address) (mark kind ok values)) _).
 destruct kind; destruct ok; try destruct completed; try destruct created; reflexivity.
Defined.
Definition encode kind ok address values := D.encode (full_schema kind ok) (full_fields kind ok address values).
Definition read_status kind source := match status kind with
 | Some (name,success) => option_map (fun marked => Bool.eqb marked success) (bool_field name source)
 | None => Some true end.
Definition decoded kind := { ok : bool & (Schema.fields (coordinates kind) * F.values (payload kind ok))%type }.
Definition decode_branch kind ok source :=
 option_map (fun values =>
   let '(address,payload) := F.split (F.schema_properties (coordinates kind)) (wire_payload kind ok) (snd (proj1_sig values)) in
   (F.to_schema (coordinates kind) address,unmark kind ok payload))
   (D.decode (full_schema kind ok) source).
Definition decode kind source : option (decoded kind) :=
 match read_status kind source with
 | Some ok => option_map (fun values => existT _ ok values) (decode_branch kind ok source)
 | None => None end.
