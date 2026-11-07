From Selvedge.Foundation Require Import RemoteIdentity.
From Selvedge.Foundation Require Import KeyedListProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import JsonProofs JsonObjectsProofs.
From Selvedge.Kernel Require Import Domain State Numbers Codec.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Remote.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.

Definition request_valid request :=
 Remote.controller_valid (Remote.controller request) && Remote.epoch_valid (Remote.epoch request) &&
 Remote.identifier_valid (Remote.request_id request) && Remote.payload_valid (Remote.intent request).

Definition granted_permissions (required granted : F.rights) : Prop :=
 (F.may_read required = true -> F.may_read granted = true) /\
 (F.may_control required = true -> F.may_control granted = true) /\
 (F.may_configure required = true -> F.may_configure granted = true) /\
 (F.may_approve required = true -> F.may_approve granted = true).

Lemma boolean_permission : forall required granted,
 (required = true -> granted = true) -> negb required || granted = true.
Proof. intros [] granted Covered; cbn; auto. Qed.

Lemma declared_permissions_are_allowed : forall required granted,
 granted_permissions required granted -> Remote.rights_allow required granted = true.
Proof.
 intros required granted [Read [Control [Configure Approve]]].
 unfold Remote.rights_allow. rewrite !andb_true_iff.
 repeat split; apply boolean_permission; assumption.
Qed.

(* A retained receipt requires current local authority. Denial needs an actual
   failed condition; diagnostic wording and competing failures have no priority
   in the access contract. *)
Inductive access_contract (required : F.rights) (controller : string) (epoch : N)
 (state : F.remote) : Remote.authorization -> Prop :=
| AccessDisabled : forall code reason, F.remote_enabled state = false ->
 access_contract required controller epoch state
   (Remote.Denied code reason)
| AccessInvalid : forall code reason,
 Remote.controller_valid controller && Remote.epoch_valid epoch = false ->
 access_contract required controller epoch state
   (Remote.Denied code reason)
| AccessRevoked : forall code reason,
 Remote.find_grant controller state = None ->
 access_contract required controller epoch state
   (Remote.Denied code reason)
| AccessExpired : forall code reason issued,
 Remote.find_grant controller state = Some issued ->
 N.eqb epoch (F.grant_epoch issued) = false ->
 access_contract required controller epoch state
   (Remote.Denied code reason)
| AccessForbidden : forall code reason issued,
 Remote.find_grant controller state = Some issued ->
 Remote.rights_allow required (F.grant_rights issued) = false ->
 access_contract required controller epoch state
   (Remote.Denied code reason)
| AccessAdmitted : forall issued, F.remote_enabled state = true ->
 Remote.controller_valid controller && Remote.epoch_valid epoch = true ->
 Remote.find_grant controller state = Some issued ->
 N.eqb epoch (F.grant_epoch issued) = true ->
 Remote.rights_allow required (F.grant_rights issued) = true ->
 access_contract required controller epoch state Remote.Admitted.

Theorem check_satisfies_complete_access_contract : forall required controller epoch state,
 access_contract required controller epoch state (Remote.check required controller epoch state).
Proof.
 intros required controller epoch state; unfold Remote.check.
 destruct (F.remote_enabled state) eqn:Enabled; cbn [negb].
 - destruct (Remote.controller_valid controller && Remote.epoch_valid epoch) eqn:Identity; cbn [negb].
   + destruct (Remote.find_grant controller state) as [issued|] eqn:Found.
     * destruct (N.eqb epoch (F.grant_epoch issued)) eqn:Generation; cbn [negb].
       -- destruct (Remote.rights_allow required (F.grant_rights issued)) eqn:Rights.
          ++ eapply AccessAdmitted; eassumption.
          ++ eapply AccessForbidden; eassumption.
       -- eapply AccessExpired; eassumption.
     * apply AccessRevoked; assumption.
   + apply AccessInvalid; assumption.
 - apply AccessDisabled; assumption.
Qed.

Inductive authorization_contract (required : F.rights) (request : Remote.request)
 (state : F.remote) : Remote.authorization -> Prop :=
| RequestDisabled : forall code reason, F.remote_enabled state = false ->
 authorization_contract required request state
   (Remote.Denied code reason)
| RequestInvalid : forall code reason, request_valid request = false ->
 authorization_contract required request state
   (Remote.Denied code reason)
