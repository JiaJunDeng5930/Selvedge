From Stdlib Require Import List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Tasks ContextUpdates WorldInvariant
 WorldInvariantProofs FeatureFrameProofs ForkLineageProofs.
Import ListNotations.

Lemma replacing_a_registry_entry_lifts_its_relation :
 forall (A : Type) (rel : A -> A -> Prop) values owner original replacement,
 (forall value, rel value value) ->
 registry_at owner values = Some original -> rel original replacement ->
 Forall2 rel values (replace owner replacement values).
Proof.
 intros A rel values; induction values as [|first rest IH]; intros owner original replacement
   Refl Found Same; [discriminate|].
 cbn in Found; cbn [replace]; destruct (N.eqb owner 0).
 - inversion Found; subst first; constructor; [exact Same|].
   clear IH Found Same. induction rest as [|value remaining IHrest]; constructor;
     [apply Refl|exact IHrest].
 - constructor; [apply Refl|eapply IH; eauto].
Qed.

Lemma replacing_equal_projection_keeps_registry_observations :
 forall (A B : Type) (observe : A -> B) values owner old next,
 registry_at owner values = Some old -> observe old = observe next ->
 map observe (replace owner next values) = map observe values.
Proof.
 intros A B observe values; induction values as [|first rest IH]; intros owner old next Found Same; [discriminate|].
 cbn in Found; cbn [replace map]; destruct (N.eqb owner 0).
 - inversion Found; subst first; rewrite Same; reflexivity.
 - cbn [map]; rewrite IH with (old:=old) by assumption; reflexivity.
Qed.

Definition registry_lookup_after_head := @Selvedge.Foundation.RegistryProofs.registry_lookup_after_head.

Lemma task_registry_requirement_from_every_lookup : forall entries owner state,
 (forall offset value, registry_at offset entries = Some value ->
   WorldInvariant.task_valid (owner + offset)%N value state = true) ->
 WorldInvariant.tasks_valid owner entries state = true.
Proof.
 intros entries; induction entries as [|first rest IH]; intros owner state Valid; [reflexivity|].
 cbn [WorldInvariant.tasks_valid]; apply andb_true_iff; split.
 - replace owner with (owner+0)%N by lia; apply Valid; reflexivity.
 - apply IH; intros offset value Found.
   replace (N.succ owner + offset)%N with (owner + N.succ offset)%N by lia.
   apply Valid; rewrite registry_lookup_after_head; exact Found.
Qed.

Definition task_progress_requirements (owner : N) (value : task) :=
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history value)) = true /\
 WorldInvariant.phase_valid value = true /\ WorldInvariant.checked_phase owner value = true /\
 WorldInvariant.operations_valid owner value = true.

Lemma a_valid_task_has_its_progress_requirements : forall owner value before,
 WorldInvariant.task_valid owner value before = true -> task_progress_requirements owner value.
Proof.
 intros owner value before Valid; unfold WorldInvariant.task_valid in Valid.
 repeat rewrite andb_true_iff in Valid; unfold task_progress_requirements; tauto.
Qed.

Lemma task_requirements_ignore_the_journal_cursor : forall owner value state,
 WorldInvariant.task_valid owner value (WorldInvariant.world_structure state) =
 WorldInvariant.task_valid owner value state.
Proof. intros owner value [sequence tasks ticket environment projects features]; reflexivity. Qed.

Lemma task_registry_requirements_ignore_the_journal_cursor : forall entries owner state,
 WorldInvariant.tasks_valid owner entries (WorldInvariant.world_structure state) =
 WorldInvariant.tasks_valid owner entries state.
Proof.
 intros entries; induction entries as [|head rest IH]; intros owner state; [reflexivity|].
 cbn [WorldInvariant.tasks_valid]; rewrite task_requirements_ignore_the_journal_cursor, IH; reflexivity.
Qed.

(* A replacement changes local progress. Its frame retains execution
   configuration; the relation's feature theorem supplies any history and
   lifecycle conditions actually observed outside the task registry. *)
Record task_configuration_frame (old next : task) : Prop := TaskConfigurationFrame {
 frame_contract : task_contract old = task_contract next;
 frame_profile : task_current_profile old = task_current_profile next;
 frame_settings : task_current_settings old = task_current_settings next;
 frame_lineage : task_lineage old = task_lineage next
}.

