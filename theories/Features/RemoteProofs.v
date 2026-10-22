From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonProofs JsonObjectsProofs.
From Selvedge.Kernel Require Import Domain State Numbers Codec.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Remote.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.

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

(* A retained receipt is considered only after the current local authority has
   admitted the controller. Each constructor records one complete outcome. *)
Inductive access_contract (required : F.rights) (controller : string) (epoch : N)
 (state : F.remote) : Remote.authorization -> Prop :=
| AccessDisabled : F.remote_enabled state = false ->
 access_contract required controller epoch state
   (Remote.Denied "remote_disabled" "Remote control is disabled on this host")
| AccessInvalid : F.remote_enabled state = true ->
 Remote.identifier_valid controller && (0 <? epoch) = false ->
 access_contract required controller epoch state
   (Remote.Denied "remote_invalid_request" "Remote request identity or intent exceeds the current protocol bounds")
| AccessRevoked : F.remote_enabled state = true ->
 Remote.identifier_valid controller && (0 <? epoch) = true ->
 Remote.find_grant controller state = None ->
 access_contract required controller epoch state
   (Remote.Denied "remote_controller_revoked" "This controller has no active local grant")
| AccessExpired : forall issued, F.remote_enabled state = true ->
 Remote.identifier_valid controller && (0 <? epoch) = true ->
 Remote.find_grant controller state = Some issued ->
 N.eqb epoch (F.grant_epoch issued) = false ->
 access_contract required controller epoch state
   (Remote.Denied "remote_grant_expired" "This device grant generation is no longer current")
| AccessForbidden : forall issued, F.remote_enabled state = true ->
 Remote.identifier_valid controller && (0 <? epoch) = true ->
 Remote.find_grant controller state = Some issued ->
 N.eqb epoch (F.grant_epoch issued) = true ->
 Remote.rights_allow required (F.grant_rights issued) = false ->
 access_contract required controller epoch state
   (Remote.Denied "remote_permission_denied" "This device grant does not permit this operation")
| AccessAdmitted : forall issued, F.remote_enabled state = true ->
 Remote.identifier_valid controller && (0 <? epoch) = true ->
 Remote.find_grant controller state = Some issued ->
 N.eqb epoch (F.grant_epoch issued) = true ->
 Remote.rights_allow required (F.grant_rights issued) = true ->
 access_contract required controller epoch state Remote.Admitted.

Theorem check_satisfies_complete_access_contract : forall required controller epoch state,
 access_contract required controller epoch state (Remote.check required controller epoch state).
Proof.
 intros required controller epoch state; unfold Remote.check.
 destruct (F.remote_enabled state) eqn:Enabled; cbn [negb].
 - destruct (Remote.identifier_valid controller && (0 <? epoch)) eqn:Identity; cbn [negb].
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
| RequestDisabled : F.remote_enabled state = false ->
 authorization_contract required request state
   (Remote.Denied "remote_disabled" "Remote control is disabled on this host")
| RequestInvalid : F.remote_enabled state = true -> Remote.request_valid request = false ->
 authorization_contract required request state
   (Remote.Denied "remote_invalid_request" "Remote request identity or intent exceeds the current protocol bounds")
| RequestAccessDenied : forall code reason, F.remote_enabled state = true ->
 Remote.request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state (Remote.Denied code reason) ->
 authorization_contract required request state (Remote.Denied code reason)
| RequestAdmitted : F.remote_enabled state = true -> Remote.request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = true ->
 authorization_contract required request state Remote.Admitted
| RequestFull : F.remote_enabled state = true -> Remote.request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = false ->
 authorization_contract required request state
   (Remote.Denied "remote_receipts_full" "Retained command receipts are full; revoke or replace this device grant before issuing a new request")
| RequestReplay : forall receipt, F.remote_enabled state = true -> Remote.request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = Some receipt ->
 JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt) = true ->
 authorization_contract required request state (Remote.Replay (F.remote_reply receipt))
| RequestConflict : forall receipt, F.remote_enabled state = true -> Remote.request_valid request = true ->
 access_contract required (Remote.controller request) (Remote.epoch request) state Remote.Admitted ->
 find (Remote.key_matches request) (F.remote_receipts state) = Some receipt ->
 JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt) = false ->
 authorization_contract required request state
   (Remote.Denied "remote_request_conflict" "This request ID was already committed with different intent").

Theorem authorize_satisfies_complete_request_contract : forall required request state,
 authorization_contract required request state (Remote.authorize required request state).
