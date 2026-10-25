From Stdlib Require Import NArith.
From Selvedge.Kernel Require Import Domain State TaskScope.

(* Erase the lookup witness before using an observed equality. This keeps
   computation proofs independent of equality-proof representations. *)
Lemma selected_result_erases_its_lookup_witness : forall (A : Type) id before
 (continue : option (TaskScope.task_reference before) -> A)
 (compute : N -> task -> A) absent,
 (forall reference, continue (Some reference) = compute
   (TaskScope.owner reference) (TaskScope.selected reference)) ->
 continue None = absent ->
 continue (TaskScope.select id before) =
 (match find_task id before with Some current => compute id current | None => absent end).
Proof.
 intros A id before continue compute absent Erase Missing.
 assert (General : forall found (evidence : find_task id before = found),
   continue (match found as selected return find_task id before = selected ->
       option (TaskScope.task_reference before) with
     | Some current => fun observed => Some (TaskScope.TaskReference before id current observed)
     | None => fun _ => None end evidence) =
   match found with Some current => compute id current | None => absent end).
 { intros [current|] evidence; cbn; [apply Erase|exact Missing]. }
 apply General.
Qed.
