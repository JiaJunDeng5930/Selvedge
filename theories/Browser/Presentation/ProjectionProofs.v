From Stdlib Require Import List NArith.
From Stdlib Require FSets.FMapFacts Structures.OrderedTypeEx.
From Selvedge.Browser.Presentation Require Import Projection.
Import ListNotations.
Module Facts := FMapFacts.WFacts_fun OrderedTypeEx.N_as_OT TaskIdMap.

Fixpoint tree_task_ids(tree:task_tree):list N:=match tree with
|TaskTree entry children=>task_id entry::flat_map tree_task_ids children end.

Local Definition in_trees id trees := In id (flat_map tree_task_ids trees).
Local Definition waiting_for id (earlier:TaskIdMap.t unit) pending :=
 exists parent, TaskIdMap.In parent earlier /\ in_trees id (waiting_children parent pending).

Local Lemma in_cons_tree id entry children trees :
 in_trees id (TaskTree entry children::trees) <->
 task_id entry=id \/ in_trees id children \/ in_trees id trees.
Proof. unfold in_trees. cbn [flat_map tree_task_ids]. simpl. rewrite in_app_iff. tauto. Qed.

Local Lemma take_children id key earlier pending :
 waiting_for id (TaskIdMap.add key tt earlier) pending <->
 in_trees id (waiting_children key pending) \/ waiting_for id earlier (TaskIdMap.remove key pending).
Proof.
 unfold waiting_for, waiting_children. split.
 - intros [p [Seen Member]]. apply Facts.add_in_iff in Seen.
   destruct (N.eq_dec key p) as [->|Different]; [now left|right].
   exists p. rewrite Facts.remove_neq_o by exact Different. split; [destruct Seen; congruence|exact Member].
 - intros [Member|[p [Seen Member]]].
   + exists key. split; [apply Facts.add_in_iff; now left|exact Member].
   + destruct (N.eq_dec key p) as [->|Different].
     * rewrite Facts.remove_eq_o in Member by reflexivity. contradiction.
     * rewrite Facts.remove_neq_o in Member by exact Different.
       exists p. split; [apply Facts.add_in_iff; now right|exact Member].
Qed.

Local Lemma queue_child id parent earlier pending entry children :
 TaskIdMap.In parent earlier ->
 (waiting_for id earlier
   (TaskIdMap.add parent (TaskTree entry children :: waiting_children parent pending) pending) <->
  task_id entry=id \/ in_trees id children \/ waiting_for id earlier pending).
Proof.
 intros Seen. unfold waiting_for. split.
 - intros [p [Present Member]]. unfold waiting_children in Member.
   destruct (N.eq_dec parent p) as [->|Different].
   + rewrite Facts.add_eq_o in Member by reflexivity. apply in_cons_tree in Member.
     destruct Member as [Own|[Child|Rest]]; [now left|now right; left|right;right; exists p;auto].
   + rewrite Facts.add_neq_o in Member by exact Different. right;right;exists p;auto.
 - intros [Own|[Child|[p [Present Member]]]].
   + exists parent. split; [exact Seen|]. unfold waiting_children.
     rewrite Facts.add_eq_o by reflexivity. apply in_cons_tree. now left.
   + exists parent. split; [exact Seen|]. unfold waiting_children.
     rewrite Facts.add_eq_o by reflexivity. apply in_cons_tree. now right;left.
   + exists p. split; [exact Present|]. unfold waiting_children.
     destruct (N.eq_dec parent p) as [->|Different].
     * rewrite Facts.add_eq_o by reflexivity. apply in_cons_tree. now right;right.
     * rewrite Facts.add_neq_o by exact Different. exact Member.
Qed.

Local Lemma assembled_tasks values earlier id :
 let '(roots,pending):=assemble_forest earlier values in
 in_trees id roots \/ waiting_for id earlier pending <-> In id (map task_id values).
Proof.
 revert earlier. induction values as [|entry rest IH]; intros earlier.
 - cbn [assemble_forest map]. split; [|contradiction].
   intros [Member|[p [_ Member]]]; [exact Member|].
   unfold waiting_children in Member. rewrite Facts.empty_o in Member. exact Member.
 - specialize (IH (TaskIdMap.add (task_id entry) tt earlier)).
   cbn [assemble_forest]. destruct (assemble_forest _ rest) as [roots pending].
   rewrite take_children in IH. simpl map. simpl In.
   destruct (task_parent entry) as [parent|]; [destruct (TaskIdMap.mem parent earlier) eqn:Seen|].
   + apply Facts.mem_in_iff in Seen. rewrite queue_child by exact Seen. tauto.
   + rewrite in_cons_tree. tauto.
   + rewrite in_cons_tree. tauto.
Qed.

(** Selecting a Work/project changes ancestry visibility, never task membership. *)
Theorem task_forest_retains_every_task values id:
 In id(flat_map tree_task_ids(forest values))<->In id(map task_id values).
Proof.
 unfold forest. destruct (existsb _ values).
 2: { induction values as [|entry rest IH]; [simpl;tauto|].
      cbn [map flat_map tree_task_ids]. simpl. tauto. }
 pose proof (assembled_tasks values (TaskIdMap.empty unit) id) as Members.
 destruct (assemble_forest _ values) as [roots pending]. cbn [fst].
 assert (~ waiting_for id (TaskIdMap.empty unit) pending).
 { intros [p [Seen _]]. now apply Facts.empty_in_iff in Seen. }
 change (in_trees id roots <-> In id (map task_id values)). tauto.
Qed.
