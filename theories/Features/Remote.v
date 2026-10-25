From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects Schema TextJson Utf8 RemoteIdentity.
From Selvedge.Kernel Require Import Domain State Numbers Codec Configuration Scheduler Commands.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.
Module KCommands := Selvedge.Kernel.Commands.

Definition registry value := Selvedge.Features.Domain.feature_remote (world_features value).
Definition store replacement value := with_features (Selvedge.Features.State.with_remote replacement (world_features value)) value.
Definition identifier_valid := RemoteIdentity.request_valid.
Definition controller_valid := RemoteIdentity.controller_valid.
Definition epoch_valid := RemoteIdentity.epoch_valid.
Definition payload_valid source := N.of_nat (String.length (TextJson.render_json source)) <=? 65536.
Definition find_grant controller state := find (fun grant => String.eqb controller (Selvedge.Features.Domain.grant_controller grant)) (Selvedge.Features.Domain.remote_grants state).
Definition remove_grants controller := filter (fun grant => negb (String.eqb controller (Selvedge.Features.Domain.grant_controller grant))).
Definition remove_receipts controller := filter (fun receipt => negb (String.eqb controller (Selvedge.Features.Domain.remote_controller receipt))).
Definition rights_json rights := JObject [("read",JBool (Selvedge.Features.Domain.may_read rights));("control",JBool (Selvedge.Features.Domain.may_control rights));
 ("configure",JBool (Selvedge.Features.Domain.may_configure rights));("approve",JBool (Selvedge.Features.Domain.may_approve rights))].
Definition grant_json grant := JObject [("controller_id",JString (Selvedge.Features.Domain.grant_controller grant));
 ("grant_epoch",number (Selvedge.Features.Domain.grant_epoch grant));("permissions",rights_json (Selvedge.Features.Domain.grant_rights grant))].
Definition status state := JObject [("enabled",JBool (Selvedge.Features.Domain.remote_enabled state));
 ("grants",JArray (map grant_json (Selvedge.Features.Domain.remote_grants state)));
 ("receipt_count",number (N.of_nat (List.length (Selvedge.Features.Domain.remote_receipts state))));("receipt_limit",number 1024)].
Definition rights_schema := [Field "read" KBool;Field "control" KBool;Field "configure" KBool;Field "approve" KBool].
Definition parse_rights source := match Schema.decode rights_schema source,
 bool_field "read" source,bool_field "control" source,bool_field "configure" source,bool_field "approve" source with
 | Some _,Some read,Some control,Some configure,Some approve => Some (Selvedge.Features.Domain.Rights read control configure approve)
 | _,_,_,_,_ => None end.
Definition local_only value := reject "remote_local_only" "Remote administration is available only to the local owner" value.
Definition admin_enabled enabled value :=
 let state:=registry value in
 let state:=Selvedge.Features.Domain.Remote enabled (Selvedge.Features.Domain.remote_grants state) (Selvedge.Features.Domain.remote_next_epoch state) (Selvedge.Features.Domain.remote_receipts state) in
 accept (status state) (store state value) [].
Definition grant controller rights value :=
 let state:=registry value in
 if negb (controller_valid controller) then reject "remote_invalid_controller" "Controller identity must contain exactly 64 lowercase hexadecimal characters" value
 else match parse_rights rights with
 | None => reject "invalid_input" "Remote permissions require exactly four Boolean fields" value
 | Some rights =>
   if negb (remote_next_epoch state <=? RemoteIdentity.max_epoch) then
     reject "remote_epochs_exhausted" "Remote grant epochs are exhausted" value else
   if match find_grant controller state with Some _=>true | None=>N.of_nat (List.length (Selvedge.Features.Domain.remote_grants state)) <? 64 end then
   let issued:=Selvedge.Features.Domain.RemoteGrant (ControllerId controller) (GrantEpoch (Selvedge.Features.Domain.remote_next_epoch state)) rights in
   let next:=Selvedge.Features.Domain.Remote (Selvedge.Features.Domain.remote_enabled state) (issued::remove_grants controller (Selvedge.Features.Domain.remote_grants state))
     (N.succ (Selvedge.Features.Domain.remote_next_epoch state)) (remove_receipts controller (Selvedge.Features.Domain.remote_receipts state)) in
   accept (grant_json issued) (store next value) []
   else reject "remote_grants_full" "At most 64 controllers can be granted; revoke an existing controller first" value
 end.
