# Remote control

This component owns local remote-control grants, grant generations, authorization,
and retained command receipts. It does not execute tasks or authenticate a network
transport. The host supplies the authenticated controller identity; harness
composition derives required rights from the decoded command and commits the
receipt in the same native decision as that command.

Start with [MODEL.bend](MODEL.bend), then [SPEC.bend](SPEC.bend) for complete
operation meanings and [PROGRAM.bend](PROGRAM.bend) for production operations.
[CODEC.bend](CODEC.bend) owns administrative command schemas and encoding. [CONTRACT.bend](CONTRACT.bend) and
[PROOF.bend](PROOF.bend) bind complete refinement and state preservation to the
actual operations. Administrative operations are local-only at the assembly
boundary. A grant generation is never reused, including after revocation.
