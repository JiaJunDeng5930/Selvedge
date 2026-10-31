From Selvedge.Host Require Import RemoteConnectorSession RemoteRelaySession.

(** Wire codecs remain at this boundary; each rule has one typed owner. *)
Definition connector_step := RemoteConnectorSession.connector_step.
Definition pairing_step := RemoteConnectorSession.pairing_step.
Definition relay_step := RemoteRelaySession.relay_step.
Definition delivery_allowed := RemoteRelaySession.delivery_allowed.
Definition relay_host_current := RemoteRelaySession.relay_host_current.
Definition relay_frame_allowed := RemoteRelaySession.relay_frame_allowed.
Definition forward_request := RemoteRelaySession.forward_request.
Definition install_controller := RemoteRelaySession.install_controller.
