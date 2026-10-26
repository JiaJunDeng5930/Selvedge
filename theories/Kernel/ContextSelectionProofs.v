From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonObjectsProofs.
From Selvedge.Kernel Require Import Domain Numbers Codec ContextSelection.
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

Theorem selected_replacement_keeps_the_exact_suffix : forall snapshot suffix candidate scope,
 latest (snapshot ++ suffix) scope 0 Original = Replacement (N.of_nat (List.length snapshot)) candidate ->
 target_messages (snapshot ++ suffix) scope =
 (fixed snapshot ++ dialogue (artifact_items candidate) ++ scoped_messages suffix scope)%list.
Proof.
 intros snapshot suffix candidate scope selected.
 unfold target_messages. rewrite selected. unfold assemble. rewrite Nat2N.id.
 rewrite firstn_app, firstn_all, skipn_app, skipn_all, Nat.sub_diag. cbn.
 now rewrite app_nil_r.
Qed.

Theorem portable_replacement_keeps_the_exact_suffix : forall snapshot suffix candidate,
 latest (snapshot ++ suffix) "" 0 Original = Replacement (N.of_nat (List.length snapshot)) candidate ->
 portable_messages (snapshot ++ suffix) =
 (fixed snapshot ++ dialogue (artifact_items candidate) ++ retained_messages suffix)%list.
Proof.
 intros snapshot suffix candidate selected.
 unfold portable_messages. rewrite selected, Nat2N.id.
 rewrite firstn_app, firstn_all, skipn_app, skipn_all, Nat.sub_diag. cbn.
 now rewrite app_nil_r.
Qed.
Theorem a_current_snapshot_can_be_adopted : forall history candidate,
 adopt history candidate history = (history ++ [record (N.of_nat (List.length history)) candidate])%list.
Proof.
 intros. unfold adopt, history_extends, history_json. cbn beta zeta.
 rewrite length_map, Nat.leb_refl.
 rewrite firstn_all2; [rewrite equivalent_is_reflexive; reflexivity|].
 rewrite length_map. apply Nat.le_refl.
Qed.

Theorem an_extended_snapshot_can_be_adopted : forall snapshot suffix candidate,
 adopt snapshot candidate (snapshot ++ suffix) =
 (snapshot ++ suffix ++ [record (N.of_nat (List.length snapshot)) candidate])%list.
Proof.
 intros snapshot suffix candidate. unfold adopt, history_extends, history_json.
 rewrite map_app, length_map, length_app.
 assert (Fits : Nat.leb (List.length snapshot) (List.length snapshot + List.length suffix) = true).
 { apply Nat.leb_le. apply Nat.le_add_r. }
 rewrite Fits, firstn_app, <- (length_map (Codec.message_json 0) snapshot) at 1.
 rewrite firstn_all, length_map, Nat.sub_diag, firstn_O, app_nil_r,
  equivalent_is_reflexive. cbn. symmetry. apply app_assoc.
Qed.
Theorem another_scope_cannot_select_native_context : forall boundary position head tail first rest usage scope previous,
 String.eqb (String head tail) scope = false ->
 select_event position scope (Codec.message_json 0 (record boundary (NativeArtifact head tail first rest usage))) previous = previous.
Proof.
 intros boundary position head tail first rest usage scope previous different.
 change ((match natural (number boundary) with
 | Some source => if (source <=? position) && String.eqb (String head tail) scope then
     Replacement source (NativeArtifact head tail first rest usage) else previous
 | None => previous end) = previous).
 rewrite different. destruct (natural (number boundary)); cbn; [now rewrite andb_false_r|reflexivity].
Qed.
Theorem selected_summary_keeps_fixed_inputs_and_discards_replaced_dialogue : forall parts summary scope,
 let original := JObject [("role", JString "user"); ("content", JArray parts)] in
 let summary_item := PortableMessage PortableUser summary in
 target_messages [original; Codec.message_json 0 (record 1 (PortableArtifact summary_item [] JNull))] scope =
 (fixed [original] ++ [portable_message_json summary_item])%list.
