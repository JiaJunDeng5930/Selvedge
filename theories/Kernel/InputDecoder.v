From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson TextJson Utf8 Numbers.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields.
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
Definition parse_hook := HookRules.parse_hook.
Definition parse_after := HookRules.parse_after.
Definition approval_from_fields (value : ArgumentDeclaration.denote CallbackDeclarations.approval_schema) : approval_outcome :=
 match value with
 | inl reason => Approved (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inl reason) => Denied (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inl reason)) => ApprovalFailed (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr impossible)) => match impossible with end end.
Definition parse_approval_outcome source := option_map approval_from_fields
 (ArgumentDeclaration.decode CallbackDeclarations.approval_schema source).
Definition command_decoder := Decoder "command" [Field "command" KJson]
 (fun values => option_map UserCommand (Selvedge.Generated.Commands.decode (head values))).
Definition configure_decoder := Decoder "configure" Configuration.environment_schema
 (fun values => option_map Configure (Configuration.environment_of_fields values)).
(** The callback language chooses its result branch before exposing values.
    Domain handlers receive exactly that branch's fields and never reconstruct
    a relationship between independent optional payloads and a status flag. *)
Definition callback_kinds := [Context;Model;Reasoning;Tool;Hook;AfterHook;Approval].
Definition callback_named (name : string) :=
 find (fun kind => String.eqb name (callback_text kind)) callback_kinds.
Definition callback_input (kind : callback_kind) : forall ok,
 fields (CallbackDeclarations.coordinates kind) -> DeclarationFields.values (CallbackDeclarations.payload kind ok) -> option input :=
 match kind as kind return forall ok, fields (CallbackDeclarations.coordinates kind) ->
   DeclarationFields.values (CallbackDeclarations.payload kind ok) -> option input with
 | Context => fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (CallbackDeclarations.payload Context ok) -> option input then
     fun values => option_map (fun observations => ContextCompleted id ticket (Some observations) "")
       (Codec.traverse parse_observation (fst values))
   else fun values => Some (ContextCompleted id ticket None (proj1_sig (fst values)))
 | Model => fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (CallbackDeclarations.payload Model ok) -> option input then
     fun values => option_map (fun items => ModelCompleted id ticket (ModelSuccess items))
       (Codec.traverse Codec.parse_model_item (fst values))
   else fun values => Some (ModelCompleted id ticket
     (match fst (snd values) with Some _ => ModelContextLimit | None => ModelFailure (proj1_sig (fst values)) end))
 | Reasoning => fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (CallbackDeclarations.payload Reasoning ok) -> option input then
     fun values => Some (ReasoningCompleted id ticket (Reasoning.Chosen (proj1_sig (fst values)) (fst (snd values))))
   else fun values => Some (ReasoningCompleted id ticket (EvaluationFailed (proj1_sig (fst values))))
 | Tool => fun ok address values => Some (ToolCompleted (head address) (head (tail address))
     (match fst values with Some value => value | None => JNull end) (negb ok))
 | Hook => fun _ address values => Some (HookCompleted (head address) (head (tail address)) (HookRules.hook_from_fields (fst values)))
 | AfterHook => fun _ address values => Some
     (AfterCompleted (head address) (head (tail (tail address))) (head (tail address)) (HookRules.after_from_fields (fst values)))
 | Approval => fun _ address values => Some (ApprovalCompleted (head address) (head (tail address))
     (approval_from_fields (fst values)))
 | _ => fun _ _ _ => None end.
Definition decode_callback kind source :=
 match CallbackDeclarations.decode kind source with
 | Some (existT _ ok (address,values)) => callback_input kind ok address values
 | None => None end.
Definition decoders := [command_decoder;configure_decoder;
 Decoder "recover" [] (fun _ => Some Recover);Decoder "continue" [] (fun _ => Some Continue)].
Definition decode (source : json) : option input :=
 match source with
 | JObject members => if Schema.unique_names (map fst members) then
   match lookup "kind" members with
   | Some (JString name) => match callback_named name with
     | Some kind => decode_callback kind source
     | None => ModelDeclarations.decode_cases decoders source end
   | _ => None end
   else None
 | _ => None end.
Definition owns_kind (source : json) :=
 match string_field "kind" source with Some kind =>
   match callback_named kind with Some _ => true
   | None => existsb (fun decoder => String.eqb kind (decoder_name decoder)) decoders end
 | None => false end.

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
 | Some kind => match callback_named kind with
   | Some callback => match CallbackDeclarations.read_status callback source with
     | Some ok => "Invalid callback '" ++ kind ++ "'; expected " ++ TextJson.render_json (ArgumentDeclaration.schema (CallbackDeclarations.full_schema callback ok))
     | None => "Missing or invalid callback result marker" end
   | None => match find (fun decoder => String.eqb kind (decoder_name decoder)) decoders with
   | Some decoder =>
     let payload := match source with JObject members => JObject (remove_field "kind" members) | other => other end in
     match Schema.decode (decoder_fields decoder) payload with
     | None => schema_diagnostic ("input '" ++ kind ++ "'") (decoder_fields decoder) payload
     | Some _ => if String.eqb kind "command" then command_diagnostic (value_or_null "command" payload)
       else "Invalid domain values in input '" ++ kind ++ "'"
     end
   | None => "Unknown protocol input '" ++ kind ++ "'"
   end end
 | None => "Missing or invalid protocol 'kind'"
 end.
