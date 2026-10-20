From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Adapters Require Import Common Api ProviderCatalog RetryAfter RetryAfterProofs BackendRetry BackendProofs EvaluatorBudget EvaluatorPolicy.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_backend_timer_respects_header_and_budget : forall source exact,
  boolean_field source "error_present" = false -> boolean_field source "response_present" = true ->
  contains (items (get (get source "policy") "statuses")) (get source "status") = true ->
  attempt_available source = true -> header_delay source = Some exact ->
  delay_exceeds_integer exact (num (get source "policy") "max_retry_after_ms") = false ->
  base_delay source <= num (get source "policy") "max_retry_after_ms" ->
  exists milliseconds,
    get (get (Api.call "backend.retry" source) "value") "delay_ms" = number milliseconds /\
    delay_numerator exact <= milliseconds * decimal_denominator exact /\
    base_delay source <= milliseconds <= num (get source "policy") "max_retry_after_ms".
Proof.
  intros source exact error response status available header cap floor.
  rewrite (public_admitted_retry_keeps_the_header_minimum source exact error response status available header cap).
  exists (timer_milliseconds (maximum_delay (base_delay source) exact)). split; [reflexivity|].
  now apply integer_timer_meets_floor_and_exact_cap.
Qed.

Lemma successful_evaluator_retry_is_its_calculated_plan : forall source result,
  EvaluatorPolicy.retry source = success result -> retry_calculation source = result.
Proof.
  intros source result accepted. unfold EvaluatorPolicy.retry in accepted.
  destruct (String.eqb (str (retry_calculation source) "action") "fail").
  - now inversion accepted.
  - unfold checked in accepted.
    destruct (same_provider source && bounded_retry source); [now inversion accepted|discriminate].
Qed.

Theorem public_evaluator_timer_respects_header_and_fixed_budget : forall source exact result,
  str source "phase" = "cancelled" ->
  parse_retry_after (str source "retry_after") (num source "now") = Some exact ->
  Api.call "evaluator.retry" source = success result -> str result "action" = "wait" ->
  exists milliseconds,
    get result "milliseconds" = number milliseconds /\
    delay_numerator exact <= milliseconds * decimal_denominator exact /\
    100 <= milliseconds <= 5000.
Proof.
  intros source exact result phase parsed accepted waiting.
  change (EvaluatorPolicy.retry source = success result) in accepted.
  apply successful_evaluator_retry_is_its_calculated_plan in accepted.
  unfold retry_calculation in accepted. rewrite phase in accepted. cbn in accepted.
  destruct (JsonObjects.equivalent (retry_response source) (get source "plan") &&
    String.eqb (str (get source "plan") "after_cancel") "retry") eqn:plan.
  - unfold retry_header in accepted. unfold str in parsed.
    destruct (get source "retry_after") eqn:header; try discriminate parsed.
    cbn [text] in parsed, accepted. rewrite parsed in accepted.
    destruct (delay_exceeds_integer exact 5000) eqn:cap.
    + inversion accepted; subst result. discriminate waiting.
    + inversion accepted; subst result.
      exists (timer_milliseconds (maximum_delay 100 exact)). split; [reflexivity|].
      apply integer_timer_meets_floor_and_exact_cap; [lia|exact cap].
  - inversion accepted; subst result. discriminate waiting.
Qed.
