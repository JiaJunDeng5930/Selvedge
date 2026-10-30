From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain Board BoardParameters.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.

(** Board creation and revision updates share one capacity ledger. *)
Definition agent_slots value := F.board_agents (Board.registry value).
Definition occupied (slot : option F.board_agent) := match slot with Some _ => true | None => false end.
Definition live_count slots := List.length (filter occupied slots).
Definition agent_count value := live_count (agent_slots value).

Lemma replacing_present_slot_counts_the_actual_replacement slots id previous replacement :
 registry_at id slots = Some (Some previous) ->
 (live_count (replace id replacement slots) + 1 =
   live_count slots + (if occupied replacement then 1 else 0))%nat.
Proof.
 revert id previous. induction slots as [|head rest IH]; intros id previous Found; [discriminate|].
 cbn [registry_at] in Found. cbn [replace]. destruct (N.eqb id 0) eqn:Selected.
 - inversion Found; subst head. destruct replacement; unfold live_count; cbn [occupied filter List.length]; lia.
 - specialize (IH _ _ Found). destruct head; unfold live_count in *; cbn [occupied filter List.length] in *; lia.
Qed.

Lemma agent_lookup_has_a_present_slot id value previous :
 Board.lookup_agent id value = Some previous ->
 registry_at id (agent_slots value) = Some (Some previous).
Proof.
 unfold Board.lookup_agent,agent_slots. destruct (registry_at id _) as [slot|]; [|discriminate].
 intro Found. now subst slot.
Qed.

Theorem unavailable_agent_execution_precedes_capacity_and_revision source value :
 (forall revision, Board.agent_execution_available (Board.agent_parameters revision source) value = false) ->
 exists reason, Board.save_agent source value = reject "invalid_agent" reason value.
Proof.
 intro Invalid. unfold Board.save_agent.
 destruct (Board.agent_identity source); cbn beta iota zeta;
 rewrite Invalid; eexists; reflexivity.
Qed.

Theorem full_agent_capacity_rejects_only_new_agents source value :
 Board.agent_identity source = None ->
 Board.agent_execution_available (Board.agent_parameters 0 source) value = true ->
 (64 <= agent_count value)%nat ->
 Board.save_agent source value = reject "agent_limit" "The board holds at most 64 agents" value.
Proof.
 intros Creating Valid Full. unfold Board.save_agent; rewrite Creating; cbn beta iota zeta.
 rewrite Valid. cbn beta iota zeta.
 assert (Capacity : Nat.ltb (agent_count value) 64 = false) by (apply Nat.ltb_ge;exact Full).
 change (Nat.ltb (List.length (filter (fun item : option F.board_agent =>
   match item with Some _=>true | None=>false end) (F.board_agents (Board.registry value)))) 64 = false) in Capacity.
 rewrite Capacity. reflexivity.
Qed.

Theorem valid_new_agent_is_saved_below_capacity source value :
 Board.agent_identity source = None ->
 Board.agent_execution_available (Board.agent_parameters 0 source) value = true ->
 (agent_count value < 64)%nat ->
 (N.of_nat (List.length (agent_slots value)) < 4294967295)%N ->
 let saved := Board.save_agent source value in
 let identity := N.of_nat (List.length (agent_slots value)) in
 let agent := Board.agent_parameters 0 source in
 decision_reply saved = success (JObject [("agent_id",number identity);("revision",number 0)]) /\
 decision_effects saved = [] /\
 agent_slots (decision_world saved) = agent_slots value ++ [Some agent] /\
 Board.lookup_agent identity (decision_world saved) = Some agent /\
 agent_count (decision_world saved) = S (agent_count value).
Proof.
 intros Creating Valid Available Identity. cbn beta iota zeta.
 unfold Board.save_agent; rewrite Creating; cbn beta iota zeta.
 rewrite Valid. cbn beta iota zeta.
 assert (Capacity : Nat.ltb (agent_count value) 64 = true) by (apply Nat.ltb_lt;exact Available).
 assert (Space : N.ltb (N.of_nat (List.length (agent_slots value))) 4294967295 = true)
   by (apply N.ltb_lt;exact Identity).
 unfold agent_count,live_count,occupied,agent_slots in Capacity,Space.
 rewrite Capacity,Space. cbn beta iota zeta. repeat split; try reflexivity.
 - change (match registry_at (N.of_nat (List.length (agent_slots value)))
     (agent_slots value ++ [Some (Board.agent_parameters 0 source)]) with
     Some slot => slot | None => None end = Some (Board.agent_parameters 0 source)).
   rewrite registry_lookup_at_appended_index. reflexivity.
 - change (live_count (agent_slots value ++ [Some (Board.agent_parameters 0 source)]) =
     S (live_count (agent_slots value))).
   unfold live_count. rewrite filter_app,app_length. cbn. lia.
Qed.

Theorem absent_agent_precedes_revision_and_ignores_capacity source id value :
 Board.agent_identity source = Some id ->
 Board.agent_execution_available (Board.agent_parameters (N.succ (G.save_board_agent_revision source)) source) value = true ->
 Board.lookup_agent id value = None ->
 Board.save_agent source value = reject "agent_not_found" "The board agent no longer exists" value.
