# ADR 0037: production instance construction and browser compilation

## Context

The root abstract model previously declared concrete production values as laws.
Fulfilling those values required importing the full production proof assembly,
even for conceptual clients that only needed the abstract operation surface.
The browser JavaScript emitter also repeated acceptance and retention of the
non-UI production assembly already checked by the full proof gate. That extra
closure imposed compiler memory cost without changing the browser exports.

## Decision

[MODEL.bend](../../MODEL.bend) retains `SystemModel`, and
[CONCEPTS.bend](../../CONCEPTS.bend) retains `Harness`, with exactly the same
operation fields and evidence requirements. Concrete instances are ordinary
explicitly typed [PROOF.bend](../../PROOF.bend) constructors:
`system() -> Model.SystemModel()` and `harness() -> Entry.Harness`. Their returned
production operations, hidden carriers and evidence assembly are unchanged.
This separates an abstract requirement from construction of its actual instance;
it does not substitute a mock, default value or unproved assertion.

The browser build retains two generated entries. The full
`.build/ui-verification.bend` ordered import list includes root `PROOF.bend` and
all existing UI private providers. Its mandatory proof acceptance runs before
compilation and cache reuse. `.build/ui-runtime.bend` uses the identical import
order and aliases, excluding only root `PROOF.bend`; it retains every other
provider and exports the existing `BROWSER.bend` public surface. It additionally
imports `harness/approval/PROOF.bend` explicitly: the approval contracts remain
in the runtime closure, while their actual provider previously arrived through
the root assembly. Removing the two concrete-value laws separates production
instance construction; retaining this owning provider discharges the remaining
approval requirements without fabricated evidence. The compiler's strict emitter
acceptance, zero-hole and foreign-boundary checks remain unchanged.

## Limits

The split reduces the source closure compiled for the browser; it does not reduce
the production evidence required by `SystemModel` or `Harness`, skip the full
verification gate, or change kernel, host and standalone plugin compilation.
Source and compiler fingerprints still account for the compiled runtime entry
and its actual closure. This record makes no claim that a build or test run has
completed, nor that compiler or external effects are established by Bend proofs.
