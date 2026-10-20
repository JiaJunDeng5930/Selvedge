# 0032: Operational model abstraction

## Context

Concept directories and proof composition help locate code, but their arrangement
cannot isolate a state representation. A reader following imports still has to
open concrete aggregate constructors to understand how the whole system acts.
The system needs an operational interface whose properties support reasoning
without that dependency.

## Decision and reasons

Make the root `MODEL.bend` the overall model context. Its operation records bind
universal properties to the very operations a client calls. Package the execution,
application, and display layers with existential state and result carriers,
sharing the same hidden `World` across the layers. A generic package client can
use the exposed operations and observations but cannot match an abstract carrier
as an implementation constructor. Commands and observations stay transparent so
clients can construct and inspect the vocabulary they exchange.

Opaque carriers are necessary because a record of operations over a named,
concrete state type would still expose that representation. Complete-result laws
are necessary because a transition's obligations include replies and ordered
effects as well as its next state. An agreement on a state projection could leave
those observable obligations unconstrained. The executable records own these
requirements; this document does not maintain a second catalogue of their laws.

The [official Bend guide](https://github.com/bendlang/bend/blob/main/guide/GUIDE.md)
provides the language model for typed values and checked proofs. Lamport and
Merz's [Prophecy Made Simple](https://lamport.azurewebsites.net/pubs/simple.pdf),
particularly its treatment of internal variables and refinement mappings,
explains how observable behavior connects an implementation to an abstract
specification. These references inform the separation of representation from
behavior; they are not evidence that this project satisfies its contracts.

Keep `MODEL.bend` independent of production implementations and proof providers.
The root `PROOF.bend` constructs its instance from the actual production functions
and existing proofs. Representation-specific providers discharge their concrete
obligations; generic clients consume the packaged operations and evidence.
`CONCEPTS.bend` retains its existing proof composition for detailed evidence
inspection. An import catalogue alone would provide neither an opaque carrier nor
properties tied to executable operation fields.

The pinned compiler treats operation fields as affine `Type` values. Static
methods also require closed template arguments, which a runtime-unpacked
existential carrier cannot supply. Exposing the existing finite-trace production
operation supports generic execution without copying those fields or revealing
the carrier. The interface retains its universal laws and complete single-step
refinement.

## Consequences

The change adds a representation-independent model surface without changing
production behavior or replacing existing requirements. It does not enforce
privacy across all existing modules: concrete implementation adapters and proof
providers remain inspectable through their own modules. The compiler boundary is
that a generic client of the existential package cannot inspect its hidden state
as a concrete constructor.

Pure model proofs constrain produced decisions and effects. They do not establish
that a host or browser interpreter successfully performs an external effect.
Focused boundary tests and end-to-end checks remain responsible for that boundary.
