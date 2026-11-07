From Stdlib Require Import String Ascii Bool NArith.
From Selvedge.Programming Require ArgumentDeclaration.
Open Scope N_scope.

Inductive controller_id := ControllerId (controller_text : string).
Inductive request_id := RequestId (request_text : string).
Inductive grant_epoch := GrantEpoch (epoch_number : N).
Definition controller_text (value : controller_id) := match value with ControllerId text => text end.
Definition request_text (value : request_id) := match value with RequestId text => text end.
Definition epoch_number (value : grant_epoch) := match value with GrantEpoch number => number end.
Coercion controller_text : controller_id >-> string.
Coercion request_text : request_id >-> string.
Coercion epoch_number : grant_epoch >-> N.

Definition controller_declaration := ArgumentDeclaration.exact_lower_hex 64.
Definition request_valid (value : string) := negb (String.eqb value EmptyString) &&
 (N.of_nat (String.length value) <=? 128).
Definition max_epoch : N := 9007199254740991.
