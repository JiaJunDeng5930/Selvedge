From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require DeclarationFields DeclarationRegistry SchemaProjection.
From Selvedge.Foundation Require TextJson.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

From Selvedge.Kernel Require CallbackDeclarations.
Definition callback_kind := CallbackDeclarations.callback_kind.
Definition callback_text := CallbackDeclarations.callback_text.
Definition TaskTitle := CallbackDeclarations.TaskTitle.
Definition ChatgptExec := CallbackDeclarations.ChatgptExec.
Definition BoardText := CallbackDeclarations.BoardText.
Definition Approval := CallbackDeclarations.Approval.
Definition Hook := CallbackDeclarations.Hook.
Definition AfterHook := CallbackDeclarations.AfterHook.
Definition Context := CallbackDeclarations.Context.
Definition Compaction := CallbackDeclarations.Compaction.
Definition Worktree := CallbackDeclarations.Worktree.
Definition Reasoning := CallbackDeclarations.Reasoning.
Definition Model := CallbackDeclarations.Model.
Definition Tool := CallbackDeclarations.Tool.
Definition callback_coordinates (callback : option callback_kind) :=
 match callback with Some kind => CallbackDeclarations.coordinates kind | None => [] end.

(** The public discriminant, payload and callback ownership are one declaration. *)
Record variant := BuildVariant {
 tag_field : string; tag_value : json; payload_fields : schema;
 safe_fields : list string; callback_name : option callback_kind;
 variant_unique : unique_names (tag_field :: map field_name payload_fields) = true;
 callback_projection : SchemaProjection.program payload_fields (callback_coordinates callback_name)
}.
Definition declare_variant tag value body safe callback
 `{DistinctNames (tag :: map field_name body)}
 `{SchemaProjection.Available body (callback_coordinates callback)} :=
 BuildVariant tag value body safe callback names_distinct (SchemaProjection.declare body (callback_coordinates callback)).
Definition effect name body callback `{DistinctNames ("kind" :: map field_name body)}
 `{SchemaProjection.Available body (callback_coordinates callback)} :=
 declare_variant "kind" (JString name) body [] callback.
