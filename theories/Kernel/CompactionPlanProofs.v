From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json SequenceProofs JsonObjectsProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Compaction CompactionPlan ContextSelection Numbers.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem an_unfinished_summary_keeps_every_unread_scalar : forall unread carry width window reserve head tail remaining,
 skipn (N.to_nat width) unread = remaining -> remaining <> [] ->
 receive (CompactionState (PortableSource unread) carry width window reserve)
  (JObject [("summary_text",JString (String head tail))]) =
 Next (CompactionState (PortableSource remaining)
  (String head tail) width window reserve).
Proof.
 intros. unfold receive, receive_source, receive_summary. cbn. rewrite H. destruct remaining; [contradiction|].
 reflexivity.
Qed.

Theorem a_finished_summary_publishes_its_returned_continuation :
 forall unread carry width window reserve head tail,
 skipn (N.to_nat width) unread = [] ->
 receive (CompactionState (PortableSource unread) carry width window reserve)
  (JObject [("summary_text",JString (String head tail))]) =
 Compacted (PortableArtifact (PortableMessage PortableAssistant (String head tail)) []).
Proof.
 intros unread carry width window reserve head tail Finished.
 unfold receive, receive_source, receive_summary. cbn. now rewrite Finished.
Qed.
Theorem an_opaque_reply_cannot_finish_portable_work : forall unread carry width window reserve scope items,
 exists reason, receive (CompactionState (PortableSource unread) carry width window reserve)
  (JObject [("format",JString "native");("scope",JString scope);("items",JArray items)]) =
 Failed reason.
Proof. intros; eexists; reflexivity. Qed.
Theorem native_start_retains_history_and_rebuild_material :
 forall captured history raw input_tokens window reserve,
 (forall entry, In entry captured -> History.message_images entry = []) ->
 input_tokens + reserve <= window ->
 start captured history raw "chatgpt" Automatic input_tokens window reserve =
 CompactionState (NativeSource history raw) "" window window reserve.
Proof.
 intros captured history raw input_tokens window reserve NoImages Fits.
 assert (Empty : forallb (fun entry => match History.message_images entry with
   | [] => true | _ => false end) captured = true).
 { apply forallb_forall. intros entry Present. rewrite (NoImages entry Present); reflexivity. }
 unfold start. rewrite Empty.
 assert (Budget : (input_tokens + reserve <=? window) = true).
 { apply N.leb_le. exact Fits. }
 now rewrite Budget.
Qed.

Theorem images_select_structured_summary : forall captured entry image history raw provider method input_tokens window reserve,
 In entry captured -> In image (History.message_images entry) ->
 start captured history raw provider method input_tokens window reserve =
 CompactionState (StructuredSource history raw) "" window window reserve.
Proof.
 intros captured entry image history raw provider method input_tokens window reserve Present Image.
 assert (Nonempty : forallb (fun entry => match History.message_images entry with
   | [] => true | _ => false end) captured = false).
 { apply not_true_is_false. intro Empty.
   apply forallb_forall with (x := entry) in Empty; [|exact Present].
   destruct (History.message_images entry); [contradiction|discriminate]. }
 unfold start. rewrite Nonempty. reflexivity.
Qed.

Theorem native_rebuilding_uses_raw_history :
 forall history raw carry width window reserve rebuilt,
 to_portable (CompactionState (NativeSource history raw) carry width window reserve) = Some rebuilt ->
 exists fragments,
   scalar_fragments (TextJson.render_json raw) = Some fragments /\
   compaction_source rebuilt = PortableSource fragments.
Proof.
 intros history raw carry width window reserve rebuilt Rebuilt.
 unfold to_portable, portable_source in Rebuilt.
 cbn [compaction_source] in Rebuilt.
 destruct (scalar_fragments (TextJson.render_json raw)) as [parts|] eqn:Parsed;
   try discriminate.
 inversion Rebuilt; subst rebuilt.
 exists parts. split; [reflexivity|reflexivity].
Qed.

Theorem native_plan_transports_only_its_selected_history :
 forall history raw carry width window reserve,
 JsonObjects.equivalent (plan_json (CompactionState (NativeSource history raw) carry width window reserve))
 (JObject [("method", JString "native"); ("window_tokens", number window);
   ("output_reserve_tokens", number reserve); ("history", history)]) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.

Theorem structured_plan_transports_selected_history_and_summary_instruction :
 forall history raw carry width window reserve,
 JsonObjects.equivalent (plan_json (CompactionState (StructuredSource history raw) carry width window reserve))
 (JObject [("method", JString "structured"); ("window_tokens", number window);
   ("output_reserve_tokens", number reserve); ("history", history);
   ("prompt", JString structured_summary_prompt)]) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.

Theorem structured_summary_publishes_its_returned_continuation :
 forall history raw carry width window reserve head tail,
 receive (CompactionState (StructuredSource history raw) carry width window reserve)
   (JObject [("summary_text",JString (String head tail))]) =
 Compacted (PortableArtifact (PortableMessage PortableAssistant (String head tail)) []).
Proof. reflexivity. Qed.

