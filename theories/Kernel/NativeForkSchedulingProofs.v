From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require OptionList.
From Selvedge.Kernel Require TaskRegistry TaskRegistryProofs.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Kernel Require Import Domain Codec Tasks State Scheduler NativeTools.
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
 inversion Ready; reflexivity.
Qed.

Theorem a_ready_native_fork_carries_its_final_dispatch_gate : forall owner task before step,
 Scheduler.native_fork_ready owner task before = Some step ->
 (exists definition,
   Tasks.find_tool (call_name (Scheduler.native_fork_invocation step)) (contract_tools (task_contract task)) = Some definition /\
   Scheduler.call_admission definition (Scheduler.native_fork_invocation step) before = None) /\
 NativeTools.command owner (Scheduler.native_fork_invocation step) = Some (Commands.Cmd_fork (Scheduler.native_fork_request step)) /\
 Scheduler.internal_result_available task = true /\
 call_name (Scheduler.native_fork_invocation step) = "fork_task".
Proof.
 intros owner task before step Ready; unfold Scheduler.native_fork_ready in Ready.
 destruct (Scheduler.fork_dispatch_call task) as [[[invocation remaining] retry]|]; try discriminate.
 destruct (find_tool _ _) as [definition|] eqn:Found; try discriminate.
 destruct (_ && _ && _) eqn:Eligible; try discriminate.
 destruct (Scheduler.call_admission definition invocation before) eqn:Admitted; try discriminate.
 destruct (NativeTools.command owner invocation) as [command|] eqn:Decoded; try discriminate.
 destruct command; try discriminate.
 inversion Ready; subst step; cbn.
 apply andb_true_iff in Eligible as [Eligible Room].
 apply andb_true_iff in Eligible as [Retry Name].
 apply String.eqb_eq in Name.
 split; [exists definition; split; assumption|].
 repeat split; assumption.
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
 - destruct next; try discriminate.
   all: pose proof (a_ready_native_fork_keeps_the_selected_owner first current before step Selected) as Owner.
   all: exists 0%N,current; split; [reflexivity|]; split; [lia|]; now rewrite Owner.
 - destruct (IH before (N.succ first) step Selected) as [offset [task [Found [Owner Ready]]]].
   exists (N.succ offset),task; split.
   + change (registry_at (N.succ offset) (current :: rest) = Some task).
     rewrite registry_lookup_after_head; exact Found.
   + split; [lia|exact Ready].
Qed.

Lemma selected_world_step_belongs_to_its_scope permitted value selected :
 Scheduler.select_world_step permitted value = Some selected ->
 In (Scheduler.selected_owner selected, Scheduler.selected_task selected) (scheduling_tasks value).
Proof.
 unfold Scheduler.select_world_step.
 generalize (scheduling_tasks value) as work.
 induction work as [|[id task] rest IH]; [discriminate|].
 cbn [OptionList.find_map].
 destruct (Scheduler.next_runnable_step permitted id task value).
 - intros Found; inversion Found; left; reflexivity.
 - intros Found; right; now apply IH.
Qed.

Theorem the_world_native_fork_has_an_observed_ready_owner permitted before step :
 Scheduler.first_world_native_fork permitted before = Some step ->
 exists current,
 find_task (Scheduler.native_fork_owner step) before = Some current /\
 Scheduler.native_fork_ready (Scheduler.native_fork_owner step) current before = Some step.
Proof.
 unfold Scheduler.first_world_native_fork.
 destruct (Scheduler.select_world_step permitted before) as [[id task action]|] eqn:Selected; [|discriminate].
 pose proof (selected_world_step_belongs_to_its_scope _ _ _ Selected) as Member.
 change (In (id,task) (scheduling_tasks before)) in Member.
 unfold scheduling_tasks in Member.
 apply (TaskRegistryProofs.selected_scope_matches_the_task_rows _ _ _ _ _
   (TaskRegistry.scheduling_agrees (world_task_registry before))) in Member as [Found _].
 unfold Scheduler.selected_native_fork. destruct action; try discriminate;
   intros Ready; cbn in Ready;
   pose proof (a_ready_native_fork_keeps_the_selected_owner id task before step Ready) as Owner;
   exists task; rewrite Owner; split; assumption.
Qed.

Theorem a_yielded_native_fork_keeps_the_world_and_prior_effects :
 forall advance fuel execute permitted before effects accepted retained step,
 existsb Scheduler.effect_requires_commit effects = false ->
 advance (SideContext.reconcile before) effects = Some (accepted,retained) ->
 Scheduler.first_world_native_fork permitted accepted = Some step ->
 Scheduler.schedule_with advance (S fuel) execute permitted before effects =
   (accepted,retained ++ [ContinueScheduling]).
Proof.
 intros advance fuel execute permitted before effects accepted retained step NoCommit Prefix Fork.
 cbn [Scheduler.schedule_with]. rewrite NoCommit,Prefix.
 unfold Scheduler.first_world_native_fork in Fork.
 destruct (Scheduler.select_world_step permitted accepted); [|discriminate].
 now rewrite Fork.
Qed.
