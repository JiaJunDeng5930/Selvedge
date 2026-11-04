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

Lemma disabled_configuration_history_keeps_other_records : forall history,
 configuration_history false history =
   (filter (fun message => negb (reasoning_configuration message)) history, false).
Proof.
 induction history as [|message rest IH]; [reflexivity|].
 cbn [configuration_history filter]; rewrite IH; cbn [fst snd].
 destruct (reasoning_configuration message); reflexivity.
Qed.

Theorem requests_without_update_transport_omit_configuration_controls : forall select effect profile,
 configuration_updates effect = false ->
 effect_input select effect profile =
 input_items (filter (fun message => negb (reasoning_configuration message))
   (if boolean_field effect "context_selected" then items (get effect "history") else
    if is_text (get profile "scope") then select (items (get effect "history")) (str profile "scope")
    else items (get effect "history"))) profile.
Proof.
 intros select effect profile Transport; unfold effect_input.
 rewrite Transport, disabled_configuration_history_keeps_other_records; reflexivity.
Qed.

Lemma settings_retire_only_earlier_configuration_controls :
 forall updates before after owner settings profile effort,
 let setting := Codec.message_json owner (SettingsMessage settings profile effort) in
 configuration_history updates (before ++ setting :: after) =
   ((filter (fun message => negb (reasoning_configuration message)) before ++
     setting :: fst (configuration_history updates after))%list, false).
Proof.
 intros updates before; induction before as [|message rest IH]; intros after owner settings profile effort setting.
 - cbn [app configuration_history filter].
   destruct (configuration_history updates after) as [retained current].
   destruct current; reflexivity.
 - cbn [app configuration_history filter].
   unfold setting.
   rewrite (IH after owner settings profile effort).
   destruct (reasoning_configuration message); reflexivity.
Qed.

Theorem request_input_after_settings_retires_earlier_configuration_controls :
 forall select effect profile before after owner settings key effort,
 let setting := Codec.message_json owner (SettingsMessage settings key effort) in
 (if boolean_field effect "context_selected" then items (get effect "history") else
  if is_text (get profile "scope") then select (items (get effect "history")) (str profile "scope")
  else items (get effect "history")) = (before ++ setting :: after)%list ->
 effect_input select effect profile =
 input_items (filter (fun message => negb (reasoning_configuration message)) before ++
   setting :: fst (configuration_history (configuration_updates effect) after)) profile.
Proof.
 intros select effect profile before after owner settings key effort setting Selected.
 unfold effect_input; rewrite Selected; unfold setting.
 rewrite (settings_retire_only_earlier_configuration_controls
   (configuration_updates effect) before after owner settings key effort); reflexivity.
Qed.
