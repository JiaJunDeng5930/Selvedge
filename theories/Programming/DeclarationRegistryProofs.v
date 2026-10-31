From Stdlib Require Import String List Bool.
From Selvedge.Programming Require Import Schema DeclarationRegistry.
Import ListNotations.
Open Scope list_scope.

Section Registrations.
Context {A : Type} (name : A -> string).

Lemma distinct_declarations_retrieve_their_member : forall entries entry,
 unique_names (map name entries) = true ->
 In entry entries ->
 find (fun candidate => String.eqb (name entry) (name candidate)) entries = Some entry.
Proof.
 intros entries; induction entries as [|first rest IH]; intros entry Unique Present.
 - contradiction.
 - cbn [map unique_names] in Unique.
   apply andb_true_iff in Unique; destruct Unique as [Absent Unique].
   cbn [find].
   destruct Present as [Same|Present].
   + subst entry; rewrite String.eqb_refl; reflexivity.
   + destruct (String.eqb (name entry) (name first)) eqn:Same.
     * apply String.eqb_eq in Same.
       apply negb_true_iff in Absent.
       assert (Listed : existsb (String.eqb (name first)) (map name rest) = true).
       { apply existsb_exists; exists (name entry); split.
         - apply in_map; exact Present.
         - apply String.eqb_eq; symmetry; exact Same. }
       congruence.
     * apply IH; assumption.
Qed.

Theorem every_registered_declaration_is_retrievable :
 forall (registered : @DeclarationRegistry.t A name) entry,
 In entry (DeclarationRegistry.values registered) ->
 DeclarationRegistry.lookup (name entry) registered = Some entry.
Proof.
 intros registered entry Present; unfold DeclarationRegistry.lookup.
 apply distinct_declarations_retrieve_their_member.
 - apply DeclarationRegistry.unique.
 - exact Present.
Qed.

Lemma lookup_selects_a_declared_name :
 forall (registered : @DeclarationRegistry.t A name) identity entry,
 DeclarationRegistry.lookup identity registered = Some entry ->
 In entry (DeclarationRegistry.values registered) /\ identity = name entry.
Proof.
 intros registered identity entry Selected; unfold DeclarationRegistry.lookup in Selected.
 apply find_some in Selected; destruct Selected as [Present Named].
 split; [exact Present|now apply String.eqb_eq in Named].
Qed.

Theorem registration_extension_keeps_old_and_reaches_new :
 forall (previous : @DeclarationRegistry.t A name) additions
   (distinct : DistinctNames (map name (DeclarationRegistry.values previous ++ additions))),
 let extended := @DeclarationRegistry.declare A name
   (DeclarationRegistry.values previous ++ additions) distinct in
 (forall identity entry,
   DeclarationRegistry.lookup identity previous = Some entry ->
   DeclarationRegistry.lookup identity extended = Some entry) /\
 (forall entry,
   In entry additions -> DeclarationRegistry.lookup (name entry) extended = Some entry).
Proof.
 intros previous additions distinct; cbv zeta; split.
 - intros identity entry Selected.
   destruct (lookup_selects_a_declared_name previous identity entry Selected) as [Present Named].
   rewrite Named; apply every_registered_declaration_is_retrievable.
   apply in_or_app; left; exact Present.
 - intros entry Present; apply every_registered_declaration_is_retrievable.
   apply in_or_app; right; exact Present.
Qed.
End Registrations.
