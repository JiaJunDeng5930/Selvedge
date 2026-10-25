From Stdlib Require Import String List Bool NArith.
From Selvedge.Host Require Import CloudResources.
Import ListNotations.

Fixpoint allocation_authority value := match value with
  | Allocating _ => true | Persisting next => allocation_authority next | _ => false end.
Definition no_allocate (result : state * list action) :=
  allocation_authority (fst result) = false /\ ~ In Allocate (snd result).
Lemma run_preserves_retirement value : allocation_authority value = false -> no_allocate (run value).
Proof. destruct value; unfold no_allocate; cbn; intros H; try discriminate; split; auto; intuition discriminate. Qed.
Lemma termination_never_allocates source : no_allocate (terminate_or_finish source).
Proof.
  unfold terminate_or_finish, save, no_allocate. repeat match goal with
  | |- context[if ?condition then _ else _] => destruct condition
  end; cbn; intuition discriminate.
Qed.
Lemma scan_never_allocates source offset instances total : no_allocate (scan_page source offset instances total).
Proof.
  unfold scan_page. repeat match goal with
  | |- context[if ?condition then _ else _] => destruct condition
  end; try apply termination_never_allocates; unfold save,no_allocate; cbn; intuition discriminate.
Qed.
Theorem retired_allocation_cannot_return value event :
  allocation_authority value = false -> no_allocate (step value event).
Proof.
  induction value; destruct event; cbn; intros retired; try discriminate;
  try (unfold no_allocate,save; cbn; intuition discriminate);
  try apply termination_never_allocates; try apply scan_never_allocates.
  all: repeat match goal with
    | |- context[if ?condition then _ else _] => destruct condition
    end; cbn; try apply termination_never_allocates;
    try (unfold no_allocate,save; cbn; intuition discriminate).
  all: try (match goal with value : state |- _ => destruct value end; cbn in *; try discriminate;
    try (apply run_preserves_retirement; cbn; assumption);
    try (unfold no_allocate; cbn; intuition discriminate)).
Qed.

Inductive trace : state -> list observation -> state -> Prop :=
  | TraceDone value : trace value [] value
  | TraceStep before event events after :
      trace (fst (step before event)) events after -> trace before (event :: events) after.
Theorem recovery_trace_never_regains_allocation receipt events final :
  trace (recovery_state receipt) events final -> allocation_authority final = false.
Proof.
  assert (initial : allocation_authority (recovery_state receipt) = false).
  { unfold recovery_state. destruct (String.eqb _ _); reflexivity. }
  generalize dependent initial. generalize (recovery_state receipt) as start.
  intros start retired execution. induction execution; auto.
  apply IHexecution. exact (proj1 (retired_allocation_cannot_return before event retired)).
Qed.

Theorem ssh_expiry_emits_no_probe deadline now :
  (deadline <=? now)%N = true ->
  snd (ssh_probe deadline now) = [Reject deadline_message].
Proof. intros expired. unfold ssh_probe. rewrite expired. reflexivity. Qed.

Theorem durable_readiness_revalidation_keeps_connection source instance host guidance :
  step (Persisting (Ready source instance host guidance)) Resume =
    (Revalidating source instance host guidance,[Prepare]).
Proof. reflexivity. Qed.
