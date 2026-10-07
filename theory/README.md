# Existing theory, checked in Bend

`stdlib-certificates.json` contains the **original types and proof terms** quoted
from Rocq Stdlib 9.2.0, not project-written tactics with the same theorem names.
The bundle records the source files' SHA-256, tool versions, and its own content
digest. It supplies collection algebra, iteration and the six Boolean join laws.
`relation-certificates.json` adds original relational-closure definitions and
theorems, together with two explicitly labelled source theorem applications.
`rocq-maps.json` adds the original ExtLib 0.13.1 association-list definitions and
deletion proof, plus an explicit Boolean-relation instance and its premises.
All exported entities are closed under the global context: their source proofs
introduce no axioms. The applications are not described as upstream theorems;
they contain no project induction, proof search or tactics.
The natural-number eliminator is the original Corelib term, used to lift
one-step execution correspondence to every finite scheduler budget. The current
bundle records Corelib's Datatypes/Nat and Stdlib's List/PeanoNat/Bool fingerprints.

## Checked import inventory

This section is generated from all three bundles. `bun run check` rejects a stale
inventory; run `bun scripts/theory-index.mjs update` after changing the exports.

<!-- BEGIN CHECKED_THEORY_INVENTORY -->

33 quoted entities: 17 algebra/iteration, 8 relation, and 8 association-map entities. Relations include 6 upstream definitions/theorems and 2 explicit applications. The map bundle contains four upstream definitions/proofs plus one theorem application and its three reflection-premise definitions.

| Quoted entity | Checked Bend use |
| --- | --- |
| `Corelib.Init.Datatypes.list_ind` | `stdlib.list_ind` |
| `Stdlib.Lists.List.app_nil_r` | `stdlib.app_nil_r` |
| `Stdlib.Lists.List.app_assoc` | `stdlib.app_assoc` |
| `Stdlib.Lists.List.fold_left_app` | `stdlib.fold_left_app` |
| `Stdlib.Lists.List.map_app` | `stdlib.map_app` |
| `Stdlib.Lists.List.map_map` | `stdlib.map_map` |
| `Stdlib.Lists.List.map_id` | `stdlib.map_id` |
| `Corelib.Init.Datatypes.nat_ind` | `stdlib.nat_ind` |
| `Stdlib.Arith.PeanoNat.Nat.iter_swap_gen` | `stdlib.iter_swap_gen` |
| `Stdlib.Arith.PeanoNat.Nat.iter_add` | `stdlib.iter_add` |
| `Stdlib.Arith.PeanoNat.Nat.iter_ind` | `stdlib.iter_ind` |
| `Stdlib.Bool.Bool.orb_assoc` | `stdlib.orb_assoc` |
| `Stdlib.Bool.Bool.orb_comm` | `stdlib.orb_comm` |
| `Stdlib.Bool.Bool.orb_diag` | `stdlib.orb_diag` |
| `Stdlib.Bool.Bool.orb_false_l` | `stdlib.orb_false_l` |
| `Stdlib.Bool.Bool.orb_false_r` | `stdlib.orb_false_r` |
| `Stdlib.Bool.Bool.orb_true_r` | `stdlib.orb_true_r` |
| `Corelib.Relations.Relation_Definitions.relation` | Original dependency body specialized at its application |
| `Corelib.Relations.Relation_Definitions.inclusion` | Original dependency body specialized at its application |
| `Stdlib.Relations.Relation_Operators.clos_refl_trans_ind` | Original dependency body specialized at its application |
| `Stdlib.Relations.Operators_Properties.clos_refl_trans_ind_left` | Original dependency body specialized at its application |
| `Stdlib.Relations.Operators_Properties.clos_rt_is_preorder` | `relations.clos_rt_is_preorder` |
| `Stdlib.Relations.Operators_Properties.clos_rt_idempotent` | `relations.clos_rt_idempotent` |
| `ExportRelations.closure_map` | `relations.closure_map` |
| `ExportRelations.closure_invariant` | `relations.closure_invariant` |
| `ExtLib.Data.Map.FMapAList.alist_find` | `association-map.find` |
| `ExtLib.Data.Map.FMapAList.alist_remove` | `association-map.remove` (source filter specialization) |
| `Stdlib.Lists.List.filter` | `association-map.remove` (source filter specialization) |
| `ExtLib.Data.Map.FMapAList.remove_eq_alist` | `association-map.removal_absence` (original induction body) |
| `ExportMaps.removal_absence` | Checked Boolean-relation instance in `scripts/ExportMaps.v` |
| `ExportMaps.boolean_relation` | Checked Boolean-relation instance in `scripts/ExportMaps.v` |
| `ExportMaps.boolean_decision` | Checked Boolean-relation instance in `scripts/ExportMaps.v` |
| `ExportMaps.boolean_correct` | Checked Boolean-relation instance in `scripts/ExportMaps.v` |

<!-- END CHECKED_THEORY_INVENTORY -->

## Algebra and iteration bridge

`scripts/QuoteCertificate.v` provides shared syntax-only quotation.
`scripts/ExportStdlib.v` obtains the opaque proof bodies with MetaRocq 1.5.1+9.2.
`scripts/import-stdlib.mjs` translates that restricted term language to
`../bendlib/stdlib.bend`. It maps lists, append, left fold and equality to Bend Base,
specializes the imported eliminator when an affine capture cannot be a template,
and rejects unknown syntax/constants. It does **not** search for a replacement
proof. Bend checks the resulting certificates and their application interfaces.
Source `map` is represented by Base's right fold over duplicable lists: Base's
own `List.map` takes affine lists, so its name alone does not establish the
correspondence. Source `eq_ind_r` becomes the checker's equality rewrite rule,
not a fresh proof axiom. Existing map certificates are checked against this exact
representation; their use fixes recovery, task-view and branch-result batch laws.
The iterator correspondence is the exact zero/seed and successor/application
definition of Corelib `Nat.iter`. A delta-reduced iterator inside a source proof
is recognized only by this structural form, never by its name or target theorem.
Template arguments are reordered consistently because Bend requires them before
ordinary arguments. Unsupported eliminators and recursion fail closed.

