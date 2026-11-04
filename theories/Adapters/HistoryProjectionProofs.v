From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec HistoryRoleProofs ContextSelection.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory WebHistory BackendRequests.
From Selvedge.Programming Require Import AdapterResult.
Import ListNotations.
Open Scope string_scope.

(* Root histories, continuation suffixes and deferred Web histories all call
   WebHistory.history. The projection never edits the source history used for
   receipt spans, hashes or context accounting. *)
Theorem every_committed_transcript_has_both_provider_projections :
 forall owner session item speaker completion text profile,
 let source := Codec.message_json owner (SpeechTranscript owner session item speaker completion text) in
 let role := match speaker with UserSpeaker => "user" | AssistantSpeaker => "assistant" end in
 WebHistory.history_item source = Accepted [WebHistory.message role (JString text)] /\
 BackendHistory.input_item source profile = Accepted [BackendHistory.message role (JString text)].
Proof. intros;destruct speaker;split;reflexivity. Qed.

Theorem delegation_receipts_do_not_repeat_the_committed_user_message :
 forall owner session delegation mode text profile,
 let source := Codec.message_json owner (SpeechDelegation owner session delegation mode text) in
 WebHistory.history_item source = Accepted [] /\ BackendHistory.input_item source profile = Accepted [].
Proof. intros;split;reflexivity. Qed.

Theorem responses_backends_encode_reasoning_updates_as_control_items : forall owner effort profile,
 BackendHistory.input_item (Codec.message_json owner (ReasoningConfigurationMessage effort)) profile =
 Accepted [JObject [("type",JString "configuration_update");
   ("reasoning",JObject [("effort",JString effort)])]].
Proof. reflexivity. Qed.

Theorem web_history_omits_responses_reasoning_controls : forall owner effort,
 WebHistory.history_item (Codec.message_json owner (ReasoningConfigurationMessage effort)) = Accepted [].
Proof. reflexivity. Qed.

Theorem requests_without_update_transport_omit_configuration_controls : forall select effect profile,
 configuration_updates effect = false ->
 effect_input select effect profile =
 input_items (filter (fun message => negb (reasoning_configuration message))
   (if boolean_field effect "context_selected" then items (get effect "history") else
    if is_text (get profile "scope") then select (items (get effect "history")) (str profile "scope")
    else items (get effect "history"))) profile.
Proof.
 intros select effect profile Transport; unfold effect_input.
 rewrite Transport; reflexivity.
Qed.

Theorem requests_with_update_transport_keep_selected_history : forall select effect profile,
 configuration_updates effect = true ->
 effect_input select effect profile =
 input_items (if boolean_field effect "context_selected" then items (get effect "history") else
   if is_text (get profile "scope") then select (items (get effect "history")) (str profile "scope")
   else items (get effect "history")) profile.
Proof.
 intros select effect profile Transport; unfold effect_input.
 rewrite Transport; reflexivity.
Qed.
