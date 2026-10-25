From Stdlib Require Import String Ascii List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Kernel Require Import Domain Inputs ApprovalProtocol Observation.
From Selvedge.Adapters Require Import Common BackendHistory BackendRequests.
Import ListNotations.
Open Scope string_scope.
Local Lemma string_append_empty : forall text, text ++ "" = text.
Proof. induction text; cbn; congruence. Qed.
Local Lemma string_append_assoc : forall first second third,
 (first ++ second) ++ third = first ++ (second ++ third).
Proof. induction first; cbn; intros; congruence. Qed.
Local Definition utf8_continuation (character : ascii) :=
 (128 <=? Utf8.byte character)%N && (Utf8.byte character <? 192)%N.
Inductive continuation_bytes : string -> Prop :=
 | continuations_empty : continuation_bytes ""
 | continuations_cons : forall c rest, utf8_continuation c = true ->
   continuation_bytes rest -> continuation_bytes (String c rest).
Local Lemma continuation_byte : forall c,
 ((128 <=? Utf8.byte c)%N && (Utf8.byte c <=? 191)%N) = true ->
 utf8_continuation c = true.
Proof. intros c H; unfold utf8_continuation; apply andb_true_iff in H; apply andb_true_iff; split; try tauto.
 apply N.ltb_lt; destruct H as [_ H]; apply N.leb_le in H; lia. Qed.
Local Lemma continuation_shape : forall count value prefix source result,
 Utf8.continuation count value prefix source = Some result ->
 exists suffix, source = suffix ++ Utf8.remaining result /\
 Utf8.encoded result = prefix ++ suffix /\ continuation_bytes suffix /\
 (forall rest, Utf8.continuation count value prefix (suffix ++ rest) =
 Some (Utf8.Decoded (Utf8.scalar result) (Utf8.encoded result) rest)).
Proof.
 induction count as [|count IH]; intros value prefix source result H; cbn in H.
 - inversion H; subst; exists ""; cbn; rewrite string_append_empty; repeat split; try constructor; reflexivity.
 - destruct source as [|c rest]; try discriminate.
   destruct ((128 <=? Utf8.byte c)%N && (Utf8.byte c <=? 191)%N) eqn:Byte; try discriminate.
   destruct (IH _ _ _ _ H) as [suffix [Source [Encoded [Bytes Replay]]]].
   exists (String c suffix); subst rest; split; [reflexivity|].
   split; [rewrite Encoded, string_append_assoc; reflexivity|].
   split; [constructor; auto using continuation_byte|].
   intros final; cbn; rewrite Byte; apply Replay.
Qed.
Local Lemma bounded_decoded : forall minimum maximum source result,
 Utf8.bounded minimum maximum source = Some result -> source = Some result.
Proof. intros minimum maximum [value|] result H; cbn in H; try discriminate.
 destruct (_ && _ && _) eqn:Valid; inversion H; reflexivity. Qed.
Local Lemma decode_shape : forall source result,
 Utf8.decode_one source = Some result ->
 exists head tail, Utf8.encoded result = String head tail /\
 source = Utf8.encoded result ++ Utf8.remaining result /\
 utf8_continuation head = false /\ continuation_bytes tail.
Proof.
 intros [|head rest] result H; [discriminate|].
 unfold Utf8.decode_one in H.
 destruct (Utf8.byte head <? 128)%N eqn:Ascii.
 - inversion H; subst; exists head, ""; cbn; repeat split; try constructor.
   unfold utf8_continuation; apply N.ltb_lt in Ascii.
   assert ((128 <=? Utf8.byte head)%N = false) by (apply N.leb_gt; lia).
   rewrite H0; reflexivity.
 - destruct ((194 <=? Utf8.byte head)%N && (Utf8.byte head <=? 223)%N) eqn:Two;
   [|destruct ((224 <=? Utf8.byte head)%N && (Utf8.byte head <=? 239)%N) eqn:Three;
     [|destruct ((240 <=? Utf8.byte head)%N && (Utf8.byte head <=? 244)%N) eqn:Four;
       [|discriminate]]].
   all: apply bounded_decoded in H; apply continuation_shape in H.
   all: destruct H as [tail [Source [Encoded [Bytes Replay]]]]; exists head, tail; cbn in Encoded.
   all: split; [exact Encoded|]; split; [rewrite Encoded, Source; reflexivity|]; split; [|exact Bytes].
   all: unfold utf8_continuation; repeat match goal with H : (_ && _)%bool = true |- _ => apply andb_true_iff in H; destruct H end.
   all: repeat match goal with H : N.leb _ _ = true |- _ => apply N.leb_le in H end.
   all: destruct (Utf8.byte head <? 192)%N eqn:Boundary; [apply N.ltb_lt in Boundary; lia|apply andb_false_r].
