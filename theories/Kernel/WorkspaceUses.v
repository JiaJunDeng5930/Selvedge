From Stdlib Require Import String Ascii List NArith Bool.
From Selvedge.Foundation Require DependencyIndex IndexedRegistry IndexedRegistryProofs KeyedScope.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain.
Import ListNotations.
Open Scope string_scope.

Definition t := DependencyIndex.t N.
Definition empty : t := IndexedRegistry.Slots.empty _.
Definition resource_key owner := xO (IndexedRegistry.key owner).
Definition project_key project := xI (xI (IndexedRegistry.key project)).
Definition directory_key machine root :=
 xI (xO (DependencyIndex.text_address ((match machine with None => "0" | Some name => "1" ++ name end) ++
   String (ascii_of_nat 0) root))).
Fixpoint enclosing_directories (prefix path : string) :=
 match path with
 | EmptyString => [prefix]
 | String character rest =>
   let next := enclosing_directories (prefix ++ String character EmptyString) rest in
   if Ascii.eqb character "/"%char
   then prefix :: next
   else next
 end.
Definition addresses (space : workspace) resource :=
 let machine := workspace_environment space in
 let directories := flat_map (enclosing_directories EmptyString) (workspace_roots space) in
 match resource with
 | None => map (directory_key machine) directories
 | Some owner => resource_key owner :: map (directory_key machine) directories
 end.
Definition update := KeyedScope.reselect.

Definition resource_users owner (current : t) := DependencyIndex.members (resource_key owner) current.
Definition directory_users machine root (current : t) := DependencyIndex.members (directory_key machine root) current.
Definition project_tasks project (current : t) := DependencyIndex.members (project_key project) current.
Definition task_addresses (current : task) :=
 let resource_uses := if task_archived current then [] else
   let settings := contract_settings (task_contract current) in
   addresses (settings_workspace settings) (settings_resource settings) in
 match settings_project (task_current_settings current) with
 | Some project => project_key project :: resource_uses | None => resource_uses end.
Definition same_project (left right : task) :=
 match settings_project (task_current_settings left), settings_project (task_current_settings right) with
 | Some l, Some r => N.eqb l r | None, None => true | _, _ => false end.
Definition replace_task id previous current uses :=
 match previous with
 | Some old =>
   if same_project old current && Bool.eqb (task_archived old) (task_archived current) &&
      shared_value (task_contract old) (task_contract current)
   then uses
   else update true id (task_addresses current) (update false id (task_addresses old) uses)
 | None => update true id (task_addresses current) uses
 end.

Definition lookup_after_update := KeyedScope.lookup_reselect.

Local Lemma append_empty value : value ++ "" = value.
Proof. induction value; cbn; [reflexivity|now rewrite IHvalue]. Qed.
Local Lemma append_assoc first second third : (first ++ second) ++ third = first ++ (second ++ third).
Proof. induction first; cbn; [reflexivity|now rewrite IHfirst]. Qed.
Local Lemma containing_directory_exact path prefix :
 In (prefix ++ path) (enclosing_directories prefix path).
Proof.
 revert prefix. induction path as [|character rest IH]; intro prefix.
 - rewrite append_empty. now left.
 - cbn [enclosing_directories].
   specialize (IH (prefix ++ String character EmptyString)).
   rewrite append_assoc in IH.
   change (In (prefix ++ String character rest) (enclosing_directories (prefix ++ String character "") rest)) in IH.
   destruct (Ascii.eqb character "/"%char); cbn [In]; auto.
Qed.
Local Lemma containing_directory_at_separator root tail prefix :
 In (prefix ++ root) (enclosing_directories prefix ((root ++ "/") ++ tail)).
Proof.
 revert prefix. induction root as [|character rest IH]; intro prefix.
 - rewrite append_empty. now left.
 - cbn [String.append enclosing_directories].
   specialize (IH (prefix ++ String character EmptyString)).
   rewrite append_assoc in IH.
   change (In (prefix ++ String character rest)
     (enclosing_directories (prefix ++ String character "") ((rest ++ "/") ++ tail))) in IH.
   destruct (Ascii.eqb character "/"%char); cbn [In]; auto.
