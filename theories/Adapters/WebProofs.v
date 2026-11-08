From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Import WebStreamProofs Common WebCommon WebResources WebStore WebContinuation Web.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** These are Web protocol properties of the interpreters supplied to the typed
    operation declarations. Field shape and decoding are owned by that common
    constructor, so each entry needs no separate admission proof. *)
Theorem resource_acceptance_requires_identity_request_authority_and_batch : forall fields model body tools value,
  resource_object fields model body tools = success value ->
  resource_identity fields = true /\ same_model_request fields model body = true /\
  authority fields = true /\ declared_batch fields tools = true.
Proof.
 intros fields model body tools value accepted;unfold resource_object in accepted.
 destruct (resource_admissible fields model body tools) eqn:admitted.
 - unfold resource_admissible in admitted;repeat rewrite andb_true_iff in admitted;tauto.
 - destruct (negb (resource_identity fields && same_model_request fields model body));[discriminate|].
   destruct (parse_status (member_text fields "status")) as [status|];[destruct status|];
     repeat match type of accepted with context [if ?b then _ else _] => destruct b end;discriminate.
Qed.
Theorem invalid_domain_json_is_rejected : forall source,
  parse_provider_json source = None -> domain_json_failure_at (S TextJson.input_nesting) source = true ->
  exists message, decode_provider_text source = err message.
Proof. intros source parsed domain; unfold decode_provider_text; rewrite parsed,domain; eexists; reflexivity. Qed.
Theorem successful_invalid_http_json_reports_protocol_error : forall source,
  TextJson.parse_json_members source = None ->
  exists message, WebResources.http_json true source = failure "http_json_parse" message.
Proof. intros source parsed; unfold WebResources.http_json; rewrite parsed; eexists; reflexivity. Qed.
Theorem stored_response_fields_round_trip : forall stage,
  (match stage with
   | IdentifiedResponse id | CommittedResponse id _ => response_identity (JString id) = true
   | _ => True end) ->
  read_response (response_fields stage) = Some stage.
Proof.
 intros [| |id|id body] admitted; try reflexivity.
 - change ((if response_identity (JString id) then Some (IdentifiedResponse id) else None) = Some (IdentifiedResponse id)).
   now rewrite admitted.
 - change ((if response_identity (JString id) then Some (CommittedResponse id body) else None) = Some (CommittedResponse id body)).
   now rewrite admitted.
Qed.
Theorem response_identity_cannot_change : forall current id,
  response_identity id = true -> truthy (response_id current) = true ->
  same (response_id current) id = false ->
  exists message, store_identify current id = err message.
Proof.
 intros [] candidate valid present changed; cbn [response_id] in present; try discriminate;
   unfold store_identify,bind_identity; rewrite valid,changed; eexists; reflexivity.
Qed.
Theorem committed_response_cannot_change : forall id body response updates,
  store_finish (CommittedResponse id body) response = success updates ->
  parsed_matches (JString body) (JObject response) = true.
Proof.
 intros id body response updates accepted.
 unfold store_finish,commit_response in accepted.
 destruct (bind_identity (CommittedResponse id body) (member response "id")); [discriminate|].
 destruct (parsed_matches (JString body) (JObject response)); [reflexivity|discriminate].
Qed.
Theorem existing_request_reuse_requires_body_and_connection : forall record request previous key,
  stored_as Active record = true ->
  store_prepare (Some record) request previous key = reuse_decision record -> prepare_identity record request = true.
Proof.
 intros record request previous key active reused;unfold store_prepare in reused;rewrite active in reused;cbn in reused.
 destruct (prepare_identity record request) eqn:identical;[reflexivity|discriminate].
Qed.
Theorem cancelled_request_cannot_reuse_a_different_connection : forall source,
  truthy (get source.(continuation_effect).(effect_model) "adaptive_reasoning") = false ->
  configuration_reset source = false -> cancelled source = true ->
  same (previous_field source "binding") source.(continuation_binding_value) = false ->
  exists message, WebContinuation.continuation source = err message.
