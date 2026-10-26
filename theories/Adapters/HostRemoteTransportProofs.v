From Stdlib Require Import NArith.
From Selvedge.Foundation Require Import Numbers NumbersProofs.
From Selvedge.Adapters Require Import HostRemoteTransport.
From Selvedge.Host Require Import RemoteTransport.

Theorem transport_state_wire_roundtrips : forall value,
 state_of (state_json value) = Some value.
Proof.
 destruct value; cbv beta iota zeta delta -[parse_natural show_natural].
 all: rewrite !natural_print_parse; reflexivity.
Qed.

Theorem authorization_state_wire_roundtrips : forall value,
 authorization_of (authorization_json value) = Some value.
Proof. destruct value; reflexivity. Qed.
