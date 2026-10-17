# Context selection

Separates the immutable task history from the input selected for a concrete
endpoint and account scope. Start with [MODEL.bend](MODEL.bend),
[PROGRAM.bend](PROGRAM.bend), and [PROOF.bend](PROOF.bend).

The original history remains the recovery source. A replacement event records a
complete returned window and the captured source length. Selection preserves
fixed task context and appends only records after that captured source. Native
items require their actual consumption scope; portable rebuilding uses the
readable original records, never a previous opaque replacement.
