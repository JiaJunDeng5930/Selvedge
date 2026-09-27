# Admit certified Bend transitions as the sole task runtime

## Decision

World and transition predicates are executable Bend definitions. The production
transition checks its completed candidate, including its external effects, before
output admission. A checked theorem establishes that the result either keeps the
previous world with no effects or satisfies both predicates. Generic transition
induction lifts this certificate to every finite trace from a valid initial world.

The native task implementation replaces the Rust workspace. Node and the narrow
C transport remain effect interpreters, with independent integration evidence.
Builds, developer actions, hooks, and CI use the pinned Bend compiler and native
tests. The prior runtime remains accessible through Git history.

## Reasons

Local operation lemmas alone did not connect the complete scheduler to a valid
task forest. An explicit admission certificate supplies that missing composition
boundary without a second interpreter or an independently maintained validator.
Its predicates are both the running decision procedure and the formal statement
of the admitted behavior.

Checking the completed decision matters because later internal commands can
withdraw earlier effect intents in the same commit. Such intents must not cross
the host boundary, even if an eventual cancellation could stop them.

The cost is a whole-candidate validation pass. We accept that measured cost for
this implementation instead of claiming an unproved incremental validator or
physical sharing optimization. Safety alone does not establish progress or
functional completeness; ordinary behavior tests and operation laws remain
necessary. The exploration record contains measurements and the proof-checking
tradeoffs encountered in this implementation.

Keeping a second executable Rust task model and its independent state-machine
documentation would defeat the project's single authoritative model. There is
no compatibility requirement for old persistence formats, so preserving that
runtime in the active checkout would create an unnecessary maintenance path.

## Consequences

The source/compiler fingerprint covers the checked Bend program. A journal for
another fingerprint is rejected; no automatic conversion is attempted. Worktree
executables and compiler installations stay local to their checkout.

The proof boundary ends before host execution. Commit ordering, interruption,
credentials, HTTP, MCP, process cleanup, and UI interactions are exercised with
real local implementations and synthetic external endpoints. Live vendor behavior
and the soundness of the compiler or operating system are not asserted by these
proofs. This decision supersedes the temporary Rust-retention clause in ADR 0006.
