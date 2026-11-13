# Browser semantics

`Runtime.call` is the extracted boundary for native browser observations.
`Application.call` handles browser initialization, input and observation against
the accepted world, durable namespace and publication state. It uses
`Presentation` to project individual navigation, page and layer regions from
business observations and `Session` to own navigation, dialogs and browser
resource lifetimes. `Document` compiles the affected regions into a closed DOM
vocabulary. Each publication installs its controls alongside its DOM effects.

Browser views take business facts and decisions from [Interaction](../Interaction/README.md).
Cards expose move and link choices through focused selectors, and drop targets
use the same move proposals. Native controls still require the service's current
assessment, correlated to the object, action and world sequence.

Resource tickets reject unrelated IO completions, draft revisions preserve edits
made after submission, and navigation generations preserve selection after the
user has moved on. Main and side presentations of one task share document identity
and source authority. Native keys and return targets identify the actual
presentation. Document observations require the matching identity, epoch and
authoritative prefix. A non-prefix replacement starts a new lifetime.

`Keyboard`, `Reading`, `Publication`, `Focus` and `Layout` own key normalization,
reading intent, publication generations, focus cycling and responsive allocation.
Their proof modules and `DocumentProof` are checked separately and are absent from
the executable import closure. Their statements
refer to the functions called by `Runtime`, rather than a second reference
implementation. Native events must belong to the current DOM generation. A separate published
prefix generation advances only after the real Markdown and canonical fence
observers catch up; the interaction program receives that lag observation before
admitting external actions.

Text crossing the boundary is UTF-8. Native selection observations for speech
use UTF-8 byte offsets; DOM selection effects explicitly convert their coordinate
representation. Numeric JSON lexemes remain exact. Publication generations and
durable event cursors use binary naturals, avoiding unary storage proportional
to the journal's length. Physical viewport space rounds down to CSS pixels and
measured minima round up. Fractional scroll/anchor offsets retain their decimal
spelling at the IO boundary.

The DOM, font and geometry observations, incremental Markdown parser, browser
storage, media devices, HTTP and SSE are external effects. The proofs do not
claim that those implementations or remote services obey the model. Native
completion tickets and the committed world determine whether their observations
are admitted by the owning interaction operation.


`Appearance` retains the authored SVG symbols and the independent motor-target,
writing-line and clearance dimensions. Button scenes declare their symbol; the
browser does not infer product meaning from a key or caption.

One viewport observation supplies two allocations: workspace navigation and the
currently present supporting regions. A temporary supporting dialog therefore
does not collapse otherwise viable desktop navigation. The responsive projection
renders one branch of each alternative. Its compact task drawer contains the same
header and task tree, while a higher activity retains the foreground scope.
Native modal dialogs supply background inertness, cancellation and focus isolation.
Task details borrows its opening control while modal. Its typed layer and task
view determine the control's location without traversing the conversation.

Physical view occurrences scope DOM identities and ID references. They retain the
same logical editor, document and source authority. `Focus.resolve_target` first
honors a physical key, then chooses an observed logical alias in the active view.
Surface-declared focus aliases also keep responsive return targets available.
Anchored menus refer to their actual trigger and use native CSS anchor positioning.
Graph templates remain in fixed, internally scrollable node enclosures; their
owning `Plot` calculation changes geometry without shrinking native controls.
Chart canvases retain their drawing dimensions inside a horizontal scrollport.

The foreign host sends canonical command-assessment requests unchanged and returns
ticketed observations. Superseded requests release their fetch resources. The
interaction service owns admission, correlation, stale observations and explicit
retry. Physical visibility and reduced-motion observations pause animation through
a separate native attribute; resource freshness remains a semantic scene attribute.

The checked target-resolution and compact-navigation statements concern the native
document that is actually extracted. Browser layout, CSS anchors, intrinsic text
measurement, modal behavior and font shaping execute in the browser engine; their
physical behavior is exercised through Chromium. No retired Bend pixel allocator
or compiler object representation remains in the runtime.
