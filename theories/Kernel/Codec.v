From Selvedge.Kernel Require Import ModelDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require OptionList.
From Selvedge.Foundation Require Import Json Schema JsonSchema Arguments Utf8 CallWire ModelWire.
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
Definition sandbox_fields (value : sandbox) := [
 ("mode", JString (match sandbox_access value with ReadOnly => "read-only" | WorkspaceWrite => "workspace-write" end));
 ("network_access", JBool (sandbox_network value))].
Definition sandbox_json value := JObject (sandbox_fields value).
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
Module D := ArgumentDeclaration.
Definition workspace_declaration := D.Object
 [("roots",true,D.BoundedArray 0 32 Workspace.path_declaration);("primary_root",false,D.nullable D.text)].
Definition workspace_of_values (values : D.denote workspace_declaration) : option workspace :=
 let '(roots,(primary,_)) := proj1_sig values in
 let roots := map (@proj1_sig _ _) (proj1_sig roots) in
 let primary := match primary with
 | Some (inl root) => Some (proj1_sig root)
 | None | Some (inr (inl _)) => hd_error roots
 | Some (inr (inr impossible)) => match impossible with end end in
 let space := Workspace roots primary in
 if forallb Workspace.canonical_path roots && Workspace.valid_selection space then Some space else None.
Definition parse_workspace value :=
 match D.decode workspace_declaration value with Some fields => workspace_of_values fields | None => None end.
Definition sandbox_properties (required : bool) :=
 [("mode",required,D.Value (KEnum "read-only" ["workspace-write"]));("network_access",required,D.Boolean)].
Definition sandbox_declaration := D.Object (sandbox_properties true).
Definition sandbox_patch_declaration := D.Object (sandbox_properties false).
Definition approval_declaration := D.Object
 [("mode",true,D.Value (KEnum "full-access" ["ask-for-approval";"approval-for-me"]));("reviewer_profile",false,D.text)].
Definition sandbox_mode (mode : Schema.denote (KEnum "read-only" ["workspace-write"])) :=
 if String.eqb (proj1_sig mode) "read-only" then ReadOnly else WorkspaceWrite.
Definition sandbox_of_values (values : D.denote sandbox_declaration) :=
 let '(mode,(network,_)) := proj1_sig values in Sandbox (sandbox_mode mode) network.
Definition parse_sandbox value := option_map sandbox_of_values (D.decode sandbox_declaration value).
(** A patch has optional admitted fields. Applying it cannot fail or erase an
    omitted part of the committed sandbox. *)
Definition sandbox_patch_of_values (fallback : sandbox) (values : D.denote sandbox_patch_declaration) :=
 let '(mode,(network,_)) := proj1_sig values in
 Sandbox (match mode with Some mode => sandbox_mode mode | None => sandbox_access fallback end)
   (match network with Some network => network | None => sandbox_network fallback end).
Definition parse_sandbox_patch fallback source :=
 option_map (sandbox_patch_of_values fallback) (D.decode sandbox_patch_declaration source).
Definition approval_of_values (model : profile) (catalog : list profile)
 (values : D.denote approval_declaration) : option approval_policy :=
 let '(mode,(reviewer,_)) := proj1_sig values in
 if String.eqb (proj1_sig mode) "full-access" then Some FullAccess
 else if String.eqb (proj1_sig mode) "ask-for-approval" then Some AskForApproval
 else let selected := match reviewer with
   | Some name => find (fun candidate => String.eqb (proj1_sig name) (profile_key candidate)) catalog
   | None => Some (ModelCapabilities.default_reviewer model catalog) end in
 match selected with Some reviewer => if ModelCapabilities.valid_reviewer_profile reviewer
   then Some (ReviewWith reviewer) else None | None => None end.
Definition parse_approval model catalog source :=
 match D.decode approval_declaration source with Some values => approval_of_values model catalog values | None => None end.
Definition select_optional {A : Type} (parse : json -> option A)
 (key : string) (source : json) (fallback : A) :=
 match field key source with None | Some JNull => Some fallback | Some value => parse value end.
Definition workspace_binding_json (owner : option N) :=
 JObject [("task_id",optional_number owner)].
Definition binding_declaration := D.Object [("task_id",true,D.nullable (D.Natural 0 4294967295))].
Definition binding_of_values (values : D.denote binding_declaration) : option N :=
 match fst (proj1_sig values) with
 | inl owner => Some (proj1_sig owner) | inr (inl _) => None
 | inr (inr impossible) => match impossible with end end.
