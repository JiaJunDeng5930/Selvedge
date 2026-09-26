# 0016: Reuse existing relation proofs for the whole protocol

## Decision

Model protocol reachability as the existing reflexive-transitive closure of
input-labelled edges. Each edge retains a concrete input/source and equations
binding both endpoints to `PROGRAM.transition`. The carrier includes complete
decision receipts. `CONCEPTS.Composition.protocol` requires the relation evidence
and its correspondence to the production journal and finite receipt executor.

Quote original Rocq relation definitions and proof dependencies. Reuse the existing
closure preorder/idempotence theorems and explicit applications of its original
induction theorems for simulation and invariant lifting. Generated certificates
must pass the pure Bend proof gate. Normal builds need no Rocq installation.

## Reason

A proof-carrying structure with a standard name is insufficient when its useful
theorems are still re-proved locally. Iteration already had a genuine reuse chain;
relational reachability extends that chain to arbitrary external-input choices
and macro-step grouping. Selvedge proves only one-step obligations and executable
representation correspondence, not generic path safety or batching induction.

Rocq's reusable logical evidence and Bend's affine evidence have different
elimination interfaces. Translating an unrestricted eliminator literally would
require duplicating non-Data proofs. Specialize its original term at the explicit
application instead, retaining its cases/recursive calls and checking its captured
arguments. Erase endpoint indices so live recursion decreases on the path itself;
keep concrete source values inside edge evidence for live application premises.

## Consequences

Raw original terms, theorem applications, provenance and generated certificates
are reviewable. The inventory is generated from the bundles and checked, avoiding
the previous stale count. Negative tests must catch a changed path representation
or loss of actual receipts, not merely an ill-typed program.

This does not import every Rocq library, automate correspondence discovery or
prove host processes. It does not turn differently ordered external effects into
equivalent executions, or establish fairness or eventual completion. Those would
require separate standard theories and the appropriate application premises.
