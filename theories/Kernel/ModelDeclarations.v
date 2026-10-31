From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require DeclarationRegistry.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

From Selvedge.Kernel Require CallbackDeclarations.
From Selvedge.Programming Require Import Variant.
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