Proof.
 intros required request state; unfold Remote.authorize.
 destruct (F.remote_enabled state) eqn:Enabled; cbn [negb].
 - destruct (Remote.request_valid request) eqn:Valid; cbn [negb].
   + remember (Remote.check required (Remote.controller request) (Remote.epoch request) state)
       as checked eqn:Checked.
     assert (Access : access_contract required (Remote.controller request) (Remote.epoch request) state checked).
     { subst checked; apply check_satisfies_complete_access_contract. }
     destruct checked as [code reason| |reply].
     * apply RequestAccessDenied; assumption.
     * destruct (find (Remote.key_matches request) (F.remote_receipts state)) as [receipt|] eqn:Found.
       -- destruct (JsonObjects.equivalent (Remote.intent request) (F.remote_intent receipt)) eqn:Intent.
          ++ eapply RequestReplay; eassumption.
          ++ eapply RequestConflict; eassumption.
       -- destruct (N.of_nat (List.length (F.remote_receipts state)) <? 1024) eqn:Capacity.
          ++ apply RequestAdmitted; assumption.
          ++ apply RequestFull; assumption.
     * inversion Access.
   + apply RequestInvalid; assumption.
 - apply RequestDisabled; assumption.
Qed.

Theorem initial_remote_is_valid : Remote.valid (F.feature_remote F.initial) = true.
Proof. reflexivity. Qed.

(** The premises describe a current grant and an unused receipt coordinate,
    rather than assuming that authorization already succeeded. *)
Theorem current_grant_admits_fresh_remote_request : forall required request state issued,
 F.remote_enabled state = true ->
 Remote.request_valid request = true ->
 Remote.find_grant (Remote.controller request) state = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 granted_permissions required (F.grant_rights issued) ->
 find (Remote.key_matches request) (F.remote_receipts state) = None ->
 (N.of_nat (List.length (F.remote_receipts state)) <? 1024) = true ->
 Remote.authorize required request state = Remote.Admitted.
Proof.
 intros required request state issued Enabled Valid Granted Epoch Allowed Fresh Space.
 apply declared_permissions_are_allowed in Allowed.
 assert (Identity : Remote.identifier_valid (Remote.controller request) &&
     (0 <? Remote.epoch request) = true).
 { unfold Remote.request_valid in Valid.
   apply andb_true_iff in Valid as [Valid _].
   now apply andb_true_iff in Valid as [Valid _]. }
 unfold Remote.authorize. rewrite Enabled, Valid. cbn.
 unfold Remote.check. rewrite Enabled, Identity. cbn.
 rewrite Granted, Epoch, N.eqb_refl, Allowed. cbn.
 now rewrite Fresh, Space.
Qed.

Lemma remote_registry_store : forall remote value,
 Remote.registry (Remote.store remote value) = remote.
Proof. intros remote [seq tasks ticket env projects features]. destruct features; reflexivity. Qed.

(** Disabled native grants cannot reach the command interpreter. *)
Theorem disabled_remote_cannot_execute : forall execute source request command value,
 F.remote_enabled (Remote.registry value) = false ->
 let '(_,_,result) := Remote.execute_remote execute source request command value in
 decision_world result = value /\ decision_effects result = [].
Proof.
 intros execute source request command value disabled.
 unfold Remote.execute_remote,Remote.authorize_command.
 destruct (Remote.required_rights command) as [rights|] eqn:required; [|split;reflexivity].
 unfold Remote.observation_command. rewrite required.
 destruct (F.may_read rights); cbn.
 - unfold Remote.check. rewrite disabled. split;reflexivity.
 - unfold Remote.authorize. rewrite disabled. split;reflexivity.
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
 Remote.command (G.Cmd_remote_enable payload) (Some caller) value = Some (Remote.local_only value).
Proof. reflexivity. Qed.

(** Even an effectful supplied executor cannot mutate the world through a remote query. *)
Theorem remote_query_is_read_only : forall execute source request command value,
 Remote.observation_command command=true ->
 let '(_,_,result):=Remote.execute_remote execute source request command value in
 decision_world result=value /\ decision_effects result=[].
Proof.
 intros execute source request command value readonly.
 unfold Remote.execute_remote. rewrite readonly.
 cbn beta iota zeta delta [negb].
 destruct (Remote.authorize_command true command request (Remote.registry value)) as [code reason| |reply];
   try (split;reflexivity).
 destruct (field "command" source) as [prepared|]; [|split;reflexivity].
 destruct (G.decode prepared) as [prepared_command|]; [|split;reflexivity].
 destruct (String.eqb (command_name (G.declared_command command)) (command_name (G.declared_command prepared_command)));
   [|split;reflexivity].
 destruct (Remote.authorize_command true prepared_command request (Remote.registry value)); split;reflexivity.
Qed.

