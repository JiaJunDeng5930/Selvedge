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
Theorem response_identity_cannot_change : forall record current id,
  identity id = true -> truthy (member current "response_id") = true ->
  same (member current "response_id") id = false ->
  exists message, store_identify record current id = err message.
Proof. intros record current id valid present changed; unfold store_identify; rewrite valid,present,changed; eexists; reflexivity. Qed.
Theorem existing_request_reuse_requires_body_and_connection : forall record request previous key value,
  stored_as Active record = true ->
  store_prepare (Some record) request previous key = prepare_decision "reuse" value -> prepare_identity record request = true.
Proof.
 intros record request previous key value active reused;unfold store_prepare in reused;rewrite active in reused;cbn in reused.
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
  same (member record "owner") (owner_parts "model" task JNull JNull) = true /\
  same (member record "binding") binding = true /\ same (member record "response_id") (member response "id") = true.
Proof.
 intros history model task response record deferred count hash store binding contract tools value accepted.
 unfold receipt in accepted.
 destruct ((String.eqb (member_text response "status") "completed" || String.eqb (member_text response "status") "requires_action") &&
     same (member record "response_id") (member response "id") && same (member record "binding") binding &&
     same (member record "owner") (owner_parts "model" task JNull JNull) &&
     (match TextJson.parse_json (member_text record "response"),TextJson.parse_json (member_text record "body") with
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