Theorem portable_plan_transports_only_bounded_summary_material :
 forall unread carry width window reserve,
 JsonObjects.equivalent (plan_json (CompactionState (PortableSource unread) carry width window reserve))
 (JObject [("method", JString "portable"); ("window_tokens", number window);
   ("output_reserve_tokens", number reserve);
   ("chunk", JString (String.concat "" (chunk (CompactionState (PortableSource unread) carry width window reserve))));
   ("carry", JString carry); ("prompt", JString summary_prompt)]) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.

Theorem a_portable_chunk_is_an_exact_prefix_of_unread_scalars :
 forall unread carry width window reserve,
 chunk (CompactionState (PortableSource unread) carry width window reserve) =
 firstn (N.to_nat width) unread.
Proof.
 intros.
 change (Sequence.take (N.to_nat width) unread = firstn (N.to_nat width) unread).
 apply take_equals_firstn.
Qed.

Theorem rebasing_preserves_the_unread_suffix_in_order :
 forall unread carry width window reserve rebased,
 rebase_note (CompactionState (PortableSource unread) carry width window reserve) = Some rebased ->
 exists opening closing prefix,
   scalar_fragments (opening ++ carry ++ closing) = Some prefix /\
   compaction_source rebased = PortableSource (prefix ++ unread) /\
   compaction_carry rebased = "".
Proof.
 intros unread carry width window reserve rebased Rebased.
 unfold rebase_note in Rebased.
 cbn [compaction_source compaction_carry] in Rebased.
 destruct (scalar_fragments
   ("Prior continuation note:" ++ String (Ascii.ascii_of_nat 10) carry ++
    String (Ascii.ascii_of_nat 10) "Unread task history:" ++
    String (Ascii.ascii_of_nat 10) "")) as [prefix|] eqn:Parsed;
   try discriminate.
 inversion Rebased; subst rebased.
 exists ("Prior continuation note:" ++ String (Ascii.ascii_of_nat 10) ""),
   (String (Ascii.ascii_of_nat 10) "Unread task history:" ++ String (Ascii.ascii_of_nat 10) ""), prefix.
 split; [exact Parsed|].
 cbn. split.
 - rewrite List.rev_append_rev, List.rev_append_rev, List.app_nil_r, List.rev_involutive.
   reflexivity.
 - reflexivity.
Qed.

Local Lemma fitting_portable_does_not_increase_width : forall value budget fitted,
 fit_portable value budget = Some fitted ->
 compaction_chunk_chars fitted <= compaction_chunk_chars value.
Proof.
 intros value budget fitted Fitted; unfold fit_portable in Fitted.
 destruct (plan_bytes (with_width 0 value) + 6 <=? budget).
 - injection Fitted as <-. cbn [fitted_width with_width set compaction_chunk_chars].
   apply N.le_min_l.
 - destruct (rebase_note value) as [rebased|] eqn:Rebased; cbn [option_map] in Fitted; try discriminate.
   injection Fitted as <-.
   unfold rebase_note in Rebased.
   destruct (compaction_source value); try discriminate.
   match type of Rebased with
   | context [scalar_fragments ?text] => destruct (scalar_fragments text)
   end; try discriminate.
   injection Rebased as <-.
   cbn [fitted_width with_width set compaction_chunk_chars]. apply N.le_min_l.
Qed.

Lemma fitted_transport_does_not_increase_width : forall value budget fitted,
 fit_transport value budget = Some fitted ->
 compaction_chunk_chars fitted <= compaction_chunk_chars value.
Proof.
 intros value budget fitted Fitted; unfold fit_transport in Fitted.
 destruct (compaction_source value) as [history raw|history raw|unread] eqn:Source.
 all: try solve [now apply fitting_portable_does_not_increase_width in Fitted].
 all: destruct (plan_bytes value <=? budget);
   [injection Fitted as <-; apply N.le_refl|].
 all: destruct (to_portable value) as [converted|] eqn:Converted; try discriminate;
   apply fitting_portable_does_not_increase_width in Fitted;
   unfold to_portable, portable_source in Converted; rewrite Source in Converted;
   destruct (scalar_fragments (TextJson.render_json raw)); cbn [option_map] in Converted;
   try discriminate; injection Converted as <-; exact Fitted.
Qed.

Lemma resize_reduces_width_or_fails : forall value,
 (exists smaller, resize value = Next smaller /\
   compaction_chunk_chars smaller < compaction_chunk_chars value) \/
 (exists reason, resize value = Failed reason).
Proof.
 intros value; unfold resize.
 destruct (1 <? compaction_chunk_chars value) eqn:Reducible.
 - destruct (to_portable value) as [converted|].
   + left; eexists; split; [reflexivity|].
     cbn [with_width set compaction_chunk_chars].
     apply N.div_lt; apply N.ltb_lt in Reducible; lia.
   + right; eexists; reflexivity.
 - right; eexists; reflexivity.
Qed.

Theorem native_unavailable_preserves_full_history_for_summary :
 forall history raw carry width window reserve,
 receive (CompactionState (NativeSource history raw) carry width window reserve)
   (JObject [("action", JString "native_unavailable")]) =
 Next (CompactionState (StructuredSource history raw) carry width window reserve).
Proof. reflexivity. Qed.
