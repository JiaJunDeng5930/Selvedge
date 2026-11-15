From Stdlib Require Import List Bool PeanoNat.
From Selvedge.Features Require Import Workflow WorkflowTypes.

Theorem completion_reports_all_paths_at_exits (i : execution) :
 complete i = true <->
 instance_paths i <> nil /\
 Forall (fun p => exists exit source result, path_value p = Arrived exit source result) (instance_paths i).
Proof.
 unfold complete. rewrite andb_true_iff, negb_true_iff, Nat.eqb_neq, forallb_forall.
 assert (Nonempty : length (instance_paths i) <> 0 <-> instance_paths i <> nil).
 { destruct (instance_paths i); simpl; split; congruence. }
 rewrite Nonempty, Forall_forall.
 split; intros [Present Exits]; split; try assumption.
 - intros p Member. specialize (Exits p Member). unfold arrived in Exits.
   destruct (path_value p) eqn:State; try discriminate. eauto.
 - intros p Member. destruct (Exits p Member) as [exit [source [result State]]].
   unfold arrived. now rewrite State.
Qed.

Theorem completion_does_not_hide_outstanding_paths (i : execution) :
 complete i = true ->
 forall p, In p (instance_paths i) -> arrived p = true.
Proof.
 intros Completed p Member.
 apply completion_reports_all_paths_at_exits in Completed as [_ Exits].
 rewrite Forall_forall in Exits.
 destruct (Exits p Member) as [exit [source [result State]]].
 unfold arrived. now rewrite State.
Qed.
