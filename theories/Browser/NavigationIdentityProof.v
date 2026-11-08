From Stdlib Require Import String Bool.
From Selvedge.Interaction Require Identity.
From Selvedge.Browser Require NavigationIdentity.

Theorem key_comparison_reflects_identity left right:
 NavigationIdentity.same_key left right=true <-> left=right.
Proof.
 unfold NavigationIdentity.same_key. destruct(NavigationIdentity.key_eq_dec left right);split;intros;auto;discriminate.
Qed.
Theorem a_component_cannot_be_mistaken_for_its_parent path first second:
 NavigationIdentity.Part(NavigationIdentity.Place path)(String.append first second)<>
 NavigationIdentity.Part(NavigationIdentity.Part(NavigationIdentity.Place path)first)second.
Proof. discriminate. Qed.
