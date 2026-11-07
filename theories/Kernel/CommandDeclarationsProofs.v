From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Inputs InputDecoder Packet PacketProofs.
From Selvedge.Generated Require Commands.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.
Definition command_input source := JObject [("kind",JString "command");("command",source)].
Theorem malformed_commands_are_not_durable : forall source before,
 G.decode source = None ->
 field "durable" (snd (Packet.packet (command_input source) before)) = Some (JBool false).
Proof.
 intros source before Rejected.
 assert (Decoded : Packet.decode (command_input source) = None).
 { change (option_map (@inl Inputs.input (State.world -> bool * bool * State.decision)) (option_map UserCommand (G.decode source)) = None). rewrite Rejected; reflexivity. }
 assert (Ignored : fst (Packet.packet (command_input source) before) = before /\
   field "effects" (snd (Packet.packet (command_input source) before)) = Some (JArray []) /\
   field "durable" (snd (Packet.packet (command_input source) before)) = Some (JBool false)).
 { eapply PacketProofs.packet_keeps_an_ignored_nondurable_result.
   - rewrite Decoded; reflexivity.
   - reflexivity.
   - reflexivity. }
 exact (proj2 (proj2 Ignored)).
Qed.
