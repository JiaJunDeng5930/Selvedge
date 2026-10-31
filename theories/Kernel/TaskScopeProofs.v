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

Lemma selecting_an_existing_task_retains_its_key : forall id before current,
 find_task id before = Some current ->
 exists reference, TaskScope.select id before = Some reference /\
   TaskScope.owner reference = id /\ TaskScope.selected reference = current.
Proof.
 intros id before current Found.
 assert (General : forall found (evidence : find_task id before = found),
   found = Some current ->
   exists reference,
    (match found as selected return find_task id before = selected ->
       option (TaskScope.task_reference before) with
     | Some selected => fun observed => Some (TaskScope.TaskReference before id selected observed)
     | None => fun _ => None end evidence) = Some reference /\
    TaskScope.owner reference = id /\ TaskScope.selected reference = current).
 { intros [selected|] evidence Equal; [|discriminate].
   inversion Equal; subst selected.
   exists (TaskScope.TaskReference before id current evidence); repeat split; reflexivity. }
 apply General; exact Found.
Qed.

(* Eliminate a selected reference with its observed public key. The motive can
   be the whole theorem, so a proof never repeats the business program merely
   to erase its lookup witness. *)
Lemma selected_reference_elimination : forall id before
 (property : option (TaskScope.task_reference before) -> Prop),
 (forall reference, TaskScope.owner reference = id -> property (Some reference)) ->
 (find_task id before = None -> property None) ->
 property (TaskScope.select id before).
Proof.
 intros id before property Present Missing.
 assert (General : forall found (evidence : find_task id before = found),
   property (match found as selected return find_task id before = selected ->
       option (TaskScope.task_reference before) with
     | Some current => fun observed => Some (TaskScope.TaskReference before id current observed)
     | None => fun _ => None end evidence)).
 { intros [current|] evidence; cbn; [apply Present; reflexivity|apply Missing; exact evidence]. }
 apply General.
Qed.

(* Derive an ordinary lookup view from the single scoped implementation. The
   supplied reduction only interprets plans and projections. The equality below
   is always proved by selected_result_erases_its_lookup_witness; no business
   branches are restated, and the derived proof is checked by the kernel. *)
Ltac derive_task_lookup_view program expression id before reduce_plan :=
 let abstracted := eval pattern (TaskScope.select id before) in expression in
 let result_type := type of expression in
 lazymatch abstracted with
 | ?continue _ =>
   let compute := constr:(fun (owner : N) (current : task) =>
     (ltac:(let reduced := reduce_plan
       constr:(fun observed : find_task owner before = Some current =>
         continue (Some (TaskScope.TaskReference before owner current observed))) in
       lazymatch reduced with (fun _ => ?result) => exact result end) : result_type)) in
   let absent := eval cbv beta iota zeta in (continue None) in
   exact (selected_result_erases_its_lookup_witness _ id before continue compute absent
     ltac:(intros; reflexivity) eq_refl : program =
       match find_task id before with Some current => compute id current | None => absent end)
 end.
