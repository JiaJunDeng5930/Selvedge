From Selvedge.Programming Require TaskChange.
From Selvedge.Kernel Require Import CallbackChangesProofs.
From Selvedge.Kernel Require Import TaskWakeProofs.
From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec Conversation OutputClassification Callbacks State Tasks Inputs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem nonmessage_provider_data_has_no_interactive_output_authority :
 forall owner ticket part mode phase value,
 text_default "type" (Conversation.provider_value value) "" <> "message" ->
 Callbacks.item_messages owner ticket mode phase [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part PlainOutput None) value].
Proof.
 intros owner ticket part mode phase value NotMessage.
 unfold Callbacks.item_messages; cbn [List.map]. unfold Conversation.context_origin, Conversation.provider_assistant_message.
 destruct (String.eqb (text_default "type" (provider_value value) "") "message") eqn:Kind.
 - apply String.eqb_eq in Kind; contradiction.
 - reflexivity.
Qed.
Theorem assistant_messages_inherit_the_frozen_output_mode :
 forall owner ticket part mode phase value,
 string_field "role" (Conversation.provider_value value) = Some "assistant" ->
 text_default "type" (Conversation.provider_value value) "" = "message" ->
 Callbacks.item_messages owner ticket mode phase [ContextItem part value] =
 [ModelContext (OutputOrigin owner ticket part mode (Some (Conversation.provider_assistant_phase value phase))) value].
Proof.
 intros owner ticket part mode phase value Assistant Message.
 unfold Callbacks.item_messages; cbn [List.map].
 unfold Conversation.context_origin, Conversation.provider_assistant_message, Conversation.provider_assistant.
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
 cbn beta iota; fold (TaskChange.apply (Callbacks.model_result_changes id ticket allowed mode (ModelFailure duplicate_model_identity) task) task).
 unfold Callbacks.model_result_changes.
 exists (TaskChange.apply (Callbacks.settle_model_changes (append_history [FailureMessage duplicate_model_identity] task)) (append_history [FailureMessage duplicate_model_identity] task)).
 split; [reflexivity|]. split.
 - rewrite settle_model_expression.
   destruct (unseen_model_input (append_history [FailureMessage duplicate_model_identity] task));
     destruct task as [contract chosen settings lifecycle history queued lineage handoff consumed];
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
 task_history updated = task_history task ++
   Callbacks.item_messages id ticket mode (Callbacks.phase_for_calls (Callbacks.item_calls (Codec.model_items batch)))
     (Codec.model_items batch) ++ suffix.
Proof.
 intros id ticket allowed mode batch task value operations Found Pending Admitted.
 rewrite !model_completed_expression; rewrite Found.
 unfold task_activity; rewrite Pending, N.eqb_refl.
 cbn beta iota; fold (TaskChange.apply (Callbacks.model_result_changes id ticket allowed mode (ModelSuccess batch) task) task).
 eexists; split; [reflexivity|].
 unfold Callbacks.model_result_changes; rewrite Admitted.
 remember (Callbacks.item_calls (Codec.model_items batch)) as calls.
 set (messages := Callbacks.item_messages id ticket mode (Callbacks.phase_for_calls calls) (Codec.model_items batch)).
 destruct calls as [|invocation remaining].
 - change (exists suffix, task_history (TaskChange.apply
     (Callbacks.settle_model_changes (append_history messages task))
     (append_history messages task)) = task_history task ++ messages ++ suffix).
   rewrite !settle_model_expression.
   destruct (promotion_retains_history
     (with_activity
       (if unseen_model_input (append_history messages task) then WantsModel else Idle)
       (append_history messages task))) as [suffix Promoted].
   exists suffix; rewrite Promoted, changing_activity_preserves_history.
   change ((task_history task ++ messages) ++ suffix = task_history task ++ messages ++ suffix).
   symmetry; apply app_assoc.
 - cbn [TaskChange.apply TaskChange.apply_edit fold_left].
   exists []; rewrite app_nil_r; reflexivity.
Qed.

Local Lemma model_call_is_collected : forall items invocation,
 In (CallItem invocation) items -> In invocation (Callbacks.item_calls items).
Proof.
 induction items as [|item rest IH]; intros invocation Present; [contradiction|].
 destruct Present as [Here|Later].
 - subst item; now left.
 - destruct item.
   + exact (IH invocation Later).
   + right; exact (IH invocation Later).
   + exact (IH invocation Later).
Qed.

Theorem accepted_text_in_a_tool_batch_is_published_as_commentary :
 forall id ticket allowed mode batch task value operations part text invocation,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 Callbacks.permitted_items (Codec.model_items batch) allowed task = true ->
 In (TextItem part text) (Codec.model_items batch) ->
 In (CallItem invocation) (Codec.model_items batch) ->
 exists updated entry,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess batch) value) = put_task id updated value /\
 In entry (task_history updated) /\
 entry = AssistantMessage (OutputOrigin id ticket part mode (Some Commentary)) text /\
 field "phase" (Codec.conversation_message_json id entry) = Some (JString "commentary").
Proof.
 intros id ticket allowed mode batch task value operations part text invocation Found Pending Admitted Text Call.
 destruct (accepted_model_completion_appends_each_accepted_item id ticket allowed mode batch task value
   operations Found Pending Admitted) as [updated [Committed [suffix History]]].
 pose proof (model_call_is_collected _ _ Call) as Collected.
 assert (Phase : Callbacks.phase_for_calls (Callbacks.item_calls (Codec.model_items batch)) = Commentary).
 { destruct (Callbacks.item_calls (Codec.model_items batch)); [contradiction|reflexivity]. }
 eexists updated, (AssistantMessage (OutputOrigin id ticket part mode (Some Commentary)) text).
 split; [exact Committed|]. split; [|split; reflexivity].
 rewrite History, Phase. apply in_or_app; right. apply in_or_app; left.
 apply in_map_iff. exists (TextItem part text); split; [reflexivity|exact Text].
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
   AssistantMessage (OutputOrigin id ticket part mode (Some FinalAnswer)) (proj1_sig text) :: suffix.
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
   ModelContext (OutputOrigin id ticket part mode
     (Some (Conversation.provider_assistant_phase (JObject members) FinalAnswer))) (JObject members) :: suffix.
Proof.
 intros id ticket allowed mode part members task value operations Found Pending Assistant Message.
 destruct (accepted_model_completion_appends_each_accepted_item
   id ticket allowed mode (ModelWire.singleton (ModelWire.context part members)) task value operations Found Pending eq_refl)
   as [updated [Committed [suffix History]]].
 exists updated; split; [exact Committed|]. exists suffix.
 rewrite History. change (task_history task ++
   Callbacks.item_messages id ticket mode FinalAnswer [ContextItem part (JObject members)] ++ suffix =
   task_history task ++ ModelContext (OutputOrigin id ticket part mode
     (Some (Conversation.provider_assistant_phase (JObject members) FinalAnswer))) (JObject members) :: suffix).
 rewrite (assistant_messages_inherit_the_frozen_output_mode
   id ticket part mode FinalAnswer (JObject members) Assistant Message); reflexivity.
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