(** Successful public grants consume a fresh generation, including re-grants. *)
Theorem public_grant_issues_generation : forall controller permissions rights value,
 Remote.identifier_valid controller=true -> Remote.parse_rights permissions=Some rights ->
 (match Remote.find_grant controller (Remote.registry value) with
 | Some _=>true | None=>N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end)=true ->
 exists result,
 Remote.command (G.Cmd_remote_grant (G.Build_remote_grant controller permissions)) None value=Some result /\
 F.remote_next_epoch (Remote.registry (decision_world result))=N.succ (F.remote_next_epoch (Remote.registry value)).
Proof.
 intros controller permissions rights value valid parsed capacity.
 change (Remote.command (G.Cmd_remote_grant (G.Build_remote_grant controller permissions)) None value)
   with (Some (Remote.grant controller permissions value)).
 unfold Remote.grant. rewrite valid.
 cbn beta iota zeta delta [negb]. rewrite parsed,capacity.
 eexists; split;[reflexivity|].
 cbn beta iota zeta delta [decision_world accept]. rewrite remote_registry_store. reflexivity.
Qed.

Theorem revocation_never_reuses_generation : forall controller value,
 F.remote_next_epoch (Remote.registry (decision_world (Remote.revoke controller value)))=
 F.remote_next_epoch (Remote.registry value).
Proof.
 intros. unfold Remote.revoke. destruct (negb (Remote.identifier_valid controller)).
 - reflexivity.
 - cbn beta iota zeta delta [decision_world accept]. rewrite remote_registry_store. reflexivity.
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
 Remote.request_valid request = true ->
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
 assert (Identity : Remote.identifier_valid (Remote.controller request) &&
     (0 <? Remote.epoch request) = true).
 { unfold Remote.request_valid in Valid.
   apply andb_true_iff in Valid as [Valid _].
   now apply andb_true_iff in Valid as [Valid _]. }
 assert (Checked : Remote.check required (Remote.controller request) (Remote.epoch request)
     (Remote.registry before) = Remote.Admitted).
 { unfold Remote.check. rewrite Enabled, Identity. cbn.
   now rewrite Granted, Epoch, N.eqb_refl, Allowed. }
 rewrite recorded_remote_registry by exact Bounded.
 set (retained := Remote.retain request (decision_reply candidate) (Remote.registry before)).
 assert (StillEnabled : F.remote_enabled retained = true) by exact Enabled.
 assert (StillChecked : Remote.check required (Remote.controller request) (Remote.epoch request)
     retained = Remote.Admitted) by exact Checked.
 unfold Remote.authorize. rewrite StillEnabled, Valid. cbn. rewrite StillChecked.
 cbn [retained Remote.retain Remote.key_matches].
 unfold Remote.key_matches. cbn.
 rewrite !String.eqb_refl, N.eqb_refl. cbn.
 now rewrite equivalent_is_reflexive.
Qed.

(** A retained response constrains the real dispatch entry: its reply and lack
    of new effects do not depend on the supplied executor. *)
Theorem remote_replay_has_no_effect : forall execute source command required request before candidate issued,
 Remote.required_rights command = Some required ->
 F.may_read required = false ->
 F.remote_enabled (Remote.registry before) = true ->
 Remote.request_valid request = true ->
 Remote.find_grant (Remote.controller request) (Remote.registry before) = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 granted_permissions required (F.grant_rights issued) ->
 Remote.payload_valid (decision_reply candidate) = true ->
 let after := decision_world (Remote.record_result request before candidate) in
 Remote.execute_remote execute source request command after =
 (true,false,Decision after (decision_reply candidate) []).
Proof.
 intros execute source command required request before candidate issued
   Rights Mutation Enabled Valid Granted Epoch Allowed Bounded after.
 assert (Replay : Remote.authorize required request (Remote.registry after) =
     Remote.Replay (decision_reply candidate)).
 { unfold after. eapply retained_remote_result_is_replayable; eassumption. }
 assert (Authorized : Remote.authorize_command true command request (Remote.registry after) =
     Remote.Replay (decision_reply candidate)).
 { unfold Remote.authorize_command, Remote.observation_command.
   rewrite Rights. cbn. now rewrite Mutation. }
 unfold Remote.execute_remote. rewrite Authorized. cbn.
 unfold Remote.observation_command. now rewrite Rights, Mutation.
Qed.

Lemma removed_remote_controller_is_absent : forall controller grants,
 find (fun grant => String.eqb controller (F.grant_controller grant))
   (Remote.remove_grants controller grants) = None.
Proof.
 intros controller grants. induction grants as [|grant rest IH]; cbn [Remote.remove_grants].
 - reflexivity.
 - destruct (String.eqb controller (F.grant_controller grant)) eqn:Same; cbn;
   rewrite Same; cbn; try rewrite Same; exact IH.
