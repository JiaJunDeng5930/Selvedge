From Stdlib Require Import List String NArith.
From Selvedge.Programming Require CommandResult TaskScope.
From Selvedge.Foundation Require Import Json JsonObjectsProofs.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Programming Require Import TaskScopeProofs.
From Selvedge.Kernel Require Import Tasks History Codec.
From Selvedge.Kernel Require Import CommandExecution LifecycleProofs.
From Selvedge.Programming Require TaskChangeProofs.
Import ListNotations.
Open Scope string_scope.

Theorem side_birth_serializes_as_provider_context : forall owner parent start,
 JsonObjects.equivalent (Codec.message_json owner (SideConversationBirth owner parent start))
   (JObject [("role", JString "task_context"); ("type", JString "side_conversation");
     ("owner_task", number owner); ("parent_task", number parent); ("start", number start)]) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.

Theorem successful_open_side_records_private_birth_guidance : forall parent_id contents value,
 bool_default "ok" (decision_reply (Tasks.open_side parent_id contents value)) false = true ->
 exists parent, find_task parent_id value = Some parent /\
   let inherited := Tasks.selected_context_history (task_current_settings parent) parent
     (History.snapshot_history parent_id parent) in
   let start := N.succ (N.of_nat (List.length inherited)) in
   let birth := SideConversationBirth (next_task value) parent_id start in
   let child := Tasks.fork_child (next_task value) parent_id parent (Tasks.side_input contents) (task_current_settings parent) true in
   In child (world_tasks (decision_world (Tasks.open_side parent_id contents value))) /\
   task_side_handoff child = Some (SideHandoff parent_id (N.of_nat (List.length
     (Tasks.fork_child_history (next_task value) parent_id parent (task_current_settings parent) true)))) /\
   In birth (task_history child) /\
   (exists context, In context (map (Codec.message_json (next_task value)) (task_history child)) /\
     JsonObjects.equivalent context
       (JObject [("role", JString "task_context"); ("type", JString "side_conversation");
         ("owner_task", number (next_task value)); ("parent_task", number parent_id); ("start", number start)]) = true) /\
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
          ++ exists (Codec.message_json (next_task value)
               (SideConversationBirth (next_task value) parent_id
                 (N.succ (N.of_nat (List.length
                   (Tasks.selected_context_history (task_current_settings parent) parent
                     (History.snapshot_history parent_id parent))))))).
             split.
             ** apply in_map.
                unfold Tasks.fork_child, Tasks.fork_child_history.
                simpl. apply in_or_app. left. apply in_or_app. right. simpl. left. reflexivity.
             ** apply side_birth_serializes_as_provider_context.
          ++ reflexivity.
 - intros Missing successful. discriminate.
Qed.

Local Lemma accepted_input_preserves_other_tasks : forall mode target contents before delivered other,
 target <> other ->
 Tasks.input_result mode target contents before = CommandResult.Accepted delivered ->
 find_task other (CommandResult.change_world delivered) = find_task other before.
Proof.
 intros mode target contents before delivered other Different.
 unfold Tasks.input_result.
 pattern (TaskScope.select target before).
 apply TaskScopeProofs.selected_reference_elimination.
 - intros reference Owner.
   destruct (task_lifecycle (TaskScope.selected reference)); try discriminate;
   destruct (Tasks.content_nonempty contents); try discriminate;
   destruct (Tasks.admit_input reference) as [admitted|reason]; try discriminate;
   cbn [CommandResult.map CommandResult.bind]; intro Accepted;
   inversion Accepted; subst delivered;
   apply TaskChangeProofs.a_field_plan_preserves_every_other_task;
   cbn [TaskChange.target]; congruence.
 - intros Missing; discriminate.
Qed.

(** The source cursor consumes a suffix only after ordinary parent admission.
    A second return without new history cannot send that suffix again. *)
Theorem successful_side_return_consumes_the_observed_suffix : forall id value side handoff,
 find_task id value = Some side ->
 task_side_handoff side = Some handoff ->
 id <> handoff_parent handoff ->
 bool_default "ok" (decision_reply (CommandExecution.return_side id value)) false = true ->
 let after := decision_world (CommandExecution.return_side id value) in
 let next := advance_side_handoff (N.of_nat (List.length (task_history side))) handoff in
 find_task id after = Some (with_side_handoff next side) /\
 bool_default "ok" (decision_reply (CommandExecution.return_side id after)) true = false /\
 decision_world (CommandExecution.return_side id after) = after /\
 decision_effects (CommandExecution.return_side id after) = [].
Proof.
 intros id value side handoff Found Handoff Different Successful.
 assert (Through : forall cursor, handoff_through (advance_side_handoff cursor handoff) = cursor)
   by (destruct handoff; reflexivity).
 remember (CommandExecution.return_side id value) as returned eqn:Returned in *.
 pose proof Returned as Computed.
 unfold CommandExecution.return_side in Computed; rewrite Found in Computed.
 destruct (task_lifecycle side) eqn:Life;
   try (rewrite Computed in Successful; discriminate).
 all: rewrite Handoff in Computed; cbn zeta in Computed.
 all: destruct (filter History.returned_content
   (skipn (N.to_nat (handoff_through handoff)) (task_history side)))
   as [|first rest] eqn:Content in Computed;
   try (rewrite Computed in Successful; discriminate).
 all: lazymatch type of Computed with
   | _ = CommandResult.commit _ _ ?result =>
     destruct result as [delivered|reason] eqn:Delivered in Computed
   end.
 all: cbn [CommandResult.commit CommandResult.map CommandResult.bind
   CommandResult.decide CommandResult.resolve CommandResult.accept
   CommandResult.change_value CommandResult.change_world CommandResult.change_effects
   accept decision_reply decision_world] in Computed;
   try (rewrite Computed in Successful; discriminate).
 all: pose proof (accepted_input_preserves_other_tasks Tasks.AppendInput (handoff_parent handoff) _
   value delivered id ltac:(congruence) Delivered) as Retained.
 all: rewrite Found in Retained.
 all: rewrite Computed; cbn [CommandResult.accept CommandResult.change_world accept decision_world].
 all: set (next := advance_side_handoff (N.of_nat (List.length (task_history side))) handoff) in *.
 all: assert (Installed : find_task id
   (put_task id (with_side_handoff next side) (CommandResult.change_world delivered)) =
   Some (with_side_handoff next side))
   by (eapply find_put_task; exact Retained).
 all: split; [exact Installed|].
 all: unfold CommandExecution.return_side; rewrite Installed.
 all: destruct side; cbn in Life, Handoff |- *.
 all: rewrite Life; unfold next; cbn -[N.to_nat N.of_nat advance_side_handoff];
   rewrite Through,Nat2N.id,skipn_all; repeat split; reflexivity.
Qed.

Theorem a_refused_side_return_keeps_the_world_and_effects : forall id value,
 bool_default "ok" (decision_reply (CommandExecution.return_side id value)) false = false ->
 decision_world (CommandExecution.return_side id value) = value /\
 decision_effects (CommandExecution.return_side id value) = [].
Proof.
 intros id value.
 unfold CommandExecution.return_side.
 destruct (find_task id value) as [side|]; [|intros; split; reflexivity].
 destruct (task_lifecycle side); try (intros; split; reflexivity).
 all: destruct (task_side_handoff side) as [handoff|]; try (intros; split; reflexivity).
 all: cbn zeta; destruct (filter History.returned_content
   (skipn (N.to_nat (handoff_through handoff)) (task_history side)));
   try (intros; split; reflexivity).
 all: apply CommandResult.a_failed_commit_is_atomic.
Qed.