Qed.

Local Lemma decode_replay : forall source result,
 Utf8.decode_one source = Some result -> forall rest,
 Utf8.decode_one (Utf8.encoded result ++ rest) =
 Some (Utf8.Decoded (Utf8.scalar result) (Utf8.encoded result) rest).
Proof.
 intros [|head source] result H rest; [discriminate|].
 unfold Utf8.decode_one in H.
 destruct (Utf8.byte head <? 128)%N eqn:Ascii.
 - inversion H; subst; cbn; rewrite Ascii; reflexivity.
 - destruct ((194 <=? Utf8.byte head)%N && (Utf8.byte head <=? 223)%N) eqn:Two;
   [|destruct ((224 <=? Utf8.byte head)%N && (Utf8.byte head <=? 239)%N) eqn:Three;
     [|destruct ((240 <=? Utf8.byte head)%N && (Utf8.byte head <=? 244)%N) eqn:Four;
       [|discriminate]]].
   all: pose proof H as Parsed; apply bounded_decoded in Parsed.
   all: pose proof Parsed as ParsedShape; apply continuation_shape in ParsedShape; destruct ParsedShape as [tail [Source [Encoded [Bytes Replay]]]].
   all: rewrite Encoded; cbn [String.append Utf8.decode_one]; rewrite Ascii.
   all: rewrite Two; try rewrite Three; try rewrite Four.
   all: specialize (Replay rest); rewrite Encoded in Replay; cbn [String.append] in Replay; rewrite Replay.
   all: unfold Utf8.bounded in H; rewrite Parsed in H; cbn in H.
   all: cbn [Utf8.bounded Utf8.scalar Utf8.encoded]; cbn in Encoded; rewrite <- Encoded.
   all: destruct (_ && _ && _) eqn:Valid; [reflexivity|discriminate].
Qed.
Local Lemma string_append_length : forall first second,
 String.length (first ++ second) = (String.length first + String.length second)%nat.
Proof. induction first; cbn; intros; congruence. Qed.

Inductive decoded_scalars : string -> nat -> Prop :=
 | decoded_empty : decoded_scalars "" 0
 | decoded_next : forall source result count,
   Utf8.decode_one source = Some result ->
   decoded_scalars (Utf8.remaining result) count -> decoded_scalars source (S count).
Local Lemma decoded_scalars_byte_bound : forall source count,
 decoded_scalars source count -> (count <= String.length source)%nat.
Proof.
 intros source count Parsed; induction Parsed; [cbn; lia|].
 destruct (decode_shape _ _ H) as [head [tail [Encoded [Source _]]]].
 rewrite Source, string_append_length, Encoded; cbn; lia.
Qed.
Local Lemma decoded_scalars_computations : forall source count,
 decoded_scalars source count -> forall fuel offset, (count <= fuel)%nat ->
 Utf8.validate_fuel fuel source = true /\
 Utf8.count_fuel fuel source offset = Some (count + offset)%nat.
Proof.
 intros source count Parsed; induction Parsed as [|source result count Parsed Rest IH]; intros fuel offset Enough; [destruct fuel; cbn; auto|].
 destruct source; [discriminate Parsed|]; destruct fuel; [lia|]; cbn [Utf8.validate_fuel Utf8.count_fuel].
 rewrite Parsed; specialize (IH fuel (S offset) ltac:(lia)); destruct IH as [Valid Count].
 split; [exact Valid|]; rewrite Count; f_equal; lia.
Qed.
Local Lemma well_formed_decoded_scalars : forall source,
 Utf8.well_formed source = true -> exists count, decoded_scalars source count.
