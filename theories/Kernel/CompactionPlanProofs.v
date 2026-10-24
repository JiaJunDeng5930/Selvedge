From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json SequenceProofs.
From Selvedge.Kernel Require Import Compaction CompactionPlan ContextSelection Numbers.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem an_unfinished_summary_keeps_every_unread_scalar : forall unread cursor carry width window reserve head tail usage remaining,
 skipn (N.to_nat width) unread = remaining -> remaining <> [] ->
 receive (CompactionState (PortableSource unread) cursor carry width window reserve)
  (JObject [("summary_text",JString (String head tail));("usage",usage)]) =
 Next (CompactionState (PortableSource remaining)
  (cursor + N.of_nat (List.length (firstn (N.to_nat width) unread))) (String head tail) width window reserve).
Proof.
 intros. unfold receive,receive_source. cbn. rewrite H. destruct remaining; [contradiction|].
 unfold chunk. rewrite take_equals_firstn. reflexivity.
Qed.

Theorem a_finished_summary_publishes_its_returned_continuation :
 forall unread cursor carry width window reserve head tail usage,
 skipn (N.to_nat width) unread = [] ->
 receive (CompactionState (PortableSource unread) cursor carry width window reserve)
  (JObject [("summary_text",JString (String head tail));("usage",usage)]) =
 Compacted (PortableArtifact (PortableMessage PortableAssistant (String head tail)) [] usage).
Proof.
 intros unread cursor carry width window reserve head tail usage Finished.
 unfold receive, receive_source. cbn. now rewrite Finished.
Qed.
Theorem an_opaque_reply_cannot_finish_portable_work : forall unread cursor carry width window reserve scope items,
 receive (CompactionState (PortableSource unread) cursor carry width window reserve)
  (JObject [("format",JString "native");("scope",JString scope);("items",JArray items)]) =
 Failed "The compactor returned an empty continuation note".
Proof. reflexivity. Qed.
Theorem an_admitted_plan_fits_its_byte_allocation : forall value budget,
 transport_fits value budget = true -> plan_bytes value <= budget /\ has_transport_work value = true.
Proof.
 intros. apply andb_true_iff in H as [work fits]. apply N.leb_le in fits. auto.
Qed.

Theorem native_start_retains_history_and_rebuild_material :
 forall history raw input_tokens window reserve,
 contains_image history = false -> contains_image raw = false ->
 input_tokens + reserve <= window ->
 start history raw "chatgpt" Automatic input_tokens window reserve =
 Some (CompactionState (NativeSource history raw) 0 "" window window reserve).
Proof.
 intros history raw input_tokens window reserve NoHistoryImage NoRawImage Fits.
 unfold start. rewrite NoHistoryImage, NoRawImage. cbn.
 assert (Budget : (input_tokens + reserve <=? window) = true).
 { apply N.leb_le. exact Fits. }
 now rewrite Budget.
Qed.

Theorem images_force_portable_rebuilding : forall history raw provider method input_tokens window reserve,
 contains_image history || contains_image raw = true ->
 start history raw provider method input_tokens window reserve =
 to_portable (CompactionState (NativeSource history raw) 0 "" window window reserve).
Proof.
 intros history raw provider method input_tokens window reserve HasImage.
 unfold start. rewrite HasImage. reflexivity.
Qed.

Theorem native_rebuilding_uses_raw_history :
 forall history raw cursor carry width window reserve rebuilt,
 to_portable (CompactionState (NativeSource history raw) cursor carry width window reserve) = Some rebuilt ->
 exists fragments,
   scalar_fragments (TextJson.render_json raw) = Some fragments /\
   compaction_source rebuilt = PortableSource fragments.
Proof.
 intros history raw cursor carry width window reserve rebuilt Rebuilt.
 unfold to_portable, portable_source in Rebuilt.
 cbn [compaction_source] in Rebuilt.
 destruct (scalar_fragments (TextJson.render_json raw)) as [parts|] eqn:Parsed;
   try discriminate.
 inversion Rebuilt; subst rebuilt.
 exists parts. split; [reflexivity|reflexivity].
