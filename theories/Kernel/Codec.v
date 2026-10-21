From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Context Workspace ModelCapabilities PluginProtocol.
From Selvedge.Kernel Require Export Images.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition value_or_null (key : string) (source : json) :=
 match field key source with Some value => value | None => JNull end.
Definition text_default (key : string) (source : json) (fallback : string) :=
 match string_field key source with Some text => text | None => fallback end.
Definition bool_default (key : string) (source : json) (fallback : bool) :=
 match bool_field key source with Some value => value | None => fallback end.
Definition natural_default (key : string) (source : json) (fallback : N) :=
 match natural_field key source with Some value => value | None => fallback end.
Definition array_default (key : string) (source : json) :=
 match array_field key source with Some values => values | None => [] end.
Definition optional_number (value : option N) :=
 match value with Some value => number value | None => JNull end.
Definition optional_string (value : option string) :=
 match value with Some value => JString value | None => JNull end.
Definition nonempty (text : string) := Utf8.nonblank text.
Fixpoint strings (values : list json) : option (list string) :=
 match values with
 | [] => Some []
 | JString text :: rest => option_map (cons text) (strings rest)
 | _ => None
 end.
Definition workspace_json (value : workspace) := JObject [
 ("roots", JArray (map JString (workspace_roots value)));
 ("primary_root", optional_string (workspace_primary value))].
Definition sandbox_json (value : sandbox) := JObject [
 ("mode", JString (match sandbox_access value with ReadOnly => "read-only" | WorkspaceWrite => "workspace-write" end));
 ("network_access", JBool (sandbox_network value))].
Definition approval_json (value : approval_policy) :=
 match value with
 | FullAccess => JObject [("mode", JString "full-access")]
 | AskForApproval => JObject [("mode", JString "ask-for-approval")]
 | ReviewWith profile => JObject [("mode", JString "approval-for-me"); ("reviewer_profile", JString (profile_key profile))]
 end.
Definition settings_json (value : task_settings) := JObject [
 ("workspace", workspace_json (settings_workspace value));
 ("sandbox", sandbox_json (settings_sandbox value));
 ("approval", approval_json (settings_approval value));
 ("project_id", optional_number (settings_project value));
 ("workspace_resource", optional_number (settings_resource value))].
Definition parse_workspace (value : json) : option workspace :=
 match Schema.decode Workspace.workspace_schema value with None => None | Some _ =>
 match array_field "roots" value with
 | Some values => match strings values with
 | Some roots =>
   if Nat.leb (List.length roots) 32 && Schema.unique_names roots && forallb Workspace.valid_path roots then
   let primary := match string_field "primary_root" value with
     | Some root => Some root | None => hd_error roots end in
   match primary with
   | Some root => if existsb (String.eqb root) roots then Some (Workspace roots primary) else None
   | None => Some (Workspace roots None)
   end else None
 | None => None end
 | None => None end end.
Definition parse_sandbox (value : json) : option sandbox :=
 match Schema.decode [Field "mode" KText; Field "network_access" KBool] value with None => None | Some _ =>
 match string_field "mode" value, bool_field "network_access" value with
 | Some "read-only", Some network => Some (Sandbox ReadOnly network)
 | Some "workspace-write", Some network => Some (Sandbox WorkspaceWrite network)
 | _, _ => None end end.
Definition parse_approval (model : profile) (catalog : list profile) (value : json) : option approval_policy :=
 match Schema.decode [Field "mode" KText; Field "reviewer_profile" (KOptional KText)] value with None => None | Some _ =>
 match string_field "mode" value with
 | Some "full-access" => Some FullAccess
 | Some "ask-for-approval" => Some AskForApproval
 | Some "approval-for-me" =>
   let reviewer := match string_field "reviewer_profile" value with
    | Some name => find (fun candidate => String.eqb name (profile_key candidate)) catalog
    | None => Some (ModelCapabilities.default_reviewer model catalog) end in
   match reviewer with Some reviewer => if ModelCapabilities.valid_reviewer_profile reviewer
     then Some (ReviewWith reviewer) else None | None => None end
 | _ => None end end.
