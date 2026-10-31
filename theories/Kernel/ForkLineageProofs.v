From Stdlib Require Import List Bool NArith Lia.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State Tasks.
Import ListNotations.
Open Scope list_scope.

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
 intros ancestor left right Same; unfold Tasks.descendant_count.
 rewrite <- (length_map task_lineage (filter (fun task => existsb (N.eqb ancestor) (task_lineage task)) left)),
   <- (length_map task_lineage (filter (fun task => existsb (N.eqb ancestor) (task_lineage task)) right)).
 rewrite <- !filter_map_swap, Same; reflexivity.
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
 (Tasks.descendant_count ancestor (world_tasks before) <= contract_max_descendants (task_contract current))%N ->
 find_task ancestor before = Some current ->
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
 - lia.
Qed.
