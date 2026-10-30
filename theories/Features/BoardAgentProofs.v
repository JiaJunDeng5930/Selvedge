From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain Board BoardParameters.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.

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

Theorem invalid_agent_precedes_capacity_lookup_and_revision supplied expected name profile reasoning instructions settings capacity value :
 (forall revision, Board.valid_agent
   (F.BoardAgent revision name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = false) ->
 exists reason, Board.save_agent supplied expected name profile reasoning instructions settings capacity value =
   reject "invalid_agent" reason value.
Proof.
 intro Invalid. unfold Board.save_agent; cbn beta iota zeta.
 destruct (String.eqb supplied "") eqn:Creating; cbn beta iota zeta.
 - rewrite (Invalid 0%N). eexists; reflexivity.
 - destruct (text_id supplied); cbn beta iota zeta.
   + rewrite (Invalid (N.succ expected)). eexists; reflexivity.
   + eexists; reflexivity.
Qed.

Corollary empty_agent_name_precedes_capacity_lookup_and_revision supplied expected profile reasoning instructions settings capacity value :
 exists reason, Board.save_agent supplied expected "" profile reasoning instructions settings capacity value =
   reject "invalid_agent" reason value.
Proof.
 apply invalid_agent_precedes_capacity_lookup_and_revision. intro revision. reflexivity.
Qed.

Theorem full_agent_capacity_rejects_only_new_agents expected name profile reasoning instructions settings capacity value :
 Board.valid_agent (F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = true ->
 (64 <= agent_count value)%nat ->
 Board.save_agent "" expected name profile reasoning instructions settings capacity value =
 reject "agent_limit" "The board holds at most 64 agents" value.
Proof.
 intros Valid Full. unfold Board.save_agent; cbn beta iota zeta.
 rewrite String.eqb_refl,Valid. cbn beta iota zeta.
 assert (Capacity : Nat.ltb (agent_count value) 64 = false) by (apply Nat.ltb_ge;exact Full).
 change (Nat.ltb (List.length (filter (fun item : option F.board_agent =>
   match item with Some _=>true | None=>false end) (F.board_agents (Board.registry value)))) 64 = false) in Capacity.
 rewrite Capacity. reflexivity.
Qed.

Theorem valid_new_agent_is_saved_below_capacity expected name profile reasoning instructions settings capacity value :
 Board.valid_agent (F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = true ->
 (agent_count value < 64)%nat ->
 (N.of_nat (List.length (agent_slots value)) < 4294967295)%N ->
 let saved := Board.save_agent "" expected name profile reasoning instructions settings capacity value in
 let identity := N.of_nat (List.length (agent_slots value)) in
 let agent := F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity in
 decision_reply saved = success (JObject [("agent_id",number identity);("revision",number 0)]) /\
 decision_effects saved = [] /\
 agent_slots (decision_world saved) = agent_slots value ++ [Some agent] /\
 Board.lookup_agent identity (decision_world saved) = Some agent /\
 agent_count (decision_world saved) = S (agent_count value).
Proof.
 intros Valid Available Identity. cbn beta iota zeta.
 unfold Board.save_agent; cbn beta iota zeta.
 rewrite String.eqb_refl,Valid. cbn beta iota zeta.
 assert (Capacity : Nat.ltb (agent_count value) 64 = true) by (apply Nat.ltb_lt;exact Available).
 assert (Space : N.ltb (N.of_nat (List.length (agent_slots value))) 4294967295 = true)
   by (apply N.ltb_lt;exact Identity).
 unfold agent_count,live_count,occupied,agent_slots in Capacity,Space.
 rewrite Capacity,Space. cbn beta iota zeta. repeat split; try reflexivity.
 - change (match registry_at (N.of_nat (List.length (agent_slots value)))
     (agent_slots value ++ [Some (F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity)]) with
     Some slot => slot | None => None end =
     Some (F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity)).
   rewrite registry_lookup_at_appended_index. reflexivity.
 - change (live_count (agent_slots value ++ [Some (F.BoardAgent 0 name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity)]) =
     S (live_count (agent_slots value))).
   unfold live_count. rewrite filter_app,app_length. cbn. lia.
Qed.

Theorem absent_agent_precedes_revision_and_ignores_capacity supplied id expected name profile reasoning instructions settings capacity value :
 String.eqb supplied "" = false -> text_id supplied = Some id ->
 Board.valid_agent (F.BoardAgent (N.succ expected) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = true ->
 Board.lookup_agent id value = None ->
 Board.save_agent supplied expected name profile reasoning instructions settings capacity value =
 reject "agent_not_found" "The board agent no longer exists" value.
Proof.
 intros Existing Identity Valid Missing.
 unfold Board.save_agent; cbn beta iota zeta.
 rewrite Existing,Identity. cbn beta iota zeta. rewrite Valid,Missing. reflexivity.
Qed.

Theorem stale_agent_revision_rejects_even_at_capacity supplied id expected previous name profile reasoning instructions settings capacity value :
 String.eqb supplied "" = false -> text_id supplied = Some id ->
 Board.valid_agent (F.BoardAgent (N.succ expected) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = true ->
 Board.lookup_agent id value = Some previous -> expected <> F.agent_revision previous ->
 Board.save_agent supplied expected name profile reasoning instructions settings capacity value =
 reject "agent_conflict" "This board agent changed" value.
Proof.
 intros Existing Identity Valid Found Different.
 unfold Board.save_agent; cbn beta iota zeta.
 rewrite Existing,Identity. cbn beta iota zeta. rewrite Valid,Found.
 apply N.eqb_neq in Different. rewrite Different. reflexivity.
Qed.

Theorem current_agent_update_succeeds_without_a_capacity_precondition supplied id expected previous name profile reasoning instructions settings capacity value :
 String.eqb supplied "" = false -> text_id supplied = Some id ->
 Board.valid_agent (F.BoardAgent (N.succ expected) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity) value = true ->
 Board.lookup_agent id value = Some previous -> expected = F.agent_revision previous ->
 let saved := Board.save_agent supplied expected name profile reasoning instructions settings capacity value in
 let agent := F.BoardAgent (N.succ expected) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity in
 decision_reply saved = success (JObject [("agent_id",number id);("revision",number (N.succ expected))]) /\
 decision_effects saved = [] /\
 Board.lookup_agent id (decision_world saved) = Some agent /\
 agent_count (decision_world saved) = agent_count value /\
 List.length (agent_slots (decision_world saved)) = List.length (agent_slots value).
Proof.
 intros Existing Identity Valid Found Current. cbn beta iota zeta.
 pose proof (agent_lookup_has_a_present_slot id value previous Found) as Present.
 unfold Board.save_agent; cbn beta iota zeta.
 rewrite Existing,Identity. cbn beta iota zeta. rewrite Valid,Found,Current,N.eqb_refl.
 cbn beta iota zeta. repeat split; try reflexivity.
 - change (match registry_at id (replace id
     (Some (F.BoardAgent (N.succ (F.agent_revision previous)) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity))
     (agent_slots value)) with Some slot=>slot | None=>None end =
     Some (F.BoardAgent (N.succ (F.agent_revision previous)) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity)).
   rewrite (registry_replace_selected _ _ _ _ _ Present). reflexivity.
 - change (live_count (replace id
     (Some (F.BoardAgent (N.succ (F.agent_revision previous)) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity))
     (agent_slots value)) = live_count (agent_slots value)).
   pose proof (replacing_present_slot_counts_the_actual_replacement _ _ _
     (Some (F.BoardAgent (N.succ (F.agent_revision previous)) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity)) Present).
   cbn [occupied] in H. lia.
 - change (List.length (replace id
     (Some (F.BoardAgent (N.succ (F.agent_revision previous)) name profile reasoning instructions (Board.retained settings Codec.empty_settings_request) capacity))
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