Definition from_branch (branch : DeclarationFields.branch) (safe : list string)
 (callback : option callback_kind)
 `{SchemaProjection.Available (DeclarationFields.shape (DeclarationFields.payload_fields branch)) (callback_coordinates callback)} : variant.
Proof.
 refine (BuildVariant (DeclarationFields.tag_field branch) (DeclarationFields.tag_value branch)
   (DeclarationFields.shape (DeclarationFields.payload_fields branch)) safe callback _ (SchemaProjection.declare _ _)).
 rewrite DeclarationFields.shape_names; exact (DeclarationFields.branch_distinct branch).
Defined.
Definition variant_key (declaration : variant) := TextJson.render_json (tag_value declaration).
(** Correlation coordinates are language-owned fields. Protocol declarations
    supply only their body; encoding always takes the coordinates from the
    installed request instance. *)
Inductive correlation := OwnedTicket (owner_field : string) | StandaloneIdentity (identity_field : string).
Definition correlation_fields (shape : correlation) := match shape with
 | OwnedTicket owner => [Field owner KNatural; Field "ticket" KNatural]
 | StandaloneIdentity identity => [Field identity KNatural] end.
Record request_variant := BuildRequestVariant {
 request_name : string;
 request_correlation : correlation;
 request_body : schema;
 request_callback : callback_kind;
 request_unique : unique_names ("kind" :: map field_name (correlation_fields request_correlation ++ request_body)) = true;
 request_projection : SchemaProjection.program (correlation_fields request_correlation)
   (CallbackDeclarations.coordinates request_callback)
}.
Definition declare_request name shape body callback
 `{DistinctNames ("kind" :: map field_name (correlation_fields shape ++ body))}
 `{SchemaProjection.Available (correlation_fields shape) (CallbackDeclarations.coordinates callback)} :=
 BuildRequestVariant name shape body callback names_distinct
   (SchemaProjection.declare (correlation_fields shape) (CallbackDeclarations.coordinates callback)).
Definition request_body_fields (request : request_variant) := request_body request.
Definition request_variant_view (request : request_variant) :=
 BuildVariant "kind" (JString (request_name request))
   (correlation_fields (request_correlation request) ++ request_body_fields request)
   [] (Some (request_callback request)) (request_unique request)
   (SchemaProjection.prefix (request_body request) (request_projection request)).
Definition request_fields (request : request_variant) (owner identity : N)
 (body : fields (request_body_fields request))
 : fields (payload_fields (request_variant_view request)) :=
 match request_correlation request as shape
   return fields (correlation_fields shape ++ request_body_fields request) with
 | OwnedTicket name => @FCons (Field name KNatural)
     (Field "ticket" KNatural :: request_body_fields request) owner
     (@FCons (Field "ticket" KNatural) (request_body_fields request) identity body)
 | StandaloneIdentity name => @FCons (Field name KNatural) (request_body_fields request) identity body end.
Definition identity := [Field "task_id" KNatural; Field "ticket" KNatural].
Definition task_only := [Field "task_id" KNatural].
Definition model := Field "model" KJson.
Definition history := Field "history" (KArray KJson).
Definition settings := Field "settings" KJson.
Definition resource := Field "resource" KJson.
Definition tools := Field "tools" (KArray KJson).
Definition callable := Field "callable" (KArray KText).
Definition execution := Field "execution" KJson.
Definition invocation := Field "call" KJson.
Definition plugin := Field "plugin" KJson.
Definition output := [Field "context_selected" KBool; Field "context_scope" KText].
Definition observe_context := effect "observe_context" (identity ++ [settings;resource;
 Field "definitions" (KArray KJson); Field "bindings" (KArray KJson)]) (Some Context).
Definition plain_output_name := "plain".
Definition interactive_output_name := "interactive-v1".
Definition output_mode_kind := KEnum plain_output_name [interactive_output_name].
Definition request_model := effect "model" (identity ++ [model;Field "output_mode" output_mode_kind;
 settings;resource;Field "sampling" KJson;history] ++ output ++
 [Field "context_replacement_source" (KOptional KNatural); Field "output_reserve_tokens" KNatural;
 Field "source_length" KNatural;tools;callable]) (Some Model).
Definition reasoning := effect "reasoning" (identity ++ [model;history;Field "project_context" KJson;
 Field "history_preview" KBool;Field "history_preview_bytes" KNatural]) (Some Reasoning).
Definition tool := effect "tool" (identity ++ [Field "operation_id" KNatural;Field "tool" KJson;invocation;execution]) (Some Tool).
Definition approval := effect "approval" (identity ++ [model;invocation;Field "settings" KJson;
 Field "instructions" KText;Field "user_requests" (KArray KText)]) (Some Approval).
Definition hook := effect "hook" (identity ++ [plugin;Field "tool" KJson;invocation]) (Some Hook).
Definition after_hook := effect "after_hook" (identity ++ [Field "operation_id" KNatural;plugin;invocation;
 Field "value" KJson;Field "error" KBool]) (Some AfterHook).
Definition plugin_events := effect "plugin_events" [Field "events" (KArray KJson)] None.
Definition reset_model_session := effect "reset_model_session" task_only None.
Definition cancel := effect "cancel" task_only None.
Definition cancel_ticket := effect "cancel_ticket" identity None.
Definition continue := effect "continue" [] None.
Definition worktree_create := effect "worktree_create" ([Field "backend" (KEnum "local" ["tencent_cvm"])] ++ task_only ++
 [Field "source_root" KText;Field "workspace" KJson]) (Some (Worktree true)).
Definition worktree_archive := effect "worktree_archive" ([Field "backend" (KEnum "local" ["tencent_cvm"])] ++ task_only ++
 [Field "root" KText;Field "source_root" KText]) (Some (Worktree false)).
Definition task_title_request := declare_request "task_title" (OwnedTicket "task_id") [model;Field "prompt" KText] TaskTitle.
Definition task_title := request_variant_view task_title_request.
Definition board_text_request := declare_request "board_text" (OwnedTicket "card_id")
 [model;Field "prompt" KText;Field "retitle" KBool] BoardText.
Definition board_text := request_variant_view board_text_request.
Definition chatgpt_exec_request := declare_request "chatgpt_exec" (StandaloneIdentity "operation_id")
 [Field "arguments" KJson;execution] ChatgptExec.
Definition chatgpt_exec := request_variant_view chatgpt_exec_request.
Definition chatgpt_cancel := effect "chatgpt_cancel" [Field "operation_id" KNatural] None.
Definition context_scope_request := declare_request "context_scope" (OwnedTicket "task_id")
 [model] (Compaction false).
Definition context_scope := request_variant_view context_scope_request.
Definition context_measure_request := declare_request "context_measure" (OwnedTicket "task_id")
 ([model;history] ++ output ++ [tools;settings;callable;Field "validating" KBool]) (Compaction false).
Definition context_measure := request_variant_view context_measure_request.
Definition context_compaction_body := [model] ++ output ++
 [Field "method" KText;Field "window_tokens" KNatural;Field "output_reserve_tokens" KNatural].
Definition context_compaction_metadata := identity ++ context_compaction_body.
Definition context_compaction_request := declare_request "context_compaction" (OwnedTicket "task_id")
 (context_compaction_body ++ [Field "plan" KJson]) (Compaction true).
Definition context_compaction := request_variant_view context_compaction_request.
Definition compaction_clock := effect "compaction_clock" [Field "deadline" KNatural] None.
Definition compaction_cancel := effect "compaction_cancel" identity None.
Definition registered_effects := DeclarationRegistry.declare variant_key
 [observe_context;request_model;reasoning;tool;approval;hook;after_hook;plugin_events;
 reset_model_session;cancel;cancel_ticket;continue;worktree_create;worktree_archive;task_title;board_text;
 chatgpt_exec;chatgpt_cancel;context_scope;context_measure;context_compaction;compaction_clock;compaction_cancel].
Definition effects := DeclarationRegistry.values registered_effects.
Definition audio_max_bytes := Field "max_bytes" KNatural.
Definition audio_timeout_ms := Field "timeout_ms" KNatural.
Definition audio_connect_timeout_ms := Field "connect_timeout_ms" KNatural.
Definition audio_session_max_ms := Field "session_max_ms" KNatural.
Definition audio_message := Field "message" KText.
Definition audio_allowed := declare_variant "allowed" (JBool true)
 [audio_max_bytes;audio_timeout_ms;audio_connect_timeout_ms;audio_session_max_ms]
 ["max_bytes";"timeout_ms";"connect_timeout_ms";"session_max_ms"] None.
Definition audio_rejected := declare_variant "allowed" (JBool false) [audio_message] [] None.
Definition registered_audio := DeclarationRegistry.declare variant_key [audio_allowed;audio_rejected].
Definition audio_admission := DeclarationRegistry.values registered_audio.
Definition encode (declaration : variant) (values : fields declaration.(payload_fields)) :=
 JObject ((declaration.(tag_field),declaration.(tag_value)) :: encode_fields values).
Record packet := Packet { packet_declaration : variant; packet_fields : fields (payload_fields packet_declaration) }.
Definition pack declaration (values : Schema.tuple (payload_fields declaration)) :=
 Packet declaration (Schema.of_tuple _ values).
Definition encode_packet value := encode (packet_declaration value) (packet_fields value).
Definition matches declaration source := match Json.field (tag_field declaration) source with
 | Some value => Json.equal value (tag_value declaration) | None => false end.
Definition decode declaration source := match source with
 | JObject members => if matches declaration source then
   Schema.decode (payload_fields declaration) (JObject (Json.remove_field (tag_field declaration) members)) else None
 | _ => None end.
Record decoder (A : Type) := Decoder {
 decoder_declaration : variant; decoder_construct : fields (payload_fields decoder_declaration) -> option A
}.
Arguments Decoder {A} _ _.
Arguments decoder_declaration {A} _.
Arguments decoder_construct {A} _ _.
Definition decode_cases {A} (cases : list (decoder A)) source :=
 match find (fun entry => matches (decoder_declaration entry) source) cases with
 | Some entry => match decode (decoder_declaration entry) source with
   | Some values => decoder_construct entry values | None => None end
 | None => None end.
Fixpoint kind_json (kind : kind) : json := match kind with
 | KText => JString "text" | KBool => JString "boolean" | KNatural => JString "natural"
 | KInteger => JString "integer" | KDecimal => JString "decimal" | KJson => JString "json"
 | KArray item => JObject [("array",kind_json item)]
 | KOptional item => JObject [("optional",kind_json item)]
 | KEnum first rest => JObject [("enum",JArray (map JString (first::rest)))] end.
Definition fields_json (fields : schema) := JArray (map (fun field => JObject [
 ("name",JString field.(field_name));("type",kind_json field.(field_kind));("omittable",JBool field.(field_omittable))]) fields).
Definition variant_json (declaration : variant) := JObject [("tag_field",JString declaration.(tag_field));
 ("tag",declaration.(tag_value));("fields",fields_json declaration.(payload_fields));
 ("safe_fields",JArray (map JString declaration.(safe_fields)));
 ("callback",match declaration.(callback_name) with Some name => JString (callback_text name) | None => JNull end)].
