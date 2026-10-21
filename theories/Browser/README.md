# Browser semantics

`Runtime.call` is the JSON boundary extracted into the production browser bundle.
`Document` interprets the interaction module's semantic scene into a closed DOM
vocabulary; product actions and labels remain in the interaction module. DOM nodes
carry plain JSON records, never a compiler's internal constructor layout.

`Native` owns key normalization, reading intent, publication generations, focus
cycling, and width allocation. `NativeProof` and `DocumentProof` are checked
separately and are absent from the executable import closure. Their statements
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
