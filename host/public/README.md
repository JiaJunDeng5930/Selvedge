# Browser adapter

`BROWSER.bend` is compiled into `generated/browser-model.mjs`. Its state and
`webui/document.bend` document are the browser's only product model and rendered
UI. `app.mjs` executes compiled decisions synchronously, commits the document,
and interprets the resulting physical and network effects asynchronously.
Commands cross `/api/browser/command` as the Bend JSON value already produced by
the model. World snapshots use `bend-value.mjs` to restore native BigInt values;
sequence and completion acceptance remain in Bend.

`renderer.mjs` executes Element, Text, Markdown, Portal and TargetProperties.
It retains keyed DOM elements and applies changed attributes/properties/styles
without decoding product roles or field types. Input composition and selection
are preserved. Declarative native event keys are handed to compiled wrappers.
Bend supplies SVG elements, labels, controls and all page layout.

Focus, clipboard, attachment handles, geometry, reading corrections and SSE are
browser capabilities. The adapter reports their observations and correlated
completion tickets to Bend. Stream parts remain transport facts; Bend decides
which facts have a presentation. Rendering and encoding failures have Bend-owned
screens. The static HTML loading/error text only covers loading the compiled
program itself.

## Incremental Markdown

`markdown.mjs` retains its paced text buffer, bounded streaming parser and worker
formatting. Code fences create fixed empty toolbar and code targets using compiled
`code_key` identities. Literal code updates go to `code_source`; Bend fills the
toolbar through Portal and controls wrapping through TargetProperties. The
parser creates no product buttons or copy behavior. Raw HTML is not executed,
links use approved protocols, and code/math decorations remain worker-bounded.

`style.css` contains reset, font/token foundations and Markdown presentation.
Product layout and control appearance are prescribed in Bend styles. The tokens
are the pinned desktop asset; the browser does not import React components.
