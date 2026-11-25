From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Kernel Require Import Domain State.

Record task_reference (before : world) := TaskReference {
 owner : N;
 selected : task;
 observed : find_task owner before = Some selected
}.
Arguments owner {before}.
Arguments selected {before}.
Arguments observed {before}.
Definition select (id : N) (before : world) : option (task_reference before) :=
 match find_task id before as found return find_task id before = found -> option (task_reference before) with
 | Some current => fun evidence => Some (TaskReference before id current evidence)
 | None => fun _ => None end eq_refl.

(** Traverse the registry once and retain the same identity witness as a
    point lookup. The suffix witness is erased from execution. *)
Definition observes_suffix before (offset : N) (tasks : list task) :=
 forall index, find_task (offset + index) before = registry_at index tasks.

Lemma observes_first before offset current rest :
 observes_suffix before offset (current :: rest) ->
 find_task offset before = Some current.
Proof.
 intros Observed. specialize (Observed 0%N).
 now rewrite N.add_0_r in Observed.
Qed.

Lemma observes_tail before offset current rest :
 observes_suffix before offset (current :: rest) ->
 observes_suffix before (N.succ offset) rest.
Proof.
 intros Observed index. rewrite N.add_succ_l, <- N.add_succ_r.
 specialize (Observed (N.succ index)).
 cbn [registry_at] in Observed.
 rewrite (proj2 (N.eqb_neq _ _) (N.neq_succ_0 index)), N.pred_succ in Observed.
 exact Observed.
Qed.

Fixpoint first_in {A : Type} (before : world) (choose : task_reference before -> option A)
 (offset : N) (tasks : list task) : observes_suffix before offset tasks -> option A :=
 match tasks as remaining return observes_suffix before offset remaining -> option A with
 | nil => fun _ => None
 | current :: rest => fun observed =>
   match choose (TaskReference before offset current (observes_first before offset current rest observed)) with
   | Some result => Some result
   | None => first_in before choose (N.succ offset) rest (observes_tail before offset current rest observed)
   end
 end.

Lemma observes_registry before : observes_suffix before 0%N (world_tasks before).
Proof. intro index; now rewrite N.add_0_l. Qed.

Definition first_matching {A : Type} (before : world) (choose : task_reference before -> option A) :=
 first_in before choose 0%N (world_tasks before) (observes_registry before).
