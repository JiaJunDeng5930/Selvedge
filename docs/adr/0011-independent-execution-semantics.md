# 0011: Close the specification over independent execution semantics

Status: accepted for the Bend branch.

## Reason

A command specification parameterized by the production scheduler leaves that
part of the behavior unconstrained. An incorrect scheduler can satisfy the
statement because it appears on both sides. Safety does not repair this gap.

## Decision

The command, protocol, commit and execution specifications must have no import
path to PROGRAM. Execution resolves domain work into an explicit action and
gives that action an exact decision meaning. PROGRAM realizes actions and finite
runs; PROOF composes their correspondences into the committed input refinement.

Finite-run induction uses the quoted Corelib `nat_ind` certificate. Only the
application's base and successor correspondence obligations are proved here.
Fuel exhaustion means a continuation effect, not termination or fairness.

## Evidence

The architecture test checks the transitive import closure and the conceptual
specification's scheduler binding. Production action/scheduler mutations must
fail proof checking. A corrupted imported induction step must also fail. Both
PROOF and MAIN are checked, and the native/host integration suite exercises the
resulting executable. These gates make no claim about remote model liveness.