Proof.
 unfold Utf8.well_formed; intros source; generalize (Utf8.byte_length source).
 intros fuel; revert source; induction fuel as [|fuel IH]; intros [|head rest] Valid.
 - exists 0%nat; constructor.
 - discriminate.
 - exists 0%nat; constructor.
 - cbn [Utf8.validate_fuel] in Valid; destruct (Utf8.decode_one (String head rest)) as [result|] eqn:Parsed; [|discriminate].
   destruct (IH _ Valid) as [count Decoded].
   exists (S count); econstructor; eauto.
Qed.
Local Lemma decoded_scalars_well_formed : forall source count,
 decoded_scalars source count ->
 Utf8.well_formed source = true /\ Utf8.scalar_count source = Some count.
Proof.
 intros source count Parsed; unfold Utf8.well_formed, Utf8.scalar_count.
 pose proof (decoded_scalars_computations _ _ Parsed (String.length source) 0
  (decoded_scalars_byte_bound _ _ Parsed)) as [Valid Count].
 rewrite Nat.add_0_r in Count; auto.
Qed.

Local Lemma excerpt_end_offset : forall source count offset,
 request_excerpt_end count source offset = (offset + request_excerpt_end count source 0)%nat.
Proof.
 induction source as [|head rest IH]; intros count offset; cbn; [lia|].
 destruct (_ && _); [rewrite (IH count (S offset)), (IH count 1%nat); lia|].
 destruct count; [lia|]; rewrite (IH count (S offset)), (IH count 1%nat); lia.
Qed.
Local Lemma excerpt_end_continuations : forall source,
 continuation_bytes source -> forall count rest offset,
 request_excerpt_end count (source ++ rest) offset =
 request_excerpt_end count rest (offset + String.length source).
Proof.
 intros source Bytes; induction Bytes; intros count source offset; cbn.
 - rewrite Nat.add_0_r; reflexivity.
 - change (utf8_continuation c) with
   ((128 <=? Utf8.byte c)%N && (Utf8.byte c <? 192)%N) in H.
   rewrite H, IHBytes; f_equal; lia.
Qed.
Local Lemma substring_prefix : forall prefix rest count,
 String.substring 0 (String.length prefix + count) (prefix ++ rest) =
 prefix ++ String.substring 0 count rest.
Proof. induction prefix; intros; cbn; [reflexivity|rewrite IHprefix; reflexivity]. Qed.
Local Lemma excerpt_empty_budget : forall source result,
 Utf8.decode_one source = Some result -> bounded_excerpt 0 source = "".
Proof.
 intros source result Parsed; destruct (decode_shape _ _ Parsed) as [head [tail [Encoded [Source [Leading Bytes]]]]].
 unfold bounded_excerpt; rewrite Source, Encoded; cbn [String.append request_excerpt_end].
 unfold utf8_continuation in Leading; rewrite Leading; reflexivity.
Qed.
Local Lemma excerpt_next_scalar : forall source result count,
 Utf8.decode_one source = Some result ->
 bounded_excerpt (S count) source = Utf8.encoded result ++ bounded_excerpt count (Utf8.remaining result).
Proof.
 intros source result count Parsed; destruct (decode_shape _ _ Parsed) as [head [tail [Encoded [Source [Leading Bytes]]]]].
 unfold bounded_excerpt; rewrite Source; rewrite Encoded at 1.
 cbn [String.append request_excerpt_end].
 unfold utf8_continuation in Leading; rewrite Leading.
 rewrite (excerpt_end_continuations _ Bytes), excerpt_end_offset.
 rewrite Source in Parsed.
 replace (1 + String.length tail + request_excerpt_end count (Utf8.remaining result) 0)%nat
 with (String.length (Utf8.encoded result) + request_excerpt_end count (Utf8.remaining result) 0)%nat
 by (rewrite Encoded; cbn; lia).
 apply substring_prefix.
Qed.
Local Lemma bounded_excerpt_scalars : forall source scalars,
 decoded_scalars source scalars -> forall count,
 exists rest, source = bounded_excerpt count source ++ rest /\
 decoded_scalars (bounded_excerpt count source) (Nat.min count scalars).