Proof. intros source adaptive reset cancelled different; unfold WebContinuation.continuation; rewrite adaptive,reset,cancelled,different; eexists; reflexivity. Qed.
Theorem tool_continuation_requires_complete_unique_result_batch : forall source receipt suffix value,
  receipt.(receipt_requires_action) = true -> continue_receipt source receipt suffix = success value ->
  continuation_batch_matches receipt.(receipt_calls) suffix = true /\
  continuation_batch_complete receipt.(receipt_calls) suffix = true.
Proof.
 intros source receipt suffix value tools accepted;unfold continue_receipt in accepted;rewrite tools in accepted.
 destruct (continuation_batch_matches receipt.(receipt_calls) suffix && continuation_batch_complete receipt.(receipt_calls) suffix) eqn:complete;
   [now apply andb_true_iff|discriminate].
Qed.
Theorem receipt_is_bound_to_actual_task_connection_and_response : forall history model task response record deferred count hash store binding contract tools value,
  receipt history model task response record deferred count hash store binding contract tools = success value ->
  same (stored_member record "owner") (owner_parts "model" task JNull JNull) = true /\
  same (stored_member record "binding") binding = true /\ same (response_id record.(stored_response)) (member response "id") = true.
Proof.
 intros history model task response record deferred count hash store binding contract tools value accepted.
 unfold receipt in accepted.
 destruct record.(stored_response) as [| | identified | id raw]; try discriminate.
 cbn [response_id].
 destruct ((String.eqb (member_text response "status") "completed" || String.eqb (member_text response "status") "requires_action") &&
     same (JString id) (member response "id") && same (stored_member record "binding") binding &&
     same (stored_member record "owner") (owner_parts "model" task JNull JNull) &&
     (match TextJson.parse_json raw,TextJson.parse_json (text (stored_member record "body")) with
      | Some persisted,Some body => same (JObject response) persisted && resource_admissible response (get model "name") body tools
      | _,_ => false end)) eqn:bound;[|discriminate].
 repeat rewrite andb_true_iff in bound;tauto.
Qed.
Theorem receipt_metadata_uses_one_current_format : forall rows identity created value,
  store_metadata rows identity created = success value ->
  get value "format" = JString current_format /\ forall row, In row rows -> eq row "format" current_format = true.
Proof.
 intros rows identity created value accepted;unfold store_metadata in accepted.
 destruct rows as [|row rest].
 - destruct created;[|discriminate]. inversion accepted;subst;split;[reflexivity|]. intros item member;inversion member.
 - destruct rest as [|next rest];[|discriminate].
   destruct (is_text (get row "format") && eq row "format" current_format && WebCommon.nonempty (get row "identity")) eqn:admitted;[|discriminate].
   inversion accepted;subst;split;[reflexivity|].
   intros item member;cbn in member;destruct member as [<-|[]].
   now apply andb_true_iff in admitted as [admitted _];apply andb_true_iff in admitted as [_ admitted].
Qed.

Definition retained_request_matches record invocation_prefix : Prop :=
 record.(stored_response) <> RejectedResponse /\ match invocation_prefix with
 | None => True
 | Some prefix =>
     (text (stored_member record "invocation") = prefix ++ ":0" \/
       String.prefix ((prefix ++ ":0") ++ ":context:") (text (stored_member record "invocation")) = true) \/
     (text (stored_member record "invocation") = prefix ++ ":1" \/
       String.prefix ((prefix ++ ":1") ++ ":context:") (text (stored_member record "invocation")) = true)
 end.
Lemma retire_match_true_iff : forall record invocation_prefix,
 retire_match record invocation_prefix = true <-> retained_request_matches record invocation_prefix.
Proof.
 intros record [prefix|]; unfold retire_match, retained_request_matches.
 - rewrite andb_true_iff; unfold invocation_ticket.
   repeat rewrite orb_true_iff; repeat rewrite String.eqb_eq.
   destruct record.(stored_response); intuition discriminate.
 - rewrite andb_true_r.
   destruct record.(stored_response); intuition discriminate.
