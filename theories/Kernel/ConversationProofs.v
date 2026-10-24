From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Json Utf8.
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
Local Lemma promotion_extends_history : forall task,
 exists suffix, task_history (Tasks.promote task) = task_history task ++ suffix.
Proof.
 intros task; unfold Tasks.promote.
 destruct (task_lifecycle task) as [phase operations|phase operations|phase operations|];
 try destruct phase; try destruct calls; destruct (task_queued task); cbn;
 try (exists []; rewrite app_nil_r; reflexivity);
 eexists; reflexivity.
Qed.

Fixpoint model_output_parts (items : list model_item) : list N :=
 match items with
 | [] => []
 | TextItem part _ :: rest | ContextItem part _ :: rest => part :: model_output_parts rest
 | CallItem _ :: rest => model_output_parts rest
 end.

Local Lemma permitted_text_head : forall part text rest allowed task ids parts,
 Callbacks.permitted_items (TextItem part text :: rest) allowed task ids parts = true ->
 negb (existsb (N.eqb part) parts) = true /\
 Utf8.well_formed text = true /\
 Callbacks.permitted_items rest allowed task ids (part :: parts) = true.
Proof.
 intros; cbn [Callbacks.permitted_items] in H.
 repeat rewrite andb_true_iff in H. tauto.
Qed.

Local Lemma permitted_context_head : forall part value rest allowed task ids parts,
 Callbacks.permitted_items (ContextItem part value :: rest) allowed task ids parts = true ->
 negb (existsb (N.eqb part) parts) = true /\
 Callbacks.permitted_items rest allowed task ids (part :: parts) = true.
Proof.
 intros part value rest allowed task ids parts Permitted.
 destruct value; cbn [Callbacks.permitted_items] in Permitted;
   repeat rewrite andb_true_iff in Permitted; tauto.
Qed.

Local Lemma permitted_call_head : forall invocation rest allowed task ids parts,
 Callbacks.permitted_items (CallItem invocation :: rest) allowed task ids parts = true ->
 Callbacks.permitted_items rest allowed task (call_id invocation :: ids) parts = true.
Proof.
 intros; cbn [Callbacks.permitted_items] in H.
 repeat rewrite andb_true_iff in H. tauto.
Qed.

Local Lemma permitted_model_parts_avoid_prior_parts : forall items allowed task ids parts,
 Callbacks.permitted_items items allowed task ids parts = true ->
 forall part, In part (model_output_parts items) -> ~ In part parts.
Proof.
 induction items as [|item rest IH]; intros allowed task ids parts Permitted part InPart.
 - simpl in InPart; contradiction.
 - destruct item as [head text|invocation|head value].
   + destruct (permitted_text_head head text rest allowed task ids parts Permitted)
       as [Fresh [_ Rest]].
     cbn [model_output_parts] in InPart. destruct InPart as [Same|InRest].
     * subst part. intro Prior.
       assert (Already : existsb (N.eqb head) parts = true).
       { apply existsb_exists. exists head. split; [exact Prior|apply N.eqb_refl]. }
       rewrite Already in Fresh. discriminate.
     * intro Prior. apply (IH allowed task ids (head :: parts) Rest part InRest).
       now right.
   + pose proof (permitted_call_head invocation rest allowed task ids parts Permitted) as Rest.
     apply (IH allowed task (call_id invocation :: ids) parts Rest part).
     exact InPart.
   + destruct (permitted_context_head head value rest allowed task ids parts Permitted)
       as [Fresh Rest].
     cbn [model_output_parts] in InPart. destruct InPart as [Same|InRest].
     * subst part. intro Prior.
       assert (Already : existsb (N.eqb head) parts = true).
       { apply existsb_exists. exists head. split; [exact Prior|apply N.eqb_refl]. }
       rewrite Already in Fresh. discriminate.
     * intro Prior. apply (IH allowed task ids (head :: parts) Rest part InRest).
       now right.
Qed.

Local Lemma permitted_model_items_have_unique_parts : forall items allowed task,
 forall ids parts,
 Callbacks.permitted_items items allowed task ids parts = true -> NoDup (model_output_parts items).
Proof.
 induction items as [|item rest IH]; intros allowed task ids parts Permitted.
 - constructor.
 - destruct item as [head text|invocation|head value].
   + destruct (permitted_text_head head text rest allowed task ids parts Permitted)
       as [Fresh [_ Rest]].
     cbn [model_output_parts]. constructor.
     * intro InRest.
       pose proof (permitted_model_parts_avoid_prior_parts rest allowed task ids (head :: parts) Rest head InRest) as NotPrior.
       apply NotPrior. now left.
     * exact (IH allowed task ids (head :: parts) Rest).
   + pose proof (permitted_call_head invocation rest allowed task ids parts Permitted) as Rest.
     exact (IH allowed task (call_id invocation :: ids) parts Rest).
   + destruct (permitted_context_head head value rest allowed task ids parts Permitted)
       as [Fresh Rest].
     cbn [model_output_parts]. constructor.
     * intro InRest.
       pose proof (permitted_model_parts_avoid_prior_parts rest allowed task ids (head :: parts) Rest head InRest) as NotPrior.
       apply NotPrior. now left.
     * exact (IH allowed task ids (head :: parts) Rest).
Qed.

Local Lemma duplicate_model_output_parts_are_not_permitted : forall items allowed task,
 ~ NoDup (model_output_parts items) -> Callbacks.permitted_items items allowed task [] [] = false.
