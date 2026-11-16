From Stdlib Require Import Bool NArith List Lia.
From Selvedge.Host Require Import RemoteTransport.
Import ListNotations.
Open Scope N_scope.

Theorem rejected_identity_ignores_async_observations cfg generation event :
 event <> Enable -> event <> Stop ->
 exists next_generation, generation <= next_generation /\
 step cfg (AuthenticationFailed generation) event = (AuthenticationFailed next_generation,[]).
Proof.
 destruct event; intros; try contradiction.
 all: exists generation; split; [apply N.le_refl|].
 all: unfold step, current, RemoteTransport.generation; try rewrite andb_false_r; reflexivity.
Qed.

Theorem current_retry_rearms_or_connects cfg generation tries deadline now :
 match snd (step cfg (Retrying generation tries deadline) (Retry generation now)) with
 | [RetryAt own scheduled] => own = generation /\ scheduled = deadline /\ now < deadline
 | [Connect next] => generation < next /\ deadline <= now
 | _ => False end.
Proof.
 cbn [step]. rewrite N.eqb_refl.
 destruct (deadline <=? now) eqn:Due; cbn.
 - split; [apply N.lt_succ_diag_r|now apply N.leb_le].
 - repeat split; try reflexivity. now apply N.leb_gt.
Qed.
