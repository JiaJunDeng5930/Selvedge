From Stdlib Require Import String List Bool NArith PeanoNat Lia DecimalString DecimalN DecimalPos.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Kernel Require Import Numbers Domain State Tasks WorldInvariant.
Import ListNotations.

Lemma encoded_natural_is_injective : forall left right,
 number left = number right -> left = right.
Proof.
 intros left right Equal; unfold number, number_text, show_natural in Equal.
 injection Equal as Equal.
 assert (Nonempty : forall value, N.to_uint value <> Decimal.Nil).
 { intros [|value]; [discriminate|apply DecimalPos.Unsigned.to_uint_nonnil]. }
 apply DecimalN.Unsigned.to_uint_inj.
 apply (f_equal NilZero.uint_of_string) in Equal.
 rewrite !NilZero.usu in Equal by apply Nonempty; now injection Equal.
Qed.

Lemma matching_lineage_is_equal : forall left right,
 WorldInvariant.same_values number left right = true -> left = right.
Proof.
 intros left right Equal; apply JsonProofs.equal_reflects_equality in Equal.
 injection Equal as Equal; revert right Equal.
 induction left as [|first rest IH]; intros [|other tail] Equal; cbn in Equal; try discriminate.
 - reflexivity.
 - change (number first :: map number rest = number other :: map number tail) in Equal.
   injection Equal as Head Tail; f_equal.
   + apply encoded_natural_is_injective; unfold number; now rewrite Head.
   + apply IH; exact Tail.
Qed.

Lemma task_registry_requirement_at : forall entries first state offset value,
 WorldInvariant.tasks_valid first entries state = true ->
 registry_at offset entries = Some value ->
 WorldInvariant.task_valid (first + offset)%N value state = true.
Proof.
 induction entries as [|head tail IH]; intros first state offset value Valid Found; [discriminate|].
 cbn [WorldInvariant.tasks_valid] in Valid; apply andb_true_iff in Valid as [Head Tail].
 cbn [registry_at] in Found; destruct (N.eqb offset 0) eqn:Zero.
 - apply N.eqb_eq in Zero; subst offset; inversion Found; subst value.
   now rewrite N.add_0_r.
 - apply N.eqb_neq in Zero.
   specialize (IH (N.succ first) state (N.pred offset) value Tail Found).
   replace (N.succ first + N.pred offset)%N with (first + offset)%N in IH by lia.
   exact IH.
Qed.

Theorem lookup_task_requirements : forall before owner value,
 WorldInvariant.well_formed before -> find_task owner before = Some value ->
 WorldInvariant.task_valid owner value (WorldInvariant.world_structure before) = true.
Proof.
 intros before owner value Valid Found.
 pose proof (WorldInvariant.tasks_requirement before Valid) as Tasks.
 change (registry_at owner (world_tasks (WorldInvariant.world_structure before)) = Some value) in Found.
 exact (task_registry_requirement_at _ 0 _ owner value Tasks Found).
Qed.

Lemma task_valid_has_its_lineage_requirement : forall owner value state,
 WorldInvariant.task_valid owner value state = true ->
 WorldInvariant.lineage_valid owner value state = true.
Proof.
 intros owner value state Valid; unfold WorldInvariant.task_valid in Valid.
 repeat rewrite andb_true_iff in Valid; tauto.
Qed.

Theorem legal_lineage_references_precede_the_owner : forall before owner value,
 WorldInvariant.well_formed before -> find_task owner before = Some value ->
 Forall (fun ancestor => (ancestor < owner)%N) (task_lineage value).
