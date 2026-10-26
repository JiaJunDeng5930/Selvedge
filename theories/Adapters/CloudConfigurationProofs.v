From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common CloudConfiguration.
Open Scope string_scope.

Theorem enabled_configuration_passed_admission : forall source value,
  CloudConfiguration.call source = success value ->
  value <> JBool false ->
  CloudConfiguration.valid (get source "cloud") = true /\ value = get source "cloud".
Proof.
  intros source value accepted enabled. unfold CloudConfiguration.call in accepted.
  destruct (CloudConfiguration.disabled (get source "cloud")) eqn:disabled.
  - inversion accepted; subst. contradiction.
  - destruct (CloudConfiguration.valid (get source "cloud")) eqn:valid.
    + inversion accepted; subst. auto.
    + discriminate.
Qed.

Theorem configured_backend_is_tencent : forall value,
  CloudConfiguration.valid value = true ->
  str value "backend" = WorkspaceBackend.name WorkspaceBackend.TencentCvm.
Proof.
 intros source Accepted; unfold CloudConfiguration.valid, D.check in Accepted.
 destruct (D.decode declaration source) as [values|] eqn:Decoded; [|discriminate].
 destruct source as [|flag|number|text|items|members]; try discriminate.
 cbn [declaration D.decode] in Decoded.
 match type of Decoded with (if ?shape then _ else _) = _ => destruct shape; [|discriminate] end.
 destruct (Json.lookup "backend" members) as [raw|] eqn:Backend; [|discriminate].
 destruct raw as [|flag|number|name|items|object]; try discriminate.
 cbn [D.of_kind D.decode] in Decoded.
 match type of Decoded with context [if ?allowed then _ else _] =>
   destruct allowed eqn:Allowed; [|discriminate] end.
 unfold D.check_text in Allowed.
 destruct (Utf8.scalar_count name); [|discriminate].
 apply andb_true_iff in Allowed as [_ Choice]; cbn in Choice.
 rewrite orb_false_r in Choice; apply String.eqb_eq in Choice.
 unfold Common.str,Common.text,Common.get,Json.field; rewrite Backend; exact Choice.
Qed.
