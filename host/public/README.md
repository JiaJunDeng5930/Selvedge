# Browser host

`app.mjs` observes HTTP, SSE, DOM, storage and media resources. It sends domain JSON
to the extracted interaction program and interprets the returned effects. The
browser mounts its workspace shell first and publishes the typed regions that
change in each subsequent transaction. Product commands,
field schemas, layout choices, publication admission, composition state, reading
intent and code-block behavior are Gallina definitions.

`model-boundary.mjs` depends only on the host extraction, so Bun and the standalone
plugin do not load the UI models. `browser-model-boundary.mjs` adds the browser and
interaction entry points. Their JSON text boundary retains numeric lexemes and
UTF-8 text; no compiler-private object layout is shared with JavaScript.

The extracted browser program calls `native-dom.mjs` to create and update
elements, text and Markdown, and to mount children in physical Markdown targets.
The adapter retains keyed elements and delegates input decisions to the extracted
field-session state machine. Gallina constructs SVG primitives and coordinates.
Native dialog behavior, focus, selection, pointer hit tests and physical
measurements remain browser observations and effects.

The interaction program records each control's receiver when its region is
published. Native events resolve against those receivers and the active modal
scope. Region publication places keyed roots within their workspace hosts and
commits their DOM and bindings together. An edit publishes its composer, a
details toggle updates the relevant toolbar and panel, and the model picker
publishes through the overlay region. A fence callback updates its own
Markdown mount.

The pinned Markdown parser and formatter assets remain under `vendor`, with their
licenses. Only a real mounted Markdown record owns its fence observer; a rendering
or measurement clone cannot authorize an interactive document. Source origin,
epoch, revision and parser prefix are returned to the owning interaction model.
Browser receipts wait for Markdown records with pending parser or formatter work.
Code-copy results, delayed feedback, uploads, connection attempts, audio resources
and local-storage completion are correlated with their model-issued identities.

`generated` contains reproducible build artifacts copied by `bun run build` and
is not tracked. Run the browser tests through the real service fixtures in
`scripts/test-*-browser.py`; a synthetic page that substitutes a model is not an
acceptance test.


The DOM adapter maintains physical identities independently of logical document
and editor ownership. Logical focus and reading requests are resolved by the
extracted browser rules against observed native targets. Responsive navigation
uses one real header; native dialog order follows the declared layer order.
Anchored dialogs use their captured trigger and CSS anchor positioning. Native
modal inertness also governs layout reveal and animation, without introducing a
second application navigation or viewport state.
