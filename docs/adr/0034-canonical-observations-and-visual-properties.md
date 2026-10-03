# ADR 0034: Canonical observations and visual properties

Derived copies of a page and competing writes of the same visual property
made independently valid local models disagree. Each existing UI object now
has one authoritative semantic or visual definition; consumers project that
definition. Identity references and physically observed snapshots remain
separate from the entity they describe.

Long proof conclusions have one named proposition, consumed by the production
proof and requirement record. Independent specifications are retained: reducing
duplicate text must not turn a refinement proof into implementation self-equality.

Rendering owns the translation to platform properties. A visual property's
semantic value belongs to its appearance, rather than to later CSS overrides.
This keeps failures traceable to either the source value or its realization.
