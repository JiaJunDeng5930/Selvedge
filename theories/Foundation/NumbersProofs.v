From Stdlib Require Import String List Bool NArith Numbers.DecimalString Numbers.DecimalN.
From Selvedge.Foundation Require Import Numbers.

Lemma natural_print_parse : forall value,
 Selvedge.Foundation.Numbers.parse_natural (show_natural value) = Some value.
Proof.
 intros value.
 assert (Nonempty : N.to_uint value <> Decimal.Nil).
 { intro H. pose proof (DecimalN.Unsigned.of_to value) as Roundtrip.
   rewrite H in Roundtrip; cbn in Roundtrip. subst value. discriminate. }
 pose proof (NilZero.usu (N.to_uint value) Nonempty) as Printed.
 change (NilZero.uint_of_string (show_natural value) = Some (N.to_uint value)) in Printed.
 unfold Selvedge.Foundation.Numbers.parse_natural.
 destruct (show_natural value) eqn:Text; [cbn in Printed; discriminate|].
 rewrite Printed, DecimalN.Unsigned.of_to; reflexivity.
Qed.
