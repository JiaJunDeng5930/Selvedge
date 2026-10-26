From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import Json JsonProofs Schema.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Features Require Import BoardFacts.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Callbacks
 TicketedRequest WorldInvariant WorldInvariantProofs CallbacksProofs LifecycleProofs.
Import ListNotations.

Lemma forallb_equal_predicates : forall (A : Type) (left right : A -> bool) values,
 (forall value, left value = right value) -> forallb left values = forallb right values.
Proof.
 intros A left right values Equal; induction values; cbn; [reflexivity|rewrite Equal, IHvalues; reflexivity].
Qed.

(* Existing task lenses provide the observation used by the preservation lift:
   pending-operation changes do not rewrite the rest of a stored task. *)
Definition without_archived_operations (value : task) :=
 match task_lifecycle value with Archived _ => with_operations [] value | _ => value end.

Local Ltac erase_task_projection :=
 intros [contract profile settings lifecycle history queued lineage side cursor consumed];
 destruct lifecycle; reflexivity.

Lemma observing_equal_operation_erasure : forall (A : Type) (observe : task -> A) left right,
 (forall value, observe (without_archived_operations value) = observe value) ->
 without_archived_operations left = without_archived_operations right -> observe left = observe right.
Proof.
 intros A observe left right Stable Same.
 rewrite <- (Stable left), <- (Stable right), Same; reflexivity.
Qed.

Definition registry_lookup_commutes_with_mapping := @Selvedge.Foundation.RegistryProofs.registry_lookup_commutes_with_mapping.

Lemma observing_a_registry_with_equal_operation_erasure :
 forall (A : Type) (observe : task -> A) missing before after owner,
 (forall value, observe (without_archived_operations value) = observe value) ->
 map without_archived_operations (world_tasks before) = map without_archived_operations (world_tasks after) ->
 (match find_task owner before with Some value => observe value | None => missing end) =
 (match find_task owner after with Some value => observe value | None => missing end).
Proof.
 intros A observe missing before after owner Stable Same.
 assert (Lookup : option_map without_archived_operations (find_task owner before) =
   option_map without_archived_operations (find_task owner after)).
 { unfold find_task; rewrite <- !registry_lookup_commutes_with_mapping, Same; reflexivity. }
 destruct (find_task owner before) as [old|]; destruct (find_task owner after) as [next|];
   cbn in Lookup; try discriminate; [|reflexivity].
 inversion Lookup. eapply observing_equal_operation_erasure; eauto.
Qed.

Lemma replacing_a_registry_entry_preserves_equal_observations :
 forall (A B : Type) (observe : A -> B) values owner original replacement,
 registry_at owner values = Some original -> observe original = observe replacement ->
 map observe values = map observe (replace owner replacement values).
Proof.
 intros A B observe values; induction values as [|first rest IH]; intros owner original replacement
   Found Same; [discriminate|].
 cbn in Found; cbn [replace map]. destruct (N.eqb owner 0); cbn [map].
 - inversion Found; subst first; rewrite Same; reflexivity.
 - f_equal; eapply IH; eauto.
Qed.

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

Lemma descendant_count_ignores_operation_erasure : forall owner values,
 Tasks.descendant_count owner (map without_archived_operations values) = Tasks.descendant_count owner values.
Proof.
 intros owner values; unfold Tasks.descendant_count. f_equal.
 induction values as [|first rest IH]; [reflexivity|].
 assert (Lineage : task_lineage (without_archived_operations first) = task_lineage first).
 { destruct first as [contract profile settings lifecycle history queued lineage side cursor consumed];
     destruct lifecycle; reflexivity. }
 cbn [map filter]; rewrite Lineage.
 destruct (existsb (N.eqb owner) (task_lineage first)); cbn; [now rewrite IH|exact IH].
Qed.

Theorem task_requirements_lift_across_operation_changes :
 forall owner old next before after,
 without_archived_operations old = without_archived_operations next ->
 map without_archived_operations (world_tasks before) = map without_archived_operations (world_tasks after) ->
 world_projects before = world_projects after ->
 (WorldInvariant.operations_valid owner old = true -> WorldInvariant.operations_valid owner next = true) ->
 WorldInvariant.task_valid owner old before = true ->
 WorldInvariant.task_valid owner next after = true.
