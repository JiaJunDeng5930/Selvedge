# Browser adapter

`../../BROWSER.bend` is compiled into `generated/browser-model.mjs`. Its state and
`../../browser/document/MODEL.bend` document are the browser's only product model and rendered
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

Message fields and file controls share the declared `SelectFiles` binding. The
adapter turns file selection, pasted clipboard images and dropped files into
opaque handles; the existing upload service owns progress and settlement. Images
use the same authenticated content-addressed attachment vault as the task board.
Markdown's `browser.image` admission loads those vault URLs as native images and
reports decoded dimensions back through ordinary content measurement; other image
URLs remain explicit links.

Stream notifications retain their order through the Bend adapter. Consecutive
text observations can share a publication; commit and stream lifecycle boundaries
flush earlier observations first. Notification turns yield so native input and
physical measurement can progress during sustained output.

`connection.mjs` observes one authenticated HTTP/SSE connection. Services own
connection tickets and recovery timers; the adapter does not maintain a retry
loop. `appearance.mjs` passes stored preferences back into that same service
model, and `keyboard.mjs` preserves native key observations for the compiled
editor's normalization and default-handling decision.

Ordered focus effects retain their order while a target awaits publication.
The adapter retries the current ticket's queue when the document is published;
newer focus tickets retire obsolete requests. This lets a newly created tab be
exposed before the following effect restores the page's focus. Each focus also
requests nearest-edge scrolling, since native focus can leave a partially
visible control clipped.

Authored `data-reveal-on-layout="true"` targets request nearest-edge scrolling
after publication, without moving keyboard focus. `layout-reveal.mjs` compares
their layout position, size and enclosing scrollport sizes; user scrolling alone
does not renew the request. Bend chooses the targets, and the adapter interprets
the same generic constraint for any native element.

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

Physical Markdown minimum-width observations measure unwrapped code through its
horizontal scroll viewport. Only parser-created `pre` elements in the measured
primitive's own Markdown root receive temporary inline-size containment; toolbar
and native Portal content retain their minima. The adapter restores each original
containment value and priority before measuring full preferred width, actual
AtWidth height or targets, including when minimum observation throws. Visible
Markdown layout and the allocated reading-width limits are unchanged.

Skill suggestions are rendered by the compiled editor as a document overlay.
The adapter forwards native selection and key observations, interprets catalog
observations and restores committed selection effects. CSS anchors position the
list against its textarea; focus-preserving pointer targets keep composition and
keyboard ownership in that textarea. UTF-16 DOM offsets are converted to Bend
Unicode scalar positions at this boundary.
