# Platform-independent interaction

Combines application interaction state, user inputs and observable scenes independently of browser geometry.

Start with [MODEL.bend](MODEL.bend), [TYPES.bend](TYPES.bend), [STATE.bend](STATE.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

`TYPES.bend` defines the input, state and observation vocabulary. `STATE.bend`
owns the computations over those values; clients that exchange vocabulary do
not need to import its implementation.

[experience/README.md](experience/README.md) is the entry for object ownership,
property decisions, workspace membership and action identity. Presentation builds
controls through its operational constructors before browser interpretation.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../PROOF.bend) assembles the production evidence.

`submission_obstruction_access` observes the actual service prerequisite of an
application input. Its optional reason distinguishes connection from the owning
editor's pending file uploads. Admission derives its blocked status from the same
observation, and `control` combines that reason with intrinsic availability.
The service requirements bind submission and workspace retry to that editor's
uploads and the connection, confirmation to the connection, and direct commands
to their service dependency. Local actions require no connection.
`actual_control_observation` binds the complete observed control to this same
production observation.
