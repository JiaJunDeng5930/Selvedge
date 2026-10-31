From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Inputs InputDecoder Packet.
From Selvedge.Generated Require Commands.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.
Definition command_input source := JObject [("kind",JString "command");("command",source)].
Theorem malformed_commands_are_not_durable : forall source before,
 G.decode source = None ->
 let '(durable,_,_,_) := Packet.transition (command_input source) before in durable = false.
Proof.
 intros source before Rejected.
 assert (Decoded : Packet.decode (command_input source) = None).
 { change (option_map (@inl Inputs.input (State.world -> bool * bool * State.decision)) (option_map UserCommand (G.decode source)) = None). rewrite Rejected; reflexivity. }
 unfold Packet.transition; rewrite Decoded.
 reflexivity.
Qed.