Proof.
 intros source scalars Parsed; induction Parsed as [|source result scalars Parsed Rest IH]; intros count.
 - exists ""; destruct count; cbn [bounded_excerpt request_excerpt_end String.substring Nat.min]; auto using decoded_empty.
 - destruct count as [|count].
   + rewrite (excerpt_empty_budget _ _ Parsed); exists source; split; [reflexivity|constructor].
   + rewrite (excerpt_next_scalar _ _ count Parsed).
     destruct (IH count) as [suffix [Source Prefix]].
     exists suffix; split.
     * destruct (decode_shape _ _ Parsed) as [head [tail [_ [Original _]]]].
       rewrite Original; rewrite Source at 1; rewrite string_append_assoc; reflexivity.
     * cbn [Nat.min]; econstructor; [apply (decode_replay source result Parsed)|exact Prefix].
Qed.
Theorem bounded_excerpt_preserves_utf8 : forall source count,
 Utf8.well_formed source = true ->
 exists scalars rest,
 Utf8.scalar_count source = Some scalars /\
 source = bounded_excerpt count source ++ rest /\
 Utf8.well_formed (bounded_excerpt count source) = true /\
 Utf8.scalar_count (bounded_excerpt count source) = Some (Nat.min count scalars).
Proof.
 intros source count Valid; destruct (well_formed_decoded_scalars _ Valid) as [scalars Parsed].
 destruct (bounded_excerpt_scalars _ _ Parsed count) as [rest [Prefix Excerpt]].
 destruct (decoded_scalars_well_formed _ _ Parsed) as [_ Total].
 destruct (decoded_scalars_well_formed _ _ Excerpt) as [Utf8 Count].
 exists scalars, rest; auto.
Qed.
Local Lemma decoded_scalars_append : forall source count,
 decoded_scalars source count -> forall rest extra,
 decoded_scalars rest extra -> decoded_scalars (source ++ rest) (count + extra).
Proof.
 intros source count Parsed; induction Parsed as [|source result count Parsed Rest IH]; intros suffix extra Suffix.
 - exact Suffix.
 - destruct (decode_shape _ _ Parsed) as [head [tail [_ [Source _]]]].
   rewrite Source, string_append_assoc.
   econstructor; [apply (decode_replay source result Parsed)|].
   apply IH; exact Suffix.
Qed.
Theorem plain_text_keeps_admitted_utf8 : forall parts,
 Forall (fun part => match part with TextPart text => Utf8.well_formed text = true | ImagePart _ => True end) parts ->
 Utf8.well_formed (request_plain_text parts) = true.
Proof.
 intros parts Valid; induction Valid as [|part parts Valid Rest IH]; [reflexivity|].
 destruct part as [text|image]; cbn [request_plain_text]; [|exact IH].
 destruct (well_formed_decoded_scalars _ Valid) as [first First].
 destruct (well_formed_decoded_scalars _ IH) as [second Second].
 apply (proj1 (decoded_scalars_well_formed _ _ (decoded_scalars_append _ _ First _ _ Second))).
Qed.
Open Scope list_scope.
Theorem plain_text_omits_images : forall before image after,
 request_plain_text (before ++ ImagePart image :: after) = request_plain_text (before ++ after).
Proof.
 induction before as [|part before IH]; intros; [reflexivity|].
 destruct part; cbn [request_plain_text List.app]; rewrite IH; reflexivity.
Qed.

Definition user_contents (history : list Domain.message) : list content :=
 flat_map (fun item => match item with UserMessage parts => [parts] | _ => [] end) history.
Local Lemma firstn_cons_bounded : forall (A : Type) limit (value : A) rest,
 firstn limit (value :: firstn limit rest) = firstn limit (value :: rest).
Proof.
 intros A [|limit] value rest; [reflexivity|].
 change (value :: firstn limit (firstn (S limit) rest) = value :: firstn limit rest).
 rewrite firstn_firstn, Nat.min_l by lia; reflexivity.
Qed.
Local Lemma bounded_recent_user_contents : forall history limit initial,
 fold_left (fun requests item => match item with
   | UserMessage parts => firstn limit (parts :: requests) | _ => requests end)
 history (firstn limit initial) = firstn limit (rev (user_contents history) ++ initial).
Proof.
 induction history as [|item history IH]; intros limit initial.
 - cbn [fold_left user_contents flat_map rev]; reflexivity.
 - destruct item; cbn [fold_left user_contents flat_map List.app] in *; try apply IH.
   rewrite firstn_cons_bounded, IH; cbn [rev]; rewrite <- app_assoc; cbn [List.app].
   reflexivity.