Definition parse_workspace_binding source := option_map binding_of_values (D.decode binding_declaration source).
Definition guidance_declaration := Guidance.declaration.
Definition guidance_member (workspace : workspace) (guidance : Guidance.t) := match guidance with
 | None => true | Some observed => match workspace_primary workspace with
 | Some root => String.eqb root (Guidance.root observed) | None => false end end.
Definition inherited_guidance (workspace : workspace) (guidance : Guidance.t) :=
 if guidance_member workspace guidance then guidance else None.
Definition parse_guidance (workspace : workspace) source :=
 match Guidance.parse source with Some observed => if guidance_member workspace observed then Some observed else None
 | None => None end.
Definition requested_guidance (values : option (D.denote guidance_declaration)) :=
 match values with Some values => Guidance.of_values values | None => Some None end.
Definition settings_declaration (observed : bool) := D.Object
 ([("workspace",false,workspace_declaration);("sandbox",false,sandbox_patch_declaration);
   ("approval",false,approval_declaration);("project_id",false,D.Natural 0 4294967295)] ++
  if observed then [("guidance",false,guidance_declaration);("workspace_binding",false,binding_declaration)] else []).
(** Settings requests keep syntax admission separate from resolution against
    the current project registry and the selected profile. *)
Record settings_request := SettingsRequest {
 workspace_override : option (D.denote workspace_declaration);
 sandbox_override : option (D.denote sandbox_patch_declaration);
 approval_override : option (D.denote approval_declaration);
 project_override : option N;
 guidance_observation : option (D.denote guidance_declaration);
 binding_observation : option (option N)
}.
Definition empty_settings_request := SettingsRequest None None None None None None.
Definition settings_request_of_values (observed : bool) : D.denote (settings_declaration observed) -> settings_request :=
 match observed as observed return D.denote (settings_declaration observed) -> settings_request with
 | true => fun values => let '(space,(sandbox,(approval,(project,(guidance,(binding,_)))))) := proj1_sig values in
   SettingsRequest space sandbox approval (option_map (@proj1_sig _ _) project) guidance (option_map binding_of_values binding)
 | false => fun values => let '(space,(sandbox,(approval,(project,_)))) := proj1_sig values in
   SettingsRequest space sandbox approval (option_map (@proj1_sig _ _) project) None None end.
Definition settings_request_json (value : settings_request) := JObject
 (flat_map (fun entry => match snd entry with Some value => [(fst entry,value)] | None => [] end)
  [("workspace",option_map (D.encode workspace_declaration) (workspace_override value));
   ("sandbox",option_map (D.encode sandbox_patch_declaration) (sandbox_override value));
   ("approval",option_map (D.encode approval_declaration) (approval_override value));
   ("project_id",option_map number (project_override value));
   ("guidance",option_map (D.encode guidance_declaration) (guidance_observation value));
   ("workspace_binding",option_map workspace_binding_json (binding_observation value))]).
Definition with_requested_project (project : option N) (value : settings_request) :=
 SettingsRequest (workspace_override value) (sandbox_override value) (approval_override value)
   project (guidance_observation value) (binding_observation value).
Definition settings_of_request (model : profile) (catalog : list profile)
 (request : settings_request) (fallback : task_settings) : option task_settings :=
 match requested_guidance (guidance_observation request) with
 | None => None
 | Some guidance =>
 match (match workspace_override request with None => Some (settings_workspace fallback)
        | Some values => workspace_of_values values end),
       (match approval_override request with None => Some (settings_approval fallback)
        | Some values => approval_of_values model catalog values end) with
 | Some workspace, Some approval =>
   let sandbox := match sandbox_override request with None => settings_sandbox fallback
     | Some values => sandbox_patch_of_values (settings_sandbox fallback) values end in
   let contents := match guidance with
     | None => match workspace_override request with
       | None => settings_guidance fallback
       | Some _ => inherited_guidance workspace (settings_guidance fallback) end
     | Some observed => Some observed end in
   let owner := match binding_observation request with Some owner => owner
     | None => match workspace_override request with Some _ => None | None => settings_resource fallback end end in
   if guidance_member workspace guidance then
     Some (Settings workspace (match project_override request with Some id => Some id | None => settings_project fallback end)
       sandbox approval contents (settings_worktree fallback) owner) else None
 | _,_ => None end end.
Definition profile_json (value : profile) := profile_metadata value.
Definition reviewer_json (value : reviewer) := match value with
 | HumanReviewer => JObject [("kind",JString "human")]
 | ModelReviewer profile => JObject [("kind",JString "model");("profile",profile_json profile)] end.
