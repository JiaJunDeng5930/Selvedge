From Selvedge.Kernel Require Import CallbackChangesProofs TaskWakeProofs.
From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec Conversation OutputClassification Callbacks State Tasks Inputs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem nonmessage_provider_data_has_no_interactive_output_authority :
 forall owner ticket part mode value,
 text_default "type" (Conversation.provider_value value) "" <> "message" ->
 Callbacks.item_messages owner ticket mode [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part PlainOutput) value].
Proof.
 intros owner ticket part mode value NotMessage.
 unfold Callbacks.item_messages; cbn [List.map]. unfold Conversation.context_output_mode, Conversation.provider_assistant_message.
 destruct (String.eqb (text_default "type" (provider_value value) "") "message") eqn:Kind.
 - apply String.eqb_eq in Kind; contradiction.
 - reflexivity.
Qed.
Theorem assistant_messages_inherit_the_frozen_output_mode :
 forall owner ticket part mode value,
 string_field "role" (Conversation.provider_value value) = Some "assistant" ->
 text_default "type" (Conversation.provider_value value) "" = "message" ->
 Callbacks.item_messages owner ticket mode [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part mode) value].
Proof.
 intros owner ticket part mode value Assistant Message.
 unfold Callbacks.item_messages; cbn [List.map].
 unfold Conversation.context_output_mode, Conversation.provider_assistant_message, Conversation.provider_assistant.
 rewrite Assistant, Message, String.eqb_refl. reflexivity.
Qed.

Local Lemma changing_activity_preserves_history : forall phase task,
 task_history (with_activity phase task) = task_history task.
Proof.
 intros phase task; unfold with_activity; destruct (task_lifecycle task); reflexivity.
Qed.
Theorem a_duplicate_model_batch_is_consumed_without_losing_history_or_effects :
 forall id ticket allowed mode items task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 ModelWire.admit_batch items = None ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (model_outcome_from_items items) value) = put_task id updated value /\
 (task_activity updated = Idle \/ task_activity updated = WantsModel) /\
 exists suffix,
 task_history updated = task_history task ++ [FailureMessage duplicate_model_identity] ++ suffix /\
 decision_effects (Callbacks.model_completed id ticket (model_outcome_from_items items) value) = [].
Proof.
 intros id ticket allowed mode items task value operations Found Pending Duplicated.
 unfold model_outcome_from_items; rewrite Duplicated.
 rewrite !model_completed_expression; rewrite Found.
 unfold task_activity; rewrite Pending, N.eqb_refl.
 cbn beta iota; fold (Callbacks.model_result id ticket allowed mode (ModelFailure duplicate_model_identity) task).
 unfold Callbacks.model_result, Callbacks.model_result_changes.
 exists (Callbacks.settle_model (append_history [FailureMessage duplicate_model_identity] task)).
 split; [reflexivity|]. split.
 - rewrite settle_model_expression.
   destruct (unseen_model_input (append_history [FailureMessage duplicate_model_identity] task));
     destruct task as [contract chosen settings lifecycle history queued lineage parent cursor consumed];
     cbn in Pending; subst lifecycle; destruct queued;
     first [left; reflexivity | right; reflexivity].
 - rewrite settle_model_expression.
   destruct (promotion_retains_history
     (with_activity
       (if unseen_model_input (append_history [FailureMessage duplicate_model_identity] task)
        then WantsModel else Idle)
       (append_history [FailureMessage duplicate_model_identity] task))) as [suffix Promoted].
   exists suffix; split; [|reflexivity].
   rewrite Promoted, changing_activity_preserves_history.
   change ((task_history task ++ [FailureMessage duplicate_model_identity]) ++ suffix =
     task_history task ++ [FailureMessage duplicate_model_identity] ++ suffix).
   symmetry; apply app_assoc.
Qed.

(** Acceptance fixes provenance from the pending request, before queued input is
    promoted. The suffix is only subsequent input; the accepted output remains
    an ordered part of the actual committed task history. *)
Theorem accepted_model_completion_appends_each_accepted_item :
 forall id ticket allowed mode batch task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 Callbacks.permitted_items (Codec.model_items batch) allowed task = true ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess batch) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++ Callbacks.item_messages id ticket mode (Codec.model_items batch) ++ suffix.
