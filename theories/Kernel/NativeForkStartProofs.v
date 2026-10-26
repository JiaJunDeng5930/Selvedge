From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State Tasks Scheduler WorldInvariant
 ForkPreservation NativeResultWorldFrame NativeResultTicketProofs NativeForkPreservation.
Import ListNotations.
Open Scope list_scope.

Lemma a_final_native_call_has_its_stored_dispatch_phase : forall source invocation remaining retry,
 Scheduler.fork_dispatch_call source = Some (invocation,remaining,retry) ->
 WorldInvariant.phase_calls (task_activity source) = invocation :: remaining /\
 WorldInvariant.task_tickets (with_activity (PendingCalls remaining) source) = WorldInvariant.task_tickets source /\
 exists phase operations running,
 task_lifecycle source = result_lifecycle running phase operations /\ phase <> Idle.
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed] invocation remaining retry Ready.
 unfold Scheduler.fork_dispatch_call in Ready; cbn [task_lifecycle] in Ready.
 destruct lifecycle as [phase operations|phase operations|phase operations|operations]; cbn in Ready; try discriminate.
 all: match type of Ready with
 | context [Scheduler.ready_operation ?pending] => destruct (Scheduler.ready_operation pending) eqn:?
 | context [Scheduler.ready_settlement ?pending] => destruct (Scheduler.ready_settlement pending) eqn:?
 end; cbn in Ready; try discriminate.
 all: destruct phase; cbn in Ready; try discriminate.
 all: repeat match type of Ready with
 | context [match ?value with _ => _ end] => destruct value eqn:?; cbn in Ready; try discriminate
 end.
 all: inversion Ready; subst; cbn [WorldInvariant.phase_calls task_activity].
 all: split; [reflexivity|]; split.
 all: try (unfold WorldInvariant.task_tickets,with_activity; cbv [set]; cbn; reflexivity).
 all: first [eexists _,_,true; split; [reflexivity|discriminate]
            | eexists _,_,false; split; [reflexivity|discriminate]].
Qed.

Theorem starting_an_accepted_native_call_preserves_every_world_requirement :
 forall before owner source invocation remaining retry,
 WorldInvariant.well_formed before -> find_task owner before = Some source ->
 Scheduler.fork_dispatch_call source = Some (invocation,remaining,retry) ->
 WorldInvariant.well_formed (put_task owner (with_activity (PendingCalls remaining) source) before).
Proof.
 intros before owner source invocation remaining retry Valid Found Ready.
 destruct (a_final_native_call_has_its_stored_dispatch_phase source invocation remaining retry Ready)
   as [Calls [Tickets [phase [operations [running [Lifecycle NonIdle]]]]]].
 pose proof (ForkLineageProofs.lookup_task_requirements before owner source Valid Found) as Requirements.
 rewrite task_requirements_ignore_the_journal_cursor in Requirements.
 pose proof (a_valid_task_has_its_progress_requirements owner source before Requirements)
   as [Context [Phase [Checked Operations]]].
 set (next := with_activity (PendingCalls remaining) source).
 destruct (changing_an_active_phase_keeps_its_observations source phase operations running
   (PendingCalls remaining) Lifecycle) as [ActivityAfter [HistoryAfter [SameOperations SameFrame]]].
 fold next in ActivityAfter,HistoryAfter,SameOperations,SameFrame.
 assert (PhaseAfter : WorldInvariant.phase_valid next = true).
 { unfold WorldInvariant.phase_valid in Phase |- *.
   rewrite Calls in Phase.
   rewrite ActivityAfter,HistoryAfter; cbn [WorldInvariant.phase_calls].
   change (WorldInvariant.calls_valid (task_history source) remaining && true = true).
   apply andb_true_iff in Phase as [ValidCalls _].
   unfold WorldInvariant.calls_valid in *.
   apply andb_true_iff in ValidCalls as [Open Unique].
   cbn [forallb] in Open; apply andb_true_iff in Open as [_ Tail].
   apply ForkNativeHistoryProofs.unique_names_nodup in Unique.
   inversion Unique; subst.
   rewrite Tail; cbn; rewrite andb_true_r; apply ForkNativeHistoryProofs.unique_names_nodup; assumption. }
 assert (OperationsAfter : WorldInvariant.operations_valid owner next = true).
 { unfold WorldInvariant.operations_valid in Operations |- *.
   rewrite Calls in Operations.
   rewrite ActivityAfter,SameOperations; cbn [WorldInvariant.phase_calls].
   unfold next,with_activity; rewrite Lifecycle; destruct running;
   change (N.leb (N.of_nat (List.length (task_operations source))) Limits.operation_limit &&
     Schema.unique_names (map call_id remaining ++ map (fun operation => call_id (operation_call operation)) (task_operations source)) &&
     forallb (fun operation => WorldInvariant.hooks_correspond owner source (operation_call operation) [] &&
       WorldInvariant.operation_history source operation && WorldInvariant.operation_stage_valid owner source operation &&
       match Tasks.find_tool (call_name (operation_call operation)) (contract_tools (task_contract source)) with Some _ => true | None => false end)
       (task_operations source) = true).
   all: repeat rewrite andb_true_iff in Operations |- *.
   all: destruct Operations as [[Capacity Unique] Existing]; repeat split; try assumption.
   all: cbn [map] in Unique; apply ForkNativeHistoryProofs.unique_names_nodup in Unique.
   all: inversion Unique; subst; apply ForkNativeHistoryProofs.unique_names_nodup; assumption. }
 assert (Frame : native_result_retains_task source next).
 { split; [symmetry; exact SameFrame|]; split; [exists []; now rewrite app_nil_r|].
   rewrite Lifecycle; destruct running; [exact I|]. intros Equal; contradiction. }
 assert (NewTickets : WorldInvariant.tickets_valid (put_task owner next (with_ticket (world_next_ticket before) before)) = true).
 { apply (a_native_result_preserves_global_ticket_ownership before owner source next false Valid Found).
   unfold next; rewrite Tickets,app_nil_r; reflexivity. }
 assert (NextContext : forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true).
 { rewrite HistoryAfter; exact Context. }
 assert (NextChecked : WorldInvariant.checked_phase owner next = true).
 { unfold WorldInvariant.checked_phase; rewrite ActivityAfter; reflexivity. }
 pose proof (native_result_replacement_preserves_every_world_requirement before owner source next
   (world_next_ticket before) Valid Found Frame (N.le_refl _) NextContext PhaseAfter NextChecked OperationsAfter NewTickets) as Preserved.
 rewrite with_the_current_ticket_is_the_original_world in Preserved; exact Preserved.
Qed.
