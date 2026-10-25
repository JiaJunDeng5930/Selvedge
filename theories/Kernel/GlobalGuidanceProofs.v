From Stdlib Require Import String Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain ContextUpdates Configuration.

Theorem global_snapshot_is_valid : forall source snapshot,
 ContextUpdates.global_guidance_snapshot source = Some snapshot ->
 ContextUpdates.valid_snapshot snapshot = true.
Proof.
 intros source snapshot Created; unfold ContextUpdates.global_guidance_snapshot in Created.
 destruct (string_field "path" source); [|discriminate].
 destruct (string_field "revision" source); [|discriminate].
 destruct (string_field "content" source); [|discriminate].
 unfold ContextUpdates.construct_snapshot in Created.
 destruct (ContextUpdates.valid_snapshot _) eqn:Valid; [|discriminate].
 inversion Created; subst; exact Valid.
Qed.

Theorem valid_global_instructions_has_snapshot : forall source,
 source <> JNull -> Configuration.valid_global_instructions source = true ->
 exists snapshot, ContextUpdates.global_guidance_snapshot source = Some snapshot /\
   ContextUpdates.valid_snapshot snapshot = true.
Proof.
 intros source Present Admitted.
 assert (Constructed : exists snapshot, ContextUpdates.global_guidance_snapshot source = Some snapshot).
 { unfold Configuration.valid_global_instructions in Admitted.
   destruct source; try contradiction;
   destruct (Schema.decode _ _) eqn:Shape; try discriminate;
   destruct (ContextUpdates.global_guidance_snapshot _) eqn:Created; try discriminate;
   eexists; reflexivity. }
 destruct Constructed as [snapshot Created]; exists snapshot; split; [exact Created|].
 eapply global_snapshot_is_valid; exact Created.
Qed.
