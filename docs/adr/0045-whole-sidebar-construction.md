# Whole-sidebar construction

The previous navigation policy made membership, row slots and contextual actions
explicit for project and task rows. Top-level destinations still used generic
content-sized buttons, and the independent-task collection used document-section
heading and spacing rules. A valid row in isolation could therefore disagree
with the neighboring row's alignment and interaction extent. Proofs of those
local constructions did not establish a coherent navigation surface.

The sidebar now needs construction authority over the relationships its entries
share. Creation and destination actions retain their distinct application inputs;
the navigation role declares that their presentation participates in the same
row organization as projects and tasks. This avoids recognizing navigation by
particular labels, command strings or accidental ancestry in the rendered DOM.
Selection, expansion, task execution and interest continue to have separate
meanings.

A shared source constructor owns row allocation and its leading, title and
trailing positions. A single-action entry uses its entire allocated row as the
command surface. A project header retains its independent disclosure, opening
and auxiliary commands within the same geometry. Command preservation and
constructor correspondence bind these different interaction structures to the
actual returned source. Sharing alignment does not erase their domain behavior.

A composed project header is a region containing several commands. Native-button
pseudo-states therefore cannot paint its whole row. The resolved navigation
representation retains owner feedback independently from auxiliary visibility: a
non-hover device can expose actions without highlighting every project. Appearance
resolves that feedback into the region's actual background before construction,
and the constructor preserves that background. This keeps interaction feedback
under the same model authority as its cause instead of adding an unrelated CSS
rule for containers.

The existing category and proof-provider mechanism is reused so production
consumers obtain construction evidence before extracting the source node.
The source-construction module is separate from the pure navigation policy and
from its consumer. This avoids the import cycle through document source, design
and control representation that would result from putting source construction
inside the policy module.

Navigation collection captions locate items; document section headings introduce
substantive content. Giving both the same strong typography and heading minimum
height promoted classification above the tasks it described. An explicit
navigation-caption information role allows the sidebar to retain its membership
boundary with appropriate emphasis and measured line geometry.

Collection, heading-to-member and member-to-member organization reuse the
existing hierarchy grammar. Navigation depth already allocates subordinate
horizontal position, so applying the generic nested-member inset as well would
encode the same relationship twice. The hierarchy therefore exposes a same-level
member frame that preserves its member spacing without adding physical nesting.
The existing nested-member frame keeps its original purpose.

The decision is supported by the installed Codex 26.1007.30912 implementation:
its actual navigation callers use whole-row command surfaces, coordinated leading
slots and a tertiary section-caption treatment. Its desktop pixel calibration
is reference evidence, not a universal requirement for this interface. Actual
browser acceptance must establish the shared axes, row interaction extent,
classification hierarchy and relative grouping distances, alongside preserved
commands and contextual behavior.
