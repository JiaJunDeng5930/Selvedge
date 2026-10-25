From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson TextJson Utf8 Numbers.
From Selvedge.Kernel Require Import HookRules Numbers Domain Codec Inputs ContextUpdates Configuration Reasoning ApprovalProtocol.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Record decoder := Decoder {
 decoder_name : string;
 decoder_fields : schema;
 decoder_construct : fields decoder_fields -> option input
}.
Definition coordinates := [Field "task_id" KNatural; Field "ticket" KNatural].
Definition parse_reason_decision := HookRules.parse_reason_decision.
Definition parse_hook := HookRules.parse_hook.
Definition parse_after := HookRules.parse_after.
Definition parse_approval_outcome (source : json) : option approval_outcome :=
 match Schema.decode [Field "decision" KText; Field "reason" KText] source with
 | None => None
 | Some fields =>
   let reason := head (tail fields) in
   let outcome := match head fields with "allow" => Approved reason | "deny" => Denied reason
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
Definition configure_decoder := Decoder "configure"
 [Field "profiles" (KArray KJson); Field "tools" (KArray KJson); Field "plugins" (KOptional (KArray KJson));
  Field "max_fork" KNatural;Field "max_descendants" KNatural;Field "project" (KOptional KJson);Field "instructions" KJson]
 (fun values => option_map Configure (Configuration.parse_environment (Schema.encode _ values))).
Definition context_decoder := Decoder "context_observed"
 (coordinates ++ [Field "ok" KBool;Field "observations" (KOptional (KArray KJson));Field "message" (KOptional KText)])
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  let ok := head values in let values := tail values in let observations := head values in let diagnostic := head (tail values) in
  if ok then match observations,diagnostic with
  | Some observations,None => option_map (fun observations => ContextCompleted id ticket (Some observations) "") (Codec.traverse parse_observation observations)
  | _,_ => None end
  else match observations,diagnostic with
  | None,Some text => if Nat.leb (Utf8.byte_length text) 4096 then Some (ContextCompleted id ticket None text) else None
  | _,_ => None end).
Definition model_decoder := Decoder "model"
 (coordinates ++ [Field "ok" KBool;Field "items" (KOptional (KArray KJson));Field "message" (KOptional KText);Field "failure_kind" (KOptional (KEnum "context_limit" []))])
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
Definition reasoning_decoder := Decoder "reasoning"
 (coordinates ++ [Field "ok" KBool;Field "effort" (KOptional KText);Field "generations" (KOptional KNatural);Field "message" (KOptional KText)])
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
Definition tool_decoder := Decoder "tool"
 (coordinates ++ [Field "value" (KOptional KJson);Field "error" KBool])
 (fun values =>
  let id := head values in let values := tail values in let ticket := head values in let values := tail values in
  Some (ToolCompleted id ticket (match head values with Some value => value | None => JNull end) (head (tail values)))).
Definition hook_decoder := Decoder "hook" (coordinates ++ [Field "outcome" KJson])
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  option_map (HookCompleted id ticket) (parse_hook (head (tail values)))).
Definition after_decoder := Decoder "after_hook"
 (coordinates ++ [Field "operation_id" KNatural;Field "outcome" KJson])
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  let values := tail values in let operation := head values in
  option_map (AfterCompleted id operation ticket) (parse_after (head (tail values)))).
Definition approval_decoder := Decoder "approval" (coordinates ++ [Field "outcome" KJson])
 (fun values => let id := head values in let values := tail values in let ticket := head values in
  option_map (ApprovalCompleted id ticket) (parse_approval_outcome (head (tail values)))).
Definition decoders := [command_decoder;configure_decoder;context_decoder;model_decoder;reasoning_decoder;
 tool_decoder;hook_decoder;after_decoder;approval_decoder;
 Decoder "recover" [] (fun _ => Some Recover);Decoder "continue" [] (fun _ => Some Continue)].
(* DEFENSE: Native callbacks can supply the other variant's fields as explicit
   nulls; optional decoding alone would conflate those keys with absence. *)
Definition variant_fields_valid (kind : string) (source : json) :=
 match kind with
 | "context_observed" => match bool_field "ok" source with
   | Some true => negb (has_field "message" source)
   | Some false => negb (has_field "observations" source)
   | None => true end
 | "reasoning" => match bool_field "ok" source with
   | Some true => negb (has_field "message" source)
   | Some false => negb (has_field "effort" source || has_field "generations" source)
   | None => true end
 | _ => true end.
Definition decode (source : json) : option input :=
 match source with
 | JObject fields => if Schema.unique_names (map fst fields) then
   match lookup "kind" fields with
   | Some (JString kind) => match find (fun decoder => String.eqb kind (decoder_name decoder)) decoders with
     | None => None
     | Some decoder => if variant_fields_valid kind (JObject fields) then
       match Schema.decode (decoder_fields decoder) (JObject (remove_field "kind" fields)) with
       | Some values => decoder_construct decoder values | None => None end else None
     end
   | _ => None end
   else None
 | _ => None end.
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
