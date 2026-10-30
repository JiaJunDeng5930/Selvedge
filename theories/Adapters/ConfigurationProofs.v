From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common Observation Configuration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem accepted_evaluator_plan_uses_a_declared_provider : forall definitions instructions budget source result,
  Configuration.call definitions instructions budget "config.evaluator_plan" source = success result ->
  has_error result = false ->
  exists provider,
    In provider (map evaluator_name evaluator_providers) /\
    get (get (hd JNull (items (get result "fields"))) "value") "literal" = JString provider /\
    Forall (fun assignment => get assignment "key" = JString "provider" ->
      get (get assignment "value") "literal" = JString provider) (items (get result "fields")).
Proof.
  intros definitions instructions budget source result accepted valid.
  change (success (evaluator_plan source) = success result) in accepted.
  inversion accepted; subst result; clear accepted.
  unfold evaluator_plan in valid |- *.
  destruct (negb (identifier (get source "name"))); [discriminate|].
  destruct (negb (fields_only ["provider";"model";"endpoint";"api_key_env";"timeout_ms";"max_attempts"]
    (get source "entry"))); [discriminate|].
  remember (find _ evaluator_providers) as choice eqn:selected.
  destruct choice as [[provider model endpoint]|]; [|discriminate].
  destruct ((negb (present (observed_field (get source "entry") "model")) ||
    identifier (observed_field (get source "entry") "model")) &&
    (negb (present (observed_field (get source "entry") "api_key_env")) ||
    variable (observed_field (get source "entry") "api_key_env"))); [|discriminate].
  symmetry in selected. apply find_some in selected as [member _].
  exists provider. split.
  - now apply in_map with (f := evaluator_name) in member.
  - split; [reflexivity|].
    cbn; repeat constructor; intro same; try discriminate; reflexivity.
Qed.

Theorem accepted_context_request_uses_declared_sources : forall definitions instructions budget source requested,
  Configuration.call definitions instructions budget "config.context_transport" source = success (literal JNull) ->
  In requested (items (get source "definitions")) -> In requested (items definitions).
Proof.
  intros definitions instructions budget source requested accepted member.
  change (success (context_transport definitions source) = success (literal JNull)) in accepted.
  unfold context_transport in accepted.
  destruct (context_transport_valid definitions source) eqn:valid; [|discriminate].
  unfold context_transport_valid in valid.
  repeat rewrite andb_true_iff in valid.
  destruct valid as [[shape declared] observed].
  apply forallb_forall with (x := requested) in declared; [|exact member].
  apply existsb_exists in declared as [canonical [inside same]].
  apply equal_reflects_equality in same. now subst.
Qed.

Lemma bounded_observation_is_in_range : forall value lower upper,
  bound value lower upper = true -> lower <= nat_value value <= upper.
Proof.
  intros value lower upper. unfold bound,nat_value.
  destruct (natural value); [|discriminate].
  rewrite andb_true_iff. intros [L R].
  apply N.leb_le in L. apply N.leb_le in R. auto.
Qed.

Theorem admitted_thresholds_have_required_order : forall source,
  thresholds_valid source = true ->
  1 <= nat_value (policy_field source "background_percent") /\
  nat_value (policy_field source "background_percent") < nat_value (policy_field source "blocking_percent") /\
  nat_value (policy_field source "blocking_percent") < 100.
Proof.
  intros source H. unfold thresholds_valid in H.
  repeat rewrite andb_true_iff in H.
  destruct H as [[[[[shape enabled] background] blocking] ordered] idle].
  apply bounded_observation_is_in_range in background.
  apply bounded_observation_is_in_range in blocking.
  apply N.ltb_lt in ordered. lia.
Qed.

Theorem successful_compaction_has_required_threshold_order : forall budget source result,
  compaction budget source = success result ->
  1 <= nat_value (get result "background_percent") /\
  nat_value (get result "background_percent") < nat_value (get result "blocking_percent") /\
  nat_value (get result "blocking_percent") < 100.
Proof.
  intros budget source result E. unfold compaction in E.
  destruct (thresholds_valid source && is_array (policy_field source "targets") &&
    targets_valid budget (get source "profiles") (nat_value (policy_field source "idle_lead_ms")) []
      (items (policy_field source "targets"))) eqn:guard; [|discriminate].
  inversion E; subst result. cbn.
  apply admitted_thresholds_have_required_order.
  repeat rewrite andb_true_iff in guard. tauto.
Qed.

Theorem successful_remote_configuration_requires_https_origin : forall source value,
  remote source = success (JObject [("relay_url",value)]) ->
  str (get source "endpoint_observation") "protocol" = "https:".
Proof.
  intros source value H. unfold remote in H.
  destruct (get source "remote"); try (destruct value0); try discriminate;
    try match type of H with context [if ?condition then _ else _] =>
      destruct condition eqn:guard; [|discriminate] end;
    repeat rewrite andb_true_iff in guard;
    repeat match goal with H : _ /\ _ |- _ => destruct H end;
    match goal with H : String.eqb _ "https:" = true |- _ => apply String.eqb_eq in H;exact H end.
Qed.
