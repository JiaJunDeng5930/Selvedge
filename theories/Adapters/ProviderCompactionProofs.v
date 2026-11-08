From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json JsonObjectsProofs.
From Selvedge.Adapters Require Import Common ProviderCompaction Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_structured_summary_appends_its_instruction_after_selected_history : forall source,
  let original := get source "effect" in
  let plan := get original "plan" in
  str plan "method" = "structured" ->
  Api.call "backend.compaction_effect" source = success (JObject [
    ("kind",JString "context_compaction"); ("context_selected",JBool true);
    ("model",get original "model"); ("instructions",JString "");
    ("history",JArray (items (get plan "history") ++
      [JObject [("role",JString "task_context"); ("type",JString "environment_notice");
        ("content",get plan "prompt")]])%list)]).
Proof.
 intros source; cbv zeta; intro Method.
 change (Api.call "backend.compaction_effect" source) with (success (effect source)).
 unfold effect. now rewrite Method.
Qed.

Theorem public_opaque_requests_never_use_textual_fallback : forall source,
  opaque_request (get source "request") = true ->
  Api.call "backend.compaction_meter_fallback" source =
    success (JObject [("action",JString "error")]).
Proof. intros source H;change (meter_fallback source = action "error");
  unfold meter_fallback;rewrite H;reflexivity. Qed.
Theorem public_token_counter_rejects_negative_or_nonnumeric : forall source,
  wire_natural (get (get source "response") "input_tokens") = None ->
  exists message, Api.call "backend.compaction_meter_result" source = err message.
Proof. intros source H; exists "The provider returned an invalid input token count"; change (meter_result source = err "The provider returned an invalid input token count"); unfold meter_result; now rewrite H. Qed.
Theorem public_valid_token_count_is_retained : forall source count,
  wire_natural (get (get source "response") "input_tokens") = Some count ->
  JsonObjects.equivalent (Api.call "backend.compaction_meter_result" source) (success (JObject [
    ("scope",get source "scope"); ("input_tokens",number count)])) = true.
Proof.
 intros source count H;change (Api.call "backend.compaction_meter_result" source) with (meter_result source).
 unfold meter_result;rewrite H;apply equivalent_is_reflexive.
Qed.
Theorem public_dispatch_respects_context_window : forall source,
  Api.call "backend.compaction_budget" source = success (JString "dispatch") ->
  num source "input_tokens" + num (get source "plan") "output_reserve_tokens" <=
    num (get source "plan") "window_tokens".
Proof. intros source H;change (budget source = success (JString "dispatch")) in H;unfold budget in H.
  destruct (N.leb _ _) eqn:E;[now apply N.leb_le|discriminate]. Qed.
Theorem public_fitting_request_dispatches : forall source,
  num source "input_tokens" + num (get source "plan") "output_reserve_tokens" <=
    num (get source "plan") "window_tokens" ->
  Api.call "backend.compaction_budget" source = success (JString "dispatch").
Proof. intros source H;change (budget source = success (JString "dispatch"));unfold budget;
  apply N.leb_le in H;now rewrite H. Qed.
Theorem public_missing_model_is_not_a_capability_failure : forall source,
  str source "code" = "model_not_found" ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof. intros source H;change (meter_fallback source = action "error");unfold meter_fallback,unsupported_route;
  rewrite H;cbn;repeat rewrite andb_false_r;reflexivity. Qed.
Theorem public_readable_unsupported_route_uses_byte_bound : forall source,
  opaque_request (get source "request") = false -> unsupported_route source = true ->
  JsonObjects.equivalent (Api.call "backend.compaction_meter_fallback" source) (success (JObject [
    ("action",JString "local"); ("scope",get source "scope");
    ("input_tokens",get source "bytes")])) = true.
Proof.
 intros source H R;change (Api.call "backend.compaction_meter_fallback" source) with (meter_fallback source).
 unfold meter_fallback;rewrite H,R;apply equivalent_is_reflexive.
Qed.

Theorem public_account_image_requests_use_the_complete_request_estimate : forall source,
  ProviderCatalog.account (get source "profile") = true ->
  0 < request_image_count (get source "request") ->
  JsonObjects.equivalent (Api.call "backend.compaction_measurement_plan" source)
    (success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",number (N.of_nat (String.length (TextJson.render_json (get source "request"))) +
        1844 * request_image_count (get source "request")))])) = true.
Proof.
 intros source account images.
 change (Api.call "backend.compaction_measurement_plan" source) with (measurement_plan source).
 unfold measurement_plan; rewrite account.
 assert (has_images : N.ltb 0 (request_image_count (get source "request")) = true)
   by (apply N.ltb_lt; exact images).
 rewrite has_images; apply equivalent_is_reflexive.
Qed.
Theorem public_other_requests_use_provider_measurement : forall source,
  (ProviderCatalog.account (get source "profile") &&
    N.ltb 0 (request_image_count (get source "request"))) = false ->
  Api.call "backend.compaction_measurement_plan" source = success (JObject [("action",JString "remote")]).
Proof.
 intros source Remote.
 change (measurement_plan source = success (JObject [("action",JString "remote")])).
 unfold measurement_plan; now rewrite Remote.
Qed.

Definition encrypted_continuation (request : json) := exists item ciphertext,
  In item (items (get request "input")) /\
  (str item "type" = "reasoning" \/ str item "type" = "compaction") /\
  get item "encrypted_content" = JString ciphertext /\ ciphertext <> "".

Theorem complete_request_encrypted_continuation_is_opaque : forall value,
  encrypted_continuation value -> opaque_request value = true.
Proof.
 intros value [item [ciphertext [Member [Kind [Content Nonempty]]]]].
 unfold opaque_request; apply orb_true_iff; left.
 apply existsb_exists; exists item; split; [exact Member|].
 unfold encrypted_input_item, str in *.
 destruct Kind as [Kind|Kind]; rewrite Kind, Content; cbn;
   apply negb_true_iff; now apply String.eqb_neq.
Qed.
Theorem public_image_requests_never_use_textual_fallback : forall source item image,
  In item (items (get (get source "request") "input")) ->
  In image (input_parts item) -> str image "type" = "input_image" ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof.
 intros source item image Item Image Kind.
 apply public_opaque_requests_never_use_textual_fallback.
 unfold opaque_request; apply orb_true_iff; right; apply N.ltb_lt.
 assert (Member : In image (input_images (get source "request"))).
 { unfold input_images; apply filter_In; split.
   - apply in_flat_map; exists item; auto.
   - now rewrite Kind. }
 unfold request_image_count.
 destruct (input_images (get source "request")); [contradiction|cbn; lia].
Qed.
Theorem public_encrypted_requests_never_use_textual_fallback : forall source,
  encrypted_continuation (get source "request") ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof.
 intros source Encrypted; apply public_opaque_requests_never_use_textual_fallback.
 now apply complete_request_encrypted_continuation_is_opaque.
Qed.