Proof.
 intros id ticket allowed mode batch task value operations Found Pending Admitted.
 rewrite !model_completed_expression; rewrite Found.
 unfold task_activity; rewrite Pending, N.eqb_refl.
 cbn beta iota; fold (Callbacks.model_result id ticket allowed mode (ModelSuccess batch) task).
 eexists; split; [reflexivity|].
 unfold Callbacks.model_result, Callbacks.model_result_changes; rewrite Admitted.
 destruct (Callbacks.item_calls (Codec.model_items batch)) as [|invocation remaining].
 - change (exists suffix, task_history (Callbacks.settle_model
     (append_history (Callbacks.item_messages id ticket mode (Codec.model_items batch)) task)) =
     task_history task ++ Callbacks.item_messages id ticket mode (Codec.model_items batch) ++ suffix).
   rewrite !settle_model_expression.
   destruct (promotion_retains_history
     (with_activity
       (if unseen_model_input (append_history (Callbacks.item_messages id ticket mode (Codec.model_items batch)) task)
        then WantsModel else Idle)
       (append_history (Callbacks.item_messages id ticket mode (Codec.model_items batch)) task))) as [suffix Promoted].
   exists suffix; rewrite Promoted, changing_activity_preserves_history.
   change ((task_history task ++ Callbacks.item_messages id ticket mode (Codec.model_items batch)) ++ suffix =
     task_history task ++ Callbacks.item_messages id ticket mode (Codec.model_items batch) ++ suffix).
   symmetry; apply app_assoc.
 - cbn [TaskChange.apply TaskChange.apply_edit fold_left].
   exists []; rewrite app_nil_r; reflexivity.
Qed.

Theorem actual_text_completion_retains_its_content_and_request_identity :
 forall id ticket allowed mode part (text : ModelWire.D.denote ModelWire.D.text) task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket
   (ModelSuccess (ModelWire.singleton (ModelWire.text part text))) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++
   AssistantMessage (OutputOrigin id ticket part mode) (proj1_sig text) :: suffix.
Proof.
 intros id ticket allowed mode part text task value operations Found Pending.
 destruct (accepted_model_completion_appends_each_accepted_item
   id ticket allowed mode (ModelWire.singleton (ModelWire.text part text)) task value operations Found Pending eq_refl)
   as [updated [Committed [suffix History]]].
 exists updated; split; [exact Committed|]. exists suffix; rewrite History; reflexivity.
Qed.

Theorem actual_assistant_context_retains_its_native_data_and_frozen_mode :
 forall id ticket allowed mode part members task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 string_field "role" (Conversation.provider_value (JObject members)) = Some "assistant" ->
 text_default "type" (Conversation.provider_value (JObject members)) "" = "message" ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket
   (ModelSuccess (ModelWire.singleton (ModelWire.context part members))) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++
   ModelContext (OutputOrigin id ticket part mode) (JObject members) :: suffix.
Proof.
 intros id ticket allowed mode part members task value operations Found Pending Assistant Message.
 destruct (accepted_model_completion_appends_each_accepted_item
   id ticket allowed mode (ModelWire.singleton (ModelWire.context part members)) task value operations Found Pending eq_refl)
   as [updated [Committed [suffix History]]].
 exists updated; split; [exact Committed|]. exists suffix.
 rewrite History. change (task_history task ++
   Callbacks.item_messages id ticket mode [ContextItem part (JObject members)] ++ suffix =
   task_history task ++ ModelContext (OutputOrigin id ticket part mode) (JObject members) :: suffix).
 rewrite (assistant_messages_inherit_the_frozen_output_mode
   id ticket part mode (JObject members) Assistant Message); reflexivity.
Qed.

(** Role metadata on provider reasoning or compaction does not turn diagnostic
    evidence into assistant speech. The native payload remains in history. *)
Theorem nonmessage_context_is_not_presented_as_assistant_speech :
 forall viewer origin content,
 text_default "type" (Conversation.provider_value content) "" <> "message" ->
 Conversation.json_message_role (Codec.message_json viewer (ModelContext origin content)) = None /\
 Conversation.json_message_assistant (Codec.message_json viewer (ModelContext origin content)) = false.
Proof.
 intros viewer origin content Nonmessage.
 change ((if provider_assistant_message content then Some "assistant" else None) = None /\
   provider_assistant_message content = false).
 unfold Conversation.provider_assistant_message.
 destruct (String.eqb (text_default "type" (provider_value content) "") "message") eqn:Kind.
 - apply String.eqb_eq in Kind; contradiction.
 - split; reflexivity.
Qed.

Theorem user_images_keep_their_place_between_the_original_text_parts :
 forall owner before image after,
 Conversation.json_message_text
   (Codec.message_json owner (UserMessage [TextPart before; ImagePart image; TextPart after])) =
 Some (String.append before (String.append "
![Image](/api/board/attachments/" (String.append (image_id image) (String.append ")
" after)))).
Proof.
 intros owner before image after.
 assert (End : String.append after "" = after).
 { induction after; cbn; congruence. }
 assert (Join : forall id, String.append (String.append id ")
") after = String.append id (String.append ")
" after)).
 { intro identity; induction identity; cbn; [reflexivity | f_equal; exact IHidentity]. }
 cbn; rewrite End, Join; reflexivity.
Qed.