| RequestAccessDenied : forall code reason,
 access_contract required (Remote.controller request) (Remote.epoch request) state (Remote.Denied code reason) ->
 authorization_contract required request state (Remote.Denied code reason)
| RequestAdmitted : F.remote_enabled state = true -> request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = true ->
 authorization_contract required request state Remote.Admitted
| RequestFull : forall code reason,
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = false ->
 authorization_contract required request state
   (Remote.Denied code reason)
| RequestReplay : forall receipt, F.remote_enabled state = true -> request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = Some receipt ->
 JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt) = true ->
 authorization_contract required request state (Remote.Replay (F.remote_reply receipt))
| RequestConflict : forall code reason receipt,
 find (Remote.key_matches request) (F.remote_receipts state) = Some receipt ->
 JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt) = false ->
 authorization_contract required request state
   (Remote.Denied code reason).

Theorem authorize_satisfies_complete_request_contract : forall required request state,
 authorization_contract required request state (Remote.authorize required request state).
Proof.
 intros required request state; unfold Remote.authorize.
 remember (Remote.check required (Remote.controller request) (Remote.epoch request) state)
   as checked eqn:Checked.
 assert (Access : access_contract required (Remote.controller request) (Remote.epoch request) state checked).
 { subst checked; apply check_satisfies_complete_access_contract. }
 destruct checked as [code reason| |reply].
 - apply RequestAccessDenied; assumption.
 - inversion Access as [| | | | |issued Enabled Identity Granted Epoch Allowed]; subst.
   destruct (Remote.identifier_valid (Remote.request_id request) && Remote.payload_valid (Remote.intent request)) eqn:Payload; cbn [negb].
   + assert (Valid : request_valid request = true).
     { unfold request_valid. rewrite Identity. exact Payload. }
     destruct (find (Remote.key_matches request) (F.remote_receipts state)) as [receipt|] eqn:Found.
     * destruct (JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt)) eqn:Intent.
       -- eapply RequestReplay; eassumption.
       -- eapply RequestConflict; eassumption.
     * destruct (N.of_nat (List.length (F.remote_receipts state)) <? 1024) eqn:Capacity.
       -- apply RequestAdmitted; assumption.
       -- apply RequestFull; assumption.
   + apply RequestInvalid. unfold request_valid. rewrite Identity. exact Payload.
 - inversion Access.
Qed.

(** The premises describe a current grant and an unused receipt coordinate,
    rather than assuming that authorization already succeeded. *)
Theorem current_grant_admits_fresh_remote_request : forall required request state issued,
 F.remote_enabled state = true ->
 request_valid request = true ->
 Remote.find_grant (Remote.controller request) state = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 granted_permissions required (F.grant_rights issued) ->
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = true ->
 Remote.authorize required request state = Remote.Admitted.
Proof.
 intros required request state issued Enabled Valid Granted Epoch Allowed Fresh Space.
 apply declared_permissions_are_allowed in Allowed.
 assert (Identity : Remote.controller_valid (Remote.controller request) &&
     Remote.epoch_valid (Remote.epoch request) = true).
 { unfold request_valid in Valid.
   apply andb_true_iff in Valid as [Valid _].
   now apply andb_true_iff in Valid as [Valid _]. }
 assert (Payload : Remote.identifier_valid (Remote.request_id request) &&
   Remote.payload_valid (Remote.intent request) = true).
 { unfold request_valid in Valid. rewrite Identity in Valid. exact Valid. }
 unfold Remote.authorize, Remote.check. rewrite Enabled, Identity. cbn.
 rewrite Granted, Epoch, N.eqb_refl, Allowed, Payload. cbn.
 now rewrite Fresh, Space.
Qed.

Lemma remote_registry_store : forall remote value,
 Remote.registry (Remote.store remote value) = remote.
Proof. intros remote [seq tasks ticket env projects features]. destruct features; reflexivity. Qed.

(** Disabled native grants cannot reach the command interpreter. *)
Theorem disabled_remote_cannot_execute : forall execute prepared configuration request command value,
 F.remote_enabled (Remote.registry value) = false ->
 let '(_,_,result) := Remote.execute_remote execute prepared configuration request command value in
 decision_world result = value /\ decision_effects result = [].
