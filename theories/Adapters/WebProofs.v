From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Import Common WebCommon WebResources WebStore WebContinuation Web Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Lemma accepted_resource_has_admission : forall source value,
  WebResources.resource source = success value -> resource_admissible source = true.
Proof.
  intros source value H;unfold WebResources.resource in H.
  destruct (resource_admissible source) eqn:A;[reflexivity|].
  destruct (negb (resource_identity source && same_model_request source));[discriminate|].
  destruct (parse_status (str (get source "value") "status")) as [status|];[destruct status|];
    repeat match type of H with context [if ?b then _ else _] => destruct b end;discriminate.
Qed.

Theorem public_resource_acceptance_requires_identity_request_authority_and_batch : forall source value,
  Api.call "web.resource" source = success value ->
  resource_identity source = true /\ same_model_request source = true /\
  authority (get source "value") = true /\ declared_batch source = true.
Proof.
  intros source value H.
  change ((if base_source source && any_source source then WebResources.resource source
    else err "Invalid ChatGPT Web JSON source") = success value) in H.
  destruct (base_source source && any_source source);[|discriminate].
  apply accepted_resource_has_admission in H;unfold resource_admissible in H.
  repeat rewrite andb_true_iff in H;tauto.
Qed.

Theorem public_admitted_resource_is_returned : forall source,
  base_source source = true -> resource_identity source = true -> same_model_request source = true ->
  authority (get source "value") = true -> declared_batch source = true ->
  Api.call "web.resource" source = success (get source "value").
Proof.
  intros source B I R A C.
  change ((if base_source source && any_source source then WebResources.resource source
    else err "Invalid ChatGPT Web JSON source") = success (get source "value")).
  unfold any_source;rewrite B;cbn;unfold WebResources.resource,resource_admissible;now rewrite I,R,A,C.
Qed.

Theorem public_raw_json_parse_preserves_value : forall source value,
  base_source source = true -> strings source ["text"] = true ->
  TextJson.parse_json (str source "text") = Some value ->
  Api.call "web.decode" source = success value.
Proof.
 intros source value B S P.
 change ((if base_source source && strings source ["text"] then decode_text (str source "text")
   else err "Invalid ChatGPT Web JSON source") = success value).
 rewrite B,S;cbn;unfold decode_text;now rewrite P.
Qed.
Theorem public_invalid_raw_json_is_rejected : forall source,
  base_source source = true -> strings source ["text"] = true ->
  TextJson.parse_json (str source "text") = None ->
  domain_json_failure (str source "text") = false ->
  Api.call "web.decode" source = failure "SyntaxError" "Invalid ChatGPT Web JSON".
Proof.
 intros source B S P D.
 change ((if base_source source && strings source ["text"] then decode_text (str source "text")
   else err "Invalid ChatGPT Web JSON source") = failure "SyntaxError" "Invalid ChatGPT Web JSON").
 rewrite B,S;cbn;unfold decode_text;now rewrite P,D.
Qed.
Theorem public_invalid_domain_json_is_rejected : forall source,
  base_source source = true -> strings source ["text"] = true ->
  TextJson.parse_json (str source "text") = None ->
  domain_json_failure (str source "text") = true ->
  Api.call "web.decode" source = err "Invalid ChatGPT Web JSON: duplicate object field or malformed Unicode".
Proof.
 intros source B S P D.
 change ((if base_source source && strings source ["text"] then decode_text (str source "text")
   else err "Invalid ChatGPT Web JSON source") = err "Invalid ChatGPT Web JSON: duplicate object field or malformed Unicode").
 rewrite B,S;cbn;unfold decode_text;now rewrite P,D.
Qed.
Theorem public_successful_invalid_http_json_reports_protocol_error : forall source,
  base_source source = true ->
  objects source ["response"] && Json.is_bool (get (get source "response") "ok") &&
    natural (get (get source "response") "status") && strings source ["text"] = true ->
  TextJson.parse_json_members (str source "text") = None -> boolean_field (get source "response") "ok" = true ->
  Api.call "web.http_json" source = failure "http_json_parse" "The service returned invalid JSON".
Proof.
 intros source B S P O.
 change ((if base_source source && (objects source ["response"] && Json.is_bool (get (get source "response") "ok") &&
    natural (get (get source "response") "status") && strings source ["text"]) then WebResources.http_json source
    else err "Invalid ChatGPT Web JSON source") = failure "http_json_parse" "The service returned invalid JSON").
 rewrite B,S;cbn;unfold WebResources.http_json;now rewrite P,O.
