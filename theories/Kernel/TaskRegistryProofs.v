From Stdlib Require Import List NArith Sorting.Permutation Sorting.Sorted SetoidList.
From Selvedge.Foundation Require IndexedRegistry.
From Selvedge.Kernel Require Import Domain TaskRegistry.
Import ListNotations.
Open Scope N_scope.

Lemma address_identity address : key (N.pred (N.pos address)) = address.
Proof.
 assert (Same : N.pos (key (N.pred (N.pos address))) = N.pos address).
 { unfold key, IndexedRegistry.key. rewrite N.succ_pos_spec. apply N.succ_pred. discriminate. }
 now injection Same.
Qed.
Lemma identity_address id : N.pred (N.pos (key id)) = id.
Proof. unfold key, IndexedRegistry.key. now rewrite N.succ_pos_spec, N.pred_succ. Qed.

Theorem selected_entries_are_ordered scope :
 Sorted (fun left right => N.leb (fst left) (fst right) = true) (selected_entries scope).
Proof. apply Ordered.Sorted_sort. Qed.

Theorem selected_entry_matches_its_index id task scope :
 In (id,task) (selected_entries scope) <-> index_at id scope = Some task.
Proof.
 unfold selected_entries, index_at.
 split; intros Selected.
 - apply (Permutation_in (id,task) (Permutation_sym (Ordered.Permuted_sort _))) in Selected.
   apply in_map_iff in Selected as [[address current] [Same Member]].
   inversion Same; subst.
   change (Slots.find (key (N.pred (N.pos address))) scope = Some task).
   rewrite address_identity.
   apply Slots.find_1, Slots.elements_2, InA_alt.
   exists (address,task); split; [split;reflexivity|exact Member].
 - apply (Permutation_in (id,task) (Ordered.Permuted_sort _)).
   apply in_map_iff. exists (key id,task); split; [now rewrite identity_address|].
   apply Slots.find_2, Slots.elements_1, InA_alt in Selected.
   destruct Selected as [[address current] [[Identity Same] Member]].
   change (key id = address) in Identity. cbn in Same.
   now subst.
Qed.

Theorem selected_scope_matches_the_task_rows accepts entries scope id task :
 agrees accepts entries scope ->
 In (id,task) (selected_entries scope) <->
 IndexedRegistry.lookup id entries = Some task /\ accepts task = true.
Proof.
 intros Agrees. rewrite selected_entry_matches_its_index, Agrees. unfold eligible.
 destruct (IndexedRegistry.lookup id entries) as [current|] eqn:Found; [|split;[discriminate|intros [Missing _]; discriminate]].
 destruct (accepts current) eqn:Accepts; split; intros Selected.
 - inversion Selected; subst. auto.
 - now destruct Selected as [Same _].
 - discriminate.
 - destruct Selected as [Same Enabled]. inversion Same; subst; congruence.
Qed.

Theorem title_scope_matches_the_unissued_task table id task :
 In (id, task) (selected_entries (title_requests table)) <->
 IndexedRegistry.lookup id (rows table) = Some task /\ title_candidate (issued_titles table) id task = true.
Proof.
 rewrite selected_entry_matches_its_index, title_requests_agree. unfold eligible.
 destruct (IndexedRegistry.lookup id (rows table)) as [current|]; [|intuition discriminate].
 destruct (title_candidate (issued_titles table) id current) eqn:Candidate; split.
 - intro Same. inversion Same; subst. auto.
 - now intros [Same _].
 - discriminate.
 - intros [Same Eligible]. inversion Same; subst. congruence.
Qed.
