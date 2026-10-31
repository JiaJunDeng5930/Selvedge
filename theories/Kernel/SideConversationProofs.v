From Stdlib Require Import List String NArith.
From Selvedge.Programming Require CommandResult TaskScope.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Programming Require Import TaskScopeProofs.
From Selvedge.Kernel Require Import Tasks History Codec.
Import ListNotations.
Open Scope string_scope.

Theorem side_birth_serializes_as_provider_context : forall owner parent start,
 Codec.message_json owner (SideConversationBirth owner parent start) =
 JObject [("role", JString "task_context"); ("type", JString "side_conversation");
   ("owner_task", number owner); ("parent_task", number parent); ("start", number start)].
Proof. reflexivity. Qed.

Theorem successful_open_side_records_private_birth_guidance : forall parent_id contents value,
 decision_reply (Tasks.open_side parent_id contents value) =
   success (JObject [("task_id", number (next_task value)); ("parent_task_id", number parent_id)]) ->
 exists parent, find_task parent_id value = Some parent /\
   let inherited := Tasks.selected_context_history (task_current_settings parent) parent
     (History.snapshot_history parent_id parent) in
   let start := N.succ (N.of_nat (List.length inherited)) in
   let birth := SideConversationBirth (next_task value) parent_id start in
   let child := Tasks.fork_child (next_task value) parent_id parent (Tasks.side_input contents) (task_current_settings parent) true in
   In child (world_tasks (decision_world (Tasks.open_side parent_id contents value))) /\
   task_side_parent child = Some parent_id /\
   In birth (task_history child) /\
   In (JObject [("role", JString "task_context"); ("type", JString "side_conversation");
     ("owner_task", number (next_task value)); ("parent_task", number parent_id); ("start", number start)])
     (map (Codec.message_json (next_task value)) (task_history child)) /\
   task_side_cursor child = N.of_nat (List.length
     (Tasks.fork_child_history (next_task value) parent_id parent (task_current_settings parent) true)) /\
   History.returned_content birth = false.
Proof.
 intros parent_id contents value.
 unfold Tasks.open_side.
 pattern (TaskScope.select parent_id value).
 apply TaskScopeProofs.selected_reference_elimination.
 - intros reference Owner successful.
   cbn beta iota zeta in successful |-.
   set (parent := TaskScope.selected reference) in *.
   destruct (String.eqb (task_status parent) "archived") eqn:Archived; [discriminate|].
   destruct (Tasks.ancestors_fit (parent_id :: task_lineage parent) 1 value)
     eqn:Capacity; [|discriminate].
   destruct (Tasks.admit_input reference) as [admitted|reason] eqn:Admission; [|discriminate].
   exists parent. split.
   + rewrite <- Owner. exact (TaskScope.observed reference).
   + cbn [CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
       CommandResult.accept decision_world accept append_task with_tasks world_tasks].
     split.
     * apply in_or_app. right. simpl. left. reflexivity.
     * split; [reflexivity|].
       split.
       -- unfold Tasks.fork_child, Tasks.fork_child_history.
          simpl. apply in_or_app. left. apply in_or_app. right. simpl. left. reflexivity.
       -- split.
          ++ rewrite <- side_birth_serializes_as_provider_context.
             apply in_map.
             unfold Tasks.fork_child, Tasks.fork_child_history.
             simpl. apply in_or_app. left. apply in_or_app. right. simpl. left. reflexivity.
          ++ split; [reflexivity|reflexivity].
 - intros Missing successful. discriminate.
Qed.
