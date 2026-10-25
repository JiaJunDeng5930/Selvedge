From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Domain State Numbers Codec Workspace Queries ChatgptArguments TicketedRequest.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Worktree WorkspaceBinding.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Definition registry value := Selvedge.Features.Domain.feature_sharing (world_features value).
Definition store replacement value := with_features (Selvedge.Features.State.with_sharing replacement (world_features value)) value.
Definition grant connection state := find (fun grant=>N.eqb connection (Selvedge.Features.Domain.connection_id grant)) (Selvedge.Features.Domain.sharing_grants state).
Definition find_job id state := option_map snd (find (fun item=>N.eqb id (fst item)) (Selvedge.Features.Domain.sharing_jobs state)).
Definition project id value := match registry_at id (world_projects value) with
 | Some project=>if project_deleted project then None else Some project | None=>None end.
Definition member id values := existsb (N.eqb id) values.
Definition authority connection project state := match grant connection state with
 | Some grant=>if member project (Selvedge.Features.Domain.connection_projects grant) then Some grant else None | None=>None end.
Definition owned connection project job := N.eqb connection (Selvedge.Features.Domain.job_connection job) && N.eqb project (Selvedge.Features.Domain.job_project job).
Definition pending job := match Selvedge.Features.Domain.job_state job with Selvedge.Features.Domain.JobRunning=>true | _=>false end.
Definition with_outcome outcome job := set Selvedge.Features.Domain.job_state (fun _=>outcome) job.
Definition receipt id job :=
 let '(status,error,value):=match Selvedge.Features.Domain.job_state job with
 | Selvedge.Features.Domain.JobRunning=>("running",false,JNull)
 | Selvedge.Features.Domain.JobFinished value error=>("completed",error,value)
 | Selvedge.Features.Domain.JobInterrupted reason=>("interrupted",true,JObject [("error",JObject [("code",JString "outcome_unknown");("message",JString reason)])]) end in
 JObject [("operation_id",number id);("project_id",number (Selvedge.Features.Domain.job_project job));("request_id",JString (Selvedge.Features.Domain.job_request job));
 ("status",JString status);("error",JBool error);("value",value)].
Definition summary id job := match receipt id job with JObject fields=>JObject (remove_field "value" fields) | value=>value end.
Definition forbidden := Selvedge.Kernel.State.failure "project_forbidden" "This connection has no grant for that project".
Definition missing_operation := Selvedge.Kernel.State.failure "operation_not_found" "No retained operation belongs to that project and connection".
Definition project_summary sandbox id value := match project id value with
 | None=>JNull
 | Some project=>JObject [("project_id",number id);("name",JString (project_name project));
   ("root_count",number (N.of_nat (List.length (workspace_roots (project_workspace project)))));
   ("primary_root",optional_string (workspace_primary (project_workspace project)));("sandbox",sandbox_json sandbox)] end.
Definition projects connection value := match grant connection (registry value) with
 | None=>forbidden
 | Some grant=>Selvedge.Kernel.State.success (JArray (map (fun id=>project_summary (Selvedge.Features.Domain.connection_sandbox grant) id value) (Selvedge.Features.Domain.connection_projects grant))) end.
Definition read_project connection id value := match authority connection id (registry value) with
 | None=>forbidden | Some _=>Queries.read_project id value end.
Definition read_job connection project id value := match authority connection project (registry value) with
 | None=>forbidden
 | Some _=>match find_job id (registry value) with
   | None=>missing_operation
   | Some job=>if owned connection project job then Selvedge.Kernel.State.success (receipt id job) else missing_operation end end.
Definition jobs connection project value := match authority connection project (registry value) with
 | None=>forbidden
 | Some _=>Selvedge.Kernel.State.success (JArray (fold_right (fun item rest=>let '(id,job):=item in
     if owned connection project job then summary id job::rest else rest) [] (Selvedge.Features.Domain.sharing_jobs (registry value)))) end.