Qed.

Theorem public_response_identity_cannot_change : forall source,
  base_source source = true -> objects source ["record";"current"] = true ->
  identity (get source "id") = true -> truthy (get (get source "current") "response_id") = true ->
  same (get (get source "current") "response_id") (get source "id") = false ->
  Api.call "web.store_identify" source = err "ChatGPT Web changed the response identity".
Proof.
 intros source B S I P D.
 change ((if base_source source && objects source ["record";"current"] then store_identify source
   else err "Invalid ChatGPT Web JSON source") = err "ChatGPT Web changed the response identity").
 rewrite B,S;cbn;unfold store_identify;now rewrite I,P,D.
Qed.
Theorem public_existing_request_reuse_requires_body_and_connection : forall source value,
  truthy (get source "record") = true -> retired_as Active (get source "record") = true ->
  Api.call "web.store_prepare" source = prepare_decision "reuse" value -> prepare_identity source = true.
Proof.
 intros source value R A H.
 change ((if base_source source && (objects source ["request"] && is_object (get (get source "request") "body") && strings source ["new_key"])
   then store_prepare source else err "Invalid ChatGPT Web JSON source") = prepare_decision "reuse" value) in H.
 destruct (base_source source && (objects source ["request"] && is_object (get (get source "request") "body") && strings source ["new_key"]));[|discriminate].
 unfold store_prepare in H;rewrite R,A in H;cbn in H.
 destruct (prepare_identity source) eqn:I;[reflexivity|discriminate].
Qed.
Theorem public_cancelled_request_cannot_reuse_a_different_connection : forall source,
  base_source source = true -> continuation_source source = true ->
  truthy (get (get (get source "effect") "model") "adaptive_reasoning") = false ->
  configuration_reset source = false -> cancelled source = true ->
  same (get (get source "previous") "binding") (get source "binding") = false ->
  Api.call "web.continuation" source = err "The cancelled ChatGPT Web request belongs to a different connection".
Proof.
 intros source B S A R C D.
 change ((if base_source source && continuation_source source then
   WebContinuation.continuation BackendRequests.structured_text source else err "Invalid ChatGPT Web JSON source") =
   err "The cancelled ChatGPT Web request belongs to a different connection").
 rewrite B,S;cbn;unfold WebContinuation.continuation;now rewrite A,R,C,D.
Qed.
Theorem public_tool_continuation_requires_complete_unique_result_batch : forall source value,
  truthy (get (get (get source "effect") "model") "adaptive_reasoning") = false ->
  configuration_reset source || negb (cancelled source) || same (get (get source "previous") "binding") (get source "binding") = true ->
  continuation_owner source = true -> continuation_binding source = true -> continuation_span source = true ->
  eq (continuation_receipt source) "status" "completed" = false ->
  eq (continuation_receipt source) "status" "requires_action" = true ->
  Api.call "web.continuation" source = success value ->
  continuation_batch_matches source = true /\ continuation_batch_complete source = true.
Proof.
 intros source value A C O B S N R H.
 change ((if base_source source && continuation_source source then
   WebContinuation.continuation BackendRequests.structured_text source else err "Invalid ChatGPT Web JSON source") = success value) in H.
 destruct (base_source source && continuation_source source);[|discriminate].
 unfold WebContinuation.continuation in H;rewrite A,C,O,B,S,N,R in H.
 destruct (continuation_batch_matches source && continuation_batch_complete source) eqn:E;[now apply andb_true_iff|discriminate].
Qed.
Theorem public_empty_existing_receipt_database_is_rejected : forall identity,
  Utf8.well_formed identity = true ->
  Api.call "web.store_metadata" (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool false)]) = metadata_error.
Proof.
 intros identity H.
 change ((if base_source (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool false)]) &&
  metadata_source (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool false)])
  then metadata_error else err "Invalid ChatGPT Web JSON source") = metadata_error).
 unfold base_source;cbn -[Utf8.well_formed];rewrite H;reflexivity.
Qed.
Theorem public_new_receipt_database_is_initialized : forall identity,
  Utf8.well_formed identity = true ->
  Api.call "web.store_metadata" (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool true)]) =
  success (JObject [("create",JBool true);("identity",JString identity);("format",JString current_format)]).
