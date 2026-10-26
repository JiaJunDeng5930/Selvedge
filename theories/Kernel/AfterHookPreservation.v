From Selvedge.Kernel Require Import FeatureFrameProofs ForkPreservation TicketSupplyProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import Json JsonProofs Schema.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Features Require Import BoardFacts.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Callbacks
 TicketedRequest WorldInvariant WorldInvariantProofs CallbacksProofs LifecycleProofs.
Import ListNotations.

(* Archived results may advance pending operations while retaining every
   other field. The complete world lift is the common task-replacement law. *)
Definition without_archived_operations (value : task) :=
 match task_lifecycle value with Archived _ => with_operations [] value | _ => value end.

Definition replacing_a_registry_entry_lifts_its_relation :=
 @TaskFrameProofs.replacing_a_registry_entry_lifts_its_relation.

Lemma operation_identifiers_are_part_of_the_ticket_supply : forall operation,
 In (operation_id operation) (WorldInvariant.operation_tickets operation).
Proof. intros; unfold WorldInvariant.operation_tickets; left; reflexivity. Qed.

Lemma unique_operation_tickets_imply_unique_identifiers : forall operations,
 NoDup (flat_map WorldInvariant.operation_tickets operations) ->
 NoDup (map operation_id operations).
Proof.
 induction operations as [|first rest IH]; intros Unique; [constructor|].
 cbn [flat_map] in Unique; unfold WorldInvariant.operation_tickets at 1 in Unique.
 cbn in Unique; inversion Unique as [|? ? Fresh Tail]; subst.
 cbn; constructor; [|apply IH; eapply NoDup_app_remove_l; exact Tail].
 intros Member; apply in_map_iff in Member as [other [Same Member]].
 apply Fresh. apply in_or_app; right.
 apply in_flat_map; exists other; split; [exact Member|].
 rewrite <- Same; apply operation_identifiers_are_part_of_the_ticket_supply.
Qed.

Lemma replacing_an_absent_operation_is_identity : forall operations replacement,
 ~ In (operation_id replacement) (map operation_id operations) ->
 TicketedRequest.replace_operation replacement operations = operations.
Proof.
 induction operations as [|first rest IH]; intros replacement Absent; [reflexivity|].
 unfold TicketedRequest.replace_operation in *; cbn.
 destruct (N.eqb (operation_id replacement) (operation_id first)) eqn:Same.
 - exfalso; apply Absent; left; symmetry; apply N.eqb_eq; exact Same.
 - f_equal; apply IH. intro Present; apply Absent; right; exact Present.
Qed.

Lemma a_unique_operation_identifier_selects_exactly_one_operation :
 forall operations selected other,
 NoDup (map operation_id operations) ->
 In selected operations -> In other operations ->
 operation_id selected = operation_id other -> selected = other.
Proof.
 induction operations as [|first rest IH]; intros selected other Unique Selected Other Same;
   [contradiction|].
 cbn in Unique; inversion Unique as [|? ? Fresh Tail]; subst.
 destruct Selected as [<-|Selected]; destruct Other as [<-|Other]; [reflexivity| | |].
 - exfalso; apply Fresh. apply in_map_iff; exists other; auto.
 - exfalso; apply Fresh. apply in_map_iff; exists selected; split; [exact Same|exact Selected].
 - eapply IH; eauto.
Qed.

Theorem staging_an_after_hook_adds_exactly_one_fresh_ticket :
 forall operations original plugin pending result error ticket,
 NoDup (map operation_id operations) ->
 In original operations ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 ticket <> operation_id original ->
 Permutation
   (flat_map WorldInvariant.operation_tickets
     (TicketedRequest.replace_operation
       (Operation (operation_id original) (operation_call original) (operation_announced original)
         (AwaitingAfterHook ticket plugin pending result error)) operations))
   (ticket :: flat_map WorldInvariant.operation_tickets operations).
