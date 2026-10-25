From Stdlib Require Import String NArith Lia.
From Selvedge.Foundation Require Import EnrollmentCredential.
From Selvedge.Host Require Import RemoteProtocol RelayAdmission.
Open Scope string_scope.
Open Scope N_scope.

Lemma substring_covers text count :
 (String.length text <= count)%nat -> String.substring 0 count text = text.
Proof.
 revert count; induction text; intros count enough; destruct count; cbn in *; try reflexivity; try lia.
 f_equal. apply IHtext. lia.
Qed.

Theorem enrollment_header_uses_shared_language credential :
 authorize Enrollment ("Bearer " ++ credential) =
 if EnrollmentCredential.valid credential then Credential credential else Reject 401 "unauthorized".
Proof.
 unfold authorize. cbn.
 assert (empty : String.substring 0 0 credential = "") by (destruct credential; reflexivity).
 rewrite empty. cbn. rewrite !substring_covers by lia. reflexivity.
Qed.

Theorem accepted_enrollment_header_fits_budget credential :
 authorize Enrollment ("Bearer " ++ credential) = Credential credential ->
 (N.of_nat (String.length ("Bearer " ++ credential)) <= EnrollmentCredential.authorization_maximum_length)%N.
Proof.
 intro accepted. rewrite enrollment_header_uses_shared_language in accepted.
 destruct (EnrollmentCredential.valid credential) eqn:language; [|discriminate].
 unfold EnrollmentCredential.valid in language.
 apply Bool.andb_true_iff in language as [bounds _].
 apply Bool.andb_true_iff in bounds as [_ maximum].
 apply N.leb_le in maximum.
 unfold EnrollmentCredential.authorization_maximum_length.
 change (N.of_nat (7 + String.length credential)%nat <= EnrollmentCredential.maximum_length + 7)%N.
 rewrite Nat2N.inj_add. unfold EnrollmentCredential.maximum_length in *.
 change (7 + N.of_nat (String.length credential) <= 519)%N. lia.
Qed.
