From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec Conversation Callbacks.
Import ListNotations.
Open Scope string_scope.

Theorem nonmessage_provider_data_has_no_interactive_output_authority :
 forall owner ticket part mode value,
 text_default "type" (Conversation.provider_value value) "" <> "message" ->
 Callbacks.item_messages owner ticket mode [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part PlainOutput) value].
Proof.
 intros owner ticket part mode value NotMessage.
 unfold Callbacks.item_messages; cbn [List.map]. unfold Conversation.context_output_mode.
 destruct (String.eqb (text_default "type" (provider_value value) "") "message") eqn:Kind.
 - apply String.eqb_eq in Kind; contradiction.
 - reflexivity.
Qed.
Theorem only_assistant_provider_messages_inherit_the_frozen_output_mode :
 forall owner ticket part mode value,
 string_field "role" (Conversation.provider_value value) = Some "assistant" ->
 text_default "type" (Conversation.provider_value value) "" = "message" ->
 Callbacks.item_messages owner ticket mode [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part mode) value].
Proof.
 intros owner ticket part mode value Assistant Message.
 unfold Callbacks.item_messages; cbn [List.map]. unfold Conversation.context_output_mode, Conversation.provider_assistant.
 rewrite Assistant, Message, String.eqb_refl. reflexivity.
Qed.