Lemma task_requirements_follow_configuration : forall owner old next before after,
 task_configuration_frame old next -> world_projects before = world_projects after ->
 WorldInvariant.lineage_valid owner next after = true ->
 (Tasks.descendant_count owner (world_tasks after) <= contract_max_descendants (task_contract next))%N ->
 task_progress_requirements owner next ->
 WorldInvariant.task_valid owner old before = true -> WorldInvariant.task_valid owner next after = true.
Proof.
 intros owner old next before after [ContractFrame ProfileFrame SettingsFrame LineageFrame]
   Projects Lineage Capacity [Context [Phase [Checked Operations]]] Valid.
 unfold WorldInvariant.task_valid in *; repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[[[[Contract Profile] Settings] OldContext] ContractProject] CurrentProject] OldLineage]
   OldCapacity] OldPhase] OldChecked] OldOperations].
 repeat split; try assumption.
 - rewrite <- ContractFrame; exact Contract.
 - rewrite <- ProfileFrame; exact Profile.
 - rewrite <- SettingsFrame; exact Settings.
 - unfold WorldInvariant.project_binding in *; rewrite <- ContractFrame, <- Projects; exact ContractProject.
 - unfold WorldInvariant.project_binding in *; rewrite <- SettingsFrame, <- Projects; exact CurrentProject.
 - now apply N.leb_le.
Qed.

Section TaskReplacement.
Variable relation : task -> task -> Prop.
Hypothesis RelationReflexive : forall value, relation value value.
Hypothesis RelationConfiguration : forall old next, relation old next -> task_configuration_frame old next.
Hypothesis RelationFeatures : forall before after,
 world_features before = world_features after -> world_projects before = world_projects after ->
 (world_next_ticket before <= world_next_ticket after)%N ->
 (forall owner old, find_task owner before = Some old ->
   exists next, find_task owner after = Some next /\ relation old next) ->
 features_valid before = true -> features_valid after = true.

Local Definition related_contract old next evidence :=
 frame_contract old next (RelationConfiguration old next evidence).
Local Definition related_profile old next evidence :=
 frame_profile old next (RelationConfiguration old next evidence).
Local Definition related_settings old next evidence :=
 frame_settings old next (RelationConfiguration old next evidence).
Local Definition related_lineage old next evidence :=
 frame_lineage old next (RelationConfiguration old next evidence).

Lemma related_lineage_requirements : forall id old next before after,
 relation old next ->
 (forall owner original, find_task owner before = Some original ->
   exists current, find_task owner after = Some current /\ relation original current) ->
 WorldInvariant.lineage_valid id old before = true ->
 WorldInvariant.lineage_valid id next after = true.
Proof.
 intros id old next before after Frame Retained Valid.
 unfold WorldInvariant.lineage_valid in *.
 rewrite <- (related_lineage _ _ Frame), <- (related_contract _ _ Frame).
 destruct (task_lineage old) as [|ancestor tail]; [reflexivity|].
 destruct (find_task ancestor before) as [original|] eqn:Found; [|discriminate].
 destruct (Retained ancestor original Found) as [current [After ParentFrame]]. rewrite After.
 rewrite <- (related_lineage _ _ ParentFrame), <- (related_contract _ _ ParentFrame).
 exact Valid.
Qed.

Lemma task_replacement_retains_each_lookup : forall before owner old next ticket,
 find_task owner before = Some old -> relation old next ->
 forall queried original, find_task queried before = Some original ->
 exists current, find_task queried (put_task owner next (with_ticket ticket before)) = Some current /\
   relation original current.
Proof.
 intros before owner old next ticket Found Frame.
 set (after := put_task owner next (with_ticket ticket before)).
 intros queried original Lookup; destruct (N.eq_dec queried owner) as [Same|Other].
   - subst queried; rewrite Found in Lookup; inversion Lookup; subst original.
     exists next; split; [|exact Frame].
     unfold after; unfold find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn;
       eapply registry_replace_selected; exact Found.
   - exists original; split.
     + unfold after, find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn.
       rewrite RegistryProofs.registry_replace_other by congruence; exact Lookup.
     + apply RelationReflexive.
Qed.

Theorem task_replacement_preserves_registry_requirements :
 forall before owner old next ticket,
 WorldInvariant.well_formed before -> find_task owner before = Some old ->
 relation old next -> task_progress_requirements owner next ->
 WorldInvariant.tasks_valid 0 (world_tasks (put_task owner next (with_ticket ticket before)))
   (put_task owner next (with_ticket ticket before)) = true.
