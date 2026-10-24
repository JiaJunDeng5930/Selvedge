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

Lemma registry_replace_preserves_another_index : forall (A : Type) (values : list A) selected other replacement,
 selected <> other ->
 registry_at other (replace selected replacement values) = registry_at other values.
Proof.
 intros A values; induction values as [|first rest IH]; intros selected other replacement Different; cbn.
 - reflexivity.
 - destruct (N.eqb selected 0) eqn:Selected; destruct (N.eqb other 0) eqn:Other.
   + apply N.eqb_eq in Selected; apply N.eqb_eq in Other; congruence.
   + cbn; rewrite Other; reflexivity.
   + cbn; rewrite Other; reflexivity.
   + cbn; rewrite Other; apply IH.
     apply N.eqb_neq in Selected; apply N.eqb_neq in Other; lia.
Qed.

Lemma registry_append_selects_new_work : forall (A : Type) (values : list A) replacement,
 registry_at (N.of_nat (List.length values)) (values ++ [replacement]) = Some replacement.
Proof.
 intros A values; induction values as [|first rest IH]; intros replacement; cbn [List.length List.app].
 - reflexivity.
 - rewrite Nat2N.inj_succ.
   assert (Nonzero : N.eqb (N.succ (N.of_nat (List.length rest))) 0 = false)
     by (apply N.eqb_neq; lia).
   change ((if N.eqb (N.succ (N.of_nat (List.length rest))) 0 then Some first else
     registry_at (N.pred (N.succ (N.of_nat (List.length rest)))) (rest ++ [replacement])) = Some replacement).
   rewrite Nonzero, N.pred_succ; apply IH.
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
 - unfold Work.lookup; cbn; apply registry_append_selects_new_work.
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
 unfold Work.lookup; cbn; now apply registry_replace_preserves_another_index.
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
 unfold Work.lookup; cbn; now apply registry_replace_preserves_another_index.
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
Theorem failed_owned_birth_rolls_back : forall owner original created,
 bool_field "ok"%string (decision_reply created) <> Some true ->
 decision_world (Work.own_created owner original created) = original /\
 decision_effects (Work.own_created owner original created) = [].
Proof.
 intros owner original created failed. unfold Work.own_created.
 destruct (bool_field "ok"%string (decision_reply created)) as [[|]|]; try (split;reflexivity).
 contradiction.
Qed.

Theorem accepted_root_creation_records_its_work : forall owner original created,
 bool_field "ok"%string (decision_reply created) = Some true ->
 F.association (next_task original)
   (F.feature_task_owners (world_features (decision_world (Work.own_created owner original created)))) = Some owner.
Proof.
 intros owner original created Accepted; unfold Work.own_created; rewrite Accepted.
 change (F.association (next_task original)
   ((next_task original,owner)::F.feature_task_owners (world_features (decision_world created))) = Some owner).
 change (option_map (@snd N N)
   (if N.eqb (next_task original) (next_task original) then Some (next_task original,owner)
    else find (fun entry => N.eqb (next_task original) (fst entry))
      (F.feature_task_owners (world_features (decision_world created)))) = Some owner).
 now rewrite N.eqb_refl.
Qed.

Theorem new_root_ownership_preserves_existing_roots : forall owner original created other,
 bool_field "ok"%string (decision_reply created) = Some true ->
 other <> next_task original ->
 F.association other
   (F.feature_task_owners (world_features (decision_world (Work.own_created owner original created)))) =
 F.association other (F.feature_task_owners (world_features (decision_world created))).
Proof.
 intros owner original created other Accepted Different; unfold Work.own_created; rewrite Accepted.
 change (F.association other
   ((next_task original,owner)::F.feature_task_owners (world_features (decision_world created))) =
   F.association other (F.feature_task_owners (world_features (decision_world created)))).
 change (option_map (@snd N N)
   (if N.eqb other (next_task original) then Some (next_task original,owner)
    else find (fun entry => N.eqb other (fst entry))
      (F.feature_task_owners (world_features (decision_world created)))) =
   option_map (@snd N N) (find (fun entry => N.eqb other (fst entry))
      (F.feature_task_owners (world_features (decision_world created))))).
 apply N.eqb_neq in Different; now rewrite Different.
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