Proof.
 intros owner old next before after Erased Registry Projects Operations Valid.
 assert (Contract : task_contract old = task_contract next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Profile : task_current_profile old = task_current_profile next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Settings : task_current_settings old = task_current_settings next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (History : task_history old = task_history next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Lineage : task_lineage old = task_lineage next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Phase : WorldInvariant.phase_valid old = WorldInvariant.phase_valid next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Checked : WorldInvariant.checked_phase owner old = WorldInvariant.checked_phase owner next).
 { eapply observing_equal_operation_erasure; [erase_task_projection|exact Erased]. }
 assert (Ancestors : WorldInvariant.lineage_valid owner old before = WorldInvariant.lineage_valid owner next after).
 { unfold WorldInvariant.lineage_valid; rewrite <- Lineage, <- Contract.
   destruct (task_lineage old) as [|parent tail]; [reflexivity|].
   apply observing_a_registry_with_equal_operation_erasure; [erase_task_projection|exact Registry]. }
 assert (Descendants : Tasks.descendant_count owner (world_tasks before) =
   Tasks.descendant_count owner (world_tasks after)).
 { rewrite <- (descendant_count_ignores_operation_erasure owner (world_tasks before)),
     <- (descendant_count_ignores_operation_erasure owner (world_tasks after)), Registry; reflexivity. }
 unfold WorldInvariant.task_valid in *; apply andb_true_iff in Valid as [Static Pending].
 apply andb_true_iff; split; [|apply Operations; exact Pending].
 unfold WorldInvariant.project_binding in *.
 rewrite <- Contract, <- Profile, <- Settings, <- History, <- Phase, <- Checked, <- Ancestors,
   <- Descendants, <- Projects; exact Static.
Qed.

Theorem task_registry_requirements_lift_across_operation_changes :
 forall owner old next before after,
 Forall2 (fun old next => without_archived_operations old = without_archived_operations next /\
   forall owner, WorldInvariant.operations_valid owner old = true ->
     WorldInvariant.operations_valid owner next = true) old next ->
 map without_archived_operations (world_tasks before) = map without_archived_operations (world_tasks after) ->
 world_projects before = world_projects after ->
 WorldInvariant.tasks_valid owner old before = true -> WorldInvariant.tasks_valid owner next after = true.
Proof.
 intros owner old next before after Related; revert owner.
 induction Related; intros owner Registry Projects Valid; [reflexivity|].
 cbn in Valid |- *; apply andb_true_iff in Valid as [Head Tail].
 apply andb_true_iff; split.
 - destruct H as [Erased Operations]; eapply task_requirements_lift_across_operation_changes; eauto.
 - apply IHRelated; assumption.
Qed.

Section FeatureOperationFrame.
Variables before after : world.
Hypothesis SameRegistry : map without_archived_operations (world_tasks before) = map without_archived_operations (world_tasks after).
Hypothesis SameFeatures : world_features before = world_features after.
Hypothesis SameProjects : world_projects before = world_projects after.
Hypothesis LaterTickets : (world_next_ticket before <= world_next_ticket after)%N.

Local Lemma same_task_presence : forall owner,
 WorldInvariant.present (find_task owner before) = WorldInvariant.present (find_task owner after).
Proof.
 intro owner. unfold WorldInvariant.present.
 apply observing_a_registry_with_equal_operation_erasure; [reflexivity|exact SameRegistry].
Qed.

Local Lemma earlier_ticket_stays_allocated : forall ticket,
 (ticket <? world_next_ticket before)%N = true -> (ticket <? world_next_ticket after)%N = true.
Proof. intros ticket Earlier; apply N.ltb_lt in Earlier; apply N.ltb_lt; lia. Qed.

Local Lemma title_requirement_survives : forall entry,
 WorldInvariant.title_valid entry before = true -> WorldInvariant.title_valid entry after = true.
Proof.
 intros entry Valid. unfold WorldInvariant.title_valid in *.
 rewrite <- same_task_presence. apply andb_true_iff in Valid as [Found Valid].
 apply andb_true_iff; split; [exact Found|].
 destruct (Selvedge.Features.Domain.title_value entry); try exact Valid.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Ticket Profile] Capable] Budget].
 repeat split; try assumption; apply earlier_ticket_stays_allocated; exact Ticket.
