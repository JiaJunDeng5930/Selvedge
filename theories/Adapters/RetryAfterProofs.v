From Stdlib Require Import NArith Lia.
From Selvedge.Adapters Require Import RetryAfter.
Open Scope N_scope.

Lemma delay_denominator_is_positive : forall delay,
  0 < decimal_denominator delay.
Proof.
  intro delay. unfold decimal_denominator.
  assert (10 ^ N.of_nat (delay_precision delay) <> 0) by (apply N.pow_nonzero; discriminate).
  lia.
Qed.

Theorem integer_timer_does_not_precede_exact_delay : forall delay,
  delay_numerator delay <= timer_milliseconds delay * decimal_denominator delay.
Proof.
  intro delay. unfold timer_milliseconds.
  pose proof (delay_denominator_is_positive delay) as positive.
  pose proof (N.div_mod (delay_numerator delay + decimal_denominator delay - 1)
    (decimal_denominator delay) ltac:(lia)) as quotient.
  pose proof (N.mod_lt (delay_numerator delay + decimal_denominator delay - 1)
    (decimal_denominator delay) ltac:(lia)) as remainder.
  nia.
Qed.

Theorem integer_timer_is_the_first_admissible_millisecond : forall delay milliseconds,
  delay_numerator delay <= milliseconds * decimal_denominator delay ->
  timer_milliseconds delay <= milliseconds.
Proof.
  intros delay milliseconds admitted. unfold timer_milliseconds.
  pose proof (delay_denominator_is_positive delay) as positive.
  apply N.lt_succ_r, N.Div0.div_lt_upper_bound. nia.
Qed.

Theorem integer_timer_preserves_an_exact_integer_cap : forall delay maximum,
  delay_exceeds_integer delay maximum = false -> timer_milliseconds delay <= maximum.
Proof.
  intros delay maximum bounded. apply integer_timer_is_the_first_admissible_millisecond.
  unfold delay_exceeds_integer in bounded. apply N.ltb_ge in bounded. nia.
Qed.

Lemma integer_delay_keeps_its_millisecond : forall milliseconds,
  timer_milliseconds (integer_delay milliseconds) = milliseconds.
Proof.
  intro milliseconds. change ((milliseconds + 1 - 1) / 1 = milliseconds).
  now rewrite N.add_sub, N.div_1_r.
Qed.

Theorem integer_timer_meets_floor_and_exact_cap : forall delay minimum maximum,
  minimum <= maximum -> delay_exceeds_integer delay maximum = false ->
  let timer := timer_milliseconds (maximum_delay minimum delay) in
  delay_numerator delay <= timer * decimal_denominator delay /\ minimum <= timer <= maximum.
Proof.
  intros delay minimum maximum floor cap. unfold maximum_delay.
  destruct (delay_exceeds_integer delay minimum) eqn:above.
  - pose proof (integer_timer_does_not_precede_exact_delay delay) as not_early.
    pose proof (integer_timer_preserves_an_exact_integer_cap delay maximum cap) as not_late.
    pose proof (delay_denominator_is_positive delay) as positive.
    unfold delay_exceeds_integer in above. apply N.ltb_lt in above. nia.
  - rewrite integer_delay_keeps_its_millisecond.
    unfold delay_exceeds_integer in above. apply N.ltb_ge in above. nia.
Qed.
