From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Codec.
Import ListNotations.
Open Scope string_scope.

(** Refusing a command is distinct from committing an observed IO failure.
    Refusals carry no candidate world or effects.  A successful command may
    still record a failed external operation in its resulting world. *)
Record refusal := Refusal { refusal_code : string; refusal_message : string }.
Inductive result (A : Type) := Accepted (value : A) | Rejected (reason : refusal).
Arguments Accepted {A}.
Arguments Rejected {A}.
Definition refuse {A} (code message : string) : result A := Rejected (Refusal code message).
Definition bind {A B} (value : result A) (next : A -> result B) : result B :=
 match value with Accepted value => next value | Rejected reason => Rejected reason end.
Definition map {A B} (f : A -> B) (value : result A) : result B :=
 bind value (fun value => Accepted (f value)).
Fixpoint traverse {A B} (f : A -> result B) (values : list A) : result (list B) :=
 match values with
 | [] => Accepted []
 | value :: rest => bind (f value) (fun value => map (cons value) (traverse f rest))
 end.

(** The successful branch stores an unencoded reply value.  Encoding occurs
    only when the typed outcome reaches the decision boundary. *)
Record change := Change {
 change_value : json;
 change_world : world;
 change_effects : list effect
}.
Definition accept (value : change) :=
 State.accept (change_value value) (change_world value) (change_effects value).
Definition append_effects (effects : list effect) (value : change) :=
 Change (change_value value) (change_world value) (change_effects value ++ effects).
Definition reject (before : world) (reason : refusal) :=
 State.reject (refusal_code reason) (refusal_message reason) before.
Definition resolve {A} (before : world) (run : A -> decision) (value : result A) :=
 match value with Accepted value => run value | Rejected reason => reject before reason end.
Definition decide (before : world) (value : result change) := resolve before accept value.
Definition commit {A} (before : world) (run : A -> change) (value : result A) :=
 decide before (map run value).
Lemma appending_effects_keeps_the_committed_world : forall A before (run : A -> change) value effects,
 decision_world (commit before (fun value => append_effects effects (run value)) value) =
 decision_world (commit before run value).
Proof. intros A before run [value|reason]; reflexivity. Qed.

Lemma rejection_is_atomic : forall before reason,
 decision_world (reject before reason) = before /\ decision_effects (reject before reason) = [].
Proof. intros; split; reflexivity. Qed.
Lemma rejection_has_a_failure_reply : forall before reason,
 bool_default "ok" (decision_reply (reject before reason)) false = false.
Proof. reflexivity. Qed.
Lemma acceptance_has_a_success_reply : forall value,
 bool_default "ok" (decision_reply (accept value)) false = true.
Proof. reflexivity. Qed.
Lemma a_successful_decision_identifies_its_typed_change : forall before value reply after effects,
 decide before value = State.accept reply after effects ->
 value = Accepted (Change reply after effects).
Proof.
 intros before [[payload next emitted]|reason] reply after effects Accepted; [|discriminate].
 cbn [decide resolve accept State.accept] in Accepted.
 injection Accepted as World Reply Effects; subst; reflexivity.
Qed.
Lemma appending_effects_to_an_accepted_result : forall before value reply after effects extra,
 decide before value = State.accept reply after effects ->
 commit before (append_effects extra) value = State.accept reply after (effects ++ extra).
Proof.
 intros before value reply after effects extra Accepted.
 apply a_successful_decision_identifies_its_typed_change in Accepted; now rewrite Accepted.
Qed.
Theorem a_failed_command_is_atomic : forall before value,
 bool_default "ok" (decision_reply (decide before value)) false = false ->
 decision_world (decide before value) = before /\ decision_effects (decide before value) = [].
Proof. intros before [value|reason] Failed; [discriminate|apply rejection_is_atomic]. Qed.
Theorem a_failed_commit_is_atomic : forall A before (run : A -> change) value,
 bool_default "ok" (decision_reply (commit before run value)) false = false ->
 decision_world (commit before run value) = before /\ decision_effects (commit before run value) = [].
Proof. intros; now apply a_failed_command_is_atomic. Qed.

Lemma resolve_bind : forall A B before (run : B -> decision) (next : A -> result B) value,
 resolve before run (bind value next) = resolve before (fun value => resolve before run (next value)) value.
Proof. intros A B before run next [value|reason]; reflexivity. Qed.
Lemma traverse_refuses_first : forall A B (f : A -> result B) value rest reason,
 f value = Rejected reason -> traverse f (value :: rest) = Rejected reason.
Proof. intros; cbn [traverse]; now rewrite H. Qed.
Lemma traverse_refuses_tail : forall A B (f : A -> result B) value rest first reason,
 f value = Accepted first -> traverse f rest = Rejected reason ->
 traverse f (value :: rest) = Rejected reason.
Proof. intros; cbn [traverse]; rewrite H; cbn [bind]; now rewrite H0. Qed.
