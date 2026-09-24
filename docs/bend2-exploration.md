# Bend 2 migration: exploration record

This record collects findings from implementing the executable model. The current
requirements themselves live in `LAWS.bend`, the domain in `MODEL.bend`, and the
executed transition in `PROGRAM.bend`. Dates describe observations on this branch,
not claims about all Bend versions.

## 2026-09-24: establish the existing implementation

The starting worktree already contained a native Bend kernel, a Node host, and
twelve passing kernel/journal tests. Bend 2.0.27 checked `PROOF.bend` and compiled
`MAIN.bend`. This established an executable baseline, not full service validation:
there were no tests yet for the HTTP, provider, process, or MCP integrations.

### A theorem needs the same program entity as the running implementation

The replay composition law instantiates a generic transition-system theorem with
`PROGRAM.next`. History and queue laws instantiate the list monoid laws with the
actual append operation. This is stronger than proving properties of an independent
model and testing that an implementation resembles it. The remaining trust boundary
includes Bend's checker, native compiler, runtime, C token transport, and host.

Several existing laws deliberately name local operations: preserving a contract
when changing a phase, refusing an archived task's input, or rejecting a stale
result before scheduling. They are not yet global invariants of every reachable
world. The scope of each theorem must remain visible in its statement; counting
proved helpers cannot establish a whole-program preservation theorem.

### Termination describes a transition, not the life of a service

The checked program consumes explicit scheduling and rendering budgets. Remaining
work becomes a `ContinueScheduling` effect. The external stdin loop in `MAIN.bend`
uses unchecked recursion and constructs no proof. This provides a useful place to
separate a total mathematical operation from an indefinitely available service;
it does not prove fairness or eventual completion of a task.

### Output admission belongs inside the modeled transition

The host cannot roll back a pure kernel that has already advanced after discovering
that its output cannot be transported. `PROGRAM.deliver` checks the complete output
before admitting the new world or effects. Its rejection laws refer to that actual
admission function. Serialization and transport bounds are consequently part of
the transition's meaning, rather than a host-only optimization.

### External effects require an explicit knowledge state

A journal proves neither that an external command ran nor that it did not run
before a crash. Recovery distinguishes retry-safe internal operations from unknown
external outcomes. The existing SQLite tests exercise commit failure and replay;
the pure recovery laws only constrain the decisions made after that observation.

### Reproducible entry points matter to the experiment

`npm run check` now checks host syntax and all imported proof obligations, including
when a compiled kernel is cached. `npm test` builds the native kernel and runs the
integration suite. The root README points readers to the three executable entry
files rather than presenting the earlier Rust runtime as the experiment's entry.

## 2026-09-24: make observation a program entity

The initial implementation represented read, list, and describe as ordinary
commands. Persistence and scheduling each enumerated them, and read-only proofs
followed the error branches of individual query implementations. This duplicated
the conceptual claim that these commands merely observe the world.

`MODEL.Query` now represents that concept. Its interpreter returns only JSON;
it cannot return a new world or dispatchable effects. `InputMode` supplies the
shared classification used by persistence and scheduling. A tool that reads a
task reuses the same interpreter, but its result is still a durable history event.
Identical data access does not imply identical operational meaning.

The checked laws now quantify over every query and every world, including failed
queries and output admission failures. They establish unchanged world, no effects,
and no durable journal input. A generic transition-system theorem proves that
inserting an identity step anywhere in a trace preserves the final state. The
domain proof instantiates it with `PROGRAM.next` and the query preservation law.
This is a concrete use of stuttering in transition systems. It does not claim that
the observed reply stream is unchanged, or that scheduler fairness is proved.

This refactoring reduces proof dependence on query implementation details: a new
query case inherits the observation laws through the result type and wrapper.
The domain fact and reusable induction are separate, so the generic proof never
unfolds the entire server or serializer.

Bend 2.0.27 requires a match scrutinee to be a parameter or field; matching a
computed classification needs a helper definition. This affects how the executable
model is factored, rather than the classification itself. The installed guide's
explicit equality motives also proved useful for keeping generic replay induction
independent of the concrete task transition.

## Outstanding exploration questions

- Prove useful world invariants through arbitrary admitted transitions, beyond the
  currently proved local operations and replay algebra.
- Establish the host protocol behavior with actual HTTP, model, tool, and restart
  tests; keep this evidence distinct from mathematical proof.
- Measure replay cost and shared-history memory behavior on substantial task trees.
- Validate live model authentication and MCP interoperability separately from local
  deterministic fixtures. No live credentials or external model calls have been
  used by the baseline tests.
