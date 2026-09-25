# 0012: Theory-indexed whole-program composition

Status: accepted for the Bend branch.

## Reason

A collection of local equalities is not yet a compositional program object. A
generic invariant proof inside the project also does not meet the requirement
to reuse existing standard results. Finally, pure packet processing outside the
proof closure leaves a gap between the proved transition and its deployed entry.

## Decision

CONCEPTS declares four proof-carrying concepts: meaning, composition, recovery and
observation. Concrete type/function bindings live below this entry in architecture.
The complete trace is a discrete dynamical system whose receipts retain entire
decisions. Its simulation, partition and safety lifting instantiate original
Stdlib iterator certificates. The application proves the step correspondence and
the relation between its tape and the production fold-based journal.

The pure native packet interface has an independent specification. MAIN contains
only IO, while every pure runtime dependency belongs to the proof closure. Local
proof providers form an explicit acyclic dependency graph by semantic boundary;
PROOF assembles the conceptual program only after these obligations are filled.

Both normal checking and cached builds use a shared pure-proof gate. A compiler
success that reports foreign or unsafe dependencies is not proof success. The
native IO entry is checked separately and retains its explicit trust boundary.

## Evidence and limits

Mutation tests cover ignored inputs, lost receipts, wrong durability, no-op replay,
fabricated foreign theorem proofs and missing iterator steps. Mutants first pass
ordinary type checking at the same project root, then fail their required proof.

These results establish finite deterministic trace properties. They do not prove
network delivery, SQLite implementation correctness, remote model termination,
summary fidelity or arbitrary concurrent effect commutativity. Host ordering and
recovery contracts remain integration-tested external obligations.
