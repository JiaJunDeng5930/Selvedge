From Stdlib Require Import String.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import RemoteProtocol RemoteControl.
Open Scope string_scope.
Definition call operation source :=
 if String.eqb operation "control.remote.connector" then success (RemoteControl.connector_step (get source "state") (get source "event"))
 else if String.eqb operation "control.remote.current" then success (JBool (RemoteControl.current (get source "state") (get source "event")))
 else if String.eqb operation "control.remote.relay" then success (RemoteControl.relay_step (get source "state") (get source "event"))
 else if String.eqb operation "control.remote.relay_frame_allowed" then success (JBool (RemoteControl.relay_frame_allowed source))
 else if String.eqb operation "control.remote.host_current" then success (JBool (RemoteControl.relay_host_current source))
 else if String.eqb operation "control.remote.delivery" then success (JBool (RemoteControl.delivery_allowed source))
 else if String.eqb operation "control.remote.pairing" then success (RemoteControl.pairing_step (get source "state") (get source "event"))
 else let accepted:=
 if String.eqb operation "control.remote.host_frame" then RemoteProtocol.host_frame source
 else if String.eqb operation "control.remote.relay_frame" then RemoteProtocol.relay_frame source
 else if String.eqb operation "control.remote.controller_frame" then RemoteProtocol.controller_frame source
 else if String.eqb operation "control.remote.controller_request" then RemoteProtocol.controller_request source
 else if String.eqb operation "control.remote.response" then RemoteProtocol.response source
 else if String.eqb operation "control.remote.controller_id" then RemoteProtocol.controller source
 else false in success (JBool accepted).