Proof.
 intros execute prepared configuration request command value disabled.
 unfold Remote.execute_remote.
 destruct (Remote.configuration_allowed command configuration); [|split;reflexivity].
 unfold Remote.authorize_command, Remote.with_command_rights.
 destruct (Remote.required_rights command) as [rights|] eqn:required; [|split;reflexivity].
 destruct (F.may_read rights); cbn beta iota zeta delta [andb negb].
 - unfold Remote.check. rewrite disabled. split;reflexivity.
 - unfold Remote.authorize, Remote.check. rewrite disabled. split;reflexivity.
Qed.

(** Preparation can introduce permission-requiring settings. A fresh request
    cannot execute or return a successful observation under those missing rights. *)
Theorem prepared_remote_permissions_are_required :
 forall execute prepared configuration request original value admitted required issued,
 G.admit prepared = Some admitted ->
 Remote.required_rights (G.admitted_value admitted) = Some required ->
 Remote.find_grant (Remote.controller request) (Remote.registry value) = Some issued ->
 Remote.rights_allow required (F.grant_rights issued) = false ->
 find (Remote.key_matches request) (F.remote_receipts (Remote.registry value)) = None ->
 let '(_,_,result) := Remote.execute_remote execute prepared configuration request original value in
 field "ok" (decision_reply result) = Some (JBool false) /\
 decision_world result = value /\ decision_effects result = [].
Proof.
 intros execute prepared configuration request original value admitted required issued
   Prepared Rights Granted Forbidden Fresh.
 unfold Remote.execute_remote.
 destruct (Remote.configuration_allowed original configuration); [|repeat split;reflexivity].
 remember (Remote.authorize_command original request (Remote.registry value)) as authorization eqn:Authorized.
 destruct authorization as [code reason| |reply].
 - repeat split;reflexivity.
 - rewrite Prepared; cbn beta iota zeta.
   destruct (Remote.configuration_allowed (G.admitted_value admitted) configuration); [|repeat split;reflexivity].
   destruct (String.eqb (command_name (G.declared_command original))
     (command_name (G.declared_command (G.admitted_value admitted)))); [|repeat split;reflexivity].
   unfold Remote.with_command_rights. rewrite Rights.
   unfold Remote.check.
   destruct (F.remote_enabled (Remote.registry value)); cbn [negb]; [|repeat split;reflexivity].
   destruct (Remote.controller_valid (Remote.controller request) && Remote.epoch_valid (Remote.epoch request));
     cbn [negb]; [|repeat split;reflexivity].
   rewrite Granted.
   destruct (N.eqb (Remote.epoch request) (F.grant_epoch issued)); cbn [negb].
   + rewrite Forbidden. repeat split;reflexivity.
   + repeat split;reflexivity.
 - exfalso. unfold Remote.authorize_command, Remote.with_command_rights in Authorized.
   destruct (Remote.required_rights original) as [original_rights|]; [|discriminate].
   destruct (F.may_read original_rights).
   + pose proof (check_satisfies_complete_access_contract original_rights
       (Remote.controller request) (Remote.epoch request) (Remote.registry value)) as Access.
     rewrite <- Authorized in Access. inversion Access.
   + pose proof (authorize_satisfies_complete_request_contract original_rights request
       (Remote.registry value)) as Access.
     rewrite <- Authorized in Access. inversion Access; subst; congruence.
Qed.

(** A replay returns its retained reply without running the interpreter again. *)
Theorem oversized_remote_reply_rolls_back : forall request before candidate,
 Remote.payload_valid (decision_reply candidate) = false ->
 decision_world (Remote.record_result request before candidate) = before /\
 decision_effects (Remote.record_result request before candidate) = [].
Proof. intros. unfold Remote.record_result. rewrite H. split;reflexivity. Qed.

(** Receipt insertion cannot change the grant generation or grant authority. *)
Theorem remote_receipt_preserves_authority : forall request before candidate,
 let current:=Remote.registry (decision_world (Remote.record_result request before candidate)) in
 F.remote_enabled current = F.remote_enabled (Remote.registry before) /\
 F.remote_grants current = F.remote_grants (Remote.registry before) /\
 F.remote_next_epoch current = F.remote_next_epoch (Remote.registry before).