Definition revoke controller value :=
 if negb (controller_valid controller) then reject "remote_invalid_controller" "Controller identity must contain exactly 64 lowercase hexadecimal characters" value else
 let state:=registry value in
 let next:=Selvedge.Features.Domain.Remote (Selvedge.Features.Domain.remote_enabled state) (remove_grants controller (Selvedge.Features.Domain.remote_grants state))
   (Selvedge.Features.Domain.remote_next_epoch state) (remove_receipts controller (Selvedge.Features.Domain.remote_receipts state)) in
 accept (JObject [("controller_id",JString controller);("revoked",JBool true)]) (store next value) [].
Definition handle_remote_status (_payload : Selvedge.Generated.Commands.remote_status_payload)
 (caller : option N) (value : world) : json :=
 match caller with None => Selvedge.Kernel.State.success (status (registry value))
 | Some _ => decision_reply (local_only value) end.
Definition admin_command (change : world -> decision) (caller : option N) (value : world) :=
 match caller with None => change value | Some _ => local_only value end.
Definition handle_remote_enable (_payload : Selvedge.Generated.Commands.remote_enable_payload)
 (caller : option N) (value : world) : decision := admin_command (admin_enabled true) caller value.
Definition handle_remote_disable (_payload : Selvedge.Generated.Commands.remote_disable_payload)
 (caller : option N) (value : world) : decision := admin_command (admin_enabled false) caller value.
Definition handle_remote_grant (payload : Selvedge.Generated.Commands.remote_grant_payload)
 (caller : option N) (value : world) : decision :=
 admin_command (grant (Selvedge.Generated.Commands.remote_grant_controller_id payload)
   (Selvedge.Generated.Commands.remote_grant_permissions payload)) caller value.
Definition handle_remote_revoke (payload : Selvedge.Generated.Commands.remote_revoke_payload)
 (caller : option N) (value : world) : decision :=
 admin_command (revoke (Selvedge.Generated.Commands.remote_revoke_controller_id payload)) caller value.
Definition query (command : Selvedge.Generated.Commands.command) (caller : option N) (value : world) : option json :=
 match command with
 | Selvedge.Generated.Commands.Cmd_remote_status payload => Some (handle_remote_status payload caller value)
 | _ => None end.
Definition command (command : Selvedge.Generated.Commands.command) (caller : option N) (value : world) : option decision :=
 match command with
 | Selvedge.Generated.Commands.Cmd_remote_enable payload => Some (handle_remote_enable payload caller value)
 | Selvedge.Generated.Commands.Cmd_remote_disable payload => Some (handle_remote_disable payload caller value)
 | Selvedge.Generated.Commands.Cmd_remote_grant payload => Some (handle_remote_grant payload caller value)
 | Selvedge.Generated.Commands.Cmd_remote_revoke payload => Some (handle_remote_revoke payload caller value)
 | _ => None end.