Proof.
 intros identity H.
 change ((if base_source (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool true)]) &&
  metadata_source (JObject [("rows",JArray []);("new_identity",JString identity);("created",JBool true)])
  then success (JObject [("create",JBool true);("identity",JString identity);("format",JString current_format)]) else err "Invalid ChatGPT Web JSON source") =
  success (JObject [("create",JBool true);("identity",JString identity);("format",JString current_format)])).
 unfold base_source;cbn -[Utf8.well_formed];rewrite H;reflexivity.
Qed.

Theorem public_receipt_is_bound_to_actual_task_connection_and_response : forall source value,
  Api.call "web.receipt" source = success value ->
  eq (get source "effect") "kind" "model" = true /\
  same (get (get source "record") "owner") (owner_value (get source "effect")) = true /\
  same (get (get source "record") "binding") (get source "binding") = true /\
  same (get (get source "record") "response_id") (get (get source "resource") "id") = true.
Proof.
 intros source value H.
 change ((if base_source source && receipt_source source then WebContinuation.receipt source
   else err "Invalid ChatGPT Web JSON source") = success value) in H.
 destruct (base_source source && receipt_source source) eqn:A;[|discriminate].
 apply andb_true_iff in A as [_ A];unfold receipt_source in A.
 repeat rewrite andb_true_iff in A;tauto.
Qed.

Theorem public_successful_sse_eof_has_no_unfinished_line_or_data : forall source value,
  Api.call "web.sse_step" source = success value ->
  boolean_field source "eof" = true -> get value "error" = JNull ->
  str (get source "state") "pending" ++ str source "chunk" = "" /\
  List.length (items (get (get source "state") "data")) = 0%nat.
Proof.
 intros source value H E F.
 change ((if base_source source && stream_source source then WebStream.sse_step source
   else err "Invalid ChatGPT Web JSON source") = success value) in H.
 destruct (base_source source && stream_source source);[|discriminate].
 unfold WebStream.sse_step in H;rewrite E in H.
 destruct (String.eqb (WebStream.pending (WebStream.read_state (get source "state")) ++ str source "chunk") "" &&
   Nat.eqb (List.length (WebStream.event_data (WebStream.read_state (get source "state")))) 0) eqn:A.
 - apply andb_true_iff in A as [P D].
   apply String.eqb_eq in P;apply Nat.eqb_eq in D;split;[exact P|].
   unfold WebStream.read_state in D;cbn in D;now rewrite length_map in D.
 - unfold WebStream.work_json in H;cbn in H;inversion H;subst value;discriminate F.
Qed.


Theorem production_sse_scanner_is_independent_of_feed_boundaries : forall first second reversed bytes work maximum,
  WebStream.scan (List.app first second) reversed bytes work maximum =
    let '(next_reversed,next_bytes,next_work) := WebStream.scan first reversed bytes work maximum in
    WebStream.scan second next_reversed next_bytes next_work maximum.
Proof.
 intros;unfold WebStream.scan;rewrite fold_left_app.
 destruct (fold_left (WebStream.scan_character maximum) first (reversed,bytes,work)) as [[r b] w];reflexivity.
Qed.

Theorem public_receipt_metadata_uses_one_current_format : forall source value,
  Api.call "web.store_metadata" source = success value ->
  get value "format" = JString current_format /\
  forall row, In row (items (get source "rows")) -> eq row "format" current_format = true.
Proof.
  intros source value accepted.
  change ((if base_source source && metadata_source source then store_metadata source
    else err "Invalid ChatGPT Web JSON source") = success value) in accepted.
  destruct (base_source source && metadata_source source); [|discriminate].
  unfold store_metadata in accepted.
  destruct (items (get source "rows")) as [|row rest] eqn:rows.
  - destruct (boolean_field source "created"); [|discriminate].
    inversion accepted; subst. split; [reflexivity|]. intros item member. inversion member.
  - destruct rest as [|next rest]; [|discriminate].
    destruct (is_text (get row "format") && eq row "format" current_format && WebCommon.nonempty (get row "identity")) eqn:admitted; [|discriminate].
    inversion accepted; subst. split; [reflexivity|].
    intros item member. cbn in member. destruct member as [<-|[]].
    now apply Bool.andb_true_iff in admitted as [admitted _]; apply Bool.andb_true_iff in admitted as [_ admitted].
Qed.


(** The scanner carries a local byte count only while consuming a chunk.  Its
    relation to the actual reversed bytes lets the public result inherit the
    configured line limit without trusting a serialized counter. *)
