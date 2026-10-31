From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Services.
From Selvedge.Programming Require Resource.

Theorem disconnected_upload_retry_emits_no_effect state ticket:
 Services.connected state=false ->
 Services.service_step(Services.RetryUpload ticket)state=Services.keep state.
Proof. intro Offline. cbn[Services.service_step]. unfold Services.retry_upload. rewrite Offline. reflexivity. Qed.
Theorem stale_connection_receipt_cannot_change_its_owner state incoming current outcome:
 Services.connection state=Services.ConnectionLoading current -> incoming<>current ->
 Services.connection(Services.service_state(Services.service_step(Services.Authenticated incoming outcome)state))=
 Services.connection state.
Proof.
 intros Connection Different. cbn[Services.service_step]. unfold Services.auth_result. rewrite Connection.
 apply N.eqb_neq in Different. rewrite Different. exact Connection.
Qed.

Theorem revoked_disconnect_is_retained state ticket reason:
 Services.connection state=Services.ConnectionReady ticket ->
 Services.connection(Services.service_state
   (Services.service_step(Services.Disconnected ticket reason true)state))=
 Services.ConnectionRevoked ticket reason.
Proof.
 intro Ready. cbn[Services.service_step]. unfold Services.connection_ticket_matches,Services.connection_matches,
   Services.connection_ticket. rewrite Ready. cbn. rewrite N.eqb_refl. reflexivity.
Qed.

Theorem rejected_disconnect_receipt_is_ignored state ticket reason revoked:
 Services.connection_active(Services.connection state)&&
   Services.connection_ticket_matches ticket(Services.connection state)=false ->
 Services.service_step(Services.Disconnected ticket reason revoked)state=Services.keep state.
Proof.
 intro Rejected. cbn[Services.service_step]. rewrite Rejected. reflexivity.
Qed.
