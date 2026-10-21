From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation Http.
Import ListNotations.
Open Scope string_scope.

Theorem http_body_requires_authorization : forall source target value,
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  authorized source = true.
Proof.
  intros source target value H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)) eqn:authorized.
  - unfold authorization_rejection in H.
    destruct (connection_path source); discriminate.
  - apply negb_false_iff in authorized; exact authorized.
Qed.

Theorem http_body_requires_local_origin : forall source target value,
  connection_path source = false ->
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  local_origin_valid source = true.
Proof.
  intros source target value local H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)); [unfold authorization_rejection in H;rewrite local in H;discriminate|].
  rewrite local in H.
  destruct (negb (local_origin_valid source)) eqn:origin; [discriminate|].
  apply negb_false_iff in origin; exact origin.
Qed.

Theorem http_body_requires_connection_method_and_origin : forall source target value,
  connection_path source = true ->
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  str source "method" = "POST" /\ connection_origin_valid source = true.
Proof.
  intros source target value connection H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)); [unfold authorization_rejection in H;rewrite connection in H;discriminate|].
  rewrite connection in H.
  destruct (negb (String.eqb (str source "method") "POST")) eqn:method; [discriminate|].
  destruct (negb (connection_origin_valid source)) eqn:origin; [discriminate|].
  apply negb_false_iff in method. apply String.eqb_eq in method.
  apply negb_false_iff in origin; auto.
Qed.
