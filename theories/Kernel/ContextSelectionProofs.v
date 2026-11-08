From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonObjectsProofs NumbersProofs.
From Selvedge.Foundation Require OptionList.
From Selvedge.Kernel Require Import Domain Numbers Codec ContextSelection ContextTypes ContextUpdates.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem an_unresolved_captured_call_cannot_be_compacted : forall captured whole invocation,
 In (FunctionCall invocation) captured -> has_output whole (call_id invocation) = false ->
 settled_calls captured whole = false.
Proof.
 intros captured whole invocation Present Missing.
 unfold settled_calls.
 destruct (forallb _ captured) eqn:Settled; [|reflexivity].
 apply forallb_forall with (x := FunctionCall invocation) in Settled; [|exact Present].
 cbn in Settled; rewrite Missing in Settled; discriminate.
Qed.

Theorem a_closed_prefix_contains_every_captured_call_output : forall history invocation,
 closed_prefix history = true -> In (FunctionCall invocation) history ->
 has_output history (call_id invocation) = true.
Proof.
 intros history invocation Closed Present.
 unfold closed_prefix, settled_calls in Closed.
 now apply forallb_forall with (x:=FunctionCall invocation) in Closed.
Qed.

Theorem adoption_keeps_the_original_history : forall snapshot candidate current,
 exists suffix, adopt snapshot candidate current = (current ++ suffix)%list.
Proof.
 intros. unfold adopt. destruct (history_extends snapshot current).
 - eexists. reflexivity.
 - exists []. now rewrite app_nil_r.
Qed.

Theorem selected_replacement_keeps_the_exact_suffix : forall snapshot suffix candidate tracked scope,
 latest (snapshot ++ suffix) scope 0 Original = Replacement (N.of_nat (List.length snapshot)) candidate tracked ->
 target_messages (snapshot ++ suffix) scope =
 (tracked ++ fixed snapshot ++ artifact_items candidate ++ scoped_messages suffix scope)%list.
Proof.
 intros snapshot suffix candidate tracked scope selected.
 unfold target_messages. rewrite selected. unfold assemble, replacement_prefix. rewrite Nat2N.id.
 rewrite firstn_app, firstn_all, skipn_app, skipn_all, Nat.sub_diag. cbn.
 now rewrite app_nil_r, <- !app_assoc.
Qed.

Theorem selected_replacement_drops_compacted_reasoning_updates :
 forall before owner effort after suffix candidate tracked scope,
 let snapshot := (before ++ Codec.message_json owner (ReasoningConfigurationMessage effort) :: after)%list in
 latest (snapshot ++ suffix) scope 0 Original =
   Replacement (N.of_nat (List.length snapshot)) candidate tracked ->
 target_messages (snapshot ++ suffix) scope =
   (tracked ++ fixed (before ++ after) ++ artifact_items candidate ++ scoped_messages suffix scope)%list.
Proof.
 intros before owner effort after suffix candidate tracked scope snapshot Selected.
 rewrite (selected_replacement_keeps_the_exact_suffix snapshot suffix candidate tracked scope Selected).
 unfold snapshot, fixed; rewrite !flat_map_app; reflexivity.
Qed.

Theorem portable_replacement_keeps_the_exact_suffix : forall snapshot suffix candidate tracked,
 latest (snapshot ++ suffix) "" 0 Original = Replacement (N.of_nat (List.length snapshot)) candidate tracked ->
 portable_messages (snapshot ++ suffix) =
 (tracked ++ fixed snapshot ++ artifact_items candidate ++ retained_messages suffix)%list.
Proof.
 intros snapshot suffix candidate tracked selected.
 unfold portable_messages. rewrite selected. unfold replacement_prefix. rewrite Nat2N.id.
 rewrite firstn_app, firstn_all, skipn_app, skipn_all, Nat.sub_diag. cbn.
 now rewrite app_nil_r, <- !app_assoc.
Qed.
Theorem a_current_snapshot_can_be_adopted : forall history candidate,
 adopt history candidate history = (history ++ [record history candidate])%list.
