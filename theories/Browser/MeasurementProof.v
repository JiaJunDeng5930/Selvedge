From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require Import Runtime Observation LayoutProof.
Import ListNotations.
Open Scope string_scope.

Theorem stale_measurement_failure_does_not_replace_the_current_page source measured current reason :
 Runtime.binary_field "measured_generation" source = Some measured ->
 Runtime.binary_field "current_generation" source = Some current ->
 string_field "reason" source = Some reason ->
 measured <> current ->
 Runtime.call "measurement_failure" source = success JNull.
Proof.
 intros Measured Current Reason Different.
 change (Runtime.measurement_failure_call source = success JNull).
 unfold Runtime.measurement_failure_call.
 rewrite Measured, Current, Reason.
 unfold Observation.measurement_failure, Observation.current_measurement.
 assert (Stale : N.eqb measured current = false) by (apply N.eqb_neq; exact Different).
 rewrite Stale; reflexivity.
Qed.

Theorem owned_measurement_failure_keeps_its_diagnostic source generation reason :
 Runtime.binary_field "measured_generation" source = Some generation ->
 Runtime.binary_field "current_generation" source = Some generation ->
 string_field "reason" source = Some reason ->
 Runtime.call "measurement_failure" source = success (JString reason).
Proof.
 intros Measured Current Reason.
 change (Runtime.measurement_failure_call source = success (JString reason)).
 unfold Runtime.measurement_failure_call.
 rewrite Measured, Current, Reason.
 unfold Observation.measurement_failure, Observation.current_measurement.
 rewrite N.eqb_refl; reflexivity.
Qed.

Theorem stale_measurement_does_not_decode_receipts source measured current :
 Runtime.binary_field "measured_generation" source = Some measured ->
 Runtime.binary_field "current_generation" source = Some current ->
 measured <> current ->
 Runtime.call "environment" source = success (JObject [("stale", JBool true)]).
Proof.
 intros Measured Current Different.
 change (Runtime.environment_call source = success (JObject [("stale", JBool true)])).
 unfold Runtime.environment_call.
 rewrite Measured, Current.
 unfold Observation.current_measurement.
 assert (Stale : N.eqb measured current = false) by (apply N.eqb_neq; exact Different).
 rewrite Stale; reflexivity.
Qed.

Theorem changed_root_font_rejects_the_measurement source observations generation requested observed :
 Runtime.binary_field "measured_generation" source = Some generation ->
 Runtime.binary_field "current_generation" source = Some generation ->
 Runtime.natural_field "requested_root_font_size_milli" source = Some requested ->
 field "observations" source = Some observations ->
 Runtime.natural_field "root_font_size_milli" observations = Some observed ->
 requested <> observed ->
 Runtime.call "environment" source = success (JObject [("stale", JBool true)]).
Proof.
 intros Measured Current Requested Observations Observed Different.
 change (Runtime.environment_call source = success (JObject [("stale", JBool true)])).
 unfold Runtime.environment_call.
 rewrite Measured, Current.
 unfold Observation.current_measurement; rewrite N.eqb_refl.
 rewrite Requested, Observations, Observed.
 assert (Stale : Nat.eqb requested observed = false) by (apply Nat.eqb_neq; exact Different).
 rewrite Stale; reflexivity.
Qed.

Lemma selected_observation_is_complete valid key observations selected :
 Observation.first_valid_observation valid key observations = Some selected ->
 In selected observations /\ Observation.named_observation key selected = true /\ valid selected = true.
Proof.
 unfold Observation.first_valid_observation.
 intro Selected; apply find_some in Selected as [Member Matches].
 apply andb_true_iff in Matches as [Key Complete]; auto.
Qed.

Lemma named_observation_has_requested_key key observed :
 Observation.named_observation key observed = true ->
 string_field "key" observed = Some key.
Proof.
 unfold Observation.named_observation.
 destruct (string_field "key" observed) as [actual|] eqn:Key; try discriminate.
 intro Matches; apply String.eqb_eq in Matches; subst actual; reflexivity.
Qed.

Theorem metric_lookup_keeps_the_first_complete_receipt key prefix selected suffix :
 Forall (fun observed =>
   Observation.named_observation key observed && Observation.valid_metric observed = false) prefix ->
 Observation.named_observation key selected && Observation.valid_metric selected = true ->
 Runtime.observed_metric key (prefix ++ selected :: suffix) = Some selected.