Qed.
Definition newest_matching_request records invocation_prefix selected : Prop := match selected with
 | Some record => In record records /\ retained_request_matches record invocation_prefix /\
     forall candidate, In candidate records -> retained_request_matches candidate invocation_prefix ->
       nat_value (stored_member candidate "ordinal") <= nat_value (stored_member record "ordinal")
 | None => forall candidate, In candidate records -> ~ retained_request_matches candidate invocation_prefix
 end.
Lemma retire_candidate_is_newest_match : forall records invocation_prefix,
 newest_matching_request records invocation_prefix (retire_candidate records invocation_prefix).
Proof.
 intros records invocation_prefix; induction records as [|record records IH].
 - cbn [retire_candidate newest_matching_request]; intros candidate member; inversion member.
 - change (newest_matching_request (record :: records) invocation_prefix
     (if retire_match record invocation_prefix then Some
       (match retire_candidate records invocation_prefix with
        | None => record
        | Some previous => if nat_value (stored_member previous "ordinal") <? nat_value (stored_member record "ordinal") then record else previous end)
      else retire_candidate records invocation_prefix)).
   destruct (retire_candidate records invocation_prefix) as [previous|];
     cbn [newest_matching_request] in IH.
   + destruct IH as [member [eligible maximal]].
     destruct (retire_match record invocation_prefix) eqn:matches.
     * destruct (nat_value (stored_member previous "ordinal") <? nat_value (stored_member record "ordinal")) eqn:newer;
         cbn [newest_matching_request].
       -- split; [now left|]. split; [now apply retire_match_true_iff|].
          intros candidate [<-|present] admitted; [apply N.le_refl|].
          eapply N.le_trans; [exact (maximal candidate present admitted)|].
          apply N.lt_le_incl, N.ltb_lt; exact newer.
       -- split; [now right|]. split; [exact eligible|].
          intros candidate [<-|present] admitted.
          ++ now apply N.ltb_ge in newer.
          ++ exact (maximal candidate present admitted).
     * cbn [newest_matching_request]; split; [now right|]. split; [exact eligible|].
       intros candidate [<-|present] admitted.
       -- apply retire_match_true_iff in admitted; rewrite matches in admitted; discriminate.
       -- exact (maximal candidate present admitted).
   + destruct (retire_match record invocation_prefix) eqn:matches;
       cbn [newest_matching_request].
     * split; [now left|]. split; [now apply retire_match_true_iff|].
       intros candidate [<-|present] admitted; [apply N.le_refl|].
       exfalso; exact (IH candidate present admitted).
     * intros candidate [<-|present] admitted.
       -- apply retire_match_true_iff in admitted; rewrite matches in admitted; discriminate.
       -- exact (IH candidate present admitted).
Qed.
Theorem latest_request_selects_newest_match : forall records,
 exists selected,
   store_latest records = success (match selected with Some record => stored_json record | None => JNull end) /\
   newest_matching_request records None selected.
Proof.
 intros records; exists (retire_candidate records None); split;
   [reflexivity|apply retire_candidate_is_newest_match].
Qed.
Theorem cancellation_selects_newest_match : forall rows records owner ticket,
 boolean_field (store_metadata rows "" false) "ok" = true ->
 exists selected,
   retire_existing rows records owner ticket = success (match selected with
     | Some record => JObject [("record",stored_json record);("updates",JObject [("retired",retirement_code Cancelled)])]
     | None => JNull end) /\
   newest_matching_request records
     (option_map (fun ticket => owner ++ ":" ++ name_or_number ticket) ticket) selected.
Proof.
 intros rows records owner ticket metadata;
   exists (retire_candidate records (option_map (fun ticket => owner ++ ":" ++ name_or_number ticket) ticket)).
 split; [unfold retire_existing; now rewrite metadata|apply retire_candidate_is_newest_match].
Qed.
