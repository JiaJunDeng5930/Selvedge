From Selvedge.Programming Require Callback.
From Selvedge.Programming Require InputRoute.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import SchemaJson TextJson Utf8 Numbers.
From Selvedge.Programming Require ArgumentDeclaration DeclarationFields.
From Selvedge.Kernel Require Import HookRules Numbers Domain Codec Inputs ContextUpdates Configuration Reasoning ApprovalProtocol ModelDeclarations CallbackDeclarations.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition decoder := InputRoute.t input.
Definition Decoder (name : string) (description : schema) (construct : fields description -> option input)
 `{DistinctNames ("kind" :: map field_name description)} : decoder :=
 InputRoute.object name description construct.
Definition command_decoder := Decoder "command" [Field "command" KJson]
 (fun values => option_map UserCommand (Selvedge.Generated.Commands.decode (head values))).
Definition configure_decoder := Decoder "configure" Configuration.environment_schema
 (fun values => option_map Configure (Configuration.environment_of_fields values)).
(** The callback language chooses its result branch before exposing values.
    Domain handlers receive exactly that branch's fields and never reconstruct
    a relationship between independent optional payloads and a status flag. *)
Definition CallbackDecoder (description : Callback.callback_kind)
 (construct : forall ok, fields (Callback.coordinates description) ->
   DeclarationFields.values (Callback.payload description ok) -> option input) : decoder :=
 InputRoute.callback description (fun received =>
   let '(existT _ ok (address,values)) := received in construct ok address values).
Definition callback_kinds := [
 CallbackDecoder Context (fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (Callback.payload Context ok) -> option input then
     fun values => option_map (fun observations => ContextCompleted id ticket (Some observations) "")
       (Codec.traverse parse_observation (fst values))
   else fun values => Some (ContextCompleted id ticket None (proj1_sig (fst values))));
 CallbackDecoder Model (fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (Callback.payload Model ok) -> option input then
     fun values => Some (ModelCompleted id ticket (model_outcome_from_items (fst values)))
   else fun values => Some (ModelCompleted id ticket
     (match fst (snd values) with Some _ => ModelContextLimit | None => ModelFailure (proj1_sig (fst values)) end)));
 CallbackDecoder Reasoning (fun ok address =>
   let id := head address in let ticket := head (tail address) in
   if ok as ok return DeclarationFields.values (Callback.payload Reasoning ok) -> option input then
     fun values => Some (ReasoningCompleted id ticket (Reasoning.Chosen (proj1_sig (fst values)) (fst (snd values))))
   else fun values => Some (ReasoningCompleted id ticket (EvaluationFailed (proj1_sig (fst values)))));
 CallbackDecoder Tool (fun ok address values => Some (ToolCompleted (head address) (head (tail address))
     (match fst values with Some value => value | None => JNull end) (negb ok)));
 CallbackDecoder Hook (fun _ address values => Some (HookCompleted (head address) (head (tail address)) (HookRules.hook_from_fields (fst values))));
 CallbackDecoder AfterHook (fun _ address values => Some
     (AfterCompleted (head address) (head (tail (tail address))) (head (tail address)) (HookRules.after_from_fields (fst values))));
 CallbackDecoder Approval (fun _ address values => Some (ApprovalCompleted (head address) (head (tail address))
     (ApprovalProtocol.from_callback (fst values))))].
Definition decoders := [command_decoder;configure_decoder;
 Decoder "recover" [] (fun _ => Some Recover);Decoder "continue" [] (fun _ => Some Continue)].
Definition inputs := (callback_kinds ++ decoders)%list.

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
Definition diagnostic {A} (entry : InputRoute.t A) (source : json) :=
 match InputRoute.language entry with
 | InputRoute.Callback callback =>
   match Callback.read_status callback source with
   | Some ok => "Invalid callback '" ++ Callback.callback_text callback ++ "'; expected " ++
       TextJson.render_json (ArgumentDeclaration.schema (Callback.full_schema callback ok))
   | None => "Missing or invalid callback result marker" end
 | InputRoute.Object name declaration _ =>
   let payload := match source with JObject members => JObject (remove_field "kind" members) | other => other end in
   match Schema.decode declaration payload with
   | None => schema_diagnostic ("input '" ++ name ++ "'") declaration payload
   | Some _ => if String.eqb name "command" then command_diagnostic (value_or_null "command" payload)
     else "Invalid domain values in input '" ++ name ++ "'"
   end
 end.
