From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema Arguments.
Import ListNotations.
Open Scope N_scope.

Theorem accepted_numeric_arguments_respect_the_declared_bounds :
 forall declaration source argument lower upper text,
 Arguments.valid declaration source = true ->
 In argument declaration ->
 argument_bounds argument = Some (lower,upper) ->
 field (argument_name argument) source = Some (JNumber text) ->
 exists value, parse_natural text = Some value /\ lower <= value <= upper.
Proof.
 intros declaration source argument lower upper text Valid Member Bounds Present.
 unfold Arguments.valid in Valid.
 destruct (Schema.decode (Arguments.argument_schema declaration) source); [|discriminate].
 apply forallb_forall with (x := argument) in Valid; [|exact Member].
 unfold Arguments.argument_valid in Valid. rewrite Present in Valid.
 destruct (Arguments.type_valid (argument_type_of argument) (JNumber text)); [|discriminate].
 rewrite Bounds in Valid. unfold Arguments.numeric_bounds in Valid; cbn in Valid.
 destruct (parse_natural text) as [value|] eqn:Parsed; [|discriminate].
 apply andb_true_iff in Valid as [Lower Upper].
 apply N.leb_le in Lower; apply N.leb_le in Upper.
 exists value; auto.
Qed.


Theorem structured_arguments_execute_their_declaration : forall declaration value,
 Arguments.type_valid (Structured (ArgumentDeclaration.compile declaration)) value =
 ArgumentDeclaration.check declaration value.
Proof. reflexivity. Qed.
