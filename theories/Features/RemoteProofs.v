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
