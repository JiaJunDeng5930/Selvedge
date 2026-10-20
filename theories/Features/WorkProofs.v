From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Numbers.
From Selvedge.Features Require Import Domain Work WorkUIPatch.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Module K:=Selvedge.Kernel.State.

(** A stale writer cannot overwrite source, revision, ownership or task state. *)
Theorem stale_ui_is_atomic : forall value id previous patch expected,
 Work.lookup id value = Some previous -> expected <> F.work_ui_revision previous ->
 decision_world (Work.patch_work id patch expected value) = value /\
 decision_effects (Work.patch_work id patch expected value) = [].
Proof.
 intros value id previous patch expected found different.
 unfold Work.patch_work. rewrite found.
 destruct (N.ltb (F.work_ui_revision previous) 4294967295); simpl.
 - apply N.eqb_neq in different. rewrite different. split; reflexivity.
 - split; reflexivity.
Qed.
Theorem failed_patch_is_atomic : forall value id previous patch expected reason,
 Work.lookup id value = Some previous ->
 WorkUIPatch.apply (F.work_ui_source previous) patch = WorkUIPatch.Fail reason ->
 decision_world (Work.patch_work id patch expected value) = value /\
 decision_effects (Work.patch_work id patch expected value) = [].
Proof.
 intros value id previous patch expected reason found failed.
 unfold Work.patch_work. rewrite found.
 destruct (N.ltb (F.work_ui_revision previous) 4294967295); [|split;reflexivity].
 destruct (N.eqb expected (F.work_ui_revision previous)); [rewrite failed|]; split; reflexivity.
Qed.
Theorem ui_requires_task_call : forall value patch expected,
 Work.apply_ui_patch None patch expected value =
 K.reject "task_call_required"%string "Edit the shared UI through a Task tool call."%string value.
Proof. reflexivity. Qed.
Theorem failed_owned_birth_rolls_back : forall owner original created,
 bool_field "ok"%string (decision_reply created) <> Some true ->
 decision_world (Work.own_created owner original created) = original /\
 decision_effects (Work.own_created owner original created) = [].
Proof.
 intros owner original created failed. unfold Work.own_created.
 destruct (bool_field "ok"%string (decision_reply created)) as [[|]|]; try (split;reflexivity).
 contradiction.
Qed.

(** Explicit ownership wins; an unassociated fork inherits the closest
    explicitly owned ancestor, rather than assuming only roots have owners. *)
Theorem nearest_ancestor_owns_work : forall value child parent lineage owner,
 F.association child (F.feature_task_owners value)=None ->
 F.association parent (F.feature_task_owners value)=Some owner ->
 F.owner_id child (parent::lineage) value=Some owner.
Proof. intros. unfold F.owner_id. rewrite H. cbn [F.lineage_owner]. now rewrite H0. Qed.
