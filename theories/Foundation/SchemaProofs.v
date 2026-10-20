From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
Import ListNotations.

Theorem encode_declared_fields : forall description (values : fields description),
  map fst (encode_fields values) = declared_names description.
Proof. intros description values; induction values; simpl; congruence. Qed.

Theorem rejects_unknown_field : forall description source,
  keys_declared description source = false ->
  decode description (JObject source) = None.
Proof. intros; unfold decode; rewrite H; now rewrite !Bool.andb_false_r. Qed.

Theorem rejects_duplicate_fields : forall description source,
  unique_names (source_keys source) = false ->
  decode description (JObject source) = None.
Proof. intros; unfold decode; rewrite H; now rewrite Bool.andb_false_r. Qed.

Theorem rejects_duplicate_schema : forall description source,
  schema_valid description = false -> decode description source = None.
Proof. intros; destruct source; simpl; auto; now rewrite H. Qed.

Theorem update_unknown_field : forall description name source (values : fields description),
  ~ In name (declared_names description) -> update_field name source values = None.
Proof.
  intros description name source values; induction values; simpl; auto.
  intro absent. destruct (String.eqb name (field_name field)) eqn:equal.
  - apply String.eqb_eq in equal. exfalso; apply absent; now left.
  - rewrite IHvalues; auto.
Qed.

Theorem update_preserves_unrelated_field : forall description name other source
  (values replacement : fields description),
  name <> other -> update_field name source values = Some replacement ->
  lookup_field other replacement = lookup_field other values.
Proof.
  intros description name other source values.
  induction values; intros replacement distinct changed; simpl in changed; try discriminate.
  destruct (String.eqb name (field_name field)) eqn:same.
  - destruct (decode_value (field_kind field) source) eqn:decoded; inversion changed; subst.
    simpl. apply String.eqb_eq in same.
    destruct (String.eqb other (field_name field)) eqn:other_same; auto.
    apply String.eqb_eq in other_same. exfalso; apply distinct; congruence.
  - destruct (update_field name source values) eqn:updated; inversion changed; subst.
    simpl. destruct (String.eqb other (field_name field)); auto.
Qed.
