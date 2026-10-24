# Interactive Markdown

An explicit `selvedge-ui` fence declares bounded local state and controls. Ordinary
Markdown remains ordinary Markdown. The application admits fence observations
from its document lifecycle; native events cannot introduce a document or grant
permission to perform an external action.

For example:

```xml
<ui id="controls">
  <state id="name" type="string" initial="Ada" max-length={200}/>
  <stack id="body">
    <text-input id="edit" label="Name" bind="name"/>
    <button id="copy" label="Copy" action="copy" value={name}/>
  </stack>
</ui>
```

Use `Language.initial`, `Language.step_visible` and `Language.observe_owner` from
Gallina. `Language.call` provides the JSON entry for isolated language use;
`Interaction.Application.call` is the application entry that supplies current
document ownership, visibility and external-action permission. Component and
field declarations are defined in `Vocabulary.v`; resource limits are defined
in `Bounds.v`.

The parser accepts an incremental prefix. Each mounted control carries its owner,
path and occurrence, so a removed control does not authorize a later event at the
same path. Local input retains an invalid editing buffer without changing its
canonical value. Expressions use fixed-point decimal arithmetic and a shared
evaluation budget, including expansion and table presentation.

Preview and interrupted documents cannot perform authored external actions or
persist a snapshot. Complete documents may request restoration once before an
edit. Storage returns an explicit missing observation or raw text; the Gallina
JSON parser and snapshot validator admit the entire canonical payload atomically.
View ownership is checked against a trial using all restored roots: a hidden
conditional view may stay dormant, while an explicitly removed repeated item
rejects the complete entry.
Edits invalidate an outstanding restoration. Snapshots exclude raw buffers,
source observations, pending actions and derived values.

`Guarantees.v`, `SemanticsGuarantees.v` and the parent
`ApplicationGuarantees.v` state the checked guarantees and their precise premises.
Extraction and the OCaml-to-JavaScript compiler remain trusted compilation
steps. Browser storage, clipboard, navigation and command execution are external
effects; their physical success is reported through correlated callbacks rather
than established by a pure proof.

Graph templates remain inside their positioned nodes, including their local
controls. Node state and connection rules also have a readable list equivalent.
Fit uses a single column; zoom returns to the stable grid. Viewport state belongs
to the logical document, while each main or side presentation has separate DOM
keys and native editing sessions.

Build and migration decisions are recorded in repository ADRs.
