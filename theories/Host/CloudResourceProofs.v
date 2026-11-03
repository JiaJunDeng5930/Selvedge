From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import CloudResources.
Import ListNotations.
Open Scope string_scope.

Fixpoint allocation_authority value := match value with
  | Allocating _ => true | Persisting next => allocation_authority next | _ => false end.
Definition no_allocate (result : state * option action) :=
  allocation_authority (fst result) = false /\ snd result <> Some Allocate.
Lemma run_preserves_retirement value : allocation_authority value = false -> no_allocate (run value).
Proof. destruct value; unfold no_allocate; cbn; intros H; try discriminate; split; auto; intuition discriminate. Qed.
Lemma termination_never_allocates source : no_allocate (terminate_or_finish source).
Proof.
  destruct source as [context [|[instance|]]]; cbn; unfold no_allocate; cbn; intuition discriminate.
Qed.
Lemma scan_never_allocates source instances total : no_allocate (scan_page source instances total).
Proof.
  destruct instances as [|instance [|other rest]]; cbn [scan_page];
  repeat match goal with | |- context[if ?condition then _ else _] => destruct condition end;
  unfold save,no_allocate; cbn; intuition discriminate.
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
  exists reason, ssh_step deadline (SshCheck now) = Reject reason.
Proof. intros expired. cbn [ssh_step]. unfold ssh_probe. rewrite expired. eexists; reflexivity. Qed.

Theorem ssh_wait_fits_remaining_deadline deadline observed duration :
  ssh_step deadline observed = Probe duration \/ ssh_step deadline observed = Delay duration ->
  let now := match observed with SshCheck now | SshProbeResult now _ _ => now end in
  (0 < duration /\ now + duration <= deadline)%N.
Proof.
  intros scheduled. destruct observed as [now | now code error].
  - unfold ssh_step,ssh_probe in scheduled.
    destruct (deadline <=? now)%N eqn:expired; [destruct scheduled; discriminate|].
    destruct scheduled as [scheduled | scheduled]; [|discriminate].
    inversion scheduled; subst duration. apply N.leb_gt in expired.
    split; [apply N.min_glb_lt; lia|].
    pose proof (N.le_min_r 15000 (deadline - now)); lia.
  - cbn [ssh_step] in scheduled.
    destruct (N.eqb code 0); [destruct scheduled; discriminate|].
    destruct (N.eqb code 255); [|destruct scheduled; discriminate].
    destruct (deadline <=? now)%N eqn:expired; [destruct scheduled; discriminate|].
    destruct scheduled as [scheduled | scheduled]; [discriminate|].
    inversion scheduled; subst duration. apply N.leb_gt in expired.
    split; [apply N.min_glb_lt; lia|].
    pose proof (N.le_min_r 2000 (deadline - now)); lia.
Qed.

Theorem durable_readiness_revalidation_keeps_connection source instance host guidance :
  step (Persisting (Ready source instance host guidance)) Resume =
    (Revalidating source instance host,Some Prepare).
Proof. reflexivity. Qed.

Theorem reconciled_termination_requires_the_unique_owned_instance : forall source instances total next id,
 scan_page source instances total = save (Terminating next id) ->
 next = source /\ exists instance,
 instances = [instance] /\ total = 1%N /\
 is_text (get instance "InstanceId") = true /\ id = str instance "InstanceId" /\ id <> "" /\
 get instance "ImageId" = get (get (metadata source) "request") "ImageId" /\
 get instance "InstanceType" = get (get (metadata source) "request") "InstanceType" /\
 get (get instance "Placement") "Zone" = get (get (get (metadata source) "request") "Placement") "Zone" /\
 get (get instance "VirtualPrivateCloud") "VpcId" = get (get (get (metadata source) "request") "VirtualPrivateCloud") "VpcId" /\
 get (get instance "VirtualPrivateCloud") "SubnetId" = get (get (get (metadata source) "request") "VirtualPrivateCloud") "SubnetId" /\
 exists tag, In tag (items (get instance "Tags")) /\
 str tag "Key" = "selvedge-task" /\ get tag "Value" = get (metadata source) "token".
Proof.
 intros source instances total next id Selected.
 destruct instances as [|instance [|other rest]]; cbn [scan_page] in Selected; try discriminate.
 destruct (N.eqb total 1 && owned source instance && is_text (get instance "InstanceId") &&
   negb (String.eqb (str instance "InstanceId") "")) eqn:Admitted; [|discriminate].
 unfold save in Selected. inversion Selected; subst next id.
 repeat rewrite andb_true_iff in Admitted.
 assert (Count : total = 1%N) by (apply N.eqb_eq; tauto).
 assert (Nonempty : str instance "InstanceId" <> "") by
   (apply String.eqb_neq; apply negb_true_iff; tauto).
 assert (Owned : owned source instance = true) by tauto.
 unfold owned in Owned. repeat rewrite andb_true_iff in Owned.
 assert (Tagged : matching_tag source instance = true) by tauto.
 unfold matching_tag in Tagged. apply existsb_exists in Tagged as [tag [Member Match]].
 apply andb_true_iff in Match as [Name Token].
 apply String.eqb_eq in Name. apply equal_reflects_equality in Token.
 split; [reflexivity|]. exists instance. repeat split; try reflexivity; try assumption;
   try (apply equal_reflects_equality; tauto); try tauto.
 exists tag. repeat split; assumption.
Qed.