Qed.

Local Lemma tree_requirement_is_unchanged : forall entry,
 WorldInvariant.tree_owner_valid entry before = WorldInvariant.tree_owner_valid entry after.
Proof.
 intro entry. unfold WorldInvariant.tree_owner_valid. f_equal.
 apply observing_a_registry_with_equal_operation_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Local Lemma card_requirement_survives : forall card,
 WorldInvariant.card_valid card before = true -> WorldInvariant.card_valid card after = true.
Proof.
 intros card Valid. unfold WorldInvariant.card_valid in *.
 assert (Draft : Board.valid_draft (Selvedge.Features.Domain.card_contents card) before =
   Board.valid_draft (Selvedge.Features.Domain.card_contents card) after).
 { unfold Board.valid_draft, BoardFacts.valid_draft, BoardFacts.lookup_agent, BoardFacts.registry.
   rewrite SameProjects, SameFeatures; reflexivity. }
 assert (Linked : (match Selvedge.Features.Domain.card_task card with
   | Some owner => WorldInvariant.present (find_task owner before) | None => true end) =
   (match Selvedge.Features.Domain.card_task card with
   | Some owner => WorldInvariant.present (find_task owner after) | None => true end)).
 { destruct (Selvedge.Features.Domain.card_task card); [apply same_task_presence|reflexivity]. }
 apply andb_true_iff in Valid as [Static Enrichment].
 apply andb_true_iff; split; [rewrite <- Draft, <- Linked; exact Static|].
 destruct (Selvedge.Features.Domain.card_enrichment card); try exact Enrichment.
 repeat rewrite andb_true_iff in Enrichment |- *.
 destruct Enrichment as [[Ticket Revision] Active].
 repeat split; try assumption; apply earlier_ticket_stays_allocated; exact Ticket.
Qed.

Local Lemma work_task_owner_is_unchanged : forall owner,
 Work.task_owner owner before = Work.task_owner owner after.
Proof.
 intro owner; unfold Work.task_owner; rewrite <- SameFeatures.
 apply observing_a_registry_with_equal_operation_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Local Lemma graph_requirement_is_unchanged : forall owner graph,
 WorldInvariant.graph_valid owner graph before = WorldInvariant.graph_valid owner graph after.
Proof.
 intros owner graph. unfold WorldInvariant.graph_valid; rewrite <- SameFeatures. f_equal.
 apply forallb_equal_predicates; intro node; rewrite same_task_presence.
 unfold TaskGraph.task_in_work; destruct (Selvedge.Features.Domain.association owner
   (Selvedge.Features.Domain.feature_graph_owners (world_features before))); [rewrite work_task_owner_is_unchanged|]; reflexivity.
Qed.

Local Lemma graph_registry_requirement_is_unchanged :
 WorldInvariant.graph_registry_valid before = WorldInvariant.graph_registry_valid after.
Proof.
 unfold WorldInvariant.graph_registry_valid; rewrite <- SameFeatures. f_equal.
 generalize (Selvedge.Features.Domain.feature_graphs (world_features before)).
 intros graphs; generalize 0%N; induction graphs as [|graph rest IH]; intro owner; [reflexivity|].
 cbn [WorldInvariant.graphs_valid]. rewrite IH.
 destruct graph; [rewrite graph_requirement_is_unchanged|]; reflexivity.
Qed.

Local Lemma maintenance_requirement_is_unchanged : forall entry,
 WorldInvariant.maintenance_entry_valid entry before = WorldInvariant.maintenance_entry_valid entry after.
Proof.
 intros [owner entry]. unfold WorldInvariant.maintenance_entry_valid.
 apply observing_a_registry_with_equal_operation_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Local Lemma works_requirement_is_unchanged :
 WorldInvariant.works_valid before = WorldInvariant.works_valid after.
