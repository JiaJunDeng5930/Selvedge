# 0061: Check task graph declarations at the shared installation boundary

Date: 2026-10-21
Status: Accepted

## Context

Task graphs can be declared through JSON or composed in Gallina. Checking node
identities, references and message limits only while decoding JSON leaves the
ordinary composition path outside the same contract. Maintaining another set
of checks for composed graphs would duplicate the domain facts.

The previous routing proofs established rejection, atomicity and non-repetition.
Those guarantees also permit a dispatcher that never forwards anything. They
therefore do not establish the graph's purpose: declared handoffs deliver the
specified messages in order to ordinary tasks.

## Decision

Require a checked declaration for installation. Decode and ordinary composition
use the same admission predicate. Retain ordinary functions and checked data
rather than introducing a second graph language or generator; there is no new
declaration family here that would justify its maintenance cost. External JSON
still requires runtime admission.

Specify node binding independently of the production resolver, and message
meaning independently of its expansion algorithm. Otherwise a resolver that
never finds a node could make positive obligations vacuous. Connect these
relations to pending deliveries and the actual task-input operation, alongside
the existing rejection and replay guarantees.

## Limits

The checked guarantees concern declared routing and the task-state changes that
admit a delivered message. They do not establish scheduler fairness, successful
external execution or the quality of an unconstrained model's output. A handoff
with no admissible target is not evidence of delivery.

The archive's ordinary graph composition is the product reference. Rocq Stdlib
list relations provide the existing machinery for ordered expansion; no custom
proof framework is needed.