Definition selected_settings settings := match settings with None | Some JNull | Some (JObject [])=>false | _=>true end.
Definition read_rights := Selvedge.Features.Domain.Rights true false false false.
Definition control_rights := Selvedge.Features.Domain.Rights false true false false.
Definition configure_rights := Selvedge.Features.Domain.Rights false false true false.
Definition required_rights command : option Selvedge.Features.Domain.rights := match command with
 | Selvedge.Generated.Commands.Cmd_read _ | Selvedge.Generated.Commands.Cmd_list _ | Selvedge.Generated.Commands.Cmd_describe _ | Selvedge.Generated.Commands.Cmd_list_projects _
 | Selvedge.Generated.Commands.Cmd_list_worktrees _ | Selvedge.Generated.Commands.Cmd_read_worktree _ | Selvedge.Generated.Commands.Cmd_read_project _
 | Selvedge.Generated.Commands.Cmd_list_cards _ | Selvedge.Generated.Commands.Cmd_read_card _ | Selvedge.Generated.Commands.Cmd_list_board_agents _
 | Selvedge.Generated.Commands.Cmd_list_task_graphs _ | Selvedge.Generated.Commands.Cmd_read_task_graph _ => Some read_rights
 | Selvedge.Generated.Commands.Cmd_create p => Some (Selvedge.Features.Domain.Rights false true (selected_settings (Selvedge.Generated.Commands.create_settings p)) false)
 | Selvedge.Generated.Commands.Cmd_fork p => Some (Selvedge.Features.Domain.Rights false true (selected_settings (Selvedge.Generated.Commands.fork_settings p) ||
     match Selvedge.Generated.Commands.fork_settings_origin p with
     |Some origin=>String.eqb(proj1_sig origin)"environment"|None=>false end) false)
 | Selvedge.Generated.Commands.Cmd_create_idle p => Some (Selvedge.Features.Domain.Rights false true (selected_settings (Selvedge.Generated.Commands.create_idle_settings p) ||
     match Selvedge.Generated.Commands.create_idle_create_worktree p with Some enabled=>enabled | None=>false end) false)
 | Selvedge.Generated.Commands.Cmd_create_workspace_task _ | Selvedge.Generated.Commands.Cmd_create_worktree_task _ | Selvedge.Generated.Commands.Cmd_create_task_graph _ | Selvedge.Generated.Commands.Cmd_update_task_graph _
 | Selvedge.Generated.Commands.Cmd_delete_task_graph _ => Some (Selvedge.Features.Domain.Rights false true true false)
 | Selvedge.Generated.Commands.Cmd_retry_worktree_archive _ | Selvedge.Generated.Commands.Cmd_send _ | Selvedge.Generated.Commands.Cmd_steer _ | Selvedge.Generated.Commands.Cmd_cancel_operation _
 | Selvedge.Generated.Commands.Cmd_freeze _ | Selvedge.Generated.Commands.Cmd_unfreeze _ | Selvedge.Generated.Commands.Cmd_stop _ | Selvedge.Generated.Commands.Cmd_interrupt _ | Selvedge.Generated.Commands.Cmd_archive _
 | Selvedge.Generated.Commands.Cmd_compact _ | Selvedge.Generated.Commands.Cmd_create_card _ | Selvedge.Generated.Commands.Cmd_update_card _ | Selvedge.Generated.Commands.Cmd_move_card _
 | Selvedge.Generated.Commands.Cmd_archive_card _ | Selvedge.Generated.Commands.Cmd_restore_card _ | Selvedge.Generated.Commands.Cmd_delete_card _ | Selvedge.Generated.Commands.Cmd_run_card _
 | Selvedge.Generated.Commands.Cmd_link_card _ | Selvedge.Generated.Commands.Cmd_regenerate_card_title _ | Selvedge.Generated.Commands.Cmd_pin_card _ => Some control_rights
 | Selvedge.Generated.Commands.Cmd_review_approval _ => Some (Selvedge.Features.Domain.Rights false false false true)
 | Selvedge.Generated.Commands.Cmd_configure_task_execution _ | Selvedge.Generated.Commands.Cmd_create_project _ | Selvedge.Generated.Commands.Cmd_update_project _
 | Selvedge.Generated.Commands.Cmd_delete_project _ | Selvedge.Generated.Commands.Cmd_board_settings _ | Selvedge.Generated.Commands.Cmd_save_board_agent _
 | Selvedge.Generated.Commands.Cmd_delete_board_agent _ => Some configure_rights
 | _=>None end.
Definition rights_allow required granted :=
 (negb (Selvedge.Features.Domain.may_read required) || Selvedge.Features.Domain.may_read granted) &&
 (negb (Selvedge.Features.Domain.may_control required) || Selvedge.Features.Domain.may_control granted) &&
 (negb (Selvedge.Features.Domain.may_configure required) || Selvedge.Features.Domain.may_configure granted) &&
 (negb (Selvedge.Features.Domain.may_approve required) || Selvedge.Features.Domain.may_approve granted).
Inductive authorization := Denied (code reason:string) | Admitted | Replay (reply:json).
Record request := Request { controller:controller_id; epoch:RemoteIdentity.grant_epoch; request_id:RemoteIdentity.request_id; intent:json }.
Definition request_valid request := controller_valid (controller request) && epoch_valid (epoch request) &&
 identifier_valid (request_id request) && payload_valid (intent request).
Definition key_matches request receipt := String.eqb (controller request) (Selvedge.Features.Domain.remote_controller receipt) &&
 N.eqb (epoch request) (Selvedge.Features.Domain.remote_epoch receipt) && String.eqb (request_id request) (Selvedge.Features.Domain.remote_request receipt).
