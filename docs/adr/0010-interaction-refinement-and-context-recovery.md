# 0010: Whole-interaction refinement and bounded context recovery

Status: accepted for the Bend branch.

## Reason

Refining public commands did not constrain the complete asynchronous protocol or
the calling-task result of internal operations. Context management also exposed
a functional gap: a failed summary could leave active queued requests stranded
in an idle task, while satisfying both safety and an over-specific idle-phase law.

## Decision

`bendlib/protocol.bend` owns completion correlation and accepted-call resolution.
Public operations reuse COMMANDS' resolver. PROGRAM realizes those operations;
LAWS/PROOF compare complete decisions and lift all input cases through the same
commit boundary. A stale result is rejected before interpreting its payload; an
accepted internal call is settled against the resulting world, not its old caller.

`CONCEPTS.Harness` is the assembled theoretical entry. Its fields bind the actual
command/effect machine, journal action, recovery homomorphism, observations,
decision composition, context projection and interruption. Original Stdlib map
proofs supply partition/composition laws for recovery, task views and branch IDs.
Source map is explicitly represented with Base.foldr over duplicable lists.

Project guidance is a committed observation frozen into each task contract.
Provider overflow is a typed input, not a hidden retry loop. A settled history
can produce a checkpoint and a fresh model ticket; an irreducible checkpoint or
failed summary stops without new input. Independently queued requests are still
promoted in FIFO order, without accepting any rejected summary's tool calls.
The full rejected-summary equation replaces the old unconditional idle-phase
claim. Empty-queue stopping remains a separate exact requirement.

## Evidence and limits

Production mutants must fail proof checking after passing ordinary type checking.
Native and HTTP/SQLite tests cover overflow, summary failure, queued input,
freezing, cancellation, restart, and non-repetition of completed mutations.
Both PROOF and MAIN are checked: proof dependency closure is not wire integration.

No claim of summary fidelity, provider availability, operating-system correctness,
fair scheduling or arbitrary external-library import follows from these results.
The detailed experiment findings and reference revisions are recorded only in
`docs/bend2-exploration.md`, rather than duplicating the executable protocol here.
