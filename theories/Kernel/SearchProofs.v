From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Conversation Search Queries.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.

Theorem rejected_scope_contributes_no_history : forall query project work id task value,
 Search.selected project work id task value = false ->
 Search.task_hits query project work id task value = [].
Proof. intros; unfold Search.task_hits; rewrite H; reflexivity. Qed.

(* Counting happens before visibility filtering: the returned offset addresses
   the committed history, rather than a list of searchable messages. *)
Theorem every_original_record_advances_the_position : forall query summary index before hits message newer,
 fst (fst (Search.scan_message query summary (index,before,hits) (message,newer))) = N.succ index.
Proof.
 intros; unfold Search.scan_message.
 destruct (Search.readable message) as [[role text]|]; reflexivity.
Qed.

Theorem hidden_context_keeps_the_original_position : forall query summary index before hits change newer,
 Search.scan_message query summary (index,before,hits) (ContextObservation change,newer) =
 (N.succ index,before,hits).
Proof. reflexivity. Qed.

Theorem a_matching_visible_record_has_its_original_position : forall query summary index before hits message role text newer,
 Search.readable message = Some (role,text) ->
 Search.contains (Search.lower query) (Search.lower text) = true ->
 Search.scan_message query summary (index,before,hits) (message,newer) =
 (N.succ index,Search.take_text 180 text,
  JObject [("task",summary);("message_index",number index);("role",JString role);
   ("snippet",JString (Search.snippet query text));
   ("before",JString before);("after",JString newer)] :: hits).
Proof.
 intros; unfold Search.scan_message; rewrite H, H0; reflexivity.
Qed.

Theorem provider_speech_uses_the_conversation_decoder : forall origin value,
 Conversation.provider_assistant_message value = true ->
 Search.readable (ModelContext origin value) = Some ("assistant",Conversation.provider_text value).
Proof.
 intros; unfold Search.readable.
 assert (Role : Conversation.json_message_role (Codec.message_json 0 (ModelContext origin value)) = Some "assistant").
 { change ((if Conversation.provider_assistant_message value then Some "assistant" else None) = Some "assistant").
   rewrite H; reflexivity. }
 assert (Text : as_string (Conversation.json_message_content (Codec.message_json 0 (ModelContext origin value))) =
  Some (Conversation.provider_text value)) by reflexivity.
 rewrite Role, Text; reflexivity.
Qed.

Theorem a_delivered_prefix_leaves_exactly_the_next_page : forall delivered remaining limit,
 Search.page (delivered ++ remaining) (N.of_nat (List.length delivered)) limit =
 Search.page_remaining remaining (N.of_nat (List.length delivered)) limit.
Proof.
 intros; unfold Search.page.
 assert (E : N.leb (N.of_nat (List.length delivered))
   (N.of_nat (List.length (delivered ++ remaining))) = true).
 { apply N.leb_le; rewrite length_app, Nat2N.inj_add; lia. }
 rewrite E, Nat2N.id, skipn_app, skipn_all, Nat.sub_diag; reflexivity.
Qed.

Theorem the_public_search_query_calls_the_scoped_history_search : forall request caller value,
 Queries.handle_search_history request caller value =
 Search.search (Commands.search_history_query request)
   (Commands.search_history_project_id request) (Commands.search_history_work_id request)
   (Queries.default_n (Commands.search_history_after request) 0)
   (Queries.default_n (Commands.search_history_limit request) Search.default_limit) value.
Proof. reflexivity. Qed.