Definition valid (value : F.remote) :=
 ((0 <? F.remote_next_epoch value) && (F.remote_next_epoch value <=? N.succ RemoteIdentity.max_epoch)) && Nat.leb (List.length (F.remote_grants value)) 64 &&
 Schema.unique_names (map (fun grant => controller_text (F.grant_controller grant)) (F.remote_grants value)) &&
 forallb (fun grant => controller_valid (F.grant_controller grant) &&
   (epoch_valid (F.grant_epoch grant) && (F.grant_epoch grant <? F.remote_next_epoch value))) (F.remote_grants value) &&
 Nat.leb (List.length (F.remote_receipts value)) 1024 &&
 Schema.unique_names (map (fun receipt => TextJson.render_json (JArray [
   JString (F.remote_controller receipt); number (F.remote_epoch receipt); JString (F.remote_request receipt)]))
   (F.remote_receipts value)) &&
 forallb (fun receipt => controller_valid (F.remote_controller receipt) && identifier_valid (F.remote_request receipt) &&
   payload_valid (F.remote_intent receipt) && payload_valid (F.remote_reply receipt) &&
   match find_grant (F.remote_controller receipt) value with
   | Some grant => N.eqb (F.remote_epoch receipt) (F.grant_epoch grant) | None => false end) (F.remote_receipts value).
Definition check required controller epoch state :=
 if negb (Selvedge.Features.Domain.remote_enabled state) then Denied "remote_disabled" "Remote control is disabled on this host"
 else if negb (controller_valid controller && epoch_valid epoch) then Denied "remote_invalid_request" "Remote request identity or intent exceeds the current protocol bounds"
 else match find_grant controller state with
 | None=>Denied "remote_controller_revoked" "This controller has no active local grant"
 | Some grant=>if negb (N.eqb epoch (Selvedge.Features.Domain.grant_epoch grant)) then Denied "remote_grant_expired" "This device grant generation is no longer current"
   else if rights_allow required (Selvedge.Features.Domain.grant_rights grant) then Admitted
   else Denied "remote_permission_denied" "This device grant does not permit this operation"
 end.
Definition authorize required request state :=
 if negb (Selvedge.Features.Domain.remote_enabled state) then Denied "remote_disabled" "Remote control is disabled on this host"
 else if negb (request_valid request) then Denied "remote_invalid_request" "Remote request identity or intent exceeds the current protocol bounds"
 else match check required (controller request) (epoch request) state with
 | Admitted =>
   match find (key_matches request) (Selvedge.Features.Domain.remote_receipts state) with
   | Some receipt=>if JsonObjects.equivalent (intent request) (Selvedge.Features.Domain.remote_intent receipt) then Replay (Selvedge.Features.Domain.remote_reply receipt)
     else Denied "remote_request_conflict" "This request ID was already committed with different intent"
   | None=>if N.of_nat (List.length (Selvedge.Features.Domain.remote_receipts state)) <? 1024 then Admitted
     else Denied "remote_receipts_full" "Retained command receipts are full; revoke or replace this device grant before issuing a new request"
   end
 | other=>other end.
Definition observation_command command := match required_rights command with Some rights=>Selvedge.Features.Domain.may_read rights | None=>false end.
Definition authorize_command probe command request state := match required_rights command with
 | None=>Denied "remote_command_forbidden" "Remote access cannot invoke this local management command"
 | Some rights=>if probe && observation_command command then check rights (controller request) (epoch request) state
   else authorize rights request state end.
Definition probe_reply authorization value := match authorization with
 | Denied code reason=>reject code reason value
 | Admitted=>accept (JObject [("admitted",JBool true)]) value []
 | Replay reply=>accept (JObject [("replayed",JBool true);("reply",reply)]) value [] end.
Definition retain request reply state := Selvedge.Features.Domain.Remote (Selvedge.Features.Domain.remote_enabled state) (Selvedge.Features.Domain.remote_grants state)
 (Selvedge.Features.Domain.remote_next_epoch state) (Selvedge.Features.Domain.RemoteReceipt (controller request) (epoch request) (request_id request)
   (intent request) reply :: Selvedge.Features.Domain.remote_receipts state).
Definition record_result request before result :=
 if payload_valid (decision_reply result) then
 let committed:=if bool_default "ok" (decision_reply result) false then result
   else Decision before (decision_reply result) [] in
 (* The command owns other domain coordinates; this transition owns the grant
    registry and appends its receipt to the capability snapshot it authorized. *)
 Decision (store (retain request (decision_reply committed) (registry before))
   (decision_world committed)) (decision_reply committed) (decision_effects committed)
 else reject "remote_reply_limit" "The command reply exceeds remote receipt retention limits; no command or effect was committed" before.
