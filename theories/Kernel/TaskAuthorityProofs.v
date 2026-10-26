From Stdlib Require Import List Bool NArith Lia.
From Selvedge.Foundation Require Import Registry RegistryProofs.
From Selvedge.Kernel Require Import Domain State CommitAdmission.
Import ListNotations.

(* The registry walker has one indexed semantics. Business proofs provide the
   retained-task relation; they do not repeat positional list induction. *)
Lemma retained_task_registries_follow_lookups :
 forall source raw before old_features next_features old next first,
 (forall offset current, registry_at offset old = Some current ->
   exists retained, registry_at offset next = Some retained /\
   CommitAdmission.retained_task source raw before (first+offset)%N
     old_features next_features current retained = true) ->
 CommitAdmission.retained_tasks_from source raw before first old_features next_features old next = true.
Proof.
 intros source raw before old_features next_features old; induction old as [|current rest IH];
   intros next first Retained; [reflexivity|].
 destruct (Retained 0%N current eq_refl) as [retained [Found Head]].
 destruct next as [|next remaining]; [discriminate|].
 cbn [registry_at] in Found; inversion Found; subst retained.
 cbn [CommitAdmission.retained_tasks_from]; rewrite N.add_0_r in Head; rewrite Head; cbn [andb].
 apply IH; intros offset original Original.
 assert (Earlier : registry_at (N.succ offset) (current :: rest) = Some original)
   by (rewrite registry_lookup_after_head; exact Original).
 destruct (Retained (N.succ offset) original Earlier) as [after [Observed Authority]].
 exists after; split; [rewrite registry_lookup_after_head in Observed; exact Observed|].
 replace (N.succ first+offset)%N with (first+N.succ offset)%N by lia; exact Authority.
Qed.

Lemma retained_task_registries_follow_a_relation :
 forall relation source raw before old_features next_features old next first,
 (forall owner old next, relation old next ->
   CommitAdmission.retained_task source raw before owner old_features next_features old next = true) ->
 Forall2 relation old next ->
 CommitAdmission.retained_tasks_from source raw before first old_features next_features old next = true.
Proof.
 intros relation source raw before old_features next_features old next first Authority Related; revert first.
 induction Related; intros; [reflexivity|].
 cbn [CommitAdmission.retained_tasks_from]; rewrite Authority by exact H; rewrite IHRelated; reflexivity.
Qed.

Lemma appending_tasks_keeps_retained_registry_authority :
 forall source raw before first old_features next_features old next suffix,
 CommitAdmission.retained_tasks_from source raw before first old_features next_features old next = true ->
 CommitAdmission.retained_tasks_from source raw before first old_features next_features old (next ++ suffix) = true.
Proof.
 intros source raw before first old_features next_features old; revert first.
 induction old as [|current rest IH]; intros first next suffix Valid; [reflexivity|].
 destruct next as [|next remaining]; [discriminate|].
 cbn [CommitAdmission.retained_tasks_from app] in *.
 apply andb_true_iff in Valid as [Head Tail]; rewrite Head; cbn; apply IH; exact Tail.
Qed.

Lemma replacing_one_task_lifts_indexed_authority :
 forall source raw before first old_features next_features entries selected old next,
 (forall owner current,
   CommitAdmission.retained_task source raw before owner old_features next_features current current = true) ->
 registry_at selected entries = Some old ->
 CommitAdmission.retained_task source raw before (first+selected)%N old_features next_features old next = true ->
 CommitAdmission.retained_tasks_from source raw before first old_features next_features
   entries (replace selected next entries) = true.
Proof.
 intros source raw before first old_features next_features entries selected old next Reflexive Found Target.
 apply retained_task_registries_follow_lookups; intros offset current Original.
 destruct (N.eq_dec offset selected) as [Same|Different].
 - subst offset; rewrite Found in Original; inversion Original; subst current.
   exists next; split; [eapply registry_replace_selected; exact Found|exact Target].
 - exists current; split; [rewrite registry_replace_other by congruence; exact Original|apply Reflexive].
Qed.