Definition select_optional {A : Type} (parse : json -> option A)
 (key : string) (source : json) (fallback : A) :=
 match field key source with None | Some JNull => Some fallback | Some value => parse value end.
Definition task_settings_schema := [Field "workspace" (KOptional KJson); Field "sandbox" (KOptional KJson);
 Field "approval" (KOptional KJson); Field "project_id" (KOptional KNatural); Field "guidance" (KOptional KJson)].
Definition valid_guidance (value : json) := match value with JNull => true | _ =>
 match Schema.decode [Field "workspace" KText; Field "path" KText; Field "revision" KText; Field "instructions" KText] value with
 | None => false | Some _ =>
 let root := text_default "workspace" value "" in
 let path := text_default "path" value "" in
 let revision := text_default "revision" value "" in
 let instructions := text_default "instructions" value "" in
 Workspace.valid_path root && Nat.leb (String.length instructions) 32768 &&
 ((String.eqb revision "absent" && String.eqb instructions "" && String.eqb path "") ||
  (Context.policy_source_path Context.guidance_policy root path && Nat.eqb (String.length revision) 64)) end end.
Definition guidance_member (workspace : workspace) (guidance : json) := match guidance with
 | JNull => true | _ => match workspace_primary workspace, string_field "workspace" guidance with
 | Some root, Some observed => String.eqb root observed | _,_ => false end end.
Definition parse_settings (model : profile) (catalog : list profile) (value : json) (fallback : task_settings) : option task_settings :=
 match value with JNull => Some fallback | _ =>
 match Schema.decode task_settings_schema value with None => None | Some _ =>
 match value with
 | JNull => Some fallback
 | JObject fields =>
   if valid_guidance (value_or_null "guidance" value) then
   match select_optional parse_workspace "workspace" value (settings_workspace fallback),
         select_optional parse_sandbox "sandbox" value (settings_sandbox fallback),
         select_optional (parse_approval model catalog) "approval" value (settings_approval fallback) with
   | Some workspace, Some sandbox, Some approval =>
     let project := match field "project_id" value with
       | None => settings_project fallback | Some JNull => None
       | Some value => natural value end in
     let guidance := match field "guidance" value with
       | None | Some JNull => if guidance_member workspace (settings_guidance fallback) then settings_guidance fallback else JNull
       | Some guidance => guidance end in
     if guidance_member workspace guidance then
     Some (Settings workspace project sandbox approval guidance (settings_worktree fallback)
       (match field "workspace" value with Some (JObject _) => None | _ => settings_resource fallback end)) else None
   | _,_,_ => None end else None
 | _ => None end end end.
Definition profile_json (value : profile) := profile_metadata value.
Definition model_json (value : profile) := JObject [
 ("profile", JString (profile_key value)); ("provider", JString (profile_provider value));
 ("name", JString (profile_model value)); ("reasoning", JString (profile_reasoning value));
 ("adaptive_reasoning", value_or_null "adaptive_reasoning" (profile_metadata value))].
Definition with_reasoning (effort : string) (value : profile) :=
 Profile (profile_key value) (profile_provider value) (profile_model value) effort
  (profile_reasoning_options value) (profile_policy value) (profile_metadata value).
Definition parse_reasoning_policy (value : json) : option reasoning_policy :=
 match value with
 | JNull => Some FixedReasoning
 | _ => match Schema.decode [Field "evaluator" KText; Field "efforts" (KArray KText); Field "baseline" KText;
     Field "transport" (KEnum "configuration_update" ["request_effort"]); Field "max_lease" KNatural] value with
   | None => None
   | Some _ => let efforts := match strings (array_default "efforts" value) with Some values => values | None => [] end in
     let baseline := text_default "baseline" value "" in
     let maximum := natural_default "max_lease" value 0 in
     if nonempty (text_default "evaluator" value "") && Schema.unique_names efforts &&
      forallb (fun effort => nonempty effort && negb (String.eqb effort "auto")) efforts &&
      existsb (String.eqb baseline) efforts && (N.leb 1 maximum && N.leb maximum 10) then
     Some (AdaptivePolicy (AdaptiveReasoning (text_default "evaluator" value "") efforts baseline
      (if String.eqb (text_default "transport" value "") "configuration_update" then ConfigurationUpdates else RequestEffort) maximum))
     else None
   end end.
