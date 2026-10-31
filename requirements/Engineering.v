From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Schema DeclarationRegistry.
From Selvedge.Foundation Require Focus ArgumentDeclarationProofs
  NumbersProofs BoundedIntegerCorrectness.
Import ListNotations.
Open Scope list_scope.

(** * Engineering goals and their construction

    A developer should be able to change one domain rule at its owner and use
    its public meaning without reading unrelated representations. Gallina owns
    the pure rules; extraction uses those same definitions. Host code supplies
    observations and interprets effects. A second handwritten implementation of
    a pure rule would introduce another choice to maintain.

    Public vocabulary remains available for constructing commands, describing
    results and stating requirements. Internal state is changed through the
    owning operations. Computation, proof automation and requirement explanation
    have distinct dependencies: ordinary production compilation cannot resolve
    [SelvedgeRequirements], while this source can use checked production
    contracts. [scripts/rocq-sources.mjs] supplies those load paths separately.
    Source discovery and assumption checking include new requirement modules
    without adding them to a registry. Runtime dependency fingerprints do not
    include consumers in this directory.

    Ordinary functions, indexed types and existing library theories provide the
    shared construction first. MetaRocq is used where the declared structure
    must generate code, such as command projections. It remains outside runtime
    computation. A new business combination inherits the shared guarantees;
    only its own additional behavior needs another proposition.

    Rocq checks the stated relation under its premises. Requirement review
    determines whether those premises and observations express the user's
    task. The build audits the assumptions of the selected proof closure;
    generated command source is checked by the same kernel. Standard extraction
    and js_of_ocaml remain trusted translations, including the exact-number and
    UTF-8 mappings. Public execution checks exercise those translations and
    physical effects where pure contracts cannot establish the observation.

    ** A local update retains the rest of the state

    A focus decomposes a value into a writable part and a retained remainder.
    Its interpreter reconstructs the result from both, so an arbitrary sequence
    of local operations cannot replace the remainder. The quantified laws below
    concern the actual shared interpreter, independently of a global state
    enumeration or of the number of operations later supplied. *)
Export Focus(modification_has_its_selected_value, modifications_compose,
  modifications_keep_the_frame).

(** ** Admission retains the established meaning

    An external value is admitted once into the declared constrained type;
    consumers use that value instead of serializing and parsing it again.
    Internal types do not admit external JSON on the caller's behalf. The common
    admission law connects the actual check to the declared condition. *)
Export ArgumentDeclarationProofs(admitted_value_retains_its_constraint).

(** Public bounded integer fields denote exact mathematical integers. Ordinary
    internal naturals remain unrestricted; JSON transport does not silently
    round them through JavaScript numbers. The separate bounded decoder is used
    only where the field's contract requires that bound. UTF-8 and physical
    byte interpretation are checked at their owning transport boundaries. *)
Export NumbersProofs(natural_print_parse).
Export BoundedIntegerCorrectness(decode_safe_integer_mathematical_iff).

(** * Local extension without repeated shared obligations

    A new declaration must remain reachable by its own name, while adding it
    must preserve every previous selection. This is stronger than saying that
    an old first-match lookup still succeeds: a silently shadowed new entry
    would satisfy that weaker statement.

    The subject here is the production [DeclarationRegistry.lookup], used by
    provider registration and public input routing. Its controlled registry
    already carries name uniqueness. Extension therefore uses the existing
    [declare] constructor and its automatically elaborated [DistinctNames]
    argument; an owner supplies local entries, not a new preservation proof.
    The carrier and naming function remain arbitrary. *)
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

(** The extension constructor itself rules out collisions among old and new
    entries. Both clauses below are inherited by any such extension, including
    additions whose type and contents were unknown when this theorem was
    checked. There is no global enumeration of extension owners. *)
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