Definition ids_valid ids := forallb (fun id=>id <=? ChatgptArguments.identity_maximum) ids.
Definition valid_query ids reply := if ids_valid ids then reply else Selvedge.Kernel.State.failure "invalid_input" "ChatGPT identities must be unsigned 32-bit integers".
Definition handle_chatgpt_projects (p : Selvedge.Generated.Commands.chatgpt_projects_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : json :=
 valid_query [Selvedge.Generated.Commands.chatgpt_projects_connection_id p] (projects (Selvedge.Generated.Commands.chatgpt_projects_connection_id p) value).

Definition handle_chatgpt_project (p : Selvedge.Generated.Commands.chatgpt_project_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : json :=
 valid_query [Selvedge.Generated.Commands.chatgpt_project_connection_id p;Selvedge.Generated.Commands.chatgpt_project_project_id p]
   (read_project (Selvedge.Generated.Commands.chatgpt_project_connection_id p) (Selvedge.Generated.Commands.chatgpt_project_project_id p) value).

Definition handle_chatgpt_operation (p : Selvedge.Generated.Commands.chatgpt_operation_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : json :=
 valid_query [Selvedge.Generated.Commands.chatgpt_operation_connection_id p;Selvedge.Generated.Commands.chatgpt_operation_project_id p;Selvedge.Generated.Commands.chatgpt_operation_operation_id p]
   (read_job (Selvedge.Generated.Commands.chatgpt_operation_connection_id p) (Selvedge.Generated.Commands.chatgpt_operation_project_id p) (Selvedge.Generated.Commands.chatgpt_operation_operation_id p) value).

Definition handle_chatgpt_operations (p : Selvedge.Generated.Commands.chatgpt_operations_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : json :=
 valid_query [Selvedge.Generated.Commands.chatgpt_operations_connection_id p;Selvedge.Generated.Commands.chatgpt_operations_project_id p]
   (jobs (Selvedge.Generated.Commands.chatgpt_operations_connection_id p) (Selvedge.Generated.Commands.chatgpt_operations_project_id p) value).

Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) value :option json := match command with
 | Selvedge.Generated.Commands.Cmd_chatgpt_projects p => Some (handle_chatgpt_projects p _caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_project p => Some (handle_chatgpt_project p _caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_operation p => Some (handle_chatgpt_operation p _caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_operations p => Some (handle_chatgpt_operations p _caller value)
 | _=>None end.

Definition grant_schema := ChatgptArguments.grant_declaration.
Definition parse_grant source := match Schema.decode grant_schema source,natural_field "connection_id" source,
 array_field "project_ids" source,field "sandbox" source with
 | Some _,Some id,Some projects,Some sandbox=>match Schema.decode_list natural projects,parse_sandbox sandbox with
   | Some projects,Some sandbox=>Some (Selvedge.Features.Domain.ConnectionGrant id projects sandbox) | _,_=>None end
 | _,_,_,_=>None end.
Fixpoint distinct_ids ids := match ids with []=>true | id::rest=>negb (member id rest) && distinct_ids rest end.
Definition valid_grant value grant := ids_valid [Selvedge.Features.Domain.connection_id grant] &&
 (N.of_nat (List.length (Selvedge.Features.Domain.connection_projects grant)) <=? 32) && ids_valid (Selvedge.Features.Domain.connection_projects grant) &&
 distinct_ids (Selvedge.Features.Domain.connection_projects grant) &&
 forallb (fun id=>match project id value with Some _=>true | None=>false end) (Selvedge.Features.Domain.connection_projects grant).
Definition configure entries value := match Schema.decode_list parse_grant entries with
 | None=>reject "invalid_connections" "Connections need distinct identities and existing project grants" value
 | Some entries=>if (N.of_nat (List.length entries) <=? 32) && distinct_ids (map Selvedge.Features.Domain.connection_id entries) && forallb (valid_grant value) entries then
   accept (JObject []) (store (set Selvedge.Features.Domain.sharing_grants (fun _=>entries) (registry value)) value) []
   else reject "invalid_connections" "Connections need distinct identities and existing project grants" value end.
Definition replace_job id job state := set Selvedge.Features.Domain.sharing_jobs
 (fun previous=>(id,job)::filter (fun item=>negb (N.eqb id (fst item))) previous) state.
Definition retry connection request state := find (fun item=>let job:=snd item in
 N.eqb connection (Selvedge.Features.Domain.job_connection job) && String.eqb request (Selvedge.Features.Domain.job_request job)) (Selvedge.Features.Domain.sharing_jobs state).
Definition bounded_text maximum text := negb (String.eqb text "") && Utf8.well_formed text &&
 (N.of_nat (String.length text) <=? maximum).
Definition start connection project_id request arguments granted target value :=
 let state:=registry value in
 match retry connection request state with
 | Some (id,job)=>if owned connection project_id job && Json.equal (Schema.encode ChatgptArguments.argument_declaration arguments) (Selvedge.Features.Domain.job_arguments_json job) then
   accept (receipt id job) value []
   else reject "request_conflict" "This request_id already names a different command; do not retry with new arguments" value
 | None=>
 (* DEFENSE: Projects can retain a managed root while its owner is archiving;
    only a new physical execution needs an available workspace. *)
 if negb (Worktree.workspace_available (project_workspace target) value &&
    WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) value) then
 reject "worktree_unavailable" "The Project workspace belongs to an unavailable managed worktree" value
 else if (N.of_nat (List.length (Selvedge.Features.Domain.sharing_jobs state)) <? 128) && (Selvedge.Features.Domain.sharing_next state <? ChatgptArguments.identity_maximum) then
   let job:=Selvedge.Features.Domain.ConnectionJob connection project_id request arguments (project_workspace target) (project_resource target) (Selvedge.Features.Domain.connection_sandbox granted) Selvedge.Features.Domain.JobRunning in
   let issued:=TicketedRequest.Scoped.feature_run (TicketedRequest.Scoped.ConnectionRequest job) value in
   Selvedge.Kernel.State.Decision (decision_world issued)
     (success (receipt (TicketedRequest.next_identity TicketedRequest.ConnectionIdentity value) job)) (decision_effects issued)
   else reject "operation_capacity" "Forget a completed operation before starting more work" value end.
Definition run connection project_id request arguments value :=
 if negb (ids_valid [connection;project_id] && bounded_text 128 request) then
 reject "invalid_command" "A bounded request_id and valid Bash arguments are required" value
 else match ChatgptArguments.admit_args arguments with
 | None=>reject "invalid_command" "A bounded request_id and valid Bash arguments are required" value
 | Some arguments=>match authority connection project_id (registry value) with
   | None=>reject "project_forbidden" "This connection has no grant for that project" value
   | Some grant=>match project project_id value with
     | None=>reject "project_not_found" "The project is unavailable" value
     | Some target=>match workspace_primary (project_workspace target) with
       | None=>reject "empty_workspace" "The project needs a primary Workspace root" value
       | Some _=>start connection project_id request arguments grant target value end end end end.
Definition edit (remove:bool) connection project id value :=
 if negb (ids_valid [connection;project;id]) then reject "invalid_input" "ChatGPT identities must be unsigned 32-bit integers" value
 else match authority connection project (registry value) with
 | None=>reject "project_forbidden" "This connection has no grant for that project" value
 | Some _=>match find_job id (registry value) with
   | None=>Decision value missing_operation []
   | Some job=>if negb (owned connection project job) then Decision value missing_operation []
     else if remove then if pending job then reject "operation_running" "Cancel or finish the operation before forgetting it" value
       else let next:=set Selvedge.Features.Domain.sharing_jobs (filter (fun item=>negb (N.eqb id (fst item)))) (registry value) in
       accept (JObject [("operation_id",number id)]) (store next value) []
     else if pending job then
       let stopped:=with_outcome (Selvedge.Features.Domain.JobInterrupted "Cancellation requested; physical changes are not undone") job in
       accept (receipt id stopped) (store (replace_job id stopped (registry value)) value) [CancelConnectionJob id]
     else accept (receipt id job) value []
   end end.
Definition handle_configure_chatgpt_connections (p : Selvedge.Generated.Commands.configure_chatgpt_connections_payload)
 (caller : option N) (value : Selvedge.Kernel.State.world) : decision :=
 match caller with
   | None=>configure (Selvedge.Generated.Commands.configure_chatgpt_connections_connections p) value
   | Some _=>reject "local_only" "Connection grants can only be configured by the local owner" value end.

Definition handle_chatgpt_exec (p : Selvedge.Generated.Commands.chatgpt_exec_payload)
 (caller : option N) (value : Selvedge.Kernel.State.world) : decision :=
 run (Selvedge.Generated.Commands.chatgpt_exec_connection_id p) (Selvedge.Generated.Commands.chatgpt_exec_project_id p)
   (Selvedge.Generated.Commands.chatgpt_exec_request_id p) (Selvedge.Generated.Commands.chatgpt_exec_arguments p) value.

Definition handle_chatgpt_cancel (p : Selvedge.Generated.Commands.chatgpt_cancel_payload)
 (caller : option N) (value : Selvedge.Kernel.State.world) : decision :=
 edit false (Selvedge.Generated.Commands.chatgpt_cancel_connection_id p) (Selvedge.Generated.Commands.chatgpt_cancel_project_id p) (Selvedge.Generated.Commands.chatgpt_cancel_operation_id p) value.

Definition handle_chatgpt_forget (p : Selvedge.Generated.Commands.chatgpt_forget_payload)
 (caller : option N) (value : Selvedge.Kernel.State.world) : decision :=
 edit true (Selvedge.Generated.Commands.chatgpt_forget_connection_id p) (Selvedge.Generated.Commands.chatgpt_forget_project_id p) (Selvedge.Generated.Commands.chatgpt_forget_operation_id p) value.

Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) value :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_configure_chatgpt_connections p => Some (handle_configure_chatgpt_connections p caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_exec p => Some (handle_chatgpt_exec p caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_cancel p => Some (handle_chatgpt_cancel p caller value)
 | Selvedge.Generated.Commands.Cmd_chatgpt_forget p => Some (handle_chatgpt_forget p caller value)
 | _=>None end.
Definition settle id result error value :bool*bool*decision := match find_job id (registry value) with
 | Some job=>if pending job then
   let finished:=with_outcome (Selvedge.Features.Domain.JobFinished result error) job in
   (true,true,accept (JObject [("accepted",JBool true)]) (store (replace_job id finished (registry value)) value) [])
   else (false,false,accept (JObject [("accepted",JBool false)]) value [])
 | None=>(false,false,accept (JObject [("accepted",JBool false)]) value []) end.
Definition completion source value :option (bool*bool*decision) := match string_field "kind" source with
 | Some kind=>if String.eqb kind "chatgpt_result" then Some (
   match Schema.decode [Field "kind" KText;Field "operation_id" KNatural;Field "error" KBool;Field "value" KJson] source,
     natural_field "operation_id" source,bool_field "error" source,field "value" source with
   | Some _,Some id,Some error,Some result=>
     (* DEFENSE: External job callbacks must retain the unsigned identity and
        object-result contract of the execution protocol. *)
     if ids_valid [id] && (match result with JObject _=>true | _=>false end)
     then settle id result error value
     else (false,false,reject "invalid_input" "Malformed ChatGPT operation completion" value)
   | _,_,_,_=>(false,false,reject "invalid_input" "Malformed ChatGPT operation completion" value) end) else None
 | None=>None end.
Definition recover_job job := match Selvedge.Features.Domain.job_state job with
 | Selvedge.Features.Domain.JobRunning=>with_outcome (Selvedge.Features.Domain.JobInterrupted "Service restarted; execution may have happened and will not be replayed") job
 | _=>job end.
Definition recover value := store (set Selvedge.Features.Domain.sharing_jobs (map (fun item=>(fst item,recover_job (snd item)))) (registry value)) value.
Definition project_used id value :=
 existsb (fun grant=>member id (Selvedge.Features.Domain.connection_projects grant)) (Selvedge.Features.Domain.sharing_grants (registry value)) ||
 existsb (fun item=>N.eqb id (Selvedge.Features.Domain.job_project (snd item))) (Selvedge.Features.Domain.sharing_jobs (registry value)).