Definition profile_options (source : json) : option (list string * string) :=
 match source with
 | JNull => Some ([],"medium")
 | _ => match Schema.decode [Field "values" (KArray KText); Field "default" (KOptional KText)] source with
   | None => None
   | Some _ => match strings (array_default "values" source) with
     | Some (first :: rest) =>
       let values := nodup String.string_dec (first :: rest) in
       if forallb (fun effort => nonempty effort && negb (String.eqb effort "auto")) values then
       let requested := text_default "default" source "medium" in
       Some (values, if existsb (String.eqb requested) values then requested else first)
       else None
     | _ => None end
   end end.
Definition parse_profile (value : json) : option profile :=
 match string_field "key" value, string_field "provider" value, string_field "name" value,
   field "reasoning_options" value, parse_reasoning_policy (value_or_null "adaptive_reasoning" value) with
 | Some key, Some provider, Some model, Some options, Some policy =>
   match profile_options options with
   | Some (efforts,default) =>
     if nonempty key && nonempty provider && nonempty model &&
      match policy with FixedReasoning => true | AdaptivePolicy policy =>
       match efforts with [] => true | _ => forallb (fun effort => existsb (String.eqb effort) efforts) (reasoning_efforts policy) end end then
     Some (Profile key provider model (match policy with FixedReasoning => default | AdaptivePolicy _ => "auto" end) efforts policy value)
     else None
   | None => None end
 | _,_,_,_,_ => None end.
Definition tool_json (value : tool) := JObject [
 ("name", JString (tool_name value)); ("description", JString (tool_description value));
 ("parameters", tool_schema value); ("source", tool_metadata value)].
Definition parse_tool (value : json) : option tool :=
 match string_field "name" value, string_field "description" value, field "schema" value with
 | Some name, Some description, Some schema =>
   if nonempty name then Some (Tool name description schema
     (match field "plugin" value with
      | Some (JObject plugin) => JObject [("plugin", PluginProtocol.reference_json (JObject plugin)); ("name", value_or_null "remote" value)]
      | _ => JObject [("server", value_or_null "server" value); ("name", value_or_null "remote" value)]
      end)) else None
 | _,_,_ => None end.
Fixpoint traverse {A B : Type} (f : A -> option B) (values : list A) : option (list B) :=
 match values with [] => Some [] | value :: rest =>
 match f value, traverse f rest with Some value, Some rest => Some (value :: rest) | _,_ => None end end.
Definition call_json (value : call) := JObject [
 ("id", JString (call_id value)); ("name", JString (call_name value)); ("arguments", call_arguments value)].
Definition parse_call (value : json) : option call :=
 match string_field "id" value, string_field "name" value, field "arguments" value with
 | Some id, Some name, Some (JObject arguments) =>
   if nonempty id && nonempty name then Some (Call id name (JObject arguments)) else None
 | _,_,_ => None end.
Definition content_json (value : content) := JArray (map Images.content_part_json value).
Definition parse_model_item (value : json) : option model_item :=
 match string_field "type" value with
 | Some "text" => match Schema.decode [Field "type" (KEnum "text" []);Field "part" KNatural;Field "text" KText] value with
   | Some values => let part := head (tail values) in let text := head (tail (tail values)) in
      if Utf8.well_formed text then Some (TextItem part text) else None
   | None => None end
 | Some "call" => match Schema.decode [Field "type" (KEnum "call" []);Field "id" KText;Field "name" KText;Field "arguments" KJson] value with
   | Some values => let identity := head (tail values) in let name := head (tail (tail values)) in
     match head (tail (tail (tail values))) with
     | JObject arguments => if nonempty identity && nonempty name then Some (CallItem (Call identity name (JObject arguments))) else None
     | _ => None end
   | None => None end
 | Some "context" => match Schema.decode [Field "type" (KEnum "context" []);Field "part" KNatural;Field "value" KJson] value with
   | Some values => match head (tail (tail values)) with JObject fields => Some (ContextItem (head (tail values)) (JObject fields)) | _ => None end
   | None => None end
 | _ => None end.