Proof.
 intros request before candidate. cbv zeta. unfold Remote.record_result.
 destruct (Remote.payload_valid (decision_reply candidate)); cbn.
 - destruct (bool_default "ok" (decision_reply candidate) false); cbn;
   try rewrite remote_registry_store; repeat split;reflexivity.
 - repeat split;reflexivity.
Qed.

(** A task-owned execution cannot administer native remote grants. *)
Theorem delegated_remote_administration_is_denied : forall payload caller value,
 Remote.handle_remote_enable payload (Some caller) value = Remote.local_only value.
Proof. reflexivity. Qed.

(** Even an effectful supplied executor cannot mutate the world through a remote query. *)
Theorem remote_query_is_read_only : forall execute prepared configuration request command value,
 Remote.observation_command command=true ->
 let '(_,_,result):=Remote.execute_remote execute prepared configuration request command value in
 decision_world result=value /\ decision_effects result=[].
Proof.
 intros execute prepared configuration request command value readonly.
 unfold Remote.execute_remote. rewrite readonly.
 cbn beta iota zeta delta [negb].
 destruct (Remote.configuration_allowed command configuration); [|split;reflexivity].
 destruct (Remote.authorize_command command request (Remote.registry value)) as [code reason| |reply];
   try (split;reflexivity).
 destruct (G.admit prepared) as [admitted|]; [|split;reflexivity].
 set (prepared_command := G.admitted_value admitted).
 cbn beta iota zeta.
 destruct (Remote.configuration_allowed prepared_command configuration); [|split;reflexivity].
 destruct (String.eqb (command_name (G.declared_command command)) (command_name (G.declared_command prepared_command)));
   [|split;reflexivity].
 destruct (Remote.with_command_rights prepared_command
   (fun rights=>Remote.check rights (Remote.controller request) (Remote.epoch request)
     (Remote.registry value))); split;reflexivity.
Qed.

(** Successful public grants consume a fresh generation, including re-grants. *)
Theorem public_grant_issues_generation : forall payload value,
 let controller := proj1_sig (G.remote_grant_controller_id_admitted payload) in
 (F.remote_next_epoch (Remote.registry value) <=? RemoteIdentity.max_epoch)=true ->
 (match Remote.find_grant controller (Remote.registry value) with
 | Some _=>true | None=>N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end)=true ->
 exists result,
 Remote.handle_remote_grant payload None value=result /\
 F.remote_next_epoch (Remote.registry (decision_world result))=N.succ (F.remote_next_epoch (Remote.registry value)).
Proof.
 intros payload value controller Epoch capacity.
 unfold Remote.handle_remote_grant, Remote.admin_command, Remote.grant.
 fold controller. rewrite Epoch; cbn [negb]; rewrite capacity.
 eexists; split;[reflexivity|].
 cbn beta iota zeta delta [decision_world accept]. rewrite remote_registry_store. reflexivity.
Qed.

Theorem revocation_never_reuses_generation : forall controller value,
 F.remote_next_epoch (Remote.registry (decision_world (Remote.revoke controller value)))=
 F.remote_next_epoch (Remote.registry value).
Proof.
 intros. unfold Remote.revoke.
 cbn beta iota zeta delta [decision_world accept]. rewrite remote_registry_store. reflexivity.
Qed.

Lemma recorded_remote_registry : forall request before candidate,
 Remote.payload_valid (decision_reply candidate) = true ->
 Remote.registry (decision_world (Remote.record_result request before candidate)) =
 Remote.retain request (decision_reply candidate) (Remote.registry before).
Proof.
 intros request before candidate Bounded.
 unfold Remote.record_result. rewrite Bounded.
 destruct (bool_default "ok" (decision_reply candidate) false); cbn;
 apply remote_registry_store.
Qed.

(** The retained answer is reachable without assuming the Replay outcome. *)
Theorem retained_remote_result_is_replayable : forall required request before candidate issued,
 F.remote_enabled (Remote.registry before) = true ->
 request_valid request = true ->
 Remote.find_grant (Remote.controller request) (Remote.registry before) = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 granted_permissions required (F.grant_rights issued) ->
 Remote.payload_valid (decision_reply candidate) = true ->
 Remote.authorize required request
   (Remote.registry (decision_world (Remote.record_result request before candidate))) =
 Remote.Replay (decision_reply candidate).
