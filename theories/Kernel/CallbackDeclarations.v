From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Selvedge.Foundation Require Import ModelWire BoundedDiagnostic.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Kernel Require Import ApprovalProtocol.
From Selvedge.Kernel Require Guidance WorkspacePath.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition identity := [Field "task_id" KNatural;Field "ticket" KNatural].
Definition task_only := [Field "task_id" KNatural].
Definition operation_identity := Field "operation_id" KNatural.
Definition text_constraints bytes no_nul nonblank :=
 D.TextConstraints 0 D.maximum_natural bytes no_nul nonblank false None.
Definition text bytes no_nul := D.Text (text_constraints bytes no_nul false).

Record diagnostic_spec := Diagnostic {
 diagnostic_constraint : D.text_constraints;
 diagnostic_default : D.text_value (D.ConstrainedText diagnostic_constraint)
}.
Definition diagnostic_type spec := D.Textual (D.ConstrainedText (diagnostic_constraint spec)).
Definition diagnostic_admitted spec := D.denote (diagnostic_type spec).
Definition standard_diagnostic := Diagnostic (text_constraints 4096 true false)
 (exist _ BoundedDiagnostic.fallback eq_refl).
Definition approval_diagnostic := Diagnostic ApprovalProtocol.justification_constraints
 (exist _ BoundedDiagnostic.fallback eq_refl).
Definition normalize_diagnostic spec := BoundedDiagnostic.make
 (diagnostic_constraint spec) (diagnostic_default spec).

Definition marked_fields marker (body : list F.property) := match marker with
 | Some (name,success) => F.required name (D.Const (JBool success)) :: body
 | None => body end.
Definition wire_fields marker (body : bool -> list F.property) ok :=
 marked_fields (option_map (fun '(name,success) => (name,Bool.eqb ok success)) marker) (body ok).
Inductive layout := Unmarked (fields : list F.property)
 | Marked (name : string) (success : bool) (fields : bool -> list F.property).
Definition result_fields shape ok := match shape with
 | Unmarked fields => fields | Marked _ _ fields => fields ok end.
Definition result_marker shape := match shape with
 | Unmarked _ => None | Marked name success _ => Some (name,success) end.
Definition property_names address shape ok :=
 "kind" :: F.names (F.schema_properties address ++ wire_fields (result_marker shape) (result_fields shape) ok).
Definition replies (body : bool -> list F.property) := { ok : bool & F.values (body ok) }.

(** Each callback owns its vocabulary, branches and physical result observation.
    The common constructor owns framing, coordinate fields and field uniqueness;
    extending the vocabulary never extends an enumeration or a case analysis. *)
Record callback_kind := Callback {
 callback_text : string;
 coordinates : schema;
 result_layout : layout;
 diagnostic_definition : diagnostic_spec;
 observe_result : json -> option (replies (result_fields result_layout));
 reject_result : diagnostic_admitted diagnostic_definition -> bool -> F.values (result_fields result_layout false);
 distinct_success : unique_names (property_names coordinates result_layout true) = true;
 distinct_failure : unique_names (property_names coordinates result_layout false) = true
}.
Definition declare name address shape diagnostic observe reject
 `{DistinctNames (property_names address shape true)}
 `{DistinctNames (property_names address shape false)} :=
 Callback name address shape diagnostic observe reject
  (@names_distinct _ H) (@names_distinct _ H0).
Definition payload kind := result_fields (result_layout kind).
Definition status kind := result_marker (result_layout kind).
Definition diagnostic_text kind := diagnostic_type (diagnostic_definition kind).
Definition diagnostic kind := normalize_diagnostic (diagnostic_definition kind).
Definition reply_fields kind := replies (payload kind).
Definition observed_result kind := observe_result kind.
Definition failure_payload kind := reject_result kind.
Definition wire_payload kind := wire_fields (status kind) (payload kind).
Definition full_properties kind ok := F.required "kind" (D.Const (JString (callback_text kind))) ::
 F.schema_properties (coordinates kind) ++ wire_payload kind ok.
Definition full_schema kind ok := D.Object (full_properties kind ok).
Definition mark kind ok : F.values (payload kind ok) -> F.values (wire_payload kind ok) :=
 match status kind as marker return F.values (payload kind ok) ->
   F.values (wire_fields marker (payload kind) ok) with
 | Some (name,success) => fun values => (tt,values) | None => fun values => values end.
Definition unmark kind ok : F.values (wire_payload kind ok) -> F.values (payload kind ok) :=
 match status kind as marker return F.values (wire_fields marker (payload kind) ok) ->
   F.values (payload kind ok) with
 | Some (name,success) => fun values => snd values | None => fun values => values end.
Definition full_fields kind ok (address : Schema.fields (coordinates kind)) (values : F.values (payload kind ok))
 : D.denote (full_schema kind ok).
Proof.
 refine (exist _ (tt,F.append _ _ (F.from_schema address) (mark kind ok values)) _).
 destruct ok; [exact (distinct_success kind)|exact (distinct_failure kind)].
Defined.
Definition encode kind ok address values := D.encode (full_schema kind ok) (full_fields kind ok address values).
Definition read_status kind source := match status kind with
 | Some (name,success) => option_map (fun marked => Bool.eqb marked success) (bool_field name source)
 | None => Some true end.
Definition decoded kind := { ok : bool & (Schema.fields (coordinates kind) * F.values (payload kind ok))%type }.
Definition decode_branch kind ok source :=
 option_map (fun values =>
   let '(address,fields) := F.split (F.schema_properties (coordinates kind)) (wire_payload kind ok) (snd (proj1_sig values)) in
   (F.to_schema (coordinates kind) address,unmark kind ok fields))
   (D.decode (full_schema kind ok) source).
Definition decode kind source : option (decoded kind) :=
 match read_status kind source with
 | Some ok => option_map (fun values => existT _ ok values) (decode_branch kind ok source)
 | None => None end.

Definition observe_fields body ok source : option (replies body) :=
 option_map (fun values => existT _ ok values) (F.observe (body ok) source).
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
Definition wrapped property description := fun _ : bool => [F.required property description].
Definition observe_wrapped property description source : option (replies (wrapped property description)) :=
 option_map (fun value => existT _ true (value,tt)) (D.decode description source).
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
