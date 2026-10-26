From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson TextJson Utf8 Numbers.
From Selvedge.Kernel Require Import HookRules Numbers Domain Codec Inputs ContextUpdates Configuration Reasoning ApprovalProtocol ModelDeclarations CallbackDeclarations.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition decoder := ModelDeclarations.decoder input.
Definition Decoder (name : string) (description : schema) (construct : fields description -> option input) : decoder :=
 ModelDeclarations.Decoder (ModelDeclarations.Variant "kind" (JString name) description [] None) construct.
Definition decoder_name (value : decoder) := match ModelDeclarations.tag_value (ModelDeclarations.decoder_declaration value) with
 | JString name => name | _ => "" end.
Definition decoder_fields (value : decoder) := ModelDeclarations.payload_fields (ModelDeclarations.decoder_declaration value).
Definition decoder_construct := @ModelDeclarations.decoder_construct input.
Definition coordinates := ModelDeclarations.identity.
Definition parse_reason_decision := HookRules.parse_reason_decision.
Definition parse_hook := HookRules.parse_hook.
Definition parse_after := HookRules.parse_after.
Definition parse_approval_outcome (source : json) : option approval_outcome :=
 match Schema.decode [Field "decision" KText; Field "reason" KText] source with
 | None => None
 | Some fields =>
   let reason := head (tail fields) in
   let outcome := match head fields with "allow" => Approved reason | "deny" => Denied reason | "failed" => ApprovalFailed reason
    | _ => ApprovalFailed "The review did not return a valid decision" end in
   (* DEFENSE: Native approval callbacks can supply a blank reason. Reject that
      malformed outcome; invalid text still settles as a failed review. *)
   if ApprovalProtocol.valid_justification reason then
     Some (ApprovalProtocol.normalize_outcome outcome)
   else if ApprovalProtocol.valid_reason reason then None
   else Some (ApprovalProtocol.normalize_outcome outcome)
 end.
Definition command_decoder := Decoder "command" [Field "command" KJson]
 (fun values => option_map UserCommand (Selvedge.Generated.Commands.decode (head values))).
Definition configure_decoder := Decoder "configure" Configuration.environment_schema
 (fun values => option_map Configure (Configuration.environment_of_fields values)).
Definition context_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Context false)
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  let ok := head values in let values := tail values in let observations := head values in let diagnostic := head (tail values) in
  if ok then match observations,diagnostic with
  | Some observations,None => option_map (fun observations => ContextCompleted id ticket (Some observations) "") (Codec.traverse parse_observation observations)
  | _,_ => None end
  else match observations,diagnostic with
  | None,Some text => if Nat.leb (Utf8.byte_length text) 4096 then Some (ContextCompleted id ticket None text) else None
  | _,_ => None end).
Definition model_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Model false)
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  let ok := head values in let values := tail values in let items := head values in let values := tail values in
  let diagnostic := head values in let failure := head (tail values) in
  if ok then match items with
  | Some items => option_map (fun items => ModelCompleted id ticket (ModelSuccess items)) (Codec.traverse Codec.parse_model_item items)
  | None => None end
  else match diagnostic with
  | Some text => Some (ModelCompleted id ticket (match failure with Some _ => ModelContextLimit | None => ModelFailure text end))
  | None => None end).
Definition reasoning_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Reasoning false)
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  let ok := head values in let values := tail values in let effort := head values in let values := tail values in
  let generations := head values in let diagnostic := head (tail values) in
  if ok then match effort,generations,diagnostic with
  | Some effort,Some generations,None =>
      if Nat.leb (Utf8.byte_length effort) 64 then Some (ReasoningCompleted id ticket (Reasoning.Chosen effort generations)) else None
  | _,_,_ => None end
  else match effort,generations,diagnostic with
  | None,None,Some reason =>
      if Nat.leb (Utf8.byte_length reason) 4096 then Some (ReasoningCompleted id ticket (EvaluationFailed reason)) else None
  | _,_,_ => None end).
Definition tool_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Tool false)
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  Some (ToolCompleted id ticket (match head (tail values) with Some value => value | None => JNull end) (head values))).
Definition hook_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Hook false)
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  option_map (HookCompleted id ticket) (parse_hook (head (tail values)))).
Definition after_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration AfterHook false)
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  let values := tail values in let operation := head values in
  option_map (AfterCompleted id operation ticket) (parse_after (head (tail values)))).
Definition approval_decoder := ModelDeclarations.Decoder (CallbackDeclarations.declaration Approval false)
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  option_map (ApprovalCompleted id ticket) (parse_approval_outcome (head (tail values)))).
Definition decoders := [command_decoder;configure_decoder;context_decoder;model_decoder;reasoning_decoder;
 tool_decoder;hook_decoder;after_decoder;approval_decoder;
 Decoder "recover" [] (fun _ => Some Recover);Decoder "continue" [] (fun _ => Some Continue)].