Proof.
 intros Identity Valid Missing. unfold Board.save_agent; rewrite Identity; cbn beta iota zeta.
 rewrite Valid,Missing. reflexivity.
Qed.

Theorem stale_agent_revision_rejects_even_at_capacity source id previous value :
 Board.agent_identity source = Some id ->
 Board.agent_execution_available (Board.agent_parameters (N.succ (G.save_board_agent_revision source)) source) value = true ->
 Board.lookup_agent id value = Some previous -> G.save_board_agent_revision source <> F.agent_revision previous ->
 Board.save_agent source value = reject "agent_conflict" "This board agent changed" value.
Proof.
 intros Identity Valid Found Different. unfold Board.save_agent; rewrite Identity; cbn beta iota zeta.
 rewrite Valid,Found. apply N.eqb_neq in Different. rewrite Different. reflexivity.
Qed.

Theorem current_agent_update_succeeds_without_a_capacity_precondition source id previous value :
 Board.agent_identity source = Some id ->
 Board.agent_execution_available (Board.agent_parameters (N.succ (G.save_board_agent_revision source)) source) value = true ->
 Board.lookup_agent id value = Some previous -> G.save_board_agent_revision source = F.agent_revision previous ->
 let saved := Board.save_agent source value in
 let agent := Board.agent_parameters (N.succ (G.save_board_agent_revision source)) source in
 decision_reply saved = success (JObject [("agent_id",number id);("revision",number (N.succ (G.save_board_agent_revision source)))]) /\
 decision_effects saved = [] /\
 Board.lookup_agent id (decision_world saved) = Some agent /\
 agent_count (decision_world saved) = agent_count value /\
 List.length (agent_slots (decision_world saved)) = List.length (agent_slots value).
Proof.
 intros Identity Valid Found Current. cbn beta iota zeta.
 pose proof (agent_lookup_has_a_present_slot id value previous Found) as Present.
 unfold Board.save_agent; rewrite Identity; cbn beta iota zeta.
 rewrite Valid,Found,Current,N.eqb_refl.
 cbn beta iota zeta. repeat split; try reflexivity.
 - change (match registry_at id (replace id
     (Some (Board.agent_parameters (N.succ (F.agent_revision previous)) source))
     (agent_slots value)) with Some slot=>slot | None=>None end =
     Some (Board.agent_parameters (N.succ (F.agent_revision previous)) source)).
   rewrite (registry_replace_selected _ _ _ _ _ Present). reflexivity.
 - change (live_count (replace id
     (Some (Board.agent_parameters (N.succ (F.agent_revision previous)) source))
     (agent_slots value)) = live_count (agent_slots value)).
   pose proof (replacing_present_slot_counts_the_actual_replacement _ _ _
     (Some (Board.agent_parameters (N.succ (F.agent_revision previous)) source)) Present).
   cbn [occupied] in H. lia.
 - change (List.length (replace id
     (Some (Board.agent_parameters (N.succ (F.agent_revision previous)) source))
     (agent_slots value)) = List.length (agent_slots value)).
   apply registry_replace_length.
Qed.

Theorem deleting_an_unused_current_agent_frees_exactly_one_slot id expected previous value :
 Board.lookup_agent id value = Some previous -> expected = F.agent_revision previous ->
 (forall card, In (Some card) (F.board_cards (Board.registry value)) ->
   F.draft_owner (F.card_contents card) <> F.AgentOwner id) ->
 let deleted := Board.delete_agent id expected value in
 decision_reply deleted = success (JObject [("agent_id",number id)]) /\
 decision_effects deleted = [] /\
 Board.lookup_agent id (decision_world deleted) = None /\
 S (agent_count (decision_world deleted)) = agent_count value /\
 List.length (agent_slots (decision_world deleted)) = List.length (agent_slots value).
Proof.
 intros Found Current Unassigned. cbn beta iota zeta.
 pose proof (agent_lookup_has_a_present_slot id value previous Found) as Present.
 assert (Unused : existsb (fun item=>match item with Some card=>match F.draft_owner (F.card_contents card) with
   F.AgentOwner owner=>N.eqb id owner | _=>false end | None=>false end) (F.board_cards (Board.registry value)) = false).
 { apply Bool.not_true_is_false. intro Used. apply existsb_exists in Used as [slot [Member Used]].
   destruct slot as [card|]; [|discriminate].
   destruct (F.draft_owner (F.card_contents card)) eqn:Owner; try discriminate.
   apply N.eqb_eq in Used; subst. apply (Unassigned card Member). exact Owner. }
 unfold Board.delete_agent; rewrite Found,Current,N.eqb_refl,Unused.
 cbn beta iota zeta. repeat split; try reflexivity.
 - change (match registry_at id (replace id None (agent_slots value)) with Some slot=>slot | None=>None end = None).
   rewrite (registry_replace_selected _ _ _ _ _ Present). reflexivity.
 - change (S (live_count (replace id None (agent_slots value))) = live_count (agent_slots value)).
   pose proof (replacing_present_slot_counts_the_actual_replacement _ _ _ None Present).
   cbn [occupied] in H. lia.
 - change (List.length (replace id None (agent_slots value)) = List.length (agent_slots value)).
   apply registry_replace_length.
Qed.