Proof.
 intros. unfold adopt, history_extends, history_json. cbn beta zeta.
 rewrite length_map, Nat.leb_refl.
 rewrite firstn_all2; [rewrite equivalent_is_reflexive; reflexivity|].
 rewrite length_map. apply Nat.le_refl.
Qed.

Theorem an_extended_snapshot_can_be_adopted : forall snapshot suffix candidate,
 adopt snapshot candidate (snapshot ++ suffix) =
 (snapshot ++ suffix ++ [record snapshot candidate])%list.
Proof.
 intros snapshot suffix candidate. unfold adopt, history_extends, history_json.
 rewrite map_app, length_map, length_app.
 assert (Fits : Nat.leb (List.length snapshot) (List.length snapshot + List.length suffix) = true).
 { apply Nat.leb_le. apply Nat.le_add_r. }
 rewrite Fits, firstn_app, <- (length_map (Codec.message_json 0) snapshot) at 1.
 rewrite firstn_all, length_map, Nat.sub_diag, firstn_O, app_nil_r,
  equivalent_is_reflexive. cbn. symmetry. apply app_assoc.
Qed.

Local Lemma encoded_portable_messages_decode : forall messages,
 decode_portable_messages (map portable_message_json messages) = Some messages.
Proof.
 induction messages as [|[speaker text] rest IH]; [reflexivity|].
 assert (First : decode_portable_message (portable_message_json (PortableMessage speaker text)) =
   Some (PortableMessage speaker text)) by (destruct speaker; reflexivity).
 unfold decode_portable_messages in *.
 cbn [map OptionList.traverse]. now rewrite First, IH.
Qed.

Local Lemma eligible_record_selects_its_captured_context :
 forall owner snapshot candidate scope position previous,
 (N.of_nat (List.length snapshot) <=? position) = true ->
 consumes candidate scope = true ->
 select_event position scope (Codec.message_json owner (record snapshot candidate)) previous =
 Replacement (N.of_nat (List.length snapshot)) candidate (tracked_introductions snapshot).
Proof.
 intros owner snapshot candidate scope position previous Fits Consumes.
 destruct candidate as [[speaker text] rest|head tail first rest].
 - destruct speaker;
   unfold select_event, record, artifact_json, artifact_format, artifact_items,
     decode_artifact, natural_field, natural, number, number_text in *;
   cbn -[tracked_introductions decode_portable_messages Selvedge.Foundation.Numbers.parse_natural show_natural N.leb];
   rewrite natural_print_parse, encoded_portable_messages_decode, Fits; reflexivity.
 - unfold select_event, record, artifact_json, artifact_format, artifact_items,
     decode_artifact, natural_field, natural, number, number_text in *;
   cbn -[tracked_introductions Selvedge.Foundation.Numbers.parse_natural show_natural N.leb consumes];
   rewrite natural_print_parse, Fits, Consumes; reflexivity.
Qed.

Local Lemma latest_app : forall prefix suffix scope position previous,
 latest (prefix ++ suffix) scope position previous =
 latest suffix scope (position + N.of_nat (List.length prefix))
   (latest prefix scope position previous).
Proof.
 induction prefix as [|entry rest IH]; intros suffix scope position previous.
 - cbn; now rewrite N.add_0_r.
 - cbn [latest app List.length]. rewrite IH, Nat2N.inj_succ, N.add_succ_l, N.add_succ_r.
   reflexivity.
Qed.

Theorem adopted_replacement_rebuilds_from_captured_context :
 forall owner snapshot suffix candidate scope,
 consumes candidate scope = true ->
 target_messages (history_json owner (adopt snapshot candidate (snapshot ++ suffix))) scope =
 (tracked_introductions snapshot ++ fixed (history_json owner snapshot) ++ artifact_items candidate ++
   scoped_messages (history_json owner suffix) scope)%list.