Proof.
 intros items allowed task Duplicated.
 destruct (Callbacks.permitted_items items allowed task [] []) eqn:Permitted; [|reflexivity].
 exfalso. apply Duplicated. eapply permitted_model_items_have_unique_parts; exact Permitted.
Qed.

Theorem duplicate_provider_output_parts_are_rejected_without_losing_history_or_effects :
 forall id ticket allowed mode items task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 ~ NoDup (model_output_parts items) ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess items) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++
   [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] ++ suffix /\
 decision_effects (Callbacks.model_completed id ticket (ModelSuccess items) value) = [].
Proof.
 intros id ticket allowed mode items task value operations Found Pending Duplicated.
 assert (Rejected : Callbacks.permitted_items items allowed task [] [] = false).
 { now apply duplicate_model_output_parts_are_not_permitted. }
 unfold Callbacks.model_completed; rewrite Found.
 unfold task_activity; rewrite Pending, N.eqb_refl.
 unfold Callbacks.model_result; rewrite Rejected.
 exists (Callbacks.settle_model
   (append_history
     [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)).
 split.
 - cbn [decision_world acknowledged accept]. reflexivity.
 -
 assert (History : exists suffix,
   task_history (Callbacks.settle_model
     (append_history
       [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)) =
     task_history task ++
       [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] ++ suffix).
 { unfold Callbacks.settle_model.
   destruct (promotion_extends_history
     (with_activity
       (if unseen_model_input
          (append_history
            [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)
        then WantsModel else Idle)
       (append_history
         [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)))
     as [suffix Promoted].
   exists suffix. rewrite Promoted, changing_activity_preserves_history.
   change ((task_history task ++
       [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"]) ++ suffix =
     task_history task ++
       [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] ++ suffix).
   symmetry; apply app_assoc. }
 destruct History as [suffix History]. exists suffix. split; [exact History|reflexivity].
Qed.

(** Acceptance fixes provenance from the pending request, before queued input is
    promoted. The suffix is only subsequent input; the accepted output remains
    an ordered part of the actual committed task history. *)
Theorem accepted_model_completion_appends_each_accepted_item :
 forall id ticket allowed mode items task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 Callbacks.permitted_items items allowed task [] [] = true ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess items) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++ Callbacks.item_messages id ticket mode items ++ suffix.
Proof.
 intros id ticket allowed mode items task value operations Found Pending Admitted.
 unfold Callbacks.model_completed; rewrite Found.
 unfold task_activity; rewrite Pending, N.eqb_refl.
 eexists; split; [reflexivity|].
 unfold Callbacks.model_result; rewrite Admitted.
 destruct (Callbacks.item_calls items) as [|invocation remaining].
 - unfold Callbacks.settle_model.
   destruct (promotion_extends_history
     (with_activity
       (if unseen_model_input (append_history (Callbacks.item_messages id ticket mode items) task)
        then WantsModel else Idle)
       (append_history (Callbacks.item_messages id ticket mode items) task))) as [suffix Promoted].
   exists suffix; rewrite Promoted, changing_activity_preserves_history.
   change ((task_history task ++ Callbacks.item_messages id ticket mode items) ++ suffix =
     task_history task ++ Callbacks.item_messages id ticket mode items ++ suffix).
   symmetry; apply app_assoc.
 - exists []; rewrite app_nil_r, changing_activity_preserves_history; reflexivity.
Qed.

Theorem actual_text_completion_retains_its_content_and_request_identity :
 forall id ticket allowed mode part text task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 Utf8.well_formed text = true ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess [TextItem part text]) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++
   AssistantMessage (OutputOrigin id ticket part mode) text :: suffix.
Proof.
 intros id ticket allowed mode part text task value operations Found Pending Unicode.
 assert (Admitted : Callbacks.permitted_items [TextItem part text] allowed task [] [] = true).
 { cbn [Callbacks.permitted_items]; rewrite Unicode; reflexivity. }
 destruct (accepted_model_completion_appends_each_accepted_item
   id ticket allowed mode [TextItem part text] task value operations Found Pending Admitted)
   as [updated [Committed [suffix History]]].
 exists updated; split; [exact Committed|]. exists suffix; rewrite History; reflexivity.
Qed.

Theorem actual_assistant_context_retains_its_native_data_and_frozen_mode :
 forall id ticket allowed mode part content task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 string_field "role" (Conversation.provider_value content) = Some "assistant" ->
 text_default "type" (Conversation.provider_value content) "" = "message" ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess [ContextItem part content]) value) = put_task id updated value /\
 exists suffix,
 task_history updated = task_history task ++
   ModelContext (OutputOrigin id ticket part mode) content :: suffix.
Proof.
 intros id ticket allowed mode part content task value operations Found Pending Assistant Message.
 assert (Admitted : Callbacks.permitted_items [ContextItem part content] allowed task [] [] = true).
 { destruct content; cbn [provider_value value_or_null string_field field text_default] in Assistant, Message;
     try discriminate; reflexivity. }
 destruct (accepted_model_completion_appends_each_accepted_item
   id ticket allowed mode [ContextItem part content] task value operations Found Pending Admitted)
   as [updated [Committed [suffix History]]].
 exists updated; split; [exact Committed|]. exists suffix.
 rewrite History, (assistant_messages_inherit_the_frozen_output_mode
   id ticket part mode content Assistant Message); reflexivity.
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