Proof.
 unfold WorldInvariant.works_valid, WorldInvariant.work_owners_valid, Work.lookup.
 rewrite <- SameFeatures. f_equal. f_equal.
 apply forallb_equal_predicates; intros [owner work].
 apply observing_a_registry_with_equal_operation_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Theorem feature_requirements_lift_across_operation_changes :
 WorldInvariant.features_valid before = true -> WorldInvariant.features_valid after = true.
Proof.
 intro Valid. unfold WorldInvariant.features_valid in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works] Maintenance].
 repeat split.
 - unfold WorldInvariant.titles_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Titles |- *; destruct Titles as [[[TaskPrompt AgentPrompt] Unique] Entries].
   repeat split; try assumption. apply forallb_forall; intros entry Member.
   apply title_requirement_survives; apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.remote_valid in *; rewrite <- SameFeatures; exact Remote.
 - unfold WorldInvariant.worktrees_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Trees as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; rewrite <- tree_requirement_is_unchanged.
   apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.board_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Board |- *.
   destruct Board as [[[[[[[Cards Agents] CardBound] AgentBound] Entries] Unique] AgentEntries] Draft].
   repeat split; try assumption. apply forallb_forall; intros card Member.
   apply card_requirement_survives; apply forallb_forall with (x:=card) in Entries; assumption.
 - unfold WorldInvariant.sharing_valid in *; unfold WorkspaceBinding.resource_ready, WorkspaceBinding.owned in *.
   rewrite <- SameFeatures, <- SameProjects; exact Sharing.
 - rewrite <- graph_registry_requirement_is_unchanged; exact Graphs.
 - rewrite <- works_requirement_is_unchanged; exact Works.
 - unfold WorldInvariant.compaction_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Maintenance as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; rewrite <- maintenance_requirement_is_unchanged.
   apply forallb_forall with (x:=entry) in Entries; assumption.
Qed.
End FeatureOperationFrame.

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

Lemma replacing_one_registry_entry_lifts_a_fresh_ticket :
 forall (A : Type) (tickets : A -> list N) values owner original replacement ticket,
 registry_at owner values = Some original ->
 Permutation (tickets replacement) (ticket :: tickets original) ->
 Permutation (flat_map tickets (replace owner replacement values))
   (ticket :: flat_map tickets values).
Proof.
 intros A tickets values; induction values as [|first rest IH]; intros owner original replacement ticket
   Found Updated; [discriminate|].
 cbn in Found; cbn [replace].
 destruct (N.eqb owner 0) eqn:Selected.
 - inversion Found; subst first. cbn [flat_map].
   change (Permutation (tickets replacement ++ flat_map tickets rest)
     ((ticket :: tickets original) ++ flat_map tickets rest)).
   apply Permutation_app_tail; exact Updated.
 - cbn [flat_map]. eapply Permutation_trans.
   + apply Permutation_app_head; eapply IH; eauto.
   + apply Permutation_sym; apply Permutation_middle.
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
 pose proof (an_archived_after_request_adds_one_fresh_global_ticket owner task before operations
   original plugin pending result error Valid Found ArchivedTask Member Stage) as Added.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [Unique Bounded].
 set (after := decision_world (TicketedRequest.issue owner
   (TicketedRequest.After original plugin pending result error task) before)) in *.
 set (before_tickets := (flat_map WorldInvariant.task_tickets (world_tasks before) ++
   WorldInvariant.feature_tickets (world_features before))%list) in *.
 set (after_tickets := (flat_map WorldInvariant.task_tickets (world_tasks after) ++
   WorldInvariant.feature_tickets (world_features after))%list) in *.
 assert (Fresh : ~ In (world_next_ticket before) before_tickets).
 { intro Allocated. apply Forall_forall with (x:=world_next_ticket before) in Bounded;
     [lia|exact Allocated]. }
 assert (Distinct : NoDup after_tickets).
 { eapply Permutation_NoDup; [apply Permutation_sym; exact Added|constructor; assumption]. }
 assert (Next : world_next_ticket after = N.succ (world_next_ticket before)) by reflexivity.
 unfold WorldInvariant.tickets_valid; change
   (WorldInvariant.unique_tickets after_tickets &&
     forallb (fun ticket => (ticket <? world_next_ticket after)%N) after_tickets = true).
 apply andb_true_iff; split.
 - unfold WorldInvariant.unique_tickets.
   rewrite nodup_fixed_point by exact Distinct; apply Nat.eqb_refl.
 - apply forallb_forall; intros ticket Owned. rewrite Next; apply N.ltb_lt.
   apply (Permutation_in _ Added) in Owned.
   destruct Owned as [<-|Owned]; [lia|].
   apply Forall_forall with (x:=ticket) in Bounded; [lia|exact Owned].
