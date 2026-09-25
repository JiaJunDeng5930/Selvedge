# Existing theory, checked in Bend

`stdlib-certificates.json` contains the **original types and proof terms** quoted
from Rocq Stdlib 9.2.0, not project-written tactics with the same theorem names.
The bundle records the source files' SHA-256, tool versions, and its own content
digest. The included entities are `list_ind`, `List.app_nil_r`, `List.app_assoc`,
`List.fold_left_app`, `List.map_app`, `List.map_map`, `List.map_id`, and `nat_ind`.
The six algebra theorems are closed under the global
context: their source proofs introduce no axioms.
The natural-number eliminator is the original Corelib term, used to lift
one-step execution correspondence to every finite scheduler budget. The current
bundle records both Corelib's Datatypes and Stdlib's List source fingerprints.

`scripts/ExportStdlib.v` obtains the opaque proof bodies with MetaRocq 1.5.1+9.2.
`scripts/import-stdlib.mjs` translates that restricted term language to
`bendlib/stdlib.bend`. It maps lists, append, left fold and equality to Bend Base,
specializes the imported eliminator when an affine capture cannot be a template,
and rejects unknown syntax/constants. It does **not** search for a replacement
proof. Bend checks the resulting certificates and their application interfaces.
Source `map` is represented by Base's right fold over duplicable lists: Base's
own `List.map` takes affine lists, so its name alone does not establish the
correspondence. Source `eq_ind_r` becomes the checker's equality rewrite rule,
not a fresh proof axiom. Existing map certificates are checked against this exact
representation; their use fixes recovery, task-view and branch-result batch laws.

Normal builds require only the pinned Bend compiler and Node. Both `npm run check`
and `npm run build` check that the saved certificates reproduce the generated
file. To regenerate from installed Rocq/MetaRocq and inspect changes:

```sh
node scripts/import-stdlib.mjs --refresh
npm run check
git diff -- theory/stdlib-certificates.json bendlib/stdlib.bend
```

This is a deliberately small proof bridge, not a general Rocq-to-Bend compiler,
an automatic theorem search engine, or a claim that all Rocq libraries can be
imported. The translator, exporter, digest and source label are not proof oracles:
the application-specific proposition must still type-check in Bend. Its kernel,
termination check and compilation/runtime remain trusted. Negative tests corrupt
an imported proof and mutate the actual command interpreter to check these gates.

`bendlib/structures.bend` packages these results as monoids, right actions and
monoid homomorphisms. Map identity and composition also reuse the source proofs.
`CONCEPTS.bend` binds them to queues, histories, effects and actual replay. The
project proves only the correspondence, the one-step obligations, and genuinely
domain-specific facts such as context projection and cancellation. In particular,
decision combination is a **semigroup**, not a monoid: the first reply and final
world have different owners. Its associativity reduces to the imported effect-list
theorem after destructuring the three decisions.

Source: https://github.com/rocq-prover/stdlib and Rocq Corelib, copyright INRIA,
CNRS and contributors. The quoted terms and their generated translation retain
the upstream LGPL-2.1 notice; see `LICENSE` in this directory. The original raw
terms, exporter, deterministic translator, and generated editable source are
included rather than distributing an opaque binary proof dependency.
