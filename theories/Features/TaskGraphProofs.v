From Stdlib Require Import String List NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Features Require Import Domain State TaskGraph.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Module K:=Selvedge.Kernel.State.
Lemma failed_birth_is_terminal : forall nodes owner caller failure,
 fold_left (fun progress node=>TaskGraph.birth owner caller node progress) nodes (TaskGraph.BirthFailed failure) = TaskGraph.BirthFailed failure.
Proof. induction nodes;intros; simpl;auto. Qed.
(** A missing existing node after any declaration prefix cannot leave births
    or effects from that rejected installation behind. *)
Theorem missing_first_node_is_atomic : forall id owner name key target rest rules caller value,
 K.find_task target value = None ->
 decision_world (TaskGraph.install id owner name (F.ExistingNode key target::rest) rules caller value) = value /\
 decision_effects (TaskGraph.install id owner name (F.ExistingNode key target::rest) rules caller value) = [].
Proof.
 intros.
 assert (first : TaskGraph.birth owner caller (F.ExistingNode key target) (TaskGraph.Born value [] []) =
 TaskGraph.BirthFailed (K.failure "task_not_found"%string "A referenced graph task does not exist"%string)).
 { unfold TaskGraph.birth. rewrite H. reflexivity. }
 unfold TaskGraph.install. cbn -[TaskGraph.birth]. rewrite first.
 rewrite failed_birth_is_terminal. split;reflexivity.
Qed.
(** Installing a graph never dispatches the pre-existing history again. *)
Theorem unchanged_history_has_no_new_outputs : forall value id task,
 K.find_task id value = Some task -> TaskGraph.new_outputs value id task = [].
Proof.
 intros value id task found. unfold TaskGraph.new_outputs. rewrite found.
 rewrite skipn_all. reflexivity.
Qed.

(** A rule only reacts to the Task identified by its declared source. *)
Theorem different_source_never_dispatches : forall source graph nodes rule output expected,
 TaskGraph.resolve (F.rule_source rule) nodes=Some expected -> source<>expected ->
 TaskGraph.pending_rule source graph nodes rule output=[].
Proof.
 intros source graph nodes rule output expected resolved other.
 unfold TaskGraph.pending_rule. rewrite resolved.
 apply N.eqb_neq in other. now rewrite other.
Qed.

Theorem failed_installation_is_atomic : forall id owner name nodes rules caller original failure,
 fold_left (fun progress node=>TaskGraph.birth owner caller node progress) nodes
   (TaskGraph.Born original [] [])=TaskGraph.BirthFailed failure ->
 decision_world (TaskGraph.install id owner name nodes rules caller original)=original /\
 decision_effects (TaskGraph.install id owner name nodes rules caller original)=[].
Proof. intros. unfold TaskGraph.install. rewrite H. split;reflexivity. Qed.