Definition decode (source : json) : option input :=
 match source with
 | JObject members => if Schema.unique_names (map fst members) then
   match lookup "kind" members with
   | Some (JString _) => ModelDeclarations.decode_cases decoders source
   | _ => None end
   else None
 | _ => None end.
(** A decoded input remains tied to the exact source that admitted it. Internal
    Inputs.input values are still available for notification and commit algebra;
    the production packet accepts this indexed admission, not a free input. *)
Definition admitted_input (source : json) := { value : option input | decode source = value }.
Definition admit (source : json) : admitted_input source := exist _ (decode source) eq_refl.
Definition admitted_value {source : json} (value : admitted_input source) := proj1_sig value.
Theorem admitted_input_is_its_decoder_result : forall source (value : admitted_input source),
 admitted_value value = decode source.
Proof. intros source [value Decoded]; cbn; symmetry; exact Decoded. Qed.
Theorem admitted_public_command_retains_complete_declaration : forall values command,
 decoder_construct command_decoder values = Some (UserCommand command) ->
 exists admitted : Selvedge.Generated.Commands.admitted_command,
   Selvedge.Generated.Commands.admitted_source admitted = head values /\
   Selvedge.Generated.Commands.admitted_value admitted = command /\
   CommandDeclarations.valid true (head values) = true.
Proof.
 intros values command Decoded.
 change (option_map UserCommand (Selvedge.Generated.Commands.decode (head values)) =
   Some (UserCommand command)) in Decoded.
 destruct (Selvedge.Generated.Commands.decode (head values)) as [decoded|] eqn:Parsed; [|discriminate].
 inversion Decoded; subst decoded.
 exists (Selvedge.Generated.Commands.AdmittedCommand (head values) command Parsed).
 split; [reflexivity|]; split; [reflexivity|].
 exact (Selvedge.Generated.Commands.admitted_command_has_complete_declaration
   (Selvedge.Generated.Commands.AdmittedCommand (head values) command Parsed)).
Qed.
Definition owns_kind (source : json) :=
 match string_field "kind" source with Some kind => existsb (fun decoder => String.eqb kind (decoder_name decoder)) decoders | None => false end.

Open Scope string_scope.
Definition schema_diagnostic (label : string) (declaration : schema) (source : json) :=
 match source with
 | JObject members =>
   match find (fun member => negb (existsb (fun field => String.eqb (fst member) (field_name field)) declaration)) members with
   | Some (name,_) => "Unknown field '" ++ name ++ "' in " ++ label
   | None =>
     (* Explain failure with the same field decoder used for admission. *)
     match find (fun field => match Schema.decode [field]
       (JObject (filter (fun member => String.eqb (fst member) (field_name field)) members)) with
       | None => true | Some _ => false end) declaration with
     | Some field => (if has_field (field_name field) source then "Invalid field '" else "Missing field '") ++
       field_name field ++ "' in " ++ label ++ "; expected " ++
       TextJson.render_json (JObject (SchemaJson.kind_schema (field_kind field)))
     | None => "Invalid values in " ++ label
     end
   end
 | _ => "Expected an object for " ++ label
 end.
Definition command_diagnostic (source : json) :=
 match string_field "op" source with
 | Some name => match find (fun declaration => String.eqb name (command_name declaration)) Selvedge.Kernel.Commands.command_specs with
   | Some declaration => schema_diagnostic ("command '" ++ name ++ "'")
       (Field "op" (KEnum name []) :: command_fields declaration) source
   | None => "Unknown command '" ++ name ++ "'; use describe for the executable vocabulary"
   end
 | None => "Missing or invalid command 'op'; use describe for the executable vocabulary"
 end.
Definition diagnostic (source : json) :=
 match string_field "kind" source with
 | Some kind => match find (fun decoder => String.eqb kind (decoder_name decoder)) decoders with
   | Some decoder =>
     let payload := match source with JObject members => JObject (remove_field "kind" members) | other => other end in
     match Schema.decode (decoder_fields decoder) payload with
     | None => schema_diagnostic ("input '" ++ kind ++ "'") (decoder_fields decoder) payload
     | Some _ => if String.eqb kind "command" then command_diagnostic (value_or_null "command" payload)
       else "Invalid domain values in input '" ++ kind ++ "'"
     end
   | None => "Unknown protocol input '" ++ kind ++ "'"
   end
 | None => "Missing or invalid protocol 'kind'"
 end.
