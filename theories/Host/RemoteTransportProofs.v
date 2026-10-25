From Stdlib Require Import Bool NArith List Lia.
From Selvedge.Host Require Import RemoteTransport.
Import ListNotations.
Open Scope N_scope.

Definition remaining_checks state := match state with
 | FirstCheck => 4 | SecondCheck => 3 | ThirdCheck => 2 | LastCheck => 1
 | Authorized | Denied | RevisionChanged => 0 end.

(** The interpreter can request another native check only by consuming one of
    four successive states. A sequence-changing workload cannot sustain a loop. *)
Theorem authorization_retry_decreases state active allowed checked current :
 snd (authorize state (GrantChecked active allowed checked current)) = CheckAgain ->
 remaining_checks (fst (authorize state (GrantChecked active allowed checked current))) < remaining_checks state.
Proof.
 destruct state, active, allowed; cbn; try discriminate;
 destruct (N.eqb checked current); cbn; intros; try discriminate; lia.
Qed.

Theorem completed_authorization_never_reissues_capture state active allowed checked current :
 remaining_checks state = 0 ->
 snd (authorize state (GrantChecked active allowed checked current)) <> Capture.
Proof. destruct state; cbn; intros; try discriminate. Qed.

(** Authentication failure is absorbing for every asynchronous observation.
    Only a new explicit Enable may start another physical attempt. *)
Theorem rejected_identity_ignores_async_observations cfg generation event :
 event <> Enable -> event <> Stop ->
 step cfg (AuthenticationFailed generation) event = (AuthenticationFailed generation,[]).
Proof.
 destruct event; intros; try contradiction;
 unfold step, current, RemoteTransport.generation; try rewrite andb_false_r; reflexivity.
Qed.

Theorem retry_observation_before_deadline_does_not_connect cfg generation tries deadline now :
 now < deadline ->
 step cfg (Retrying generation tries deadline) (Retry generation now) = (Retrying generation tries deadline,[]).
Proof.
 intros Before. cbn [step]. rewrite N.eqb_refl, (proj2 (N.leb_gt deadline now) Before).
 reflexivity.
Qed.