Definition output_mode_name (mode : output_mode) :=
 match mode with PlainOutput => "plain" | InteractiveOutput => "interactive-v1" end.
Definition origin_json (origin : output_origin) := JObject [
 ("producer_task", number (origin_producer origin)); ("operation", number (origin_operation origin));
 ("part", number (origin_part origin)); ("mode", JString (output_mode_name (origin_mode origin)))].
Definition message_json (owner : N) (value : message) :=
 match value with
 | InstructionMessage source value => JObject [("role", JString source); ("content", value)]
 | EnvironmentNotice text => JObject [("role",JString "task_context"); ("type",JString "environment_notice"); ("content",JString text)]
 | ReasoningConfigurationMessage effort => JObject [("role",JString "task_context"); ("type",JString "reasoning_configuration"); ("effort",JString effort)]
 | SettingsMessage settings profile reasoning => JObject [("role",JString "task_context"); ("type",JString "settings"); ("content",settings_json settings); ("profile",JString profile); ("reasoning",JString reasoning)]
 | UserMessage parts => JObject [("role", JString "user"); ("content", content_json parts)]
 | AssistantMessage origin text => JObject [("role", JString "assistant"); ("origin", origin_json origin); ("content", JString text)]
 | FunctionCall call => JObject [("role", JString "function_call"); ("content", call_json call)]
 | FunctionOutput id value error => JObject [("role", JString "function_output"); ("call_id", JString id); ("content", value); ("is_error", JBool error)]
 | OperationResult ticket call value error => JObject [("role", JString "operation_result"); ("operation_id", number ticket); ("call_id", JString (call_id call)); ("tool", JString (call_name call)); ("content", value); ("is_error", JBool error)]
 | FailureMessage text => JObject [("role", JString "error"); ("content", JString text)]
 | ReasoningRecord owner effort remaining sampling => JObject [("role",JString "reasoning_record"); ("task_id",number owner);
   ("content",JObject [("effort",JString effort);("remaining",number remaining);("sampling",JBool sampling)])]
 | ModelContext origin value => JObject [("role", JString "model_context"); ("origin", origin_json origin); ("content", value)]
 | ContextReplacement value => JObject [("role", JString "context_replacement"); ("content", value)]
 | ContextObservation change => JObject [("role", JString "task_context"); ("type", JString "context_change"); ("change", Context.change_json change)]
 | SpeechTranscript owner session item speaker completion text => JObject [
   ("role", JString "speech_transcript"); ("task_id", number owner); ("session_id", JString session); ("item_id", JString item);
   ("speaker", JString (match speaker with UserSpeaker => "user" | AssistantSpeaker => "assistant" end));
   ("completion", JString (match completion with SpeechCompleted => "completed" | SpeechInterrupted => "interrupted" end)); ("content", JString text)]
 | SpeechDelegation owner session delegation mode text => JObject [("role", JString "speech_delegation_receipt"); ("task_id", number owner);
   ("session_id", JString session); ("delegation_id", JString delegation); ("mode", JString mode); ("content", JString text)]
 | HookReceipt owner call plugin outcome => JObject [("role", JString "hook_record"); ("task_id", number owner); ("call_id", JString (call_id call)); ("plugin", plugin); ("content", outcome)]
 | ApprovalReceipt owner operation call outcome => JObject [("role", JString "approval_record"); ("task_id", number owner); ("operation_id", number operation); ("call", call_json call); ("content", outcome)]
 | ToolReceipt owner operation invocation result error => JObject [("role",JString "tool_receipt");("task_id",number owner);
   ("operation_id",number operation);("call",call_json invocation);("content",result);("is_error",JBool error)]
 | AfterReceipt owner operation plugin outcome => JObject [("role",JString "after_record");("task_id",number owner);("operation_id",number operation);("plugin",plugin);("content",outcome)]
 | ForkReceipt _ call child => JObject [("role", JString "function_output"); ("call_id", JString (call_id call)); ("content", number child); ("is_error", JBool false)]
 end.
