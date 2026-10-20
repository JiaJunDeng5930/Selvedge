# Editor

Owns editor state, binding and layout behavior.

Start with [MODEL.bend](MODEL.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

`native_key` consumes `KeyObservation` before trusted editor events are formed.
Its production laws retain native composition and IME confirmation observations
and bind default handling to the same normalized event.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

Type `@` in a Task message or new Task message to search the current workspace's
skills by name or description. Arrow keys highlight results; Enter, Tab and
click insert the selected skill's explicit path reference. Escape dismisses the
list until the query changes. The textarea remains ordinary editable text;
selected references are sent as `[$name](path)` and do not load skill bodies.

`skill-mention.bend` owns trigger detection, filtering, dismissal, path escaping
and transient catalog correlation. `skill-view.bend` renders its native combobox
and listbox. Catalog observations use the existing browser observation service,
independently of task history. Native selection offsets cross the browser boundary
as Unicode scalar positions, and composition bypasses mention selection and send.
