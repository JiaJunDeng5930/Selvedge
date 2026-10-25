From Stdlib Require Import String List Bool.
Import ListNotations.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import RemoteProtocol RemoteControl RelayAdmission.
From Selvedge.Foundation Require Import BoundedInteger.
From Selvedge.Adapters Require Import HostRemoteTransport.
Open Scope string_scope.
Definition call operation source :=
 if String.eqb operation "control.remote.safe_integer" then success (match source with
 | JString lexeme => match BoundedInteger.decode_safe_integer lexeme with Some value => JString (show_integer value) | None => JNull end
 | _ => JNull end)
 else if existsb (String.eqb operation) ["control.remote.transport_initial";"control.remote.transport";"control.remote.transport_current";"control.remote.transport_running";"control.remote.authorization_initial";"control.remote.authorization"] then HostRemoteTransport.call operation source
 else if existsb (String.eqb operation) ["control.remote.enrollment_credential";"control.remote.relay_route";"control.remote.relay_body";"control.remote.relay_credential";"control.remote.relay_content";"control.remote.relay_disconnect"] then success (RelayAdmission.call operation source)
 else if String.eqb operation "control.remote.connector_initial" then success (RemoteConnectorSession.state_json RemoteConnectorSession.initial)
 else if String.eqb operation "control.remote.connector" then
   match RemoteControl.connector_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid remote connector session observation" end
 else if String.eqb operation "control.remote.relay" then success (RemoteControl.relay_step (get source "state") (get source "event"))
 else if String.eqb operation "control.remote.relay_frame_allowed" then success (JBool (RemoteControl.relay_frame_allowed source))
 else if String.eqb operation "control.remote.host_current" then success (JBool (RemoteControl.relay_host_current source))
 else if String.eqb operation "control.remote.delivery" then success (JBool (RemoteControl.delivery_allowed source))
 else if String.eqb operation "control.remote.pairing" then
   match RemoteControl.pairing_step (get source "state") (get source "event") with Some value => success value
   | None => type_error "Invalid local remote pairing observation" end
 else let accepted:=
 if String.eqb operation "control.remote.host_frame" then RemoteProtocol.host_frame source
 else if String.eqb operation "control.remote.relay_frame" then RemoteProtocol.relay_frame source
 else if String.eqb operation "control.remote.controller_frame" then RemoteProtocol.controller_frame source
 else if String.eqb operation "control.remote.controller_request" then RemoteProtocol.controller_request source
 else if String.eqb operation "control.remote.response" then RemoteProtocol.response source
 else if String.eqb operation "control.remote.controller_id" then RemoteProtocol.controller source
 else false in success (JBool accepted).