Proof.
 intros Earlier Complete.
 unfold Runtime.observed_metric, Observation.first_valid_observation.
 induction Earlier as [|first prefix Rejected Earlier IH].
 - cbn [List.app find]; rewrite Complete; reflexivity.
 - cbn [List.app find]; rewrite Rejected; exact IH.
Qed.

Theorem selected_font_metric_has_complete_positive_dimensions key observations selected :
 Runtime.observed_metric key observations = Some selected ->
 string_field "key" selected = Some key /\
 exists height advance,
   Observation.pixel_field "height" selected = Some height /\
   Observation.pixel_field "advance" selected = Some advance /\
   0 < height /\ 0 < advance.
Proof.
 intro Selected.
 apply selected_observation_is_complete in Selected as [Member [Key Valid]].
 split; [now apply named_observation_has_requested_key|].
 unfold Observation.valid_metric in Valid.
 destruct (Observation.metric_observation selected) as [metric|] eqn:Dimensions; try discriminate.
 unfold Observation.metric_observation in Dimensions.
 destruct (Observation.pixel_field "height" selected) as [height|] eqn:Height; try discriminate.
 destruct (Observation.pixel_field "advance" selected) as [advance|] eqn:Advance; try discriminate.
 cbn in Dimensions.
 pose proof (admitted_metric_is_positive height advance metric Dimensions) as [PositiveHeight PositiveAdvance].
 exists height, advance; auto.
Qed.

Theorem matched_region_requires_complete_dimensions key observations :
 (exists observed, In observed observations /\ Observation.named_observation key observed = true) ->
 (forall observed, In observed observations -> Observation.named_observation key observed = true ->
   Observation.valid_region observed = false) ->
 Runtime.observed_region key observations = None.
Proof.
 intros [observed [Member Key]] Invalid.
 unfold Runtime.observed_region.
 destruct (Observation.first_valid_observation Observation.valid_region key observations)
   as [selected|] eqn:Selected.
 - apply selected_observation_is_complete in Selected as [Present [Requested Complete]].
   rewrite (Invalid selected Present Requested) in Complete; discriminate.
 - assert (Present : existsb (Observation.named_observation key) observations = true).
   { apply existsb_exists; exists observed; auto. }
   rewrite Present; reflexivity.
Qed.

Theorem admitted_measurement_has_valid_dimensions source encoded :
 Runtime.call "environment" source =
 success (JObject [("stale", JBool false); ("environment", encoded)]) ->
 exists environment, Observation.decode_environment encoded = Some environment.
Proof.
 intro Admitted.
 change (Runtime.environment_call source =
   success (JObject [("stale", JBool false); ("environment", encoded)])) in Admitted.
 unfold Runtime.environment_call in Admitted.
 destruct (Runtime.binary_field "measured_generation" source) as [measured|]; try discriminate.
 destruct (Runtime.binary_field "current_generation" source) as [current|]; try discriminate.
 destruct (Observation.current_measurement measured current); try discriminate.
 destruct (Runtime.natural_field "requested_root_font_size_milli" source) as [requested|]; try discriminate.
 destruct (field "observations" source) as [observed|]; try discriminate.
 destruct (Runtime.natural_field "root_font_size_milli" observed) as [root|]; try discriminate.
 destruct (Nat.eqb requested root); try discriminate.
 destruct (field "width" observed); try discriminate.
 destruct (field "height" observed); try discriminate.
 destruct (field "root_font_size_milli" observed); try discriminate.
 destruct (array_field "metrics" observed) as [metrics|]; try discriminate.
 destruct (array_field "regions" observed) as [regions|]; try discriminate.
 destruct (bool_field "system_dark" source); try discriminate.
 destruct (bool_field "reduced_motion" source); try discriminate.
 destruct (Runtime.observed_metric "@font/body" metrics); try discriminate.
 destruct (Runtime.observed_metric "@font/activity-primary" metrics); try discriminate.
 destruct (Runtime.observed_metric "@font/activity-support" metrics); try discriminate.
 destruct (Runtime.observed_region "workspace" regions); try discriminate.
 destruct (Runtime.observed_region "main" regions); try discriminate.
 match type of Admitted with
 | context [Observation.decode_environment ?packet] =>
     destruct (Observation.decode_environment packet) as [environment|] eqn:Valid
 end; try discriminate.
 inversion Admitted; subst.
 exists environment; exact Valid.
Qed.