Proof.
 intros before owner; induction owner as [owner IH] using (well_founded_induction N.lt_wf_0).
 intros value Valid Found.
 pose proof (task_valid_has_its_lineage_requirement _ _ _
   (lookup_task_requirements before owner value Valid Found)) as Lineage.
 unfold WorldInvariant.lineage_valid in Lineage.
 destruct (task_lineage value) as [|parent tail] eqn:Ancestors; [constructor|].
 destruct (find_task parent (WorldInvariant.world_structure before)) as [original|] eqn:Parent;
   [|discriminate].
 apply andb_true_iff in Lineage as [Lineage _].
 apply andb_true_iff in Lineage as [Earlier Same].
 apply N.ltb_lt in Earlier; apply matching_lineage_is_equal in Same; subst tail.
 constructor; [exact Earlier|].
 change (find_task parent before = Some original) in Parent.
 pose proof (IH parent Earlier original Valid Parent) as AncestorsEarlier.
 apply Forall_forall; intros ancestor Member.
 apply Forall_forall with (x := ancestor) in AncestorsEarlier; [lia|exact Member].
Qed.

Lemma registry_lookup_implies_position_bound : forall (A : Type) (entries : list A) owner value,
 registry_at owner entries = Some value -> (owner < N.of_nat (List.length entries))%N.
Proof.
 intros A entries; induction entries as [|head tail IH]; intros owner value Found; [discriminate|].
 cbn [registry_at] in Found; cbn [List.length]; rewrite Nat2N.inj_succ.
 destruct (N.eqb owner 0) eqn:Zero.
 - apply N.eqb_eq in Zero; subst; lia.
 - apply N.eqb_neq in Zero; specialize (IH _ _ Found); lia.
Qed.

Lemma descendant_count_app : forall ancestor left right,
 Tasks.descendant_count ancestor (left ++ right) =
 (Tasks.descendant_count ancestor left + Tasks.descendant_count ancestor right)%N.
Proof.
 intros; unfold Tasks.descendant_count; rewrite filter_app, length_app, Nat2N.inj_add; reflexivity.
Qed.

Lemma descendant_count_depends_only_on_lineages : forall ancestor left right,
 map task_lineage left = map task_lineage right ->
 Tasks.descendant_count ancestor left = Tasks.descendant_count ancestor right.
Proof.
 intros ancestor left right Same; unfold Tasks.descendant_count; f_equal.
 revert right Same; induction left as [|head tail IH]; intros [|other rest] Same;
   cbn in Same; try discriminate; [reflexivity|].
 injection Same as Head Tail; cbn [filter]; rewrite Head.
 destruct (existsb (N.eqb ancestor) (task_lineage other)); cbn [List.length];
   [f_equal|]; now apply IH.
Qed.

Lemma fixed_lineage_descendant_count : forall entries lineage ancestor,
 Forall (fun value => task_lineage value = lineage) entries ->
 Tasks.descendant_count ancestor entries =
 (if existsb (N.eqb ancestor) lineage then N.of_nat (List.length entries) else 0)%N.
Proof.
 intros entries lineage ancestor Fixed.
 assert (Length : List.length (filter (fun value => existsb (N.eqb ancestor) (task_lineage value)) entries) =
   if existsb (N.eqb ancestor) lineage then List.length entries else O).
 { induction Fixed as [|value rest Head Rest IH]; cbn [filter].
   - destruct (existsb (N.eqb ancestor) lineage); reflexivity.
   - rewrite Head; destruct (existsb (N.eqb ancestor) lineage) eqn:Contains; cbn in *;
       [now rewrite IH|exact IH]. }
 unfold Tasks.descendant_count; rewrite Length.
 destruct (existsb (N.eqb ancestor) lineage); reflexivity.
Qed.

Theorem fork_descendants_have_an_exact_increment : forall before retained children parent owner ancestor count,
 map task_lineage retained = map task_lineage (world_tasks before) ->
 Forall (fun child => task_lineage child = owner :: task_lineage parent) children ->
 List.length children = N.to_nat count ->
 Tasks.descendant_count ancestor (retained ++ children) =
 (Tasks.descendant_count ancestor (world_tasks before) +
   if existsb (N.eqb ancestor) (owner :: task_lineage parent) then count else 0)%N.