Proof.
 induction operations as [|first rest IH]; intros original plugin pending result error ticket
   Unique Member Stage Fresh; [contradiction|].
 cbn in Unique; inversion Unique as [|? ? FirstFresh RestUnique]; subst.
 cbn [TicketedRequest.replace_operation map flat_map operation_id].
 destruct (N.eqb (operation_id original) (operation_id first)) eqn:Same.
 - assert (Selected : original = first).
   { eapply (a_unique_operation_identifier_selects_exactly_one_operation (first :: rest));
       [exact Unique|exact Member|left; reflexivity|apply N.eqb_eq; exact Same]. }
   subst first.
   change (Permutation
     (WorldInvariant.operation_tickets
       (Operation (operation_id original) (operation_call original) (operation_announced original)
         (AwaitingAfterHook ticket plugin pending result error)) ++
       flat_map WorldInvariant.operation_tickets
         (TicketedRequest.replace_operation
           (Operation (operation_id original) (operation_call original) (operation_announced original)
             (AwaitingAfterHook ticket plugin pending result error)) rest))
     (ticket :: WorldInvariant.operation_tickets original ++ flat_map WorldInvariant.operation_tickets rest)).
   rewrite replacing_an_absent_operation_is_identity by exact FirstFresh.
   unfold WorldInvariant.operation_tickets; cbn [operation_id operation_stage]; rewrite Stage.
   rewrite (proj2 (N.eqb_neq ticket (operation_id original)) Fresh).
   cbn; apply perm_swap.
 - destruct Member as [<-|Member]; [rewrite N.eqb_refl in Same; discriminate|].
   change (Permutation (WorldInvariant.operation_tickets first ++
     flat_map WorldInvariant.operation_tickets (TicketedRequest.replace_operation
       (Operation (operation_id original) (operation_call original) (operation_announced original)
         (AwaitingAfterHook ticket plugin pending result error)) rest))
     (ticket :: WorldInvariant.operation_tickets first ++ flat_map WorldInvariant.operation_tickets rest)).
   eapply Permutation_trans.
   + apply Permutation_app_head. apply IH; assumption.
   + apply Permutation_sym; apply Permutation_middle.
Qed.

Lemma an_after_request_preserves_its_result_history :
 forall owner task original plugin pending result error ticket,
 WorldInvariant.results_correspond owner task original result error (plugin :: pending) =
 WorldInvariant.results_correspond owner task
   (Operation (operation_id original) (operation_call original) (operation_announced original)
     (AwaitingAfterHook ticket plugin pending result error)) result error (plugin :: pending).
Proof. intros; unfold WorldInvariant.results_correspond, WorldInvariant.after_step; reflexivity. Qed.

Theorem staging_an_archived_after_hook_preserves_its_operation_requirements :
 forall owner task operations original plugin pending result error ticket,
 task_lifecycle task = Archived operations ->
 In original operations ->
 NoDup (map operation_id operations) ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 (operation_id original < ticket)%N ->
 WorldInvariant.operations_valid owner task = true ->
 WorldInvariant.operations_valid owner
   (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original) (operation_announced original)
       (AwaitingAfterHook ticket plugin pending result error)) operations) task) = true.
Proof.
 intros owner task operations original plugin pending result error ticket ArchivedTask
   Member Unique Stage Fresh Valid.
 assert (Selected : forall other, In other operations ->
   N.eqb (operation_id original) (operation_id other) = true -> original = other).
 { intros other Other Same. eapply a_unique_operation_identifier_selects_exactly_one_operation;
     eauto; apply N.eqb_eq; exact Same. }
 destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
 cbn in ArchivedTask; subst lifecycle.
 unfold WorldInvariant.operations_valid in *.
 cbv [set] in *.
 cbn in *.
 apply andb_true_iff in Valid as [Prefix Valid].
 apply andb_true_iff in Prefix as [Length Calls].
 apply andb_true_iff; split.
 - apply andb_true_iff; split.
   + unfold TicketedRequest.replace_operation; rewrite length_map; exact Length.
   + assert (CallsUnchanged :
       map (fun operation => call_id (operation_call operation))
         (TicketedRequest.replace_operation
           (Operation (operation_id original) (operation_call original) (operation_announced original)
             (AwaitingAfterHook ticket plugin pending result error)) operations) =
       map (fun operation => call_id (operation_call operation)) operations).
     { unfold TicketedRequest.replace_operation; rewrite map_map; apply map_ext_in.
       intros other Other; cbn.
       destruct (N.eqb (operation_id original) (operation_id other)) eqn:Same; [|reflexivity].
       specialize (Selected other Other Same); subst other; reflexivity. }
     rewrite CallsUnchanged; exact Calls.
 - apply forallb_forall. intros other Other.
   unfold TicketedRequest.replace_operation in Other.
   apply in_map_iff in Other as [old [<- Old]].
   apply forallb_forall with (x:=old) in Valid; [|exact Old].
   cbn; destruct (N.eqb (operation_id original) (operation_id old)) eqn:Same; [|exact Valid].
   specialize (Selected old Old Same); subst old.
   repeat rewrite andb_true_iff in Valid |- *.
   destruct Valid as [[[Hooks History] Progress] Tool].
   repeat split; try exact Hooks; try exact History; try exact Tool.
   unfold WorldInvariant.operation_stage_valid in Progress; rewrite Stage in Progress.
   unfold WorldInvariant.operation_stage_valid; cbn [operation_id operation_stage].
   apply andb_true_iff; split; [apply N.ltb_lt; exact Fresh|].
   rewrite <- an_after_request_preserves_its_result_history; exact Progress.