Normal builds require only the pinned Bend compiler and Bun. Both `bun run check`
and `bun run build` check that the saved certificates reproduce the generated
file. To regenerate from installed Rocq/MetaRocq and inspect changes:

```sh
bun scripts/import-stdlib.mjs --refresh
bun scripts/import-relations.mjs --refresh
bun scripts/import-maps.mjs --refresh
bun scripts/theory-index.mjs update
bun run check
bun run test
git diff -- theory bendlib/stdlib.bend bendlib/relations.bend bendlib/association-map.bend
```

This is a deliberately small proof bridge, not a general Rocq-to-Bend compiler,
an automatic theorem search engine, or a claim that all Rocq libraries can be
imported. The translator, exporter, digest and source label are not proof oracles:
the application-specific proposition must still type-check in Bend. Its kernel,
termination check and compilation/runtime remain trusted. Negative tests corrupt
an imported proof and mutate the actual command interpreter to check these gates.

Consumers instantiate the existing List, Bool and Nat theorems directly.
`../harness/CONTRACT.bend` binds the domain interpretations and theorem premises
to actual queues, histories, effects and replay beneath `../CONCEPTS.bend`. There is
no second general `Semigroup`, `Refinement`, `InvariantSystem`, `Dynamics` or
`Simulation` hierarchy. Original iterator theorems supply finite simulation, run
partition and invariant lifting. The project proves only representation and
single-step correspondence, required premises, and genuinely domain-specific
facts such as context projection and cancellation. In particular,
decision combination is a **semigroup**, not a monoid: the first reply and final
world have different owners. Its associativity reduces to the imported effect-list
theorem after destructuring the three decisions.

When the checker distinguishes a named run wrapper from its underlying iterator,
the imported theorem is applied pointwise to the actual function. No function
extensionality axiom is introduced. Both proof terms and their application to the
production functions must check. A shared pure-proof gate rejects foreign/unsafe
dependencies and unexpected compiler reports, including on cached builds.

## Relational protocol bridge

`scripts/ExportRelations.v` quotes the relation/inclusion definitions and existing
closure proofs. `scripts/import-relations.mjs` emits `../bendlib/relations.bend`.
Their production correspondence is required by `CONCEPTS.Composition.protocol`,
not an optional example. Builds check every bundle even with a cached kernel.

| Standard structure | Existing evidence | Production correspondence and use |
| --- | --- | --- |
| Input-labelled transition system and reachability preorder | `clos_rt_is_preorder` | `reachability.Edge` carries a real input, source state and endpoint equations against `PROGRAM.transition`. |
| Macro-step refinement and composable protocol batches | `clos_rt_idempotent` | A path of complete protocol paths flattens to one ordinary path with the same endpoints. Grouping changes; input order does not. |
| Forward simulation, allowing zero or many target steps | Explicit `clos_refl_trans_ind` application (`closure_map`) | `proofs/reachability.simulation` supplies only the production-to-independent-specification one-step square. The imported proof lifts it to arbitrary paths. |
| Safety under arbitrary finite input interleavings | Explicit `clos_refl_trans_ind_left` application (`closure_invariant`) | The application supplies `transition_preserves_world`; the existing theorem supplies path-wide safety. |

The relational carrier contains the world **and complete decisions**. Its journal
correspondence is checked against `Traces.actual`, including replies, ordered
effects and prior receipts, and against production `PROGRAM.replay`. It is not an
unrelated graph with a suggestive name. Edges admit any external input, including
model/tool/hook completions, instead of fixing one input tape in advance.

The bridge maps the three closure constructors to `Step`, `Refl` and `Trans`.
A reflexive endpoint uses an equality witness. Endpoints and intermediate states
are erased indices; step evidence separately retains the concrete source/input
needed for live proof premises. There is no constructor certifying arbitrary
unrelated endpoints.

Rocq's generic induction term may use a path both as an assumption and recursively.
Bend cannot duplicate arbitrary `Type` evidence. The translator specializes the
**original** eliminator at the explicit application, dropping only arguments that
application does not use. Every original branch and recursive call is retained;
no replacement induction is synthesized. Captured recursion arguments must be
alpha-equivalent. A changing unused prefix-witness domain is irrelevant only when
the binder really is unused; used arguments and branch bodies still must agree.
Unsupported syntax, constructors, eliminators and changed recursion fail closed.
The full generic Rocq eliminator is not claimed to have an affine Bend interface.

Domain-specific correspondence remains the project's obligation: exact command
meaning, one-step safety, authorization ownership, context projection and concrete
association-map representation. The bridge supports a declared source subset,
not all Rocq libraries or automatic theorem discovery. Reachability does not
establish external-effect commutation, fairness, liveness or process termination.
Tests break both imported evidence and type-correct production correspondence,
including deleting old receipts from an otherwise safe run.

Source: https://github.com/rocq-prover/stdlib and Rocq Corelib, copyright INRIA,
CNRS and contributors. The quoted terms and their generated translation retain
the upstream LGPL-2.1 notice; see `LICENSE` in this directory. The original raw
terms, exporter, deterministic translator, and generated editable source are
included rather than distributing an opaque binary proof dependency.