Definition reasoning_policy_json (value : reasoning_policy) := match value with
 | FixedReasoning => JNull
 | AdaptivePolicy policy => JObject [
   ("evaluator", JString (reasoning_evaluator policy));
   ("efforts", JArray (map JString (reasoning_efforts policy)));
   ("baseline", JString (reasoning_baseline policy));
   ("transport", JString (match reasoning_transport_mode policy with
     | RequestEffort => "request_effort" | ConfigurationUpdates => "configuration_update" end));
   ("max_lease", number (reasoning_max_lease policy))]
 end.
Definition model_json (value : profile) := JObject [
 ("profile", JString (profile_key value)); ("provider", JString (profile_provider value));
 ("name", JString (profile_model value)); ("reasoning", JString (profile_reasoning value));
 ("adaptive_reasoning", reasoning_policy_json (profile_policy value))].
(* Auxiliary generation uses the connection's ordinary default effort. *)
Definition task_text_model_json (value : profile) := JObject [
 ("profile", JString (profile_key value)); ("provider", JString (profile_provider value));
 ("name", JString (profile_model value)); ("reasoning", JString "default")].
Definition with_reasoning := Domain.with_reasoning.
Definition parse_reasoning_policy := Domain.parse_reasoning_policy.
Definition profile_options := Domain.profile_options.
Definition parse_profile := Domain.parse_profile.
Definition tool_json (value : tool) := JObject [
 ("name", JString (tool_name value)); ("description", JString (tool_description value));
 ("parameters", tool_schema value); ("source", tool_metadata value)].
Definition parse_tool (value : json) : option tool :=
 match string_field "name" value, string_field "description" value,
       field "schema" value, string_field "remote" value with
 | Some name, Some description, Some schema, Some remote =>
   if nonempty name then
     match field "plugin" value with
     | Some (JObject plugin) => match JsonSchema.register schema with
       | Some registered => Some (Tool name description
         (ExtensionToolSource registered (PluginProtocol.reference_json (JObject plugin)) remote))
       | None => None end
     | None | Some JNull =>
       (* MCP requires an object schema; validating its full dialect belongs to
          the server. In particular, number/$ref/anyOf are not extension rules. *)
       match string_field "server" value, schema with
       | Some server, JObject _ => Some (Tool name description (McpToolSource schema server remote))
       | _,_ => None end
     | _ => None end
   else None
 | _,_,_,_ => None end.
Definition traverse {A B : Type} (f : A -> option B) (values : list A) : option (list B) :=
 OptionList.traverse f values.
Definition call_json (value : call) := JObject [
 ("id", JString (call_id value)); ("name", JString (call_name value)); ("arguments", call_arguments value);
 ("arguments_json", JString (TextJson.render_json (call_arguments value)))].
Definition wire_call_json (value : call) := CallWire.encode (call_id value) (call_name value) (call_arguments value).
Definition content_json (value : content) := JArray (map Images.content_part_json value).
Definition model_item_of_fields (value : ModelWire.value) : model_item :=
 match value with
 | inl text => let fields := proj1_sig text in TextItem (fst (snd fields)) (proj1_sig (fst (snd (snd fields))))
 | inr (inl call) => let invocation := CallWire.of_item call in
   CallItem (Call (CallWire.identity invocation) (CallWire.name invocation) (CallWire.arguments invocation) InitialAttempt)
 | inr (inr (inl context)) => let fields := proj1_sig context in ContextItem (fst (snd fields)) (JObject (fst (snd (snd fields))))
 | inr (inr (inr impossible)) => match impossible with end end.
Definition model_items (batch : ModelWire.batch) := map model_item_of_fields (ModelWire.batch_values batch).
Definition output_mode_value (mode : output_mode) : Schema.denote ModelDeclarations.output_mode_kind := match mode with
 | PlainOutput => exist _ ModelDeclarations.plain_output_name (or_introl eq_refl)
 | InteractiveOutput => exist _ ModelDeclarations.interactive_output_name (or_intror (or_introl eq_refl)) end.
Definition output_mode_name (mode : output_mode) :=
 match mode with PlainOutput => ModelDeclarations.plain_output_name | InteractiveOutput => ModelDeclarations.interactive_output_name end.
Definition origin_json (origin : output_origin) := JObject [
 ("producer_task", number (origin_producer origin)); ("operation", number (origin_operation origin));
 ("part", number (origin_part origin)); ("mode", JString (output_mode_name (origin_mode origin)))].
Definition message_json_with (project_call : call -> json) (owner : N) (value : message) :=
 match value with
 | InstructionMessage source value => JObject [("role", JString source); ("content", value)]
 | EnvironmentNotice text => JObject [("role",JString "task_context"); ("type",JString "environment_notice"); ("content",JString text)]
 | ReasoningConfigurationMessage effort => JObject [("role",JString "task_context"); ("type",JString "reasoning_configuration"); ("effort",JString effort)]
 | SettingsMessage settings profile reasoning => JObject [("role",JString "task_context"); ("type",JString "settings"); ("content",settings_json settings); ("profile",JString profile); ("reasoning",JString reasoning)]
 | UserMessage parts => JObject [("role", JString "user"); ("content", content_json parts)]
 | AssistantMessage origin text => JObject [("role", JString "assistant"); ("origin", origin_json origin); ("content", JString text)]
 | FunctionCall call => JObject [("role", JString "function_call"); ("content", project_call call)]
 | FunctionOutput id value error => JObject [("role", JString "function_output"); ("call_id", JString id); ("content", value); ("is_error", JBool error)]
 | OperationResult ticket call value error => JObject [("role", JString "operation_result"); ("operation_id", number ticket); ("call_id", JString (call_id call)); ("tool", JString (call_name call)); ("content", value); ("is_error", JBool error)]
 | FailureMessage text => JObject [("role", JString "error"); ("content", JString text)]
 | ReasoningRecord owner effort remaining sampling => JObject [("role",JString "reasoning_record"); ("task_id",number owner);
   ("content",JObject [("effort",JString effort);("remaining",number remaining);("sampling",JBool sampling)])]
 | ModelContext origin value => JObject [("role", JString "model_context"); ("origin", origin_json origin); ("content", value)]
 | ContextReplacement value => JObject [("role", JString "context_replacement"); ("content", value)]
 | ContextObservation change => JObject [("role", JString "task_context"); ("type", JString "context_change"); ("change", Context.change_json change)]
 | SideConversationBirth side parent start => JObject [("role", JString "task_context"); ("type", JString "side_conversation");
   ("owner_task", number side); ("parent_task", number parent); ("start", number start)]
 | SpeechTranscript owner session item speaker completion text => JObject [
   ("role", JString "speech_transcript"); ("task_id", number owner); ("session_id", JString session); ("item_id", JString item);
   ("speaker", JString (match speaker with UserSpeaker => "user" | AssistantSpeaker => "assistant" end));
   ("completion", JString (match completion with SpeechCompleted => "completed" | SpeechInterrupted => "interrupted" end)); ("content", JString text)]
 | SpeechDelegation owner session delegation mode text => JObject [("role", JString "speech_delegation_receipt"); ("task_id", number owner);
   ("session_id", JString session); ("delegation_id", JString delegation); ("mode", JString mode); ("content", JString text)]
 | HookReceipt owner call plugin outcome => JObject [("role", JString "hook_record"); ("task_id", number owner); ("call_id", JString (call_id call)); ("plugin", plugin); ("content", outcome)]
 | ApprovalReceipt owner operation call reviewed_by outcome => JObject [("role", JString "approval_record"); ("task_id", number owner); ("operation_id", number operation); ("call", project_call call); ("reviewer", reviewer_json reviewed_by); ("content", outcome)]
 | ToolReceipt owner operation invocation result error => JObject [("role",JString "tool_receipt");("task_id",number owner);
   ("operation_id",number operation);("call",project_call invocation);("content",result);("is_error",JBool error)]
 | AfterReceipt owner operation plugin outcome => JObject [("role",JString "after_record");("task_id",number owner);("operation_id",number operation);("plugin",plugin);("content",outcome)]
 | ForkReceipt _ call child => JObject [("role", JString "function_output"); ("call_id", JString (call_id call));
   ("content", number child); ("is_error", JBool false); ("receipt_kind", JString "fork_result")]
 end.

Definition message_json := message_json_with wire_call_json.
Definition public_message_json := message_json_with call_json.

Theorem fork_receipt_json_preserves_provider_result : forall owner invocation child,
 field "role" (message_json owner (ForkReceipt owner invocation child)) = Some (JString "function_output") /\
 field "call_id" (message_json owner (ForkReceipt owner invocation child)) = Some (JString (call_id invocation)) /\
 field "content" (message_json owner (ForkReceipt owner invocation child)) = Some (number child) /\
 field "is_error" (message_json owner (ForkReceipt owner invocation child)) = Some (JBool false) /\
 field "receipt_kind" (message_json owner (ForkReceipt owner invocation child)) = Some (JString "fork_result").
Proof. intros; repeat split; reflexivity. Qed.
