From Stdlib Require Import String List Bool.
Import ListNotations.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import RemoteProtocol RemoteControl RelayAdmission.
From Selvedge.Foundation Require Import BoundedInteger.
From Selvedge.Adapters Require Import HostRemoteTransport.
Open Scope string_scope.
Definition admit_wire {A : Type} (decode : json -> option A) (project : A -> json) source :=
 success (match decode source with Some value => project value | None => JNull end).
Definition session_result value := match value with
 | Some value => success value | None => type_error "Invalid remote relay session observation" end.
Definition session_verdict value := session_result (option_map JBool value).
Definition call operation source :=
 if String.eqb operation "control.remote.safe_integer" then success (match source with
 | JString lexeme => match BoundedInteger.decode_safe_integer lexeme with Some value => JString (show_integer (BoundedInteger.integer_value value)) | None => JNull end
 | _ => JNull end)
 else if existsb (String.eqb operation) ["control.remote.transport_initial";"control.remote.transport";"control.remote.transport_current";"control.remote.transport_running";"control.remote.authorization_initial";"control.remote.authorization"] then HostRemoteTransport.call operation source
 else if existsb (String.eqb operation) ["control.remote.enrollment_credential";"control.remote.relay_route";"control.remote.relay_body";"control.remote.relay_credential";"control.remote.relay_content"] then success (RelayAdmission.call operation source)
 else if String.eqb operation "control.remote.connector_initial" then success (RemoteConnectorSession.state_json RemoteConnectorSession.initial)
 else if String.eqb operation "control.remote.connector" then
   match RemoteControl.connector_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid remote connector session observation" end
 else if String.eqb operation "control.remote.relay" then session_result (RemoteControl.relay_step (get source "state") (get source "event"))
 else if String.eqb operation "control.remote.relay_frame_allowed" then success
   (match RemoteControl.relay_frame_allowed source with Some value => value | None => JNull end)
 else if String.eqb operation "control.remote.relay_request" then success
   (match RemoteControl.forward_request source with Some value => value | None => JNull end)
 else if String.eqb operation "control.remote.relay_controller" then session_result (RemoteControl.install_controller source)
 else if String.eqb operation "control.remote.relay_disconnect" then session_result (RemoteRelaySession.disconnect source)
 else if String.eqb operation "control.remote.host_current" then session_verdict (RemoteControl.relay_host_current source)
 else if String.eqb operation "control.remote.delivery" then session_verdict (RemoteControl.delivery_allowed source)
 else if String.eqb operation "control.remote.pairing" then
   match RemoteControl.pairing_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid local remote pairing observation" end
 else if String.eqb operation "control.remote.host_frame" then admit_wire RemoteProtocol.decode_host_frame RemoteProtocol.encode_host_frame source
 else if String.eqb operation "control.remote.relay_frame" then admit_wire RemoteProtocol.decode_relay_frame RemoteProtocol.encode_relay_frame source
 else if String.eqb operation "control.remote.controller_frame" then admit_wire RemoteProtocol.decode_controller_frame RemoteProtocol.encode_controller_frame source
 else if String.eqb operation "control.remote.controller_request" then admit_wire RemoteProtocol.decode_controller_request RemoteProtocol.encode_controller_request source
 else if String.eqb operation "control.remote.response" then admit_wire RemoteProtocol.decode_response RemoteProtocol.encode_response source
 else if String.eqb operation "control.remote.controller_id" then success (JBool (RemoteProtocol.controller source))
 else success (JBool false).