Proof.
 intros. unfold target_messages, latest, select_event, record, artifact_json, decode_artifact,
   artifact_format, artifact_scope, artifact_items, artifact_usage, portable_message_json,
   decode_portable_message, decode_portable_messages, consumes, assemble,
   portable_speaker, portable_text.
 cbn [Pos.to_nat]. unfold scoped_messages, scoped_message. cbn [Pos.to_nat].
 now repeat rewrite app_nil_r.
Qed.

Theorem selecting_a_summary_preserves_each_original_image : forall parts image summary scope,
 In image parts -> string_field "type" image = Some "image" ->
 exists images,
 In image images /\
 In (JObject [("role",JString "user");("content",JArray images)])
  (target_messages
   [JObject [("role",JString "user");("content",JArray parts)];
    Codec.message_json 0 (record 1 (PortableArtifact (PortableMessage PortableUser summary) [] JNull))] scope).
Proof.
 intros parts image summary scope Present IsImage.
 assert (Kept : In image (image_parts (JArray parts))).
 { unfold image_parts; apply filter_In; split; [exact Present|].
   unfold text_default; rewrite IsImage; apply String.eqb_refl. }
 destruct (image_parts (JArray parts)) as [|first rest] eqn:Images; [contradiction|].
 exists (first :: rest); split; [exact Kept|].
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

Theorem readable_history_preserves_concatenation : forall first second,
 raw_messages (first ++ second) = (raw_messages first ++ raw_messages second)%list.
Proof. intros; unfold raw_messages; apply flat_map_app. Qed.

Theorem a_replacement_record_is_not_an_additional_context_source : forall replacement rest,
 raw_messages
  (JObject [("role",JString "context_replacement");("content",replacement)] :: rest) =
 raw_messages rest.
Proof. reflexivity. Qed.

Theorem an_incompatible_replacement_preserves_the_selection : forall position scope entry previous,
 compatible (value_or_null "content" entry) scope = false ->
 select_event position scope entry previous = previous.
Proof.
 intros position scope entry previous Incompatible.
 unfold compatible in Incompatible; unfold select_event.
 destruct (String.eqb (text_default "role" entry "") "context_replacement"); [|reflexivity].
 destruct (decode_artifact (value_or_null "content" entry)) as [candidate|] eqn:Candidate;
 destruct (natural_field "source_length" (value_or_null "content" entry)); try reflexivity.
 rewrite Incompatible, andb_false_r; reflexivity.
Qed.

Theorem the_history_scan_skips_an_incompatible_replacement : forall entry rest scope position previous,
 compatible (value_or_null "content" entry) scope = false ->
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
 exists images, In image images /\
 fixed_message (JObject [("role",JString role);("content",content)]) =
 [JObject [("role",JString "user");("content",JArray images)]].
Proof.
 intros role content image Role Present.
 destruct (image_parts content) as [|first rest] eqn:Images; [contradiction|].
 exists (first :: rest); split; [exact Present|].
 cbn in Role; destruct Role as [Role|[Role|[Role|Role]]]; try contradiction;
 subst role;
 change ((match image_parts content with
   | [] => []
   | images => [JObject [("role",JString "user");("content",JArray images)]] end) =
  [JObject [("role",JString "user");("content",JArray (first :: rest))]]);
 rewrite Images; reflexivity.
Qed.

Theorem portable_selection_keeps_suffix_receipts_verbatim : forall snapshot receipt rest candidate,
 latest (snapshot ++ receipt :: rest) "" 0 Original =
  Replacement (N.of_nat (List.length snapshot)) candidate ->
 text_default "role" receipt "" = "model_context" ->
 portable_messages (snapshot ++ receipt :: rest) =
 (fixed snapshot ++ dialogue (artifact_items candidate) ++ receipt :: retained_messages rest)%list.
Proof.
 intros snapshot receipt rest candidate Selected Role.
 rewrite (portable_replacement_keeps_the_exact_suffix snapshot (receipt :: rest) candidate Selected).
 unfold retained_messages; cbn [filter]; rewrite Role; reflexivity.
Qed.
