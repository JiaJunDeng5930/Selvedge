From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation BrowserAdapters.
Import ListNotations.
Open Scope string_scope.

Theorem returned_link_has_an_admitted_scheme : forall source target,
  link source = JString target ->
  starts target "#" || allowed_target target = true.
Proof.
  intros source target H. unfold link in H.
  destruct (raw_valid (get source "raw"));[|discriminate].
  destruct (starts (text (get source "raw")) "#") eqn:fragment.
  - rewrite H in fragment. change (starts target "#" = true) in fragment. now rewrite fragment.
  - match type of H with context[if ?accepted then _ else JNull] => destruct accepted eqn:admission end;[|discriminate].
    repeat rewrite andb_true_iff in admission.
    assert (allowed : allowed_target (str (get source "observation") "href") = true) by tauto.
    unfold str in allowed. rewrite H in allowed. change (allowed_target target = true) in allowed. rewrite allowed,orb_true_r;reflexivity.
Qed.
Theorem safe_fragment_navigation_is_not_rejected : forall source,
  raw_valid (get source "raw") = true -> starts (str source "raw") "#" = true ->
  link source = get source "raw".
Proof. intros source raw fragment;unfold str in fragment;unfold link;rewrite raw,fragment;reflexivity. Qed.