Definition root_task_command (command : G.command) :=
 KCommands.root_task_creation (G.encode command).
Definition configuration_allowed (original : G.command) source := match field "configuration" source with
 | None | Some JNull=>true
 | Some _=>root_task_command original end.
Definition prepared_world source value : option world := match field "configuration" source with
 | None | Some JNull=>Some value
 | Some configuration=>option_map (fun environment=>with_environment environment value) (Configuration.parse_environment configuration) end.
Definition schedules command result := bool_default "ok" (decision_reply result) false &&
 match command with Selvedge.Generated.Commands.Cmd_create_idle _ | Selvedge.Generated.Commands.Cmd_record_speech_transcript _=>false | _=>negb (observation_command command) end.
Definition execute_remote (execute:Scheduler.executor) source request original value : bool*bool*decision :=
 let query:=observation_command original in
 let denied code reason:=(negb query,false,reject code reason value) in
 (* Check even for queries, whose execution deliberately skips prepared worlds. *)
 if configuration_allowed original source then match authorize_command true original request (registry value) with
 | Denied code reason=>denied code reason
 | Replay reply=>(negb query,false,Decision value reply [])
 | Admitted=>match field "command" source with
   | Some prepared=>match Selvedge.Generated.Commands.decode prepared with
     | Some command=>if configuration_allowed command source then
       (* DEFENSE: Host preparation adds workspace/image observations; it must not change the requested operation or increase its required rights. *)
       if String.eqb (command_name (Selvedge.Generated.Commands.declared_command original)) (command_name (Selvedge.Generated.Commands.declared_command command)) then
       match authorize_command true command request (registry value) with
       | Denied code reason=>denied code reason
       | Replay reply=>(negb query,false,Decision value reply [])
       | Admitted=>if query then let result:=execute command None value in
         (false,false,Decision value (decision_reply result) []) else match prepared_world source value with
         | None=>denied "invalid_input" "The prepared remote environment is malformed"
         | Some prepared=>let result:=execute command None prepared in
           let result:=record_result request value result in (true,schedules command result,result)
         end end
       else denied "remote_intent_mismatch" "The prepared remote command must retain the original operation"
       (* DEFENSE: Native callers can submit same-name task graphs whose prepared nodes no longer create the root task named by the intent. *)
       else denied "invalid_input" "Remote environment observations are limited to task creation"
     | None=>denied "invalid_input" "The prepared remote command is malformed" end
   | None=>denied "invalid_input" "The prepared remote command is required" end
 end else denied "invalid_input" "Remote environment observations are limited to task creation".
Definition request_schema (prepared : bool) := List.app
 [Field "kind" KText;Field "controller_id" KText;Field "grant_epoch" KNatural;Field "request_id" KText;Field "intent" KJson]
 (if prepared then [Field "command" KJson;Field "configuration" KJson] else []).
Definition parse_request (prepared : bool) source := match Schema.decode (request_schema prepared) source,string_field "controller_id" source,
 natural_field "grant_epoch" source,string_field "request_id" source,field "intent" source with
 | Some _,Some controller,Some epoch,Some id,Some intent=>Some (Request (ControllerId controller) (GrantEpoch epoch) (RequestId id) intent)
 | _,_,_,_,_=>None end.
Definition completion (execute:Scheduler.executor) source value : option (bool*bool*decision) :=
 match string_field "kind" source with
 | Some kind=>if String.eqb kind "remote_check" then Some (false,false,match Schema.decode [Field "kind" KText;Field "controller_id" KText;Field "grant_epoch" KNatural] source,
     string_field "controller_id" source,natural_field "grant_epoch" source with
   | Some _,Some controller,Some epoch=>probe_reply (check read_rights controller epoch (registry value)) value
   | _,_,_=>reject "invalid_input" "Malformed remote identity check" value end)
 else if String.eqb kind "remote_probe" || String.eqb kind "remote_command" then
   Some (match parse_request (String.eqb kind "remote_command") source with
   | None=>(false,false,reject "invalid_input" "Malformed remote request" value)
   | Some request=>match Selvedge.Generated.Commands.decode (intent request) with
     | None=>(false,false,reject "invalid_input" "Malformed original remote command" value)
     | Some command=>if String.eqb kind "remote_probe" then
       (false,false,probe_reply (authorize_command true command request (registry value)) value)
       else execute_remote execute source request command value
     end end) else None
 | None=>None end.