Proof.
 intros before owner old next ticket Valid Found Frame [Context [Phase [Checked Operations]]].
 set (after := put_task owner next (with_ticket ticket before)).
 assert (Projects : world_projects before = world_projects after) by reflexivity.
 pose proof (task_replacement_retains_each_lookup before owner old next ticket Found Frame) as Retained.
 assert (Lineages : map task_lineage (world_tasks after) = map task_lineage (world_tasks before)).
 { unfold after, put_task, with_tasks, with_ticket; cbv [set]; cbn.
   eapply replacing_equal_projection_keeps_registry_observations; [exact Found|].
   apply related_lineage; exact Frame. }
 apply task_registry_requirement_from_every_lookup; intros queried current Lookup.
   rewrite N.add_0_l.
   change (find_task queried after = Some current) in Lookup.
   assert (Original : exists original, find_task queried before = Some original /\
     relation original current /\ task_progress_requirements queried current).
   { destruct (N.eq_dec queried owner) as [Same|Other].
     - subst queried.
       assert (Installed : find_task owner after = Some next).
       { unfold after; unfold find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn;
       eapply registry_replace_selected; exact Found. }
       rewrite Installed in Lookup; inversion Lookup; subst current.
       exists old; split; [exact Found|]; split; [exact Frame|].
       unfold task_progress_requirements; repeat split; assumption.
     - assert (Before : find_task queried before = Some current).
       { unfold after, find_task, put_task, with_tasks, with_ticket in Lookup; cbv [set] in Lookup; cbn in Lookup.
         rewrite RegistryProofs.registry_replace_other in Lookup by congruence; exact Lookup. }
       exists current; split; [exact Before|]; split.
       + apply RelationReflexive.
       + apply a_valid_task_has_its_progress_requirements with (before:=before).
         rewrite <- task_requirements_ignore_the_journal_cursor.
         eapply ForkLineageProofs.lookup_task_requirements; eauto. }
   destruct Original as [original [Before [Retains [CurrentContext [CurrentPhase [CurrentChecked CurrentOperations]]]]]].
   pose proof (ForkLineageProofs.lookup_task_requirements before queried original Valid Before) as OldValid.
   rewrite task_requirements_ignore_the_journal_cursor in OldValid.
   pose proof OldValid as Facts; unfold WorldInvariant.task_valid in Facts.
   repeat rewrite andb_true_iff in Facts.
   eapply task_requirements_follow_configuration; [apply RelationConfiguration; exact Retains|exact Projects| | | |exact OldValid].
   - eapply related_lineage_requirements; try eassumption; tauto.
   - rewrite <- (related_contract _ _ Retains).
     rewrite (ForkLineageProofs.descendant_count_depends_only_on_lineages queried _ _ Lineages).
     apply N.leb_le; tauto.
   - unfold task_progress_requirements; auto.
Qed.

Theorem task_replacement_preserves_every_world_requirement :
 forall before owner old next ticket,
 WorldInvariant.well_formed before -> find_task owner before = Some old ->
 relation old next ->
 (world_next_ticket before <= ticket)%N ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true ->
 WorldInvariant.phase_valid next = true -> WorldInvariant.checked_phase owner next = true ->
 WorldInvariant.operations_valid owner next = true ->
 WorldInvariant.tickets_valid (put_task owner next (with_ticket ticket before)) = true ->
 WorldInvariant.well_formed (put_task owner next (with_ticket ticket before)).
Proof.
 intros before owner old next ticket Valid Found Frame Later Context Phase Checked Operations Tickets.
 constructor.
 - exact (WorldInvariant.environment_requirement before Valid).
 - exact (WorldInvariant.projects_requirement before Valid).
 - rewrite task_registry_requirements_ignore_the_journal_cursor.
   eapply task_replacement_preserves_registry_requirements; try eassumption.
   unfold task_progress_requirements; auto.
 - exact Tickets.
 - eapply RelationFeatures with (before:=WorldInvariant.world_structure before);
     [reflexivity|reflexivity|exact Later| |exact (WorldInvariant.features_requirement before Valid)].
   exact (task_replacement_retains_each_lookup before owner old next ticket Found Frame).
Qed.
End TaskReplacement.
