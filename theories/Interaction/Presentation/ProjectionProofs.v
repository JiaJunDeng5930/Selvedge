From Stdlib Require Import List NArith.
From Selvedge.Interaction.Presentation Require Import Projection.
Import ListNotations.

Fixpoint tree_task_ids(tree:task_tree):list N:=match tree with
|TaskTree entry children=>task_id entry::flat_map tree_task_ids children end.

Lemma partition_preserves_task_membership predicate trees selected others id:
 partition predicate trees=(selected,others)->
 (In id(flat_map tree_task_ids trees)<->
  In id(flat_map tree_task_ids selected)\/In id(flat_map tree_task_ids others)).
Proof.
 intros Partition. repeat rewrite in_flat_map. split.
 - intros [tree [Present Member]].
   apply (proj1(@List.elements_in_partition task_tree predicate trees selected others Partition tree)) in Present.
   destruct Present as [Present|Present];[left|right];exists tree;auto.
 - intros [[tree [Present Member]]|[tree [Present Member]]];exists tree;split;auto;
   apply (proj2(@List.elements_in_partition task_tree predicate trees selected others Partition tree));auto.
Qed.

(** Selecting a Work/project changes ancestry visibility, never task membership. *)
Theorem task_forest_retains_every_task values id:
 In id(flat_map tree_task_ids(forest values))<->In id(map task_id values).
Proof.
 induction values as [|entry rest Retained];[simpl;tauto|].
 cbn [forest]. destruct(partition(fun tree=>same_id(Some(task_id entry))(task_parent(tree_entry tree)))(forest rest))as[children roots]eqn:Partition.
 pose proof(@partition_preserves_task_membership (fun tree=>same_id(Some(task_id entry))(task_parent(tree_entry tree)))(forest rest)children roots id Partition)as Members.
 cbn [flat_map tree_task_ids map]. rewrite in_app_iff. simpl in *;tauto.
Qed.