Qed.

Theorem revoked_remote_controller_cannot_replay : forall required request value,
 F.remote_enabled (Remote.registry value) = true ->
 Remote.request_valid request = true ->
 Remote.authorize required request
   (Remote.registry (decision_world (Remote.revoke (Remote.controller request) value))) =
 Remote.Denied "remote_controller_revoked" "This controller has no active local grant".
Proof.
 intros required request value Enabled Valid.
 assert (Identity : Remote.identifier_valid (Remote.controller request) &&
     (0 <? Remote.epoch request) = true).
 { unfold Remote.request_valid in Valid.
   apply andb_true_iff in Valid as [Valid _].
   now apply andb_true_iff in Valid as [Valid _]. }
 pose proof Identity as Identifier. apply andb_true_iff in Identifier as [Identifier _].
 set (after := decision_world (Remote.revoke (Remote.controller request) value)).
 assert (StillEnabled : F.remote_enabled (Remote.registry after) = true).
 { unfold after, Remote.revoke. rewrite Identifier. cbn.
   rewrite remote_registry_store. exact Enabled. }
 assert (Removed : Remote.find_grant (Remote.controller request) (Remote.registry after) = None).
 { unfold after, Remote.revoke. rewrite Identifier. cbn.
   rewrite remote_registry_store. unfold Remote.find_grant. cbn.
   apply removed_remote_controller_is_absent. }
 unfold Remote.authorize. rewrite StillEnabled, Valid. cbn.
 unfold Remote.check. rewrite StillEnabled, Identity. cbn. now rewrite Removed.
Qed.

Theorem local_grant_replaces_authority_and_clears_old_receipts :
 forall controller permissions rights value,
 Remote.identifier_valid controller = true -> Remote.parse_rights permissions = Some rights ->
 (match Remote.find_grant controller (Remote.registry value) with
 | Some _ => true | None => N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end) = true ->
 let previous := Remote.registry value in
 let issued := F.RemoteGrant controller (F.remote_next_epoch previous) rights in
 Remote.grant controller permissions value =
 accept (Remote.grant_json issued)
   (Remote.store (F.Remote (F.remote_enabled previous)
     (issued :: Remote.remove_grants controller (F.remote_grants previous))
     (N.succ (F.remote_next_epoch previous))
     (Remote.remove_receipts controller (F.remote_receipts previous))) value) [].
Proof.
 intros controller permissions rights value Identifier Permissions Capacity.
 unfold Remote.grant; rewrite Identifier, Permissions; cbn [negb].
 now rewrite Capacity.
Qed.

Theorem full_registry_rejects_a_new_controller : forall controller permissions rights value,
 Remote.identifier_valid controller = true -> Remote.parse_rights permissions = Some rights ->
 Remote.find_grant controller (Remote.registry value) = None ->
 (N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64) = false ->
 Remote.grant controller permissions value =
 reject "remote_grants_full" "At most 64 controllers can be granted; revoke an existing controller first" value.
Proof.
 intros controller permissions rights value Identifier Permissions Absent Full.
 unfold Remote.grant; rewrite Identifier, Permissions; cbn [negb].
 now rewrite Absent, Full.
Qed.

Lemma granting_never_reuses_a_generation : forall controller permissions value,
 F.remote_next_epoch (Remote.registry value) <=
 F.remote_next_epoch (Remote.registry (decision_world (Remote.grant controller permissions value))).
Proof.
 intros controller permissions value; unfold Remote.grant.
 destruct (Remote.identifier_valid controller); cbn [negb].
 - destruct (Remote.parse_rights permissions) as [rights|].
   + destruct (match Remote.find_grant controller (Remote.registry value) with
       | Some _ => true | None => N.of_nat (List.length (F.remote_grants (Remote.registry value))) <? 64 end);
       cbn [accept reject decision_world]; rewrite ?remote_registry_store; cbn;
       apply N.le_refl || apply N.le_succ_diag_r.
   + apply N.le_refl.
 - apply N.le_refl.
Qed.

Theorem local_administration_never_reuses_a_generation : forall command caller value result,
 Remote.command command caller value = Some result ->
 F.remote_next_epoch (Remote.registry value) <=
 F.remote_next_epoch (Remote.registry (decision_world result)).
Proof.
 intros command caller value result Handled.
 unfold Remote.command in Handled; destruct command; cbn in Handled; try discriminate.
 all: destruct caller; inversion Handled; subst result;
   try (change (F.remote_next_epoch (Remote.registry value) <= F.remote_next_epoch (Remote.registry value));
        apply N.le_refl).
 - apply granting_never_reuses_a_generation.
 - rewrite revocation_never_reuses_generation; apply N.le_refl.
Qed.
