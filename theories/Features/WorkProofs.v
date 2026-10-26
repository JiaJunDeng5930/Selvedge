From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Numbers LifecycleProofs.
From Selvedge.Features Require Import Domain State Work WorkUIPatch.
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

Theorem admitted_creation_stores_the_new_work : forall value chosen name,
 let id := N.of_nat (List.length (F.feature_works (world_features value))) in
 name = (match chosen with
   | Some text => if String.eqb text "" then String.append "Work #" (F.decimal_text id) else text
   | None => String.append "Work #" (F.decimal_text id) end)%string ->
 N.ltb id 4294967295 = true -> Work.valid_name name = true ->
 let updated := Work.create chosen value in
 Work.lookup id (decision_world updated) = Some (F.Work name "" 0) /\
 F.feature_task_owners (world_features (decision_world updated)) = F.feature_task_owners (world_features value) /\
 F.feature_graph_owners (world_features (decision_world updated)) = F.feature_graph_owners (world_features value) /\
 decision_effects updated = [].
Proof.
 intros value chosen name id Name Available Valid; subst name.
 cbv zeta; unfold Work.create; cbv beta zeta; fold id; rewrite Available, Valid.
 cbn [decision_world decision_effects]; split.
 - unfold Work.lookup; cbn; apply Selvedge.Foundation.RegistryProofs.registry_lookup_at_appended_index.
 - repeat split; reflexivity.
Qed.

Theorem rename_preserves_shared_ui_and_ownership : forall value id previous name,
 Work.lookup id value = Some previous -> Work.valid_name name = true ->
 let updated := decision_world (Work.rename id name value) in
 Work.lookup id updated = Some (F.Work name (F.work_ui_source previous) (F.work_ui_revision previous)) /\
 F.feature_task_owners (world_features updated) = F.feature_task_owners (world_features value) /\
 F.feature_graph_owners (world_features updated) = F.feature_graph_owners (world_features value) /\
 world_tasks updated = world_tasks value.
Proof.
 intros value id previous name Found Valid; cbv zeta.
 unfold Work.rename; rewrite Found, Valid; cbn [decision_world]; split.
 - unfold Work.lookup in *; cbn; now apply registry_replace_selected with previous.
 - repeat split; reflexivity.
Qed.

Theorem rename_preserves_other_works : forall value id name other,
 id <> other ->
 Work.lookup other (decision_world (Work.rename id name value)) = Work.lookup other value.
Proof.
 intros value id name other Different; unfold Work.rename.
 destruct (Work.lookup id value); [destruct (Work.valid_name name)|]; try reflexivity.
 unfold Work.lookup; cbn; now apply Selvedge.Foundation.RegistryProofs.registry_replace_other.
Qed.

Theorem shared_ui_patch_preserves_other_works : forall value id patch expected other,
 id <> other ->
 Work.lookup other (decision_world (Work.patch_work id patch expected value)) = Work.lookup other value.
Proof.
 intros value id patch expected other Different; unfold Work.patch_work.
 destruct (Work.lookup id value) as [previous|]; [|reflexivity].
 destruct (N.ltb (F.work_ui_revision previous) 4294967295); [|reflexivity].
 destruct (N.eqb expected (F.work_ui_revision previous)); [|reflexivity].
 destruct (WorkUIPatch.apply (F.work_ui_source previous) patch); [|reflexivity].
 unfold Work.lookup; cbn; now apply Selvedge.Foundation.RegistryProofs.registry_replace_other.
Qed.

Theorem shared_ui_patch_preserves_task_ownership : forall value id patch expected owner,
 Work.task_owner owner (decision_world (Work.patch_work id patch expected value)) = Work.task_owner owner value.
