From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Services Resource.

Theorem disconnected_upload_retry_emits_no_effect state ticket:
 Services.connected state=false ->
 Services.service_step(Services.RetryUpload ticket)state=Services.keep state.
Proof. intro Offline. cbn[Services.service_step]. unfold Services.retry_upload. rewrite Offline. reflexivity. Qed.
Theorem stale_connection_receipt_cannot_change_its_owner state incoming current request outcome:
 Services.connection state=Resource.Loading current request -> incoming<>current ->
 Services.connection(Services.service_state(Services.service_step(Services.Authenticated incoming outcome)state))=
 Services.connection state.
Proof.
 intros Connection Different. cbn[Services.service_step]. unfold Services.auth_result. rewrite Connection.
 apply N.eqb_neq in Different. rewrite Different. change(Services.connection state=Resource.Loading current request). exact Connection.
Qed.
