# 0062: Preserve activity and navigation contracts during semantic reconstruction

Date: 2026-10-21
Status: Accepted

## Context

The initial migration treated fields, explanatory text and reachable commands as
substitutes for the original experience. That lost which object a property
described, where its value came from, which choices depended on one another,
and what completed an activity. Project detail navigation and narrow-screen
reading and focus relationships were also lost. These are product requirements,
not constraints of Bend's representation.

The original preparation path combined complete draft requirements, directory
observations and, where no directory preparation was needed, actual command
admission. Local field checks alone cannot preserve that contract. Rebuilding a
kernel world from a browser snapshot would instead create another semantic
implementation with stale or missing facts.

## Decision

Associate properties and candidate values with their actual subjects and owners.
Use the shared field declarations and ordinary dependent constructions for these
relationships. Keep comparison, explanation and editing distinct where their
completion conditions differ. Carry all preparation failures with their repair
targets; a generic information panel cannot replace those activities.

Keep workspace and guidance together as directory preparation evidence. Public
command intents carry the workspace; the service obtains its trusted guidance
again at submission rather than accepting authority from browser-supplied text.
Read-only assessment uses that same preparation path. Treat current Task
execution settings as observations of that Task,
separate from message content and dictation revisions. A field choice must not
overwrite unrelated settings from an old cached draft.

Represent an inherited workspace separately from an explicitly empty one.
Removing the last root must not silently re-enable inheritance. Activities that
edit optional overrides must also let users return to inherited workspace and
permission values; a Task's already frozen execution settings remain concrete.

Use a read-only admission query over the worker's actual typed world, projecting
the same command definition used by submission. Correlate its result with the
editor revision and world observation. It neither commits a transition nor
interprets effects; final submission still performs authoritative admission.

Keep one observed viewport and font source while allowing navigation and
supporting content to have different capacities. Opening a foreground must not
silently change the background navigation. Move the same navigation header into
the expanded task list's modal scope rather than hiding a duplicate. Preserve
the real trigger, layer order and reading position across these placements.
Native CSS geometry replaces the old pixel allocator without replacing its
user-facing relationships.

Keep the desktop task-list visibility preference separate from an explicitly
opened task drawer. Reusing the preference as a modal activity makes a window
resize open navigation and take focus from an editor. The existing navigation
activity owns opening and closing the drawer; viewport changes only choose its
physical placement.

Capture the appropriate live return control before submission changes the
activity. Sending a message can disable its Send button; a side conversation
therefore returns to the originating composer rather than that disabled button.

Keep a document's logical owner separate from each physical view occurrence.
The same side Task can appear in the main area and a supporting panel at once;
its document and interactive state remain shared, while DOM identities,
selection and focus targets identify the actual occurrence. Duplicating the
document state or forbidding that valid placement would change the product.

Admit a restored interactive snapshot against the view structure produced by its
restored root values before committing any of it. Checking only path syntax and
then dropping unavailable views can partially restore an invalid external
snapshot. The controlled snapshot value carries successful whole-snapshot
admission to the real restoration entry.

Scale graph geometry without scaling the controls inside node templates. A
whole-canvas CSS zoom would shrink the original interaction targets and text,
changing their usability. Derive node spacing from the same displayed bounds:
the old low-zoom geometry could place nodes closer than their minimum width and
make them overlap. Correct that defect while retaining ordinary-scale spacing
and physical pan offsets.

Restore the documented remembered local-worktree choice when creating a Task.
Cloud choices do not change that local Project preference. This supersedes the
contrary preference decision in
[ADR 0054](0054-rocq-semantic-source-and-extracted-runtime.md) and the narrow
navigation substitution in
[ADR 0058](0058-native-browser-layout-with-one-semantic-scene.md); their other
semantic-source and native-geometry reasons remain valid.

## Limits

An assessment establishes its stated preparation conditions at an observation,
not eventual external success. DOM focus, inertness, font measurement, physical
layout and event delivery remain browser responsibilities. Real browser
scenarios must exercise those relationships; structural proofs do not establish
the appearance or behavior of every viewport.

References: the inherited
[experience](0041-operational-user-experience-relations.md) and
[adaptive navigation](0044-adaptive-presentation-and-navigation-relationships.md) decisions;
[original graph geometry](https://github.com/JiaJunDeng5930/Selvedge/blob/acfbe86d8181415fd887c323cbba6495509d280f/browser/controls/interactive-markdown.bend#L149-L156);
[WAI-ARIA modal dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/);
[HTML dialog](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-dialog-element).