Proof.
 intros value id patch expected owner; unfold Work.patch_work.
 destruct (Work.lookup id value) as [previous|]; [|reflexivity].
 destruct (N.ltb (F.work_ui_revision previous) 4294967295); [|reflexivity].
 destruct (N.eqb expected (F.work_ui_revision previous)); [|reflexivity].
 destruct (WorkUIPatch.apply (F.work_ui_source previous) patch); reflexivity.
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
Theorem own_birth_changes_only_ownership : forall origin before
 (owner : Work.owner_scope origin) (birth : Tasks.birth_result before) value tasks works,
 with_features (Selvedge.Features.State.with_task_owners
   (F.feature_task_owners (world_features value))
   (world_features (Work.own_birth owner birth value tasks works)))
   (Work.own_birth owner birth value tasks works) = value.
Proof.
 intros origin before owner birth [sequence tasks ticket environment projects features] TasksFrame WorksFrame.
 destruct features; reflexivity.
Qed.
Theorem witnessed_root_birth_records_its_work : forall origin before
 (owner : Work.owner_scope origin) (birth : Tasks.birth_result before) value tasks works,
 F.association (Tasks.birth_id birth) (F.feature_task_owners
   (world_features (Work.own_birth owner birth value tasks works))) = Some (Work.owner_identity owner).
Proof.
 intros; unfold Work.own_birth.
 change (F.association (Tasks.birth_id birth)
   ((Tasks.birth_id birth,Work.owner_identity owner)::F.feature_task_owners (world_features value)) = Some (Work.owner_identity owner)).
 unfold F.association; cbn; now rewrite N.eqb_refl.
Qed.
Theorem new_root_ownership_preserves_existing_roots : forall origin before
 (owner : Work.owner_scope origin) (birth : Tasks.birth_result before) value tasks works other,
 other <> Tasks.birth_id birth ->
 F.association other (F.feature_task_owners (world_features (Work.own_birth owner birth value tasks works))) =
 F.association other (F.feature_task_owners (world_features value)).
Proof.
 intros origin before owner birth value tasks works other Different; unfold Work.own_birth.
 change (F.association other ((Tasks.birth_id birth,Work.owner_identity owner)::F.feature_task_owners (world_features value)) =
   F.association other (F.feature_task_owners (world_features value))).
 unfold F.association; cbn. apply N.eqb_neq in Different; now rewrite Different.
Qed.

(** Explicit ownership wins; an unassociated fork inherits the closest
    explicitly owned ancestor, rather than assuming only roots have owners. *)
Theorem nearest_ancestor_owns_work : forall value child parent lineage owner,
 F.association child (F.feature_task_owners value)=None ->
 F.association parent (F.feature_task_owners value)=Some owner ->
 F.owner_id child (parent::lineage) value=Some owner.
Proof. intros. unfold F.owner_id. rewrite H. cbn [F.lineage_owner]. now rewrite H0. Qed.

(** An admitted exact-context patch changes the one Work-owned source and
    increments its revision. It cannot rewrite membership or Task execution. *)
Theorem admitted_patch_updates_shared_source : forall value id previous patch source,
 Work.lookup id value=Some previous ->
 N.ltb (F.work_ui_revision previous) 4294967295=true ->
 WorkUIPatch.apply (F.work_ui_source previous) patch=WorkUIPatch.Done source ->
 let updated:=decision_world (Work.patch_work id patch (F.work_ui_revision previous) value) in
 Work.lookup id updated=Some (F.Work (F.work_name previous) source (N.succ (F.work_ui_revision previous))) /\
 F.feature_task_owners (world_features updated)=F.feature_task_owners (world_features value) /\
 F.feature_graph_owners (world_features updated)=F.feature_graph_owners (world_features value) /\
 world_tasks updated=world_tasks value.
Proof.
 intros value id previous patch source found available applied.
 cbv zeta. unfold Work.patch_work. rewrite found,available,N.eqb_refl,applied.
 cbn [decision_world]. split.
 - unfold Work.lookup in *. change
   (registry_at id (replace id (F.Work (F.work_name previous) source
     (N.succ (F.work_ui_revision previous))) (F.feature_works (world_features value)))=
     Some (F.Work (F.work_name previous) source (N.succ (F.work_ui_revision previous)))).
   now apply registry_replace_selected with previous.
 - repeat split; reflexivity.
Qed.