Proof.
 intros required request before candidate issued Enabled Valid Granted Epoch Allowed Bounded.
 apply declared_permissions_are_allowed in Allowed.
 assert (Identity : Remote.controller_valid (Remote.controller request) &&
     Remote.epoch_valid (Remote.epoch request) = true).
 { unfold request_valid in Valid.
   apply andb_true_iff in Valid as [Valid _].
   now apply andb_true_iff in Valid as [Valid _]. }
 assert (Payload : Remote.identifier_valid (Remote.request_id request) &&
   Remote.payload_valid (Remote.intent request) = true).
 { unfold request_valid in Valid. rewrite Identity in Valid. exact Valid. }
 assert (Checked : Remote.check required (Remote.controller request) (Remote.epoch request)
     (Remote.registry before) = Remote.Admitted).
 { unfold Remote.check. rewrite Enabled, Identity. cbn.
   now rewrite Granted, Epoch, N.eqb_refl, Allowed. }
 rewrite recorded_remote_registry by exact Bounded.
 set (retained := Remote.retain request (decision_reply candidate) (Remote.registry before)).
 assert (StillChecked : Remote.check required (Remote.controller request) (Remote.epoch request)
     retained = Remote.Admitted) by exact Checked.
 unfold Remote.authorize. rewrite StillChecked, Payload. cbn [negb].
 cbn [retained Remote.retain Remote.key_matches].
 unfold Remote.key_matches. cbn.
 rewrite !String.eqb_refl, N.eqb_refl. cbn.
 now rewrite equivalent_is_reflexive.
Qed.

(** The public service probes before observing files or preparing configuration.
    The decoded envelope and command therefore bind a replay to the retained
    intent, while the grant generation still supplies its current authority. *)
Theorem remote_replay_has_no_effect : forall execute admitted required request before candidate issued,
 G.admit (Remote.intent request) = Some admitted ->
 Remote.required_rights (G.admitted_value admitted) = Some required ->
 F.may_read required = false ->
 F.remote_enabled (Remote.registry before) = true ->
 request_valid request = true ->
 Remote.find_grant (Remote.controller request) (Remote.registry before) = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 granted_permissions required (F.grant_rights issued) ->
 Remote.payload_valid (decision_reply candidate) = true ->
 let after := decision_world (Remote.record_result request before candidate) in
 exists reply,
 JsonObjects.equivalent reply
   (success (JObject [("replayed",JBool true);("reply",decision_reply candidate)])) = true /\
 (match field "result" reply with Some result => field "reply" result | None => None end) =
   Some (decision_reply candidate) /\
 Remote.complete_request execute false request Schema.FNil after =
 (false,false,Decision after reply []).
Proof.
 intros execute admitted required request before candidate issued
   Admitted Rights Mutation Enabled Valid Granted Epoch Allowed Bounded after.
 exists (success (JObject [("replayed",JBool true);("reply",decision_reply candidate)])).
 split; [apply equivalent_is_reflexive|].
 split; [reflexivity|].
 assert (Replay : Remote.authorize required request (Remote.registry after) =
     Remote.Replay (decision_reply candidate)).
 { unfold after. eapply retained_remote_result_is_replayable; eassumption. }
 assert (Authorized : Remote.authorize_command (G.admitted_value admitted) request (Remote.registry after) =
     Remote.Replay (decision_reply candidate)).
 { unfold Remote.authorize_command, Remote.with_command_rights.
   rewrite Rights. cbn. now rewrite Mutation. }
 unfold Remote.complete_request. rewrite Admitted; cbn beta iota zeta. now rewrite Authorized.
Qed.

Theorem revoked_remote_controller_cannot_replay : forall required controller epoch id intent value,
 let request := Remote.Request (ControllerId (proj1_sig controller)) epoch id intent in
 exists code reason,
 Remote.authorize required request
   (Remote.registry (decision_world (Remote.revoke controller value))) =
 Remote.Denied code reason.