Qed.
Theorem user_requests_are_latest_text_excerpts : forall history,
 user_requests history = map (fun parts => JString (request_excerpt (request_plain_text parts)))
 (firstn request_limit (rev (user_contents history))).
Proof.
 intros history; unfold user_requests.
 change [] with (firstn request_limit ([] : list content)).
 rewrite bounded_recent_user_contents, app_nil_r; reflexivity.
Qed.
Theorem user_requests_bounded : forall history,
 (List.length (user_requests history) <= request_limit)%nat.
Proof. intros; rewrite user_requests_are_latest_text_excerpts, length_map; apply firstn_le_length. Qed.

Theorem user_requests_preserve_admitted_text : forall history,
 Forall (fun parts => Forall (fun part => match part with
   | TextPart text => Utf8.well_formed text = true | ImagePart _ => True end) parts)
   (user_contents history) ->
 Forall (fun value => exists text scalars,
   value = JString text /\ Utf8.well_formed text = true /\
   Utf8.scalar_count text = Some scalars /\ (scalars <= request_scalars)%nat)
   (user_requests history).
Proof.
 intros history Admitted; rewrite user_requests_are_latest_text_excerpts.
 apply Forall_forall; intros value Selected; apply in_map_iff in Selected.
 destruct Selected as [parts [Value Selected]].
 assert (Present : In parts (rev (user_contents history))).
 { rewrite <- (firstn_skipn request_limit (rev (user_contents history))).
   apply in_or_app; left; exact Selected. }
 apply in_rev in Present.
 apply Forall_forall with (x:=parts) in Admitted; [|exact Present].
 pose proof (plain_text_keeps_admitted_utf8 _ Admitted) as Valid.
 destruct (bounded_excerpt_preserves_utf8 _ request_scalars Valid)
   as [total [suffix [_ [_ [Utf8 Count]]]]].
 exists (request_excerpt (request_plain_text parts)), (Nat.min request_scalars total).
 split; [symmetry; exact Value|]; split; [exact Utf8|]; split; [exact Count|apply Nat.le_min_l].
Qed.

(** The final effect and provider preparation consume this same construction.
    HTTP tests cover the external transport after this pure boundary. *)
Theorem approval_effect_uses_latest_text_excerpts : forall state owner ticket profile call task,
 field "user_requests" (Observation.effect_json state (State.RequestApproval owner ticket profile call task)) =
 Some (JArray (map (fun parts => JString (request_excerpt (request_plain_text parts)))
   (firstn request_limit (rev (user_contents (task_history task)))))).
Proof.
 intros; rewrite <- user_requests_are_latest_text_excerpts; reflexivity.
Qed.
Theorem approval_effect_carries_bounded_admitted_text : forall state owner ticket profile call task,
 Forall (fun parts => Forall (fun part => match part with
   | TextPart text => Utf8.well_formed text = true | ImagePart _ => True end) parts)
   (user_contents (task_history task)) ->
 field "user_requests" (Observation.effect_json state (State.RequestApproval owner ticket profile call task)) =
   Some (JArray (user_requests (task_history task))) /\
 (List.length (user_requests (task_history task)) <= request_limit)%nat /\
 Forall (fun value => exists text scalars,
   value = JString text /\ Utf8.well_formed text = true /\
   Utf8.scalar_count text = Some scalars /\ (scalars <= request_scalars)%nat)
   (user_requests (task_history task)).
Proof.
 intros; split; [reflexivity|]; split;
 [apply user_requests_bounded|apply user_requests_preserve_admitted_text; assumption].
Qed.
Theorem reviewer_request_uses_approval_excerpts : forall state owner ticket profile call task,
 let effect := Observation.effect_json state (State.RequestApproval owner ticket profile call task) in
 Common.get (BackendRequests.independent_effect effect) "history" =
 JArray [BackendHistory.message "user" (JString (TextJson.render_json (JObject [
   ("task_id",Common.get effect "task_id"); ("request_id",Common.get effect "ticket");
   ("command",Common.get effect "call"); ("task_settings",Common.get effect "settings");
   ("recent_user_requests_newest_first",JArray (user_requests (task_history task)));
   ("context_boundary",JString "Only the latest four user requests, each limited to 4096 characters; older requests and other task data are omitted.")])))] .
Proof. intros; reflexivity. Qed.
