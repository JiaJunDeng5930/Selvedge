From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Adapters Require Import Common ProviderCompaction Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_opaque_requests_never_use_textual_fallback : forall source,
  opaque_content (classify_content (get source "request")) = true ->
  Api.call "backend.compaction_meter_fallback" source =
    success (JObject [("action",JString "error")]).
Proof. intros source H;change (meter_fallback source = action "error");
  unfold meter_fallback;rewrite H;reflexivity. Qed.
Theorem public_token_counter_rejects_negative_or_nonnumeric : forall source,
  natural (get (get source "response") "input_tokens") = None ->
  Api.call "backend.compaction_meter_result" source =
    err "The provider returned an invalid input token count".
Proof. intros source H;change (meter_result source = err "The provider returned an invalid input token count");unfold meter_result;now rewrite H. Qed.
Theorem public_valid_token_count_is_retained : forall source count,
  natural (get (get source "response") "input_tokens") = Some count ->
  Api.call "backend.compaction_meter_result" source = success (JObject [
    ("scope",get source "scope"); ("input_tokens",get (get source "response") "input_tokens");
    ("tokenizer",JString "provider")]).
Proof. intros source count H;change (meter_result source = success (JObject [("scope",get source "scope"); ("input_tokens",get (get source "response") "input_tokens"); ("tokenizer",JString "provider")]));unfold meter_result;now rewrite H. Qed.
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
  opaque_content (classify_content (get source "request")) = false ->
  is_object (get source "request") = true -> unsupported_route source = true ->
  Api.call "backend.compaction_meter_fallback" source = success (JObject [
    ("action",JString "local"); ("scope",get source "scope");
    ("input_tokens",get source "bytes"); ("tokenizer",JString "utf8_upper_bound")]).
Proof. intros source H I R;change (meter_fallback source = success (JObject [("action",JString "local"); ("scope",get source "scope"); ("input_tokens",get source "bytes"); ("tokenizer",JString "utf8_upper_bound")]));unfold meter_fallback;now rewrite H,I,R. Qed.

Definition content_consistent value :=
  (image_count value = 0 \/ opaque_content value = true) /\
  (encrypted_content_present value = false \/ opaque_content value = true).
Lemma combine_content_consistent : forall left right,
  content_consistent left -> content_consistent right -> content_consistent (combine_content left right).
Proof.
 intros [lo le li] [ro re ri] [Limage Lencrypted] [Rimage Rencrypted];
 unfold content_consistent,combine_content in *;cbn in *;split.
 - destruct Limage as [Limage|Limage];destruct Rimage as [Rimage|Rimage].
   + left;lia.
   + right;rewrite Rimage;apply orb_true_r.
   + right;rewrite Limage;apply orb_true_l.
   + right;rewrite Limage;apply orb_true_l.
 - destruct Lencrypted as [Lencrypted|Lencrypted];destruct Rencrypted as [Rencrypted|Rencrypted].
   + left;now rewrite Lencrypted,Rencrypted.
   + right;rewrite Rencrypted;apply orb_true_r.
   + right;rewrite Lencrypted;apply orb_true_l.
   + right;rewrite Lencrypted;apply orb_true_l.
Qed.

Theorem public_account_image_requests_use_the_complete_request_estimate : forall source,
  is_object (get source "request") = true ->
  ProviderCatalog.account (get source "profile") = true ->
  0 < image_count (classify_content (get source "request")) ->
  Api.call "backend.compaction_measurement_plan" source =
    success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",number (N.of_nat (String.length (TextJson.render_json (get source "request"))) +
        1844 * image_count (classify_content (get source "request"))));
      ("tokenizer",JString "codex_image_estimate")]).
Proof.
 intros source request_object account images.
 change (Api.call "backend.compaction_measurement_plan" source) with (measurement_plan source).
 unfold measurement_plan; rewrite request_object,account.
 assert (has_images : N.ltb 0 (image_count (classify_content (get source "request"))) = true)
   by (apply N.ltb_lt; exact images).
 rewrite has_images; reflexivity.
Qed.
Theorem complete_request_classification_is_consistent : forall value,
  content_consistent (classify_content value).
Proof.
 fix induction_json 1;intro value;destruct value as [|b|n|s|values|fields];
   try (split;[left;reflexivity|left;reflexivity]).
 - cbn;induction values as [|head tail IH];[split;[left|left];reflexivity|].
   apply combine_content_consistent;[apply induction_json|exact IH].
 - cbn;induction fields as [|[name item] tail IH];[split;[left|left];reflexivity|].
   apply combine_content_consistent.
   + unfold content_consistent;cbn;split.
     * destruct (String.eqb name "image_asset" && is_object item);[right;apply orb_true_l|left];reflexivity.
     * destruct (String.eqb name "encrypted_content" && is_text item && negb (String.eqb (text item) ""));
       [right;apply orb_true_r|left];reflexivity.
   + apply combine_content_consistent;[apply induction_json|exact IH].
Qed.
Theorem complete_request_image_count_is_opaque : forall value,
  image_count (classify_content value) = 0 \/ opaque_content (classify_content value) = true.
Proof. intros value;exact (proj1 (complete_request_classification_is_consistent value)). Qed.
Theorem complete_request_encrypted_continuation_is_opaque : forall value,
  encrypted_content_present (classify_content value) = false \/ opaque_content (classify_content value) = true.
Proof. intros value;exact (proj2 (complete_request_classification_is_consistent value)). Qed.
Theorem public_image_requests_never_use_textual_fallback : forall source,
  0 < image_count (classify_content (get source "request")) ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof.
 intros source positive;apply public_opaque_requests_never_use_textual_fallback.
 destruct (complete_request_image_count_is_opaque (get source "request")) as [zero|opaque];[lia|exact opaque].
Qed.
Theorem public_encrypted_requests_never_use_textual_fallback : forall source,
  encrypted_content_present (classify_content (get source "request")) = true ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof.
 intros source encrypted;apply public_opaque_requests_never_use_textual_fallback.
 destruct (complete_request_encrypted_continuation_is_opaque (get source "request")) as [absent|opaque];
   [rewrite encrypted in absent;discriminate|exact opaque].
Qed.
