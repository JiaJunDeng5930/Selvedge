# Interaction semantics

`Application.call` is the extracted browser interaction boundary. Its operations
are `initial`, `step` and `observe`; each returns the common JSON success/error
envelope. Step consumes the same accepted world observation that observe uses,
plus the durable journal namespace, the actual publication lag and wall-clock
seconds supplied by the IO host. No Bend object representation crosses this API.

Forms derive their heterogeneous value types, codecs and field edits from
`Foundation.Schema`. A draft has one editor owner and the value type selected by
that owner. Invalid native text is retained separately from admitted values, so
editing a large integer or an incomplete JSON value never changes a typed value
into an unvalidated string. Commands enter the shared `Kernel.Commands`
declaration interpreter before they can become pending requests or effects.

`Scene` is a parameterized semantic tree. Fields carry their schema and an
explicit value-injection binding; buttons carry complete actions. Presentation
and the interactive language use this same type, and Browser interprets its
encoded boundary representation. Graphics likewise share one finite primitive
vocabulary. Keeping these ordinary interpreters separate from business
instances avoids creating another markup or command DSL.

Resource tickets, draft revisions and navigation generations have different
responsibilities. Resource tickets reject unrelated IO completions; draft
revisions preserve edits made after a submission; navigation generations prevent
an earlier creation request from selecting a task after the user has moved on.
`Resource`, `ApplicationProof` and `Documents` prove properties of the reducers
that the extracted entry composes, rather than introducing a second specification
implementation.

Document identity comes from the kernel's frozen output origin and the durable
namespace. Inherited output keeps its original producer. The interaction layer
admits a Markdown observer only for an actual visible source with the matching
identity, epoch and authoritative prefix. Non-prefix replacement starts a new
lifetime. Interrupted output remains a session observation with no submission
authority; its active retention and source archives use the language's shared
bounds. A shared Work definition uses its authoritative revision as its lifetime.

The Rocq kernel checks the Gallina definitions and their stated theorems.
Extraction, the OCaml/JavaScript toolchain, physical Markdown observations,
publication barriers, storage, network and audio effects remain distinct trust
boundaries. IO success is an observation correlated with a request, not a proof
that the external service fulfilled a business goal. Model judgments are external
inputs. Static field typing does not replace validation of these inputs.

The source inventory and integration handoff are maintained outside version
control in `.workpad/interaction-files.json` and
`.workpad/interaction-handoff.md`. They distinguish checked library modules from
final extraction and full-system acceptance.