Definition sse_buffer_within maximum (buffer : (list Ascii.ascii * N) * WebStream.stream_work) :=
 let '(reversed,bytes,work) := buffer in
 N.of_nat (List.length reversed) = bytes /\
 (WebStream.stream_error work = "" -> bytes <= maximum).
Local Lemma encoded_string_length : forall value,
 List.length (list_ascii_of_string value) = String.length value.
Proof. induction value;cbn;congruence. Qed.
Local Lemma decoded_string_length : forall bytes,
 String.length (string_of_list_ascii bytes) = List.length bytes.
Proof. induction bytes;cbn;congruence. Qed.
Local Lemma reversed_bytes_length : forall (bytes reversed : list Ascii.ascii),
 List.length (fold_left (fun result byte => byte :: result) bytes reversed) =
 (List.length bytes + List.length reversed)%nat.
Proof.
 induction bytes as [|byte bytes IH];intros reversed;cbn;[reflexivity|].
 rewrite IH;cbn;lia.
Qed.
Lemma sse_character_preserves_line_budget : forall maximum buffer character,
 sse_buffer_within maximum buffer ->
 sse_buffer_within maximum (WebStream.scan_character maximum buffer character).
Proof.
 intros maximum [[reversed bytes] work] [code character] [consistent bounded].
 unfold WebStream.scan_character;cbn.
 destruct (negb (String.eqb (WebStream.stream_error work) "")) eqn:failed.
 - split;assumption.
 - destruct (String.eqb character "
") eqn:newline.
   + destruct (String.eqb (WebStream.stream_error
       (WebStream.process_line (string_of_list_ascii (rev_append reversed [])) work maximum)) "") eqn:accepted.
     * split;[reflexivity|intros _;apply N.le_0_l].
     * split;[exact consistent|intros empty;apply String.eqb_neq in accepted;contradiction].
   + destruct (bytes + N.of_nat (String.length character) <=? maximum) eqn:within;
       unfold sse_buffer_within;cbn;split.
     * rewrite reversed_bytes_length,encoded_string_length,Nat2N.inj_add,consistent;apply N.add_comm.
     * intros _;now apply N.leb_le in within.
     * rewrite reversed_bytes_length,encoded_string_length,Nat2N.inj_add,consistent;apply N.add_comm.
     * discriminate.
Qed.
Lemma sse_scan_preserves_line_budget : forall characters maximum reversed bytes work,
 sse_buffer_within maximum (reversed,bytes,work) ->
 sse_buffer_within maximum (WebStream.scan characters reversed bytes work maximum).
Proof.
 induction characters as [|character characters IH];intros maximum reversed bytes work within;[exact within|].
 unfold WebStream.scan;cbn [fold_left].
 destruct (WebStream.scan_character maximum (reversed,bytes,work) character) as [[next bytes'] work'] eqn:step.
 change (sse_buffer_within maximum (WebStream.scan characters next bytes' work' maximum)).
 apply IH;rewrite <- step;now apply sse_character_preserves_line_budget.
Qed.
Lemma sse_initial_line_budget : forall state maximum,
 let initial := WebStream.StreamWork state [] "" in
 let admitted := if N.of_nat (String.length (WebStream.pending state)) <=? maximum
   then initial else WebStream.stream_fail initial "SSE line exceeds the configured limit" in
 sse_buffer_within maximum
   (fold_left (fun result byte => byte :: result) (list_ascii_of_string (WebStream.pending state)) [],
    N.of_nat (String.length (WebStream.pending state)),admitted).
Proof.
 intros state maximum;unfold sse_buffer_within.
 destruct (N.of_nat (String.length (WebStream.pending state)) <=? maximum) eqn:within;cbn;split.
 - rewrite reversed_bytes_length,encoded_string_length,Nat.add_0_r;reflexivity.
 - intros _;now apply N.leb_le in within.
 - rewrite reversed_bytes_length,encoded_string_length,Nat.add_0_r;reflexivity.
 - discriminate.
Qed.

Theorem production_successful_sse_step_respects_line_byte_limit : forall source value,
 WebStream.sse_step source = success value ->
 boolean_field source "eof" = false -> get value "error" = JNull ->
 N.of_nat (String.length (str (get value "state") "pending")) <= num source "maximum".
Proof.
 intros source value accepted eof no_error.
 unfold WebStream.sse_step in accepted;rewrite eof in accepted.
 destruct (Utf8.chunks (str source "chunk")) as [characters|] eqn:characters_valid;[|discriminate].
 pose proof (sse_initial_line_budget (WebStream.read_state (get source "state")) (num source "maximum")) as initial.
 pose proof (sse_scan_preserves_line_budget characters _ _ _ _ initial) as scanned.
 destruct (WebStream.scan characters
   (fold_left (fun result byte => byte :: result) (list_ascii_of_string (WebStream.pending (WebStream.read_state (get source "state")))) [])
   (N.of_nat (String.length (WebStream.pending (WebStream.read_state (get source "state")))))
   (if N.of_nat (String.length (WebStream.pending (WebStream.read_state (get source "state")))) <=? num source "maximum"
     then WebStream.StreamWork (WebStream.read_state (get source "state")) [] ""
     else WebStream.stream_fail (WebStream.StreamWork (WebStream.read_state (get source "state")) [] "") "SSE line exceeds the configured limit")
   (num source "maximum")) as [[reversed bytes] work] eqn:scan_result.
 unfold sse_buffer_within in scanned;destruct scanned as [consistent bounded].
 unfold WebStream.work_json in accepted;cbn in accepted.
 destruct (String.eqb (WebStream.stream_error work) "") eqn:empty_error.
 - apply String.eqb_eq in empty_error.
   inversion accepted;subst value;cbn.
   rewrite decoded_string_length,rev_append_rev,List.app_nil_r,length_rev,consistent.
   now apply bounded.
 - inversion accepted;subst value;discriminate no_error.
Qed.

Theorem public_successful_sse_step_respects_line_byte_limit : forall source value,
 Api.call "web.sse_step" source = success value ->
 boolean_field source "eof" = false -> get value "error" = JNull ->
 N.of_nat (String.length (str (get value "state") "pending")) <= num source "maximum".
Proof.
 intros source value accepted eof no_error.
 change ((if base_source source && stream_source source then WebStream.sse_step source
   else err "Invalid ChatGPT Web JSON source") = success value) in accepted.
 destruct (base_source source && stream_source source);[|discriminate].
 eapply production_successful_sse_step_respects_line_byte_limit;eassumption.
Qed.

Theorem public_sse_eof_rejects_unfinished_event : forall source value,
 Api.call "web.sse_step" source = success value -> boolean_field source "eof" = true ->
 (str (get source "state") "pending" ++ str source "chunk" <> "" \/
  items (get (get source "state") "data") <> []) ->
 get value "error" = JString "The SSE stream ended inside an event".
Proof.
 intros source value accepted eof unfinished.
 change ((if base_source source && stream_source source then WebStream.sse_step source
   else err "Invalid ChatGPT Web JSON source") = success value) in accepted.
 destruct (base_source source && stream_source source);[|discriminate].
 unfold WebStream.sse_step in accepted;rewrite eof in accepted.
 destruct (String.eqb (WebStream.pending (WebStream.read_state (get source "state")) ++ str source "chunk") "" &&
   Nat.eqb (List.length (WebStream.event_data (WebStream.read_state (get source "state")))) 0) eqn:complete.
 - apply andb_true_iff in complete as [pending data].
   apply String.eqb_eq in pending;apply Nat.eqb_eq in data.
   unfold WebStream.read_state in pending,data;cbn in pending,data.
   rewrite length_map in data;apply length_zero_iff_nil in data;tauto.
 - inversion accepted;subst value;reflexivity.
Qed.
Theorem public_clean_sse_eof_emits_no_frame_or_error : forall source,
 base_source source = true -> stream_source source = true -> boolean_field source "eof" = true ->
 str (get source "state") "pending" = "" -> str source "chunk" = "" ->
 items (get (get source "state") "data") = [] ->
 Api.call "web.sse_step" source = success (JObject
   [("state",WebStream.write_state (WebStream.read_state (get source "state")));("frames",JArray [])]).
Proof.
 intros source base admitted eof pending chunk data.
 change ((if base_source source && stream_source source then WebStream.sse_step source
   else err "Invalid ChatGPT Web JSON source") = success (JObject
   [("state",WebStream.write_state (WebStream.read_state (get source "state")));("frames",JArray [])])).
 rewrite base,admitted;cbn;unfold WebStream.sse_step;rewrite eof.
 unfold WebStream.read_state;cbn;rewrite pending,chunk,data;reflexivity.
Qed.
