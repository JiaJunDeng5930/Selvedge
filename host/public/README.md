# Browser host

`app.mjs` observes HTTP, SSE, DOM, storage and media resources. It sends domain JSON
to the extracted interaction program, interprets the returned effects, and asks
the extracted browser program to render its typed scene. Product commands,
field schemas, layout choices, publication admission, composition state, reading
intent and code-block behavior are Gallina definitions.

`model-boundary.mjs` depends only on the host extraction, so Bun and the standalone
plugin do not load the UI models. `browser-model-boundary.mjs` adds the browser and
interaction entry points. Their JSON text boundary retains numeric lexemes and
UTF-8 text; no compiler-private object layout is shared with JavaScript.

`renderer.mjs` interprets a closed vocabulary of elements, text, Markdown and
portals. It retains keyed native elements, delegates input decisions to the
extracted field-session state machine, and applies the scene's declared input
injection slot. SVG primitives and coordinates are constructed by Gallina;
JavaScript only creates their fixed SVG elements. Native dialog modal behavior,
focus, selection, pointer hit tests and physical measurements remain browser
observations and effects.

The pinned Markdown parser and formatter assets remain under `vendor`, with their
licenses. Only a real mounted Markdown record owns its fence observer; a rendering
or measurement clone cannot authorize an interactive document. Source origin,
epoch, revision and parser prefix are returned to the owning interaction model.
Code-copy results, delayed feedback, uploads, connection attempts, audio resources
and local-storage completion are correlated with their model-issued identities.

`generated` contains reproducible build artifacts copied by `bun run build` and
is not tracked. Run the browser tests through the real service fixtures in
`scripts/test-*-browser.py`; a synthetic page that substitutes a model is not an
acceptance test.
