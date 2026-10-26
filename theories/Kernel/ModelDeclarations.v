From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Schema.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive callback_kind :=
 | TaskTitle | ChatgptExec | BoardText | Approval | Hook | AfterHook
 | Context | Compaction (completed : bool) | Worktree (created : bool) | Reasoning | Model | Tool.
Definition callback_text (value : callback_kind) := match value with
 | TaskTitle => "task_title" | ChatgptExec => "chatgpt_result" | BoardText => "board_text"
 | Approval => "approval" | Hook => "hook" | AfterHook => "after_hook" | Context => "context_observed"
 | Compaction done => if done then "compaction_completed" else "compaction_measured"
 | Worktree created => if created then "worktree_created" else "worktree_archived"
 | Reasoning => "reasoning" | Model => "model" | Tool => "tool" end.

(** The public discriminant, payload and callback ownership are one declaration. *)
Record variant := Variant {
 tag_field : string; tag_value : json; payload_fields : schema;
 safe_fields : list string; callback_name : option callback_kind
}.
Definition effect name fields callback := Variant "kind" (JString name) fields [] callback.
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
Definition task_title := effect "task_title" (identity ++ [model;Field "prompt" KText]) (Some TaskTitle).
Definition board_text := effect "board_text" [Field "card_id" KNatural;Field "ticket" KNatural;model;
 Field "prompt" KText;Field "retitle" KBool] (Some BoardText).
Definition chatgpt_exec := effect "chatgpt_exec" [Field "operation_id" KNatural;Field "arguments" KJson;execution] (Some ChatgptExec).
Definition chatgpt_cancel := effect "chatgpt_cancel" [Field "operation_id" KNatural] None.
Definition context_scope := effect "context_scope" (identity ++ [model]) (Some (Compaction false)).
Definition context_measure := effect "context_measure" (identity ++ [model;history] ++ output ++
 [tools;settings;callable;Field "validating" KBool]) (Some (Compaction false)).
Definition context_compaction_metadata := identity ++ [model] ++ output ++
 [Field "method" KText;Field "window_tokens" KNatural;Field "output_reserve_tokens" KNatural].
Definition context_compaction := effect "context_compaction" (context_compaction_metadata ++ [Field "plan" KJson]) (Some (Compaction true)).
Definition compaction_clock := Variant "kind" (JString "compaction_clock") [Field "deadline" KNatural] [] None.
Definition compaction_cancel := effect "compaction_cancel" identity None.
Definition effects := [observe_context;request_model;reasoning;tool;approval;hook;after_hook;plugin_events;
 reset_model_session;cancel;cancel_ticket;continue;worktree_create;worktree_archive;task_title;board_text;
 chatgpt_exec;chatgpt_cancel;context_scope;context_measure;context_compaction;compaction_clock;compaction_cancel].
Definition audio_max_bytes := Field "max_bytes" KNatural.
Definition audio_timeout_ms := Field "timeout_ms" KNatural.
Definition audio_connect_timeout_ms := Field "connect_timeout_ms" KNatural.
Definition audio_session_max_ms := Field "session_max_ms" KNatural.
Definition audio_message := Field "message" KText.
Definition audio_allowed := Variant "allowed" (JBool true)
 [audio_max_bytes;audio_timeout_ms;audio_connect_timeout_ms;audio_session_max_ms]
 ["max_bytes";"timeout_ms";"connect_timeout_ms";"session_max_ms"] None.
Definition audio_rejected := Variant "allowed" (JBool false) [audio_message] [] None.
Definition audio_admission := [audio_allowed;audio_rejected].
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
