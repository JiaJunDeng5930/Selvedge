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

## Outstanding exploration questions

- Prove useful world invariants through arbitrary admitted transitions, beyond the
  currently proved local operations and replay algebra.
- Establish the host protocol behavior with actual HTTP, model, tool, and restart
  tests; keep this evidence distinct from mathematical proof.
- Measure replay cost and shared-history memory behavior on substantial task trees.
- Validate live model authentication and MCP interoperability separately from local
  deterministic fixtures. No live credentials or external model calls have been
  used by the baseline tests.
