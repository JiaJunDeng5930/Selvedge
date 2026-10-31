# Interaction semantics

`Application.call` is the extracted browser interaction boundary. Its operations
are `initial`, `step` and `observe`; each returns the common JSON success/error
envelope. Step consumes the same accepted world observation that observe uses,
plus the durable journal namespace, the actual publication lag and wall-clock
seconds supplied by the IO host.

Forms derive their heterogeneous value types, codecs and field edits from
`Programming.Schema`. A draft has one editor owner and the value type selected by
that owner. Invalid native text is retained separately from admitted values, so
editing a large integer or an incomplete JSON value never changes a typed value
into an unvalidated string. `Programming.CommandDeclarations` interprets the
`Kernel.Commands` catalogue before commands can become pending requests or effects.

The shared [presentation constructions](../Programming/README.md) live under
`Programming.Presentation`. `Surface` owns the semantic tree and common event
interpretation; page, editor and activity modules supply concrete contents.
`Browser.Document` compiles that tree into native presentation. Graphics use
`Programming.Graphics`. The interactive Markdown feature retains its own
component and state language, while its error-aware and metered computations use
`Programming.Outcome` and `Programming.Metered`.

Resource tickets, draft revisions and navigation generations have different
responsibilities. Resource tickets reject unrelated IO completions; draft
revisions preserve edits made after a submission; navigation generations prevent
an earlier creation request from selecting a task after the user has moved on.
`Programming.Resource`, `ApplicationProof` and `Documents` prove properties of the reducers
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

Project pages retain their own directories, primary directory, guidance and member
Tasks. Navigation keeps global destinations separate from Work tabs and the Task
tree. The physical browser can move the unique navigation header into an expanded
narrow Task-list dialog; global and Work overview panels still use the ordinary
layer stack and return to their actual launchers.

Message authoring and committed execution settings have separate owners. Applying
an execution choice rebases that choice on the latest Task instead of resubmitting
a cached message configuration; changing the model cannot advance the message's
revision or overwrite its text. Main and side presentations of the same Task keep
one document lifetime while native keys and captured return targets identify the
actual presentation. Closing a supporting window therefore restores its launcher
without making a second document source or asking the IO host to guess an owner.

Object menus request admission from the same kernel boundary used by committed
commands. An available native menu action requires the observation for that
subject, action, menu occurrence and world sequence; the committed command is
still resolved by the service. Directory preparation supplies a workspace intent,
while the service observes root guidance at its trusted submission boundary.