Proof.
 intros owner snapshot suffix candidate scope Consumes.
 rewrite an_extended_snapshot_can_be_adopted.
 unfold history_json at 1. rewrite !map_app. cbn [map].
 fold (history_json owner snapshot) (history_json owner suffix).
 assert (Selected :
   latest (history_json owner snapshot ++ history_json owner suffix ++
     [Codec.message_json owner (record snapshot candidate)]) scope 0 Original =
   Replacement (N.of_nat (List.length snapshot)) candidate (tracked_introductions snapshot)).
 { rewrite app_assoc, latest_app. cbn [latest].
   apply eligible_record_selects_its_captured_context; [|exact Consumes].
   rewrite N.add_0_l, length_app. unfold history_json. rewrite !length_map.
   apply N.leb_le. rewrite Nat2N.inj_add. apply N.le_add_r. }
 rewrite <- (length_map (Codec.message_json owner) snapshot) in Selected.
 rewrite (selected_replacement_keeps_the_exact_suffix _ _ _ _ _ Selected).
 unfold scoped_messages at 1. rewrite flat_map_app.
 now rewrite app_nil_r.
Qed.

Theorem selected_replacement_drops_compacted_tracked_changes :
 forall owner before change after suffix candidate tracked scope,
 let snapshot := (before ++ Codec.message_json owner (ContextObservation change) :: after)%list in
 latest (snapshot ++ suffix) scope 0 Original =
   Replacement (N.of_nat (List.length snapshot)) candidate tracked ->
 target_messages (snapshot ++ suffix) scope =
 (tracked ++ fixed (before ++ after) ++ artifact_items candidate ++ scoped_messages suffix scope)%list.
Proof.
 intros owner before change after suffix candidate tracked scope snapshot Selected.
 rewrite (selected_replacement_keeps_the_exact_suffix _ _ _ _ _ Selected).
 unfold snapshot, fixed. rewrite !flat_map_app. reflexivity.
Qed.

Theorem another_scope_cannot_select_native_context : forall history position head tail first rest scope previous,
 String.eqb (String head tail) scope = false ->
 select_event position scope (Codec.message_json 0 (record history (NativeArtifact head tail first rest))) previous = previous.
Proof.
 intros history position head tail first rest scope previous different.
 change ((match natural (number (N.of_nat (List.length history))) with
 | Some source => if (source <=? position) && String.eqb (String head tail) scope then
     Replacement source (NativeArtifact head tail first rest) (tracked_introductions history) else previous
 | None => previous end) = previous).
 rewrite different. destruct (natural (number (N.of_nat (List.length history)))); cbn; [now rewrite andb_false_r|reflexivity].
Qed.
Theorem selected_summary_keeps_fixed_inputs_and_discards_replaced_dialogue : forall parts summary scope,
 let original := JObject [("role", JString "user"); ("content", JArray parts)] in
 let summary_item := PortableMessage PortableUser summary in
 target_messages [original; Codec.message_json 0 (record [EnvironmentNotice ""] (PortableArtifact summary_item []))] scope =
 (fixed [original] ++ [portable_message_json summary_item])%list.
Proof.
 intros parts summary scope original summary_item.
 unfold target_messages. cbn [latest].
 rewrite eligible_record_selects_its_captured_context by reflexivity.
 change (((fixed [original] ++ [portable_message_json summary_item]) ++ [])%list =
   (fixed [original] ++ [portable_message_json summary_item])%list).
 apply app_nil_r.
Qed.

Theorem selecting_a_summary_preserves_each_original_image : forall parts image summary scope,
 In image parts -> string_field "type" image = Some "image" ->
 exists images message,
 In image images /\
 In message
  (target_messages
   [JObject [("role",JString "user");("content",JArray parts)];
    Codec.message_json 0 (record [EnvironmentNotice ""] (PortableArtifact (PortableMessage PortableUser summary) []))] scope) /\
 string_field "role" message = Some "user" /\ array_field "content" message = Some images.
