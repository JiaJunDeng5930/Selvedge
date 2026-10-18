# Documents

Builds rendered document content from semantic sources and defines its presentation requirements.

Start with [MODEL.bend](MODEL.bend), [SOURCE.bend](SOURCE.bend) and
[CONTRACT.bend](CONTRACT.bend). Follow [source-contract.bend](source-contract.bend)
for source validity, [render-contract.bend](render-contract.bend) for rendered
observations. `CONTRACT.bend` owns content presentation and composes these
boundaries. Source-policy validation belongs to `SOURCE.bend`, so production
clients do not import a law-bearing contract merely to validate source values.

The corresponding evidence is organized in [source-proof.bend](source-proof.bend),
[render-proof.bend](render-proof.bend) and [content-proof.bend](content-proof.bend).
[PROOF.bend](PROOF.bend) retains document dialog and realization evidence;
[presentation-proof.bend](presentation-proof.bend) remains an independent provider
for cross-concept clients. The repository [PROOF.bend](../../PROOF.bend) imports all
production providers. Read observations and intended updates before private
representations; contracts define the obligations rather than this reading guide.

`SOURCE.ExposureAttribute` declares presentation exposure independently of command
availability. `FRAME` propagates it through the allocated tree. Utility frames
retain their exact allocation checks; normal frames consume keyed exposure
expectations alongside the existing semantic, native-content and focus checks.
The generic host paint projection retains concealed allocation space.

[SPEC.bend](SPEC.bend) defines the required complete diagnostics and observation
outcomes. [diagnostic-proof.bend](diagnostic-proof.bend) connects those rules to
normal semantic frames and allocated utility frames.

A DOM lookup returns the first complete element with the exact key. A fingerprint
may rule out a match, but it cannot authorize one or combine properties from
separate duplicate observations. Missing geometry, visibility, enabled state,
keyboard/hit access, scrolling, native content ownership, focus and paint overlap
all contribute their specified diagnostics.

Tab order follows presentation order: an eligible product control, native links
owned by that node, its children, then its siblings. Disabled or concealed
controls do not enter the tab sequence; an ineligible parent does not remove
eligible descendants. Native link identities are unique and belong to current
read-only or Markdown content. A stale frame observation preserves the complete
state. A current valid frame becomes realized; a current invalid frame retains
its complete diagnostics.