Qed.
Theorem an_archived_after_request_adds_one_fresh_global_ticket :
 forall owner task before operations original plugin pending result error,
 WorldInvariant.tickets_valid before = true ->
 find_task owner before = Some task ->
 task_lifecycle task = Archived operations ->
 In original operations ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 let after := decision_world (TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before) in
 Permutation
   (flat_map WorldInvariant.task_tickets (world_tasks after) ++
     WorldInvariant.feature_tickets (world_features after))
   (world_next_ticket before ::
     (flat_map WorldInvariant.task_tickets (world_tasks before) ++
       WorldInvariant.feature_tickets (world_features before))).
Proof.
 intros owner task before operations original plugin pending result error Valid Found ArchivedTask Member Stage.
 pose proof (valid_world_execution_tickets_are_unique owner before task Valid Found) as Unique.
 unfold task_operations in Unique; rewrite ArchivedTask in Unique.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [_ Bounded].
 assert (Allocated : In (operation_id original)
   (flat_map WorldInvariant.task_tickets (world_tasks before) ++
     WorldInvariant.feature_tickets (world_features before))).
 { apply in_or_app; left; apply in_flat_map; exists task; split.
   - eapply a_registry_lookup_is_a_member; exact Found.
   - unfold WorldInvariant.task_tickets, task_operations; rewrite ArchivedTask.
     apply in_or_app; right; apply in_flat_map; exists original; split; [exact Member|].
     apply operation_identifiers_are_part_of_the_ticket_supply. }
 apply Forall_forall with (x:=operation_id original) in Bounded; [|exact Allocated].
 cbn [TicketedRequest.issue TicketedRequest.allocate_identity TicketedRequest.next_identity TicketedRequest.build decision_world accept].
 assert (Operations : task_operations task = operations).
 { unfold task_operations; rewrite ArchivedTask; reflexivity. }
 rewrite Operations.
 change (Permutation
   (flat_map WorldInvariant.task_tickets
     (replace owner (with_operations (TicketedRequest.replace_operation
       (Operation (operation_id original) (operation_call original) (operation_announced original)
         (AwaitingAfterHook (world_next_ticket before) plugin pending result error)) operations) task)
       (world_tasks before)) ++ WorldInvariant.feature_tickets (world_features before))
   ((world_next_ticket before :: flat_map WorldInvariant.task_tickets (world_tasks before)) ++
     WorldInvariant.feature_tickets (world_features before))).
 apply Permutation_app_tail.
 eapply replacing_one_registry_entry_lifts_a_fresh_ticket; [exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
 cbn in ArchivedTask; subst lifecycle.
 unfold WorldInvariant.task_tickets; cbn.
 apply staging_an_after_hook_adds_exactly_one_fresh_ticket.
 - apply unique_operation_tickets_imply_unique_identifiers; exact Unique.
 - exact Member.
 - exact Stage.
 - lia.
Qed.

Theorem an_archived_after_request_preserves_the_unique_ticket_supply :
 forall owner task before operations original plugin pending result error,
 WorldInvariant.tickets_valid before = true ->
 find_task owner before = Some task ->
 task_lifecycle task = Archived operations ->
 In original operations ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 WorldInvariant.tickets_valid (decision_world (TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before)) = true.
Proof.
 intros owner task before operations original plugin pending result error Valid Found ArchivedTask Member Stage.
 eapply one_fresh_owner_preserves_the_ticket_supply; [exact Valid|reflexivity|].
 eapply an_archived_after_request_adds_one_fresh_global_ticket; eassumption.
Qed.

Lemma an_owned_operation_identifier_precedes_the_next_ticket :
 forall owner task before original,
 WorldInvariant.tickets_valid before = true ->
 find_task owner before = Some task -> In original (task_operations task) ->
 (operation_id original < world_next_ticket before)%N.
Proof.
 intros owner task before original Valid Found Member.
 pose proof (owned_operation_tickets_are_bounded before owner task Valid Found) as Bounded.
 apply Forall_forall with (x:=original) in Bounded; [|exact Member].
 apply Forall_forall with (x:=operation_id original) in Bounded;
   [exact Bounded|apply operation_identifiers_are_part_of_the_ticket_supply].
Qed.

Theorem an_after_request_only_changes_pending_operations :
 forall owner task before operations original plugin pending result error,
 find_task owner before = Some task ->
 task_lifecycle task = Archived operations ->
 Forall2 (fun old next => without_archived_operations old = without_archived_operations next)
   (world_tasks before)
   (world_tasks (decision_world (TicketedRequest.issue owner
     (TicketedRequest.After original plugin pending result error task) before))).
Proof.
 intros owner task before operations original plugin pending result error Found ArchivedTask.
 change (Forall2 (fun old next => without_archived_operations old = without_archived_operations next) (world_tasks before)
   (replace owner (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original) (operation_announced original)
       (AwaitingAfterHook (world_next_ticket before) plugin pending result error)) (task_operations task)) task)
     (world_tasks before))).
 eapply replacing_a_registry_entry_lifts_its_relation; [intro; reflexivity|exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
 cbn in ArchivedTask; subst lifecycle; reflexivity.
Qed.

Theorem issuing_an_archived_after_hook_preserves_world_requirements :
 forall owner task before operations original plugin pending result error,
 WorldInvariant.well_formed before ->
 find_task owner before = Some task ->
 task_lifecycle task = Archived operations ->
 In original operations ->
 operation_stage original = AfterHooksReady (plugin :: pending) result error ->
 WorldInvariant.well_formed (decision_world (TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before)).
Proof.
 intros owner task before operations original plugin pending result error
   WellFormed Found ArchivedTask Member Stage.
 pose proof (ForkLineageProofs.lookup_task_requirements before owner task WellFormed Found) as TaskValid.
 pose proof (a_valid_task_has_its_progress_requirements owner task _ TaskValid)
   as [Context [Phase [Checked OperationValid]]].
 destruct WellFormed as [Environment Projects Tasks Tickets Features].
 change (WorldInvariant.tickets_valid before = true) in Tickets.
 assert (Operations : task_operations task = operations).
 { unfold task_operations; rewrite ArchivedTask; reflexivity. }
 assert (Fresh : (operation_id original < world_next_ticket before)%N).
 { eapply an_owned_operation_identifier_precedes_the_next_ticket; eauto; rewrite Operations; exact Member. }
 assert (Unique : NoDup (map operation_id operations)).
 { apply unique_operation_tickets_imply_unique_identifiers.
   rewrite <- Operations; eapply valid_world_execution_tickets_are_unique; eauto. }
 set (waiting := with_operations (TicketedRequest.replace_operation
   (Operation (operation_id original) (operation_call original) (operation_announced original)
     (AwaitingAfterHook (world_next_ticket before) plugin pending result error)) operations) task).
 set (after := decision_world (TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before)).
 assert (After : after = put_task owner waiting (with_ticket (N.succ (world_next_ticket before)) before)).
 { unfold after, TicketedRequest.issue, TicketedRequest.build; rewrite Operations; reflexivity. }
 assert (Frame : fork_retains_task task waiting).
 { unfold fork_retains_task; split.
   - unfold retained_task_frame, waiting.
     destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
     cbn in ArchivedTask; subst lifecycle; reflexivity.
   - exists []; rewrite app_nil_r. unfold waiting.
     destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed];
       destruct lifecycle; reflexivity. }
 rewrite After.
 eapply fork_replacement_preserves_every_world_requirement; try exact Frame; try exact Found.
 - constructor; assumption.
 - apply N.le_succ_diag_r.
 - unfold waiting. destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed];
     destruct lifecycle; exact Context.
 - unfold waiting, WorldInvariant.phase_valid, task_activity, with_operations.
   destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
   cbn in ArchivedTask; subst lifecycle; reflexivity.
 - unfold waiting, WorldInvariant.checked_phase, task_activity, with_operations.
   destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
   cbn in ArchivedTask; subst lifecycle; reflexivity.
 - unfold waiting. eapply staging_an_archived_after_hook_preserves_its_operation_requirements; eauto.
 - rewrite <- After. unfold after; eapply an_archived_after_request_preserves_the_unique_ticket_supply; eauto.
Qed.
