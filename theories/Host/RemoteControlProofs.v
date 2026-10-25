From Selvedge.Host Require Import RemoteConnectorSession RemoteRelaySession RemoteRelaySessionProofs.

(** The public wrappers expose these same typed steps. These trace properties
    constrain their real session states rather than arbitrary fabricated JSON. *)
Definition stale_connector_event_is_ignored := RemoteConnectorSession.stale_generation_is_ignored.
Definition relay_ticket_consumption_removes_identity := RemoteRelaySessionProofs.consumption_removes_ticket.
Definition stale_relay_generation_cannot_deliver := RemoteRelaySessionProofs.stale_generation_cannot_deliver.
Definition replaced_pairing_request_cannot_be_delivered := RemoteRelaySessionProofs.replaced_pairing_cannot_be_delivered.
