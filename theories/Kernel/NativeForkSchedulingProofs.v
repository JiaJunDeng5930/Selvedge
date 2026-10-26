From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Kernel Require Import Domain Codec Tasks State Scheduler WorldInvariant NativeTools.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma a_ready_native_fork_keeps_the_selected_owner : forall owner task before step,
 Scheduler.native_fork_ready owner task before = Some step ->
 Scheduler.native_fork_owner step = owner.
Proof.
 intros owner task before step Ready; unfold Scheduler.native_fork_ready in Ready.
 destruct (Scheduler.fork_dispatch_call task) as [[[invocation remaining] retry]|]; try discriminate.
 destruct (find_tool _ _) as [definition|]; try discriminate.
 destruct (_ && _ && _) eqn:Eligible; try discriminate.
 destruct (Scheduler.call_admission definition invocation before); try discriminate.
 destruct (NativeTools.command owner invocation) as [command|]; try discriminate.
 destruct command; try discriminate.
 destruct (N.eqb _ _) eqn:Owner; try discriminate.
 inversion Ready; reflexivity.
Qed.

Theorem a_ready_native_fork_carries_its_final_dispatch_gate : forall owner task before step,
 Scheduler.native_fork_ready owner task before = Some step ->
 Scheduler.call_admission (Scheduler.native_fork_tool step) (Scheduler.native_fork_invocation step) before = None /\
 NativeTools.command owner (Scheduler.native_fork_invocation step) = Some (Commands.Cmd_fork (Scheduler.native_fork_request step)) /\
 Scheduler.internal_result_available task = true /\
 call_name (Scheduler.native_fork_invocation step) = "fork_task" /\
 Commands.fork_task_id (Scheduler.native_fork_request step) = owner.
Proof.
 intros owner task before step Ready; unfold Scheduler.native_fork_ready in Ready.
 destruct (Scheduler.fork_dispatch_call task) as [[[invocation remaining] retry]|]; try discriminate.
 destruct (find_tool _ _) as [definition|]; try discriminate.
 destruct (_ && _ && _) eqn:Eligible; try discriminate.
 destruct (Scheduler.call_admission definition invocation before) eqn:Admitted; try discriminate.
 destruct (NativeTools.command owner invocation) as [command|] eqn:Decoded; try discriminate.
 destruct command; try discriminate.
 destruct (N.eqb _ _) eqn:Owner; try discriminate.
 inversion Ready; subst step; cbn.
 apply andb_true_iff in Eligible as [Eligible Room].
 apply andb_true_iff in Eligible as [Retry Name].
 apply String.eqb_eq in Name; apply N.eqb_eq in Owner.
 repeat split; try assumption; symmetry; exact Owner.
Qed.

Lemma a_ready_native_fork_keeps_its_frozen_tool : forall owner task before step,
 Scheduler.native_fork_ready owner task before = Some step ->
 Tasks.find_tool (call_name (Scheduler.native_fork_invocation step)) (contract_tools (task_contract task)) =
 Some (Scheduler.native_fork_tool step).
Proof.
 intros owner task before step Ready; unfold Scheduler.native_fork_ready in Ready.
 destruct (Scheduler.fork_dispatch_call task) as [[[invocation remaining] retry]|]; try discriminate.
 destruct (find_tool _ _) as [definition|] eqn:Found; try discriminate.
 destruct (_ && _ && _) eqn:Eligible; try discriminate.
 destruct (Scheduler.call_admission definition invocation before); try discriminate.
 destruct (NativeTools.command owner invocation) as [command|]; try discriminate.
 destruct command; try discriminate.
 destruct (N.eqb _ _) eqn:Owner; try discriminate.
 inversion Ready; subst step; exact Found.
Qed.

Lemma a_ready_native_fork_keeps_its_dispatch_call : forall owner task before step,
 Scheduler.native_fork_ready owner task before = Some step ->
 exists retry, Scheduler.fork_dispatch_call task =
   Some (Scheduler.native_fork_invocation step,Scheduler.native_fork_remaining step,retry).
Proof.
 intros owner task before step Ready; unfold Scheduler.native_fork_ready in Ready.
 destruct (Scheduler.fork_dispatch_call task) as [[[invocation remaining] retry]|] eqn:Call; try discriminate.
 destruct (find_tool _ _) as [definition|]; try discriminate.
 destruct (_ && _ && _) eqn:Eligible; try discriminate.
 destruct (Scheduler.call_admission definition invocation before); try discriminate.
 destruct (NativeTools.command owner invocation) as [command|]; try discriminate.
 destruct command; try discriminate.
 destruct (N.eqb _ _) eqn:Owner; try discriminate.
 inversion Ready; subst step; exists retry; reflexivity.
Qed.

Theorem the_selected_native_fork_has_an_observed_ready_owner :
 forall permitted tasks before first step,
 Scheduler.first_native_fork permitted first tasks before = Some step ->
 exists offset current,
 registry_at offset tasks = Some current /\
 Scheduler.native_fork_owner step = (first + offset)%N /\
 Scheduler.native_fork_ready (Scheduler.native_fork_owner step) current before = Some step.
Proof.
 intros permitted tasks; induction tasks as [|current rest IH]; intros before first step Selected; [discriminate|].
 cbn [Scheduler.first_native_fork] in Selected.
 destruct (Scheduler.next_runnable_step permitted first current before) as [next|] eqn:Next.
 - destruct next; [discriminate|].
   pose proof (a_ready_native_fork_keeps_the_selected_owner first current before step Selected) as Owner.
   exists 0%N,current; split; [reflexivity|]. split; [lia|]. now rewrite Owner.
 - destruct (IH before (N.succ first) step Selected) as [offset [task [Found [Owner Ready]]]].
   exists (N.succ offset),task; split.
   + change (registry_at (N.succ offset) (current :: rest) = Some task).
     rewrite registry_lookup_after_head; exact Found.
   + split; [lia|exact Ready].
Qed.

Theorem a_yielded_native_fork_keeps_the_world_and_prior_effects :
 forall fuel execute permitted before effects step,
 existsb Scheduler.frozen_inference effects = false ->
 Scheduler.first_native_fork permitted 0
   (world_tasks (SideContext.reconcile before)) (SideContext.reconcile before) = Some step ->
 Scheduler.schedule (S fuel) execute permitted before effects =
   (SideContext.reconcile before,effects ++ [ContinueScheduling]).
Proof. intros; cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted]; rewrite H, H0; reflexivity. Qed.
