From Selvedge.Host Require Import RemoteConnectorSession RemoteRelaySession.

(** Wire codecs remain at this boundary; each rule has one typed owner. *)
Definition connector_step := RemoteConnectorSession.connector_step.
Definition pairing_step := RemoteConnectorSession.pairing_step.
Definition relay_step := RemoteRelaySession.relay_step.
Definition ticket_current := RemoteRelaySession.ticket_current.
Definition delivery_allowed := RemoteRelaySession.delivery_allowed.
Definition relay_host_current := RemoteRelaySession.relay_host_current.
Definition relay_frame_allowed := RemoteRelaySession.relay_frame_allowed.
