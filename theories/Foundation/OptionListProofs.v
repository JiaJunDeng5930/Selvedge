From Selvedge.Foundation Require Import OptionList.

Lemma observe_present : forall A B (source : option A) present absent value (P : B -> Prop),
 source = Some value -> (forall evidence, P (present value evidence)) ->
 P (observe source present absent).
Proof.
 intros A B [current|] present absent value P Found Satisfied; [|discriminate].
 inversion Found; subst current; apply Satisfied.
Qed.
Lemma observe_absent : forall A B (source : option A) present absent (P : B -> Prop),
 source = None -> (forall evidence, P (absent evidence)) -> P (observe source present absent).
Proof. intros A B [current|] present absent P Missing Satisfied; [discriminate|apply Satisfied]. Qed.

Lemma observe_cases : forall A B (source : option A) present absent (P : B -> Prop),
 (forall value evidence, P (present value evidence)) ->
 (forall evidence, P (absent evidence)) -> P (observe source present absent).
Proof. intros A B [value|] present absent P Present Absent; [apply Present|apply Absent]. Qed.