Proof.
 intros before retained children parent owner ancestor count Retained Children Count.
 rewrite descendant_count_app, (descendant_count_depends_only_on_lineages _ _ _ Retained),
   (fixed_lineage_descendant_count _ _ _ Children), Count, N2Nat.id; reflexivity.
Qed.

Lemma ancestors_fit_bounds_each_ancestor : forall before parents count ancestor current,
 Tasks.ancestors_fit parents count before = true -> In ancestor parents ->
 find_task ancestor before = Some current ->
 (count + Tasks.descendant_count ancestor (world_tasks before) <=
   contract_max_descendants (task_contract current))%N.
Proof.
 intros before parents count ancestor current Fits Member Found.
 unfold Tasks.ancestors_fit, TaskConstraints.fork_capacities_valid in Fits.
 rewrite forallb_forall in Fits.
 specialize (Fits (Tasks.ancestor_capacity before ancestor) (in_map _ _ _ Member)).
 unfold Tasks.ancestor_capacity in Fits; rewrite Found in Fits; now apply N.leb_le in Fits.
Qed.

Theorem fork_preserves_existing_descendant_capacity : forall before retained children parent owner count ancestor current,
 WorldInvariant.well_formed before -> find_task ancestor before = Some current ->
 map task_lineage retained = map task_lineage (world_tasks before) ->
 Forall (fun child => task_lineage child = owner :: task_lineage parent) children ->
 List.length children = N.to_nat count ->
 Tasks.ancestors_fit (owner :: task_lineage parent) count before = true ->
 (Tasks.descendant_count ancestor (retained ++ children) <=
   contract_max_descendants (task_contract current))%N.
Proof.
 intros before retained children parent owner count ancestor current Valid Found Retained Children Count Fits.
 rewrite (fork_descendants_have_an_exact_increment _ _ _ _ _ _ _ Retained Children Count).
 destruct (existsb (N.eqb ancestor) (owner :: task_lineage parent)) eqn:Contains.
 - apply existsb_exists in Contains as [selected [Member Same]].
   apply N.eqb_eq in Same; subst selected.
   pose proof (ancestors_fit_bounds_each_ancestor _ _ _ _ _ Fits Member Found); lia.
 - pose proof (lookup_task_requirements _ _ _ Valid Found) as Requirements.
   change (WorldInvariant.task_valid ancestor current before = true) in Requirements.
   unfold WorldInvariant.task_valid in Requirements.
   repeat rewrite andb_true_iff in Requirements.
   assert (Bound : N.leb (Tasks.descendant_count ancestor (world_tasks before))
     (contract_max_descendants (task_contract current)) = true) by tauto.
   apply N.leb_le in Bound; lia.
Qed.

Lemma a_registry_member_has_a_position : forall (A : Type) (entries : list A) value,
 In value entries -> exists owner, registry_at owner entries = Some value.
Proof.
 intros A entries; induction entries as [|head tail IH]; intros value Member; [contradiction|].
 destruct Member as [Same|Member].
 - subst; exists 0%N; reflexivity.
 - destruct (IH value Member) as [owner Found].
   exists (N.succ owner); cbn [registry_at].
   assert (Nonzero : N.eqb (N.succ owner) 0 = false) by (apply N.eqb_neq; lia).
   rewrite Nonzero, N.pred_succ; exact Found.
Qed.

Lemma legal_registry_lineages_precede_the_append_position : forall before,
 WorldInvariant.well_formed before ->
 Forall (fun value => Forall (fun ancestor => (ancestor < next_task before)%N)
   (task_lineage value)) (world_tasks before).
