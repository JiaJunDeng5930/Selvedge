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

Definition content_consistent value := image_count value = 0 \/ opaque_content value = true.
Lemma combine_content_consistent : forall left right,
  content_consistent left -> content_consistent right -> content_consistent (combine_content left right).
Proof.
 intros [lo li] [ro ri] [L|L] [R|R];unfold content_consistent,combine_content in *;cbn in *.
 - left;now rewrite L,R.
 - right;now rewrite R,orb_true_r.
 - right;now rewrite L.
 - right;now rewrite L.
Qed.
Theorem complete_request_image_count_is_opaque : forall value,
  content_consistent (classify_content value).
Proof.
 fix induction_json 1;intro value;destruct value as [|b|n|s|values|fields];try (left;reflexivity).
 - cbn;induction values as [|head tail IH];[left;reflexivity|].
   apply combine_content_consistent;[apply induction_json|exact IH].
 - cbn;induction fields as [|[name item] tail IH];[left;reflexivity|].
   apply combine_content_consistent.
   + unfold content_consistent;cbn;destruct (String.eqb name "image_asset" && is_object item);[right|left];reflexivity.
   + apply combine_content_consistent;[apply induction_json|exact IH].
Qed.
Theorem public_image_requests_never_use_textual_fallback : forall source,
  0 < image_count (classify_content (get source "request")) ->
  Api.call "backend.compaction_meter_fallback" source = action "error".
Proof.
 intros source positive;apply public_opaque_requests_never_use_textual_fallback.
 destruct (complete_request_image_count_is_opaque (get source "request")) as [zero|opaque];[lia|exact opaque].
Qed.
