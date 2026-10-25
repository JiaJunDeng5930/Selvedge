From Stdlib Require Import String Ascii Bool NArith.
From Selvedge.Foundation Require Import Utf8.
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
Fixpoint lowercase_hex (value : string) := match value with
 | EmptyString => true
 | String character rest =>
   let code := N.of_nat (nat_of_ascii character) in
   (((48 <=? code) && (code <=? 57)) || ((97 <=? code) && (code <=? 102))) && lowercase_hex rest end.
Definition controller_valid (value : string) := Nat.eqb (String.length value) 64 && lowercase_hex value.
Definition request_valid (value : string) := negb (String.eqb value EmptyString) && Utf8.well_formed value &&
 (N.of_nat (String.length value) <=? 128).
Definition max_epoch : N := 9007199254740991.
Definition epoch_valid (value : N) := (0 <? value) && (value <=? max_epoch).
