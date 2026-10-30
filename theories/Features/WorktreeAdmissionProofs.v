From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain State Tasks CommandExecution TaskChangesProofs.
From Selvedge.Features Require Import WorkspaceBinding.
Import ListNotations.

(** A side's cursor belongs to the source, while admission belongs to the
    selected parent. The existing typed commit advances the cursor only after
    the ordinary input constructor accepts that parent. *)
Theorem returning_to_a_failed_parent_preserves_the_side : forall id value side parent current,
 find_task id value = Some side ->
 task_side_parent side = Some parent ->
 find_task parent value = Some current ->
 WorkspaceBinding.input_available current value = false ->
 decision_world (CommandExecution.return_side id value) = value /\
 decision_effects (CommandExecution.return_side id value) = [].
Proof.
 intros id value side parent current Found Parent Selected Failed.
 unfold CommandExecution.return_side; rewrite Found.
 destruct (task_lifecycle side); try (split; reflexivity);
 rewrite Parent; cbn zeta;
 destruct (filter _ _) as [|first rest]; try (split; reflexivity).
 all: unfold Tasks.send_result; rewrite TaskChangesProofs.input_result_expression; cbv beta zeta; rewrite Selected.
 all: destruct (task_lifecycle current); try (split; reflexivity).
 all: destruct (content_nonempty _); try (split; reflexivity).
 all: rewrite Failed; cbn; split; reflexivity.
Qed.
