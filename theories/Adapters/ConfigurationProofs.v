From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common Observation Configuration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem accepted_evaluator_plan_uses_a_declared_provider : forall definitions instructions source result,
  Configuration.call definitions instructions "config.evaluator_plan" source = success result ->
  has_error result = false ->
  exists provider,
    In provider (map evaluator_name evaluator_providers) /\
    get (get (hd JNull (items (get result "fields"))) "value") "literal" = JString provider /\
    Forall (fun assignment => get assignment "key" = JString "provider" ->
      get (get assignment "value") "literal" = JString provider) (items (get result "fields")).
Proof.
  intros definitions instructions source result accepted valid.
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

Theorem accepted_context_request_uses_declared_sources : forall definitions instructions source requested,
  Configuration.call definitions instructions "config.context_transport" source = success (literal JNull) ->
  In requested (items (get source "definitions")) -> In requested (items definitions).
Proof.
  intros definitions instructions source requested accepted member.
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