Qed.

Lemma an_owned_operation_identifier_precedes_the_next_ticket :
 forall owner task before original,
 WorldInvariant.tickets_valid before = true ->
 find_task owner before = Some task -> In original (task_operations task) ->
 (operation_id original < world_next_ticket before)%N.
Proof.
 intros owner task before original Valid Found Member.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [_ Bounded].
 apply Forall_forall with (x:=operation_id original) in Bounded; [exact Bounded|].
 apply in_or_app; left; apply in_flat_map; exists task; split.
 - eapply a_registry_lookup_is_a_member; exact Found.
 - unfold WorldInvariant.task_tickets; apply in_or_app; right.
   apply in_flat_map; exists original; split; [exact Member|].
   apply operation_identifiers_are_part_of_the_ticket_supply.
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
 assert (Erased : without_archived_operations task = without_archived_operations waiting).
 { unfold waiting, without_archived_operations.
   destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed].
   cbn in ArchivedTask; subst lifecycle; reflexivity. }
 assert (Registry : map without_archived_operations (world_tasks before) = map without_archived_operations (world_tasks after)).
 { rewrite After. change (map without_archived_operations (world_tasks before) =
     map without_archived_operations (replace owner waiting (world_tasks before))).
   eapply replacing_a_registry_entry_preserves_equal_observations; eauto. }
 assert (Related : Forall2 (fun old next => without_archived_operations old = without_archived_operations next /\
   forall owner, WorldInvariant.operations_valid owner old = true ->
     WorldInvariant.operations_valid owner next = true) (world_tasks before) (world_tasks after)).
 { rewrite After. change (Forall2 (fun old next =>
     without_archived_operations old = without_archived_operations next /\
     forall owner, WorldInvariant.operations_valid owner old = true ->
       WorldInvariant.operations_valid owner next = true)
     (world_tasks before) (replace owner waiting (world_tasks before))).
   eapply replacing_a_registry_entry_lifts_its_relation; [|exact Found|].
   - intro value; split; [reflexivity|intros; assumption].
   - split; [exact Erased|]. intros observed Valid.
     unfold waiting. eapply staging_an_archived_after_hook_preserves_its_operation_requirements; eauto. }
 constructor.
 - change (WorldInvariant.environment_valid (world_environment after) = true).
   rewrite After; exact Environment.
 - change (WorldInvariant.projects_valid after = true).
   rewrite After; exact Projects.
 - change (WorldInvariant.tasks_valid 0 (world_tasks after) (WorldInvariant.world_structure after) = true).
   eapply task_registry_requirements_lift_across_operation_changes with
     (before:=WorldInvariant.world_structure before); eauto.
 - change (WorldInvariant.tickets_valid after = true).
   unfold after; eapply an_archived_after_request_preserves_the_unique_ticket_supply; eauto.
 - change (WorldInvariant.features_valid (WorldInvariant.world_structure after) = true).
   eapply feature_requirements_lift_across_operation_changes with
     (before:=WorldInvariant.world_structure before).
   + exact Registry.
   + rewrite After; reflexivity.
   + rewrite After; reflexivity.
   + rewrite After. change (world_next_ticket before <= N.succ (world_next_ticket before))%N; lia.
   + exact Features.
Qed.