Proof.
 intros required controller epoch id intent value request.
 set (after := decision_world (Remote.revoke controller value)).
 assert (Removed : Remote.find_grant (Remote.controller request) (Remote.registry after) = None).
 { unfold after, Remote.revoke. cbn.
   rewrite remote_registry_store. unfold Remote.find_grant. cbn.
   unfold Remote.remove_grants; apply removing_a_key_clears_its_lookup. }
 pose proof (authorize_satisfies_complete_request_contract required request (Remote.registry after)) as Authorized.
 destruct (Remote.authorize required request (Remote.registry after)) as [code reason| |reply].
 - now exists code, reason.
 - inversion Authorized; subst.
   match goal with Access : access_contract _ _ _ _ Remote.Admitted |- _ =>
     inversion Access; congruence end.
 - inversion Authorized; subst.
   match goal with Access : access_contract _ _ _ _ Remote.Admitted |- _ =>
     inversion Access; congruence end.
Qed.

Theorem local_grant_replaces_authority_and_clears_old_receipts :
 forall controller rights value,
 (F.remote_next_epoch (Remote.registry value) <=? RemoteIdentity.max_epoch) = true ->
 (match Remote.find_grant (proj1_sig controller) (Remote.registry value) with
 | Some _ => true | None => N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end) = true ->
 let previous := Remote.registry value in
 let issued := F.RemoteGrant (ControllerId (proj1_sig controller)) (GrantEpoch (F.remote_next_epoch previous)) rights in
 Remote.grant controller rights value =
 accept (Remote.grant_json issued)
   (Remote.store (F.Remote (F.remote_enabled previous)
     (issued :: Remote.remove_grants (proj1_sig controller) (F.remote_grants previous))
     (N.succ (F.remote_next_epoch previous))
     (Remote.remove_receipts (proj1_sig controller) (F.remote_receipts previous))) value) [].
Proof.
 intros controller rights value Epoch Capacity.
 unfold Remote.grant. rewrite Epoch; cbn [negb]; now rewrite Capacity.
Qed.

Theorem full_registry_rejects_a_new_controller : forall controller rights value,
 Remote.find_grant (proj1_sig controller) (Remote.registry value) = None ->
 (N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64) = false ->
 let result := Remote.grant controller rights value in
 field "ok" (decision_reply result) = Some (JBool false) /\
 decision_world result = value /\ decision_effects result = [].
Proof.
 intros controller rights value Absent Full; cbv zeta.
 unfold Remote.grant.
 destruct (F.remote_next_epoch (Remote.registry value) <=? RemoteIdentity.max_epoch); cbn [negb].
 - rewrite Absent, Full. repeat split; reflexivity.
 - repeat split; reflexivity.
Qed.

Lemma granting_never_reuses_a_generation : forall controller rights value,
 F.remote_next_epoch (Remote.registry value) <=
 F.remote_next_epoch (Remote.registry (decision_world (Remote.grant controller rights value))).
Proof.
 intros controller rights value; unfold Remote.grant.
 destruct (F.remote_next_epoch (Remote.registry value) <=? RemoteIdentity.max_epoch); cbn [negb]; try apply N.le_refl.
 destruct (match Remote.find_grant (proj1_sig controller) (Remote.registry value) with
   | Some _ => true | None => N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end);
   cbn [accept reject decision_world]; rewrite ?remote_registry_store; cbn;
   apply N.le_refl || apply N.le_succ_diag_r.
Qed.

Theorem local_administration_never_reuses_a_generation : forall caller value enable disable grant revoke,
 let advances := fun result => F.remote_next_epoch (Remote.registry value) <=
   F.remote_next_epoch (Remote.registry (decision_world result)) in
 advances (Remote.handle_remote_enable enable caller value) /\
 advances (Remote.handle_remote_disable disable caller value) /\
 advances (Remote.handle_remote_grant grant caller value) /\
 advances (Remote.handle_remote_revoke revoke caller value).
Proof.
 intros caller value enable disable grant revoke; cbv zeta.
 destruct caller; repeat split;
 try (change (F.remote_next_epoch (Remote.registry value) <= F.remote_next_epoch (Remote.registry value)); apply N.le_refl).
 apply granting_never_reuses_a_generation.
Qed.

Theorem exhausted_epoch_rejects_grant_without_changing_world : forall controller rights value,
 (F.remote_next_epoch (Remote.registry value) <=? RemoteIdentity.max_epoch) = false ->
 let result := Remote.grant controller rights value in
 field "ok" (decision_reply result) = Some (JBool false) /\
 decision_world result = value /\ decision_effects result = [].
Proof.
 intros controller rights value Exhausted; cbv zeta.
 unfold Remote.grant. rewrite Exhausted; repeat split; reflexivity.
Qed.
