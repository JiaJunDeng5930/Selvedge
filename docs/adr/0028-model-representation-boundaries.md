# 0028: Model representation boundaries

## Context

Constructing or matching a lower model's aggregate state makes its representation
part of the client's implementation. A representation change then reaches callers
whose behavior depends only on an observation or an intended update. Bend module
namespaces do not provide sealed private exports, so naming an owner alone cannot
prevent these dependencies.

Public command and view values have a different role: callers need to construct
and inspect them. `Board.AgentProfile`, for example, is the editable value carried
by `SaveAgent`, not merely an internal registry record.

## Decision and reasons

Expose named observations and updates in each owning model. Upper models use those
operations to compose lower models, while the lower aggregate constructors remain
owned by their implementations and explicitly listed representation proof
providers. An update states its intended write; an accessor does not return a
complete unpacked representation. Public command, input, reply and view vocabulary
remains transparent, including `AgentProfile`.

Use parametric abstraction where it governs an actual computation. Task storage's
`Tasks.update_carrier` takes an unknown carrier and its task read/write operations;
production `update_state` specializes that computation to the domain model.
`update_world` retains the existing component frame wrapper. This gives the storage
algorithm a compiler-checked abstraction boundary without turning concrete models
into runtime dictionaries or introducing a second specification.

For the remaining concrete layers, use the ordinary source ownership gate in
`scripts/check-components.mjs`. `components.json` declares private constructors and
literal owner paths. The gate resolves import aliases and checks construction and
pattern matching outside those owners. It validates the declarations themselves
and does not grant a blanket exemption to proof modules. This complements Bend's
type checker; it does not introduce language-level sealing. The existing closed
core import boundary remains unchanged.

Group existing Locality, Core and Web contract evidence by responsibility, retaining
all mandatory obligations and production bindings. Public laws use whole-state
quantification, observations and intended updates; representation-specific
providers may open those states to establish the original complete equations.
These providers remain explicit owners. Contract groups supply a reading boundary
without a parallel property catalog or optional proof tier.

## Tradeoffs and evidence boundaries

Source ownership is a checked repository convention, so its enforcement depends
on the source scanner and ordinary build/check entry points. Parametric storage
provides a stronger language-enforced boundary for that computation, but this
change does not make all client proofs representation-independent. Some production
proofs still require the representation and are deliberately owned accordingly.
Neither mechanism claims a runtime speedup.

The proof gate continues to require complete decisions, completion correlation and
ordered effects. `test:locality` supplies separate evidence through frozen clients,
contract-preserving replacements and native extension round trips. These checks
serve different boundaries; reorganizing contracts or passing a source ownership
check does not establish native or host integration success.
