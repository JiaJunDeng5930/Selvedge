From Stdlib Require Import String List Bool.
Import ListNotations.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import RemoteConnectorSession RemoteRelaySession RelayAdmission.
From Selvedge.Foundation Require Import BoundedInteger.
From Selvedge.Adapters Require Import HostRemoteTransport.
Open Scope string_scope.
Definition session_result value := match value with
 | Some value => success value | None => type_error "Invalid remote relay session observation" end.
Definition session_verdict value := session_result (option_map JBool value).
Definition call operation source :=
 if String.eqb operation "control.remote.safe_integer" then success (match source with
 | JString lexeme => match BoundedInteger.decode_safe_integer lexeme with Some value => JString (show_integer (BoundedInteger.integer_value value)) | None => JNull end
 | _ => JNull end)
 else if existsb (String.eqb operation) ["control.remote.transport_initial";"control.remote.transport";"control.remote.transport_running";"control.remote.authorization_initial";"control.remote.authorization"] then HostRemoteTransport.call operation source
 else if existsb (String.eqb operation) ["control.remote.enrollment_credential";"control.remote.relay_route";"control.remote.relay_body";"control.remote.relay_credential";"control.remote.relay_content"] then success (RelayAdmission.call operation source)
 else if String.eqb operation "control.remote.connector_initial" then success (RemoteConnectorSession.state_json RemoteConnectorSession.initial)
 else if String.eqb operation "control.remote.connector" then
   match RemoteConnectorSession.connector_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid remote connector session observation" end
 else if String.eqb operation "control.remote.relay" then session_result (RemoteRelaySession.relay_step (get source "state") (get source "event"))
 else if String.eqb operation "control.remote.relay_frame_allowed" then success
   (match RemoteRelaySession.relay_frame_allowed source with Some value => value | None => JNull end)
 else if String.eqb operation "control.remote.relay_request" then success
   (match RemoteRelaySession.forward_request source with Some value => value | None => JNull end)
 else if String.eqb operation "control.remote.relay_controller" then session_result (RemoteRelaySession.install_controller source)
 else if String.eqb operation "control.remote.relay_disconnect" then session_result (RemoteRelaySession.disconnect source)
 else if String.eqb operation "control.remote.host_current" then session_verdict (RemoteRelaySession.relay_host_current source)
 else if String.eqb operation "control.remote.delivery" then session_verdict (RemoteRelaySession.delivery_allowed source)
 else if String.eqb operation "control.remote.pairing" then
   match RemoteConnectorSession.pairing_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid local remote pairing observation" end
 else success (JBool false).
