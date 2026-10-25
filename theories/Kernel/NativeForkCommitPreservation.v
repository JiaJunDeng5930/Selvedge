From Selvedge.Kernel Require Import State NativeForkCommit WorldInvariant DeferredCommitProofs.

Theorem native_fork_packets_preserve_world_requirements : forall before (plan : NativeForkCommit.plan before) raw,
 world_valid before = true -> world_valid (fst (NativeForkCommit.packet plan raw)) = true.
Proof.
 intros before plan raw Valid; unfold NativeForkCommit.packet.
 apply DeferredCommitProofs.packet_preserves_world_validity; exact Valid.
Qed.
