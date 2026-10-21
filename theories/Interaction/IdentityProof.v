From Stdlib Require Import String Bool.
From Selvedge.Interaction Require Identity.

Theorem key_comparison_reflects_identity left right:
 Identity.same_key left right=true <-> left=right.
Proof.
 unfold Identity.same_key. destruct(Identity.key_eq_dec left right);split;intros;auto;discriminate.
Qed.
Theorem a_component_cannot_be_mistaken_for_its_parent path first second:
 Identity.key_json(Identity.Part(Identity.Place path)(String.append first second))<>
 Identity.key_json(Identity.Part(Identity.Part(Identity.Place path)first)second).
Proof. discriminate. Qed.