Qed.

Theorem native_plan_transports_only_its_selected_history :
 forall history raw cursor carry width window reserve,
 plan_json (CompactionState (NativeSource history raw) cursor carry width window reserve) =
 JObject [("method", JString "native"); ("window_tokens", number window);
   ("output_reserve_tokens", number reserve); ("history", history)].
Proof. reflexivity. Qed.

Theorem portable_plan_transports_only_bounded_summary_material :
 forall unread cursor carry width window reserve,
 plan_json (CompactionState (PortableSource unread) cursor carry width window reserve) =
 JObject [("method", JString "portable"); ("window_tokens", number window);
   ("output_reserve_tokens", number reserve);
   ("chunk", JString (String.concat "" (chunk (CompactionState (PortableSource unread) cursor carry width window reserve))));
   ("carry", JString carry); ("prompt", JString summary_prompt)].
Proof. reflexivity. Qed.

Theorem a_portable_chunk_is_an_exact_prefix_of_unread_scalars :
 forall unread cursor carry width window reserve,
 chunk (CompactionState (PortableSource unread) cursor carry width window reserve) =
 firstn (N.to_nat width) unread.
Proof.
 intros.
 change (Sequence.take (N.to_nat width) unread = firstn (N.to_nat width) unread).
 apply take_equals_firstn.
Qed.

Theorem rebasing_preserves_the_unread_suffix_in_order :
 forall unread cursor carry width window reserve rebased,
 rebase_note (CompactionState (PortableSource unread) cursor carry width window reserve) = Some rebased ->
 exists prefix,
   scalar_fragments
     ("Prior continuation note:" ++ String (Ascii.ascii_of_nat 10) carry ++
      String (Ascii.ascii_of_nat 10) "Unread task history:" ++
      String (Ascii.ascii_of_nat 10) "") = Some prefix /\
   compaction_source rebased = PortableSource (prefix ++ unread) /\
   compaction_carry rebased = "".
Proof.
 intros unread cursor carry width window reserve rebased Rebased.
 unfold rebase_note in Rebased.
 cbn [compaction_source compaction_carry] in Rebased.
 destruct (scalar_fragments
   ("Prior continuation note:" ++ String (Ascii.ascii_of_nat 10) carry ++
    String (Ascii.ascii_of_nat 10) "Unread task history:" ++
    String (Ascii.ascii_of_nat 10) "")) as [prefix|] eqn:Parsed;
   try discriminate.
 inversion Rebased; subst rebased.
 exists prefix. split; [reflexivity|].
 cbn. split.
 - rewrite List.rev_append_rev, List.rev_append_rev, List.app_nil_r, List.rev_involutive.
   reflexivity.
 - reflexivity.
Qed.

Theorem zero_width_cannot_admit_nonempty_portable_work :
 forall unread carry window reserve budget,
 unread <> [] ->
 transport_fits (CompactionState (PortableSource unread) 0 carry 0 window reserve) budget = false.
Proof.
 intros unread carry window reserve budget Nonempty.
 unfold transport_fits, has_transport_work.
 destruct unread; [contradiction|]. reflexivity.
Qed.

Theorem native_unavailable_recovers_from_raw_history :
 forall history raw cursor carry width window reserve rebuilt,
 to_portable (CompactionState (NativeSource history raw) cursor carry width window reserve) = Some rebuilt ->
 receive (CompactionState (NativeSource history raw) cursor carry width window reserve)
   (JObject [("action", JString "native_unavailable")]) = Next rebuilt.
Proof.
 intros history raw cursor carry width window reserve rebuilt Rebuilt.
 change (match to_portable (CompactionState (NativeSource history raw) cursor carry width window reserve) with
   | Some converted => Next converted
   | None => Failed "Compaction history is not valid UTF-8"
   end = Next rebuilt).
 now rewrite Rebuilt.
Qed.