Proof.
 intros parts image summary scope Present IsImage.
 assert (Kept : In image (image_parts (JArray parts))).
 { unfold image_parts; apply filter_In; split; [exact Present|].
   unfold text_default; rewrite IsImage; apply String.eqb_refl. }
 destruct (image_parts (JArray parts)) as [|first rest] eqn:Images; [contradiction|].
 exists (first :: rest), (JObject [("role",JString "user");("content",JArray (first :: rest))]).
 split; [exact Kept|]. split; [|split; reflexivity].
 rewrite selected_summary_keeps_fixed_inputs_and_discards_replaced_dialogue.
 apply in_or_app; left; unfold fixed; apply in_flat_map.
 exists (JObject [("role",JString "user");("content",JArray parts)]).
 split; [left; reflexivity|].
 change (In (JObject [("role",JString "user");("content",JArray (first :: rest))])
  (match image_parts (JArray parts) with
   | [] => []
   | images => [JObject [("role",JString "user");("content",JArray images)]] end)).
 rewrite Images; left; reflexivity.
Qed.

Theorem an_incompatible_replacement_preserves_the_selection : forall position scope entry previous,
 (forall candidate, decode_artifact (value_or_null "content" entry) = Some candidate ->
   consumes candidate scope = false) ->
 select_event position scope entry previous = previous.
Proof.
 intros position scope entry previous Incompatible.
 unfold select_event.
 destruct (String.eqb (text_default "role" entry "") "context_replacement"); [|reflexivity].
 destruct (decode_artifact (value_or_null "content" entry)) as [candidate|];
 destruct (natural_field "source_length" (value_or_null "content" entry));
 destruct (array_field "tracked_context" (value_or_null "content" entry)); try reflexivity.
 rewrite (Incompatible candidate eq_refl), andb_false_r; reflexivity.
Qed.

Theorem the_history_scan_skips_an_incompatible_replacement : forall entry rest scope position previous,
 (forall candidate, decode_artifact (value_or_null "content" entry) = Some candidate ->
   consumes candidate scope = false) ->
 latest (entry :: rest) scope position previous = latest rest scope (N.succ position) previous.
Proof.
 intros; cbn [latest]; rewrite an_incompatible_replacement_preserves_the_selection by assumption.
 reflexivity.
Qed.

(* Tool results and announced-operation results retain the same original image
   values as user input. Compaction cannot replace them with generated text. *)
Theorem fixed_input_preserves_each_original_image : forall role content image,
 In role ["user";"function_output";"operation_result"] ->
 In image (image_parts content) ->
 exists images message, In image images /\
 In message (fixed_message (JObject [("role",JString role);("content",content)])) /\
 string_field "role" message = Some "user" /\ array_field "content" message = Some images.
Proof.
 intros role content image Role Present.
 destruct (image_parts content) as [|first rest] eqn:Images; [contradiction|].
 exists (first :: rest), (JObject [("role",JString "user");("content",JArray (first :: rest))]).
 split; [exact Present|]. split; [|split; reflexivity].
 cbn in Role; destruct Role as [Role|[Role|[Role|Role]]]; try contradiction;
 subst role;
 change (In (JObject [("role",JString "user");("content",JArray (first :: rest))])
  (match image_parts content with
   | [] => []
   | images => [JObject [("role",JString "user");("content",JArray images)]] end));
 rewrite Images; left; reflexivity.
Qed.

Theorem portable_selection_keeps_suffix_receipts_verbatim : forall snapshot receipt rest candidate tracked,
 latest (snapshot ++ receipt :: rest) "" 0 Original =
  Replacement (N.of_nat (List.length snapshot)) candidate tracked ->
 text_default "role" receipt "" = "model_context" ->
 portable_messages (snapshot ++ receipt :: rest) =
 (tracked ++ fixed snapshot ++ artifact_items candidate ++ receipt :: retained_messages rest)%list.
Proof.
 intros snapshot receipt rest candidate tracked Selected Role.
 rewrite (portable_replacement_keeps_the_exact_suffix snapshot (receipt :: rest) candidate tracked Selected).
 unfold retained_messages; cbn [filter]; rewrite Role; reflexivity.
Qed.