Qed.
Local Lemma prefix_has_suffix candidate path :
 String.prefix candidate path = true -> exists rest, path = candidate ++ rest.
Proof.
 revert path. induction candidate as [|head rest IH]; intros path Prefix; [now exists path|].
 destruct path as [|next tail]; [discriminate|].
 cbn [String.prefix] in Prefix. destruct (Ascii.ascii_dec head next) as [->|]; [|discriminate].
 destruct (IH tail Prefix) as [suffix ->]. now exists suffix.
Qed.
Lemma directory_address_selected space resource root :
 existsb (fun path => String.eqb root path || String.prefix (root ++ "/") path) (workspace_roots space) = true ->
 In (directory_key (workspace_environment space) root) (addresses space resource).
Proof.
 intro Found. unfold addresses.
 assert (Present : In (directory_key (workspace_environment space) root)
     (map (directory_key (workspace_environment space)) (flat_map (enclosing_directories EmptyString) (workspace_roots space)))).
 { apply existsb_exists in Found. destruct Found as [path [Root Within]].
   apply in_map. apply in_flat_map. exists path. split; [exact Root|].
   apply Bool.orb_true_iff in Within as [Same|Prefix].
   - apply String.eqb_eq in Same. subst path. exact (containing_directory_exact root "").
   - destruct (prefix_has_suffix _ _ Prefix) as [suffix ->].
     exact (containing_directory_at_separator root suffix ""). }
 destruct resource; cbn [In]; auto.
Qed.

Definition agrees rows (uses : t) :=
 forall key id, DependencyIndex.lookup key id uses =
 match IndexedRegistry.lookup id rows with
 | Some task => if existsb (Pos.eqb key) (task_addresses task) then Some id else None
 | None => None
 end.
Lemma empty_agrees : agrees IndexedRegistry.empty empty.
Proof.
 intros key id. unfold DependencyIndex.lookup, IndexedRegistry.lookup, empty.
 cbn [IndexedRegistry.empty IndexedRegistry.entries].
 now rewrite !IndexedRegistry.Slots.gempty.
Qed.
Lemma append_agrees rows uses task : agrees rows uses ->
 agrees (IndexedRegistry.append task rows)
   (update true (IndexedRegistry.next rows) (task_addresses task) uses).
Proof.
 intros Consistent key id. rewrite lookup_after_update.
 destruct (N.eqb_spec id (IndexedRegistry.next rows)) as [->|Different].
 - rewrite IndexedRegistryProofs.lookup_append_new, Consistent.
   destruct (existsb (Pos.eqb key) (task_addresses task)); [reflexivity|].
   destruct (IndexedRegistry.lookup (IndexedRegistry.next rows) rows) as [previous|] eqn:Found; [|reflexivity].
   exfalso. apply (N.lt_irrefl (IndexedRegistry.next rows)).
   apply (IndexedRegistry.filled rows (IndexedRegistry.next rows)). now exists previous.
 - rewrite IndexedRegistryProofs.lookup_append_before by congruence.
   now rewrite Bool.andb_false_r, Consistent.
Qed.
Lemma replace_agrees rows uses id task : agrees rows uses ->
 (id < IndexedRegistry.next rows)%N ->
 agrees (IndexedRegistry.put id task rows)
   (replace_task id (IndexedRegistry.lookup id rows) task uses).
Proof.
 intros Consistent Present key reader.
 unfold replace_task. destruct (IndexedRegistry.lookup id rows) as [old|] eqn:Found.
 - unfold shared_value. repeat rewrite Bool.andb_false_r.
   repeat rewrite lookup_after_update.
   destruct (N.eqb_spec reader id) as [->|Different].
   + rewrite IndexedRegistryProofs.lookup_put_present by exact Present.
     rewrite !Bool.andb_true_r, Consistent, Found.
     destruct (existsb (Pos.eqb key) (task_addresses task)),
       (existsb (Pos.eqb key) (task_addresses old)); reflexivity.
   + rewrite IndexedRegistryProofs.lookup_put_other by congruence.
     now rewrite !Bool.andb_false_r, Consistent.
 - exfalso. apply (IndexedRegistry.filled rows id) in Present.
   destruct Present as [value Existing]. unfold IndexedRegistry.lookup in Found. congruence.
Qed.
