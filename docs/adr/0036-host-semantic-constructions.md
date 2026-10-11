# ADR 0036: host semantic constructions over observed JSON

## Context

The task kernel already binds production behavior to native operations and laws.
Pure calculations in the JavaScript host previously sat outside that construction
boundary. A transport implementation could therefore change admission,
correlation or result interpretation without exposing a corresponding native
operation in the system model. Calling that code an effect interpreter did not
bind its pure choices to the model's semantic categories.

## Decision

Host semantic operations use the existing
[category constructions](../../bendlib/categories.bend), with complete JSON
sources and results. The shared [adapter model](../../host/adapters/MODEL.bend)
retains the original source alongside the actual result and an equation to the
owner's executable meaning. Reusing this representation avoids a second general
membership or construction framework. Capturing the full source avoids proving
only a normalized fragment while callers supply a different request.

The root [MODEL.bend](../../MODEL.bend) exposes these stateless operations and
complete correspondence through `System.host_adapters`, beside execution and
interface operations. This makes the host semantics callable through the system
surface rather than discoverable only through a separate implementation index.
[HOST.bend](../../HOST.bend) supplies their wire entry. Domain meanings and
constructors stay in the shallow, coherent [host/adapters](../../host/adapters/README.md)
concept directory, with evidence beside each responsibility. This preserves
owner-local reasoning without creating a directory or file per helper.

Standard URL and JSON parsing, clock and arithmetic observations, byte handling,
hashing, OS behavior and network observations remain explicit external
boundaries. Native operations receive those facts and perform their domain
calculations. Treating an external policy verdict as a fact would merely move the
unbound decision behind a Boolean input; it would not establish correspondence
for the production decision.

Opaque connection secrets stay outside Bend. Native plugin operations construct
a credential plan; one JavaScript [interpreter](../../host/opaque-credentials.mjs)
executes it for both host and standalone plugin callers. Sharing that interpreter
avoids independent secret-validation implementations while keeping credential
contents, lengths, hashes and Bearer bytes outside the native input. Its handling
of secret bytes remains an external boundary.

JSON numbers retain their original lexemes through the shared
[token bridge](../../host/public/json-tokens.mjs). Decimal bounds compare those
representations without constructing enormous Peano naturals for safe-integer
limits. This keeps large numeric observations intact while avoiding resource
costs unrelated to the domain calculation. Bounded conversions belong where an
operation actually requires a natural number.

The host entry reuses the existing token ABI rather than introducing a parallel
codec. [The build](../../scripts/build.mjs) includes its compiled fingerprint in
the same artifact identity as the kernel and browser, so replay identity accounts
for changed host semantics. This links the generated adapter used by callers to
the production artifact rather than relying on an independently shipped policy
copy.

## Limits

Native correspondence binds actual calculations and constructed results to their
executable meanings. It does not prove external IO, codecs, cryptography, compiler
output or secret interpretation. Proof compilation and boundary integration
checks provide separate evidence; this decision record reports no validation
result and does not duplicate the executable laws.
