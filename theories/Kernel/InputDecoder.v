From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8 Numbers.
From Selvedge.Kernel Require Import Numbers Domain Codec Inputs ContextUpdates Configuration Reasoning ApprovalProtocol.
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
Definition parse_reason_decision (decision : string) (source : json) :=
 match Schema.decode [Field "decision" (KEnum decision []);Field "reason" KText] source with
 | Some values => let reason := head (tail values) in
   if Utf8.well_formed reason && Nat.leb (String.length reason) 4096 then Some reason else None
 | None => None end.
Definition parse_hook (source : json) : option hook_outcome :=
 match string_field "decision" source with
 | Some "allow" => match Schema.decode [Field "decision" (KEnum "allow" [])] source with Some _ => Some HookAllow | _ => None end
 | Some "rewrite" => match Schema.decode [Field "decision" (KEnum "rewrite" []);Field "arguments" KJson] source with
   | Some fields => match head (tail fields) with JObject arguments => Some (HookRewrite arguments) | _ => None end
   | _ => None end
 | Some "deny" => option_map HookDeny (parse_reason_decision "deny" source)
 | Some "failed" => option_map HookFailure (parse_reason_decision "failed" source)
 | _ => None end.
Definition parse_after (source : json) : option after_outcome :=
 match string_field "decision" source with
 | Some "allow" => match Schema.decode [Field "decision" (KEnum "allow" [])] source with Some _ => Some KeepResult | _ => None end
 | Some "rewrite" => match Schema.decode [Field "decision" (KEnum "rewrite" []);Field "value" KJson] source with
   | Some fields => Some (RewriteResult (head (tail fields))) | _ => None end
 | Some "deny" => option_map DenyResult (parse_reason_decision "deny" source)
 | Some "failed" => option_map AfterFailure (parse_reason_decision "failed" source)
 | _ => None end.
Definition parse_approval_outcome (source : json) : option approval_outcome :=
 match Schema.decode [Field "decision" KText; Field "reason" KText] source with
 | None => None
 | Some fields =>
   let reason := head (tail fields) in
   let outcome := match head fields with "allow" => Approved reason | "deny" => Denied reason
    | _ => ApprovalFailed "The review did not return a valid decision" end in
   (* A blank but otherwise valid reason is malformed; invalid text still settles
      through normalize_outcome as a failed review. *)
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
  if ok then match observations with
  | Some observations => option_map (fun observations => ContextCompleted id ticket (Some observations) "") (Codec.traverse parse_observation observations)
  | None => None end
  else match diagnostic with Some text => if Nat.leb (String.length text) 4096 then Some (ContextCompleted id ticket None text) else None | None => None end).
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
  if ok then match effort,generations with Some effort,Some generations => Some (ReasoningCompleted id ticket (Reasoning.Chosen effort generations)) | _,_ => None end
  else match diagnostic with Some reason => Some (ReasoningCompleted id ticket (EvaluationFailed reason)) | None => None end).
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
Definition decode (source : json) : option input :=
 match source with
 | JObject fields => if Schema.unique_names (map fst fields) then
   match lookup "kind" fields with
   | Some (JString kind) => match find (fun decoder => String.eqb kind (decoder_name decoder)) decoders with
     | None => None
     | Some decoder => match Schema.decode (decoder_fields decoder) (JObject (remove_field "kind" fields)) with
       | Some values => decoder_construct decoder values | None => None end
     end
   | _ => None end
   else None
 | _ => None end.
Definition owns_kind (source : json) :=
 match string_field "kind" source with Some kind => existsb (fun decoder => String.eqb kind (decoder_name decoder)) decoders | None => false end.
