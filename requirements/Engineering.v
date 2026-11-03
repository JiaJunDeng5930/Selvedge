From Selvedge.Programming Require Focus ArgumentDeclarationProofs
  DeclarationRegistryProofs.
From Selvedge.Foundation Require NumbersProofs BoundedIntegerCorrectness.

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

    A reported runtime workload must finish its scheduled transitions before
    replay is measured. The benchmark supplies deterministic external replies
    and follows the kernel's continuation requests; pending maintenance cannot
    stand for a completed workload. Its provenance identifies the published
    bundles, without describing intermediate compiler files as runtime inputs.

    Checking a selected proof closure must not depend on prerequisites used
    only to ship an executable. OCaml and JavaScript extraction tools and the
    JavaScript arithmetic runtime therefore cannot block a proof-only check.
    Command generation still needs its pinned MetaRocq dependency when that
    generator is part of the requested work.

    Shipped execution paths determine the build artifacts. The generated
    command declarations are checked with their production consumers; inspection
    can use those definitions or the public service entry. An installed plugin
    must run from its built package without the original checkout or compiler.
    Its model build produces the extracted runtime and packaging selects the
    shipped files. Source and compiler fingerprints control build-cache reuse;
    placing a second manifest beside the executable would provide no
    independent runtime authentication.

    ** Choose constructions that fit the domain

    [theories/Programming] owns the project's existing reusable languages,
    controlled constructors and composition operations, together with their
    shared laws. Their scope is part of their meaning: a construction may work
    over arbitrary types or intentionally describe this project's task state.
    Domain dependence alone is not a reason to invent a more general framework.

    Membership requires a construction that another program can use: identify
    what its caller supplies, which common operation interprets or combines it,
    and which properties follow through that interface. State the premises and
    scope of those properties, distinguishing guarantees enforced by types and
    definitions from the conclusions of checked theorems. Supporting vocabulary
    and proofs belong with that construction; they need not be separate paradigms.
    A reusable function, indexed plan or proof of a fixed business operation is
    not sufficient by itself. Keep a concrete catalogue, admission policy or
    business recipe with its domain, including when it uses a shared constructor.
    Split mixed modules at this boundary without inventing a more general model.

    Before reusing one, check that its concepts, admissible values, writable
    state and observations express the requirement. Reuse and compose it when
    they do. When they do not, keep a direct domain model or use another suitable
    construction. Do not reshape the domain, add artificial state or introduce
    special cases merely to use a preferred programming paradigm. The project
    need not describe every concern through the same language.

    Extract shared construction semantics that already have a real use. Keep
    concrete declarations, policies and fixed business transitions with their
    domain owners. An extension inherits the properties enforced by its chosen
    constructor and interpreter; only its additional required behavior needs a
    local proof. New concepts must not require a central enumeration of all
    domains or a repeated list of shared proof obligations. The source location
    makes these operations discoverable; it does not impose a new dependency
    layer on otherwise independent domain models.

    ** A local update retains the rest of the state

    A focus decomposes a value into a writable part and a retained remainder.
    Its interpreter reconstructs the result from both, so an arbitrary sequence
    of local operations cannot replace the remainder. The quantified laws below
    concern the actual shared interpreter, independently of a global state
    enumeration or of the number of operations later supplied. *)
Export Focus(modification_has_its_selected_value, modifications_compose,
  modifications_keep_the_frame).

(** ** Issued identities remain fresh

    A late reply must not acquire authority over a later invocation. The actual
    allocator selects the next identity advertised by its space and advances
    that supply past the issued value. Freshness does not require consecutive
    numbering; unused identities add no correlation guarantee. Manual fork
    receipts share this ticket space with asynchronous operations, so the same
    allocator must establish freshness for both issuers. *)
From Selvedge.Kernel Require StateProofs.
Export StateProofs(identity_allocation_advances_its_supply).

(** ** Admission retains the established meaning

    An external value is admitted once into the declared constrained type;
    consumers use that value instead of serializing and parsing it again.
    Internal types do not admit external JSON on the caller's behalf. The common
    admission law connects the actual check to the declared condition.

    Schema declarations originate in code; protocol and input-route constructors
    establish field-name uniqueness. Rechecking those declarations on every
    decode adds no external-input guarantee. Incoming object keys still require
    duplicate-name and declared-field admission. *)
Export ArgumentDeclarationProofs(admitted_value_retains_its_constraint).

(** Public integer declarations admit exact mathematical values, including
    decimal and exponent forms. Each bounded field supplies its own numerical
    range; JSON transport must not silently round through JavaScript numbers.
    The shared decimal conversion constrains its exponent before expanding it,
    so a short external number cannot request astronomical allocation.

    Ordinary internal naturals and canonical integer input remain unrestricted.
    For unbounded fields, noncanonical exponent expansion has a deliberate
    4096-digit-or-input-length budget. Representing still larger exponent forms
    without expansion would add a second number model for no current user need.
    Such inputs are rejected; they are never rounded or reported as admitted.
    UTF-8 and physical byte interpretation belong to their transport boundaries. *)
Export NumbersProofs(natural_print_parse).
Export BoundedIntegerCorrectness(decode_integer_mathematical_iff,
  decode_safe_integer_mathematical_iff, decode_natural_mathematical_iff,
  unbounded_natural_print_parse).

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
(** The extension constructor itself rules out collisions among old and new
    entries. Both clauses below are inherited by any such extension, including
    additions whose type and contents were unknown when this theorem was
    checked. There is no global enumeration of extension owners. *)
Export DeclarationRegistryProofs(every_registered_declaration_is_retrievable,
  registration_extension_keeps_old_and_reaches_new).
