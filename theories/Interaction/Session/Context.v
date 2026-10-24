From Stdlib Require Import String.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import DocumentState Services.
From Selvedge.Interaction.Session Require State Navigation.
Definition document_context (namespace:string)(snapshot:json)(state:State.state):DocumentState.context:=
 DocumentState.DocumentContext namespace snapshot(Navigation.visible_task_views state)
 (Navigation.shared_occurrence state)(State.active_work(State.navigation_state state))
 (State.stream_state state)(Services.connected(State.service_state state))
 (Services.connection_revoked(Services.connection(State.service_state state))).
