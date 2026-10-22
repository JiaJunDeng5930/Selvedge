# 0069: Preserve world admission through extraction

Date: 2026-10-22
Status: Accepted

## Context

The original commit contract rejects a candidate that violates the global world
requirements before committing its state or effects. A replay theorem that only
relates two executions of the same packet function does not establish that this
contract survived extraction. Local typing also cannot establish references
between independently stored tasks, operations, projects and feature entries.

## Decision

Keep the original world requirements as named executable checks over the actual
runtime values. Reuse existing admission rules and typed constructions where they
already express the requirement. Separate validity of retained configuration from
its present availability: removing a model from the catalog does not invalidate
an already stored task contract, title request or agent profile.

Apply these checks to the complete candidate before notification and delivery.
A failed check restores the previous world and removes the candidate's effects.
The journal cursor retains its existing semantics and does not contribute a new
product invariant. Prove preservation for the exported packet operation and lift
that result to journal execution and reachability.

Keep the journal's executable trace model separate from its proofs so that the
proofs name the same packet computation used by live execution and replay.
