From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec HistoryRoleProofs.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory WebHistory.
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