Proof.
 intros before Valid; apply Forall_forall; intros value Member.
 destruct (a_registry_member_has_a_position _ _ _ Member) as [owner Found].
 pose proof (registry_lookup_implies_position_bound _ _ _ _ Found) as Bound.
 pose proof (legal_lineage_references_precede_the_owner before owner value Valid Found) as Lineage.
 apply Forall_forall; intros ancestor InLineage.
 apply Forall_forall with (x := ancestor) in Lineage; [|exact InLineage].
 unfold next_task; lia.
Qed.

Lemma descendant_count_is_zero_above_all_lineages : forall values lower owner,
 Forall (fun value => Forall (fun ancestor => (ancestor < lower)%N)
   (task_lineage value)) values -> (lower <= owner)%N ->
 Tasks.descendant_count owner values = 0%N.
Proof.
 intros values lower owner Earlier Bound; induction Earlier as [|value rest Head Rest IH];
   unfold Tasks.descendant_count in *; cbn; [reflexivity|].
 assert (Absent : existsb (N.eqb owner) (task_lineage value) = false).
 { destruct (existsb (N.eqb owner) (task_lineage value)) eqn:Present; [|reflexivity].
   apply existsb_exists in Present as [ancestor [Member Same]].
   apply Forall_forall with (x := ancestor) in Head; [|exact Member].
   apply N.eqb_eq in Same; lia. }
 rewrite Absent; exact IH.
Qed.

Theorem fresh_fork_references_have_no_descendants : forall before retained children parent owner fresh,
 WorldInvariant.well_formed before -> find_task owner before = Some parent ->
 map task_lineage retained = map task_lineage (world_tasks before) ->
 Forall (fun child => task_lineage child = owner :: task_lineage parent) children ->
 (next_task before <= fresh)%N ->
 Tasks.descendant_count fresh (retained ++ children) = 0%N.
Proof.
 intros before retained children parent owner fresh Valid Found Retained Children Fresh.
 rewrite descendant_count_app, (descendant_count_depends_only_on_lineages _ _ _ Retained).
 rewrite (descendant_count_is_zero_above_all_lineages _ _ _
   (legal_registry_lineages_precede_the_append_position before Valid) Fresh), N.add_0_l.
 apply descendant_count_is_zero_above_all_lineages with (lower := next_task before); [|exact Fresh].
 pose proof (registry_lookup_implies_position_bound _ _ _ _ Found) as Owner.
 pose proof (legal_lineage_references_precede_the_owner before owner parent Valid Found) as Ancestors.
 apply Forall_forall; intros child Member.
 apply Forall_forall with (x := child) in Children; [|exact Member].
 rewrite Children.
 constructor; [exact Owner|].
 apply Forall_forall; intros ancestor InLineage.
 apply Forall_forall with (x := ancestor) in Ancestors; [|exact InLineage].
 unfold next_task; lia.
Qed.

Theorem a_fork_child_has_its_parent_lineage_requirement : forall after parent_id parent current child_id child,
 find_task parent_id after = Some current ->
 task_lineage current = task_lineage parent -> task_contract current = task_contract parent ->
 (parent_id < child_id)%N -> task_lineage child = parent_id :: task_lineage parent ->
 contract_tools (task_contract child) = contract_tools (task_contract parent) ->
 contract_max_fork (task_contract child) = contract_max_fork (task_contract parent) ->
 contract_max_descendants (task_contract child) = contract_max_descendants (task_contract parent) ->
 contract_plugins (task_contract child) = contract_plugins (task_contract parent) ->
 WorldInvariant.lineage_valid child_id child after = true.
Proof.
 intros after parent_id parent current child_id child Found Lineage Contract Earlier Child Tools Fork Descendants Plugins.
 unfold WorldInvariant.lineage_valid; rewrite Child, Found, Lineage, Contract.
 unfold WorldInvariant.inherited_creation, WorldInvariant.same_values.
 rewrite Tools, Fork, Descendants, Plugins, !N.eqb_refl, !JsonProofs.equal_is_reflexive.
 apply N.ltb_lt in Earlier; rewrite Earlier; reflexivity.
Qed.
