From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Registry.
From Selvedge.Programming Require Import OptionObservation.
From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import Domain State Tasks TaskScope ChatgptArguments.
From Selvedge.Features Require Import Domain Observation Titles WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.

(** Resolver values retain the observations that authorize one request. The
    job and protocol input are derived from these observations; there is no
    second Boolean model of the same selection. *)
Definition ordinary_profile (selected : profile) :=
 negb (String.eqb (profile_provider selected) "echo") &&
 match profile_policy selected with FixedReasoning => true | _ => false end.

Definition sharing_registry before := F.feature_sharing (world_features before).
Definition connection_grant identity state :=
 find (fun grant => N.eqb identity (F.connection_id grant)) (F.sharing_grants state).
Definition connection_authority identity project state := match connection_grant identity state with
 | Some grant => if ConnectionGrants.admits_project project grant then Some grant else None
 | None => None end.
Definition connection_project identity before := match registry_at identity (world_projects before) with
 | Some project => if project_deleted project then None else Some project | None => None end.
Definition connection_retry identity request state := find (fun entry =>
 N.eqb identity (F.job_connection (snd entry)) && String.eqb request (F.job_request (snd entry))) (F.sharing_jobs state).
Definition connection_capacity before :=
 (N.of_nat (List.length (F.sharing_jobs (sharing_registry before))) <? 128) &&
 (F.sharing_next (sharing_registry before) <? ChatgptArguments.identity_maximum).
Definition connection_workspace target before :=
 WorkspaceBinding.workspace_available (project_workspace target) before &&
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) before.
Definition connection_has_primary target :=
 match workspace_primary (project_workspace target) with Some _ => true | None => false end.
Definition connection_job identity project request arguments grant target :=
 F.ConnectionJob identity project request arguments (project_workspace target)
   (project_resource target) (F.connection_sandbox grant) F.JobRunning.

Record resolved_connection (before : world) (identity project : N) (request : string) := ResolvedConnection {
 resolved_arguments : ChatgptArguments.arguments;
 resolved_grant : F.connection_grant;
 resolved_target : Selvedge.Kernel.Domain.project;
 resolved_authority : connection_authority identity project (sharing_registry before) = Some resolved_grant;
 resolved_target_found : connection_project project before = Some resolved_target;
 resolved_primary : connection_has_primary resolved_target = true;
 resolved_fresh : connection_retry identity request (sharing_registry before) = None;
 resolved_workspace : connection_workspace resolved_target before = true;
 resolved_capacity : connection_capacity before = true
}.
Arguments resolved_arguments {before identity project request}.
Arguments resolved_grant {before identity project request}.
Arguments resolved_target {before identity project request}.
Arguments resolved_authority {before identity project request}.
Arguments resolved_target_found {before identity project request}.
Arguments resolved_primary {before identity project request}.
Arguments resolved_fresh {before identity project request}.
Arguments resolved_workspace {before identity project request}.
Arguments resolved_capacity {before identity project request}.
Definition resolved_job {before identity project request}
 (resolved : resolved_connection before identity project request) :=
 connection_job identity project request (resolved_arguments resolved)
   (resolved_grant resolved) (resolved_target resolved).

Definition observe := @OptionObservation.observe.
Arguments observe {A B}.
Definition require {A : Type} (condition : bool) (accepted : condition = true -> CommandResult.result A)
 (code message : string) : CommandResult.result A :=
 match condition as found return condition = found -> CommandResult.result A with
 | true => accepted | false => fun _ => CommandResult.refuse code message end eq_refl.
Inductive connection_resolution (before : world) (owner project : N) (request : string) :=
 | ExistingConnection (identity : N) (job : F.connection_job)
 | NewConnection (resolved : resolved_connection before owner project request).
Arguments ExistingConnection {before owner project request}.
Arguments NewConnection {before owner project request}.
Definition resolve_connection identity project (request : ChatgptArguments.request_identifier)
 (arguments : ChatgptArguments.arguments) before
 : CommandResult.result (connection_resolution before identity project (ChatgptArguments.request_text request)) :=
 let request := ChatgptArguments.request_text request in
 observe (connection_authority identity project (sharing_registry before)) (fun grant Authority =>
 observe (connection_project project before) (fun target Project =>
 require (connection_has_primary target) (fun Primary =>
 observe (connection_retry identity request (sharing_registry before)) (fun pair _ =>
   let '(id,job) := pair in
   if N.eqb identity (F.job_connection job) && N.eqb project (F.job_project job) &&
      Json.equal (ChatgptArguments.encode arguments) (F.job_arguments_json job)
   then CommandResult.Accepted (ExistingConnection id job)
   else CommandResult.refuse "request_conflict" "This request_id already names a different command; do not retry with new arguments")
 (fun Retry =>
   (* DEFENSE: Only a new physical execution needs an available managed root;
      replaying its retained receipt must remain possible while archiving. *)
   require (connection_workspace target before) (fun Workspace =>
   require (connection_capacity before) (fun Capacity =>
     CommandResult.Accepted (NewConnection (ResolvedConnection before identity project request
       arguments grant target Authority Project Primary Retry Workspace Capacity)))
   "operation_capacity" "Forget a completed operation before starting more work")
   "worktree_unavailable" "The Project workspace belongs to an unavailable managed worktree"))
 "empty_workspace" "The project needs a primary Workspace root")
 (fun _ => CommandResult.refuse "project_not_found" "The project is unavailable"))
 (fun _ => CommandResult.refuse "project_forbidden" "This connection has no grant for that project").

Definition title_entry (owner : N) (before : world) :=
 find (fun entry => N.eqb owner (F.title_task entry)) (F.feature_titles (world_features before)).
Fixpoint split_slash (text part : string) : list string := match text with
 | EmptyString => [part]
 | String ch rest => if Ascii.eqb ch "/"%char then part :: split_slash rest ""
   else split_slash rest (String.append part (String ch "")) end.
Definition account_prefix (key : string) := match split_slash key "" with
 | "chatgpt" :: account :: _ :: _ => String.append "chatgpt/" (String.append account "/")
 | _ => "" end.
Definition capable_profile (selected : profile) := negb (String.eqb (profile_provider selected) "echo").
Definition selected_title_profile (current : task) (before : world) :=
 let profile := task_current_profile current in
 let configured := environment_profiles (world_environment before) in
 let fallback := find (fun selected => String.eqb (profile_key profile) (profile_key selected) && capable_profile selected) configured in
 let prefix := account_prefix (profile_key profile) in
 match find (fun selected => String.eqb (profile_provider profile) "chatgpt" &&
   negb (String.eqb prefix "") && String.prefix prefix (profile_key selected) &&
   String.eqb (profile_provider selected) "chatgpt" && String.eqb (profile_model selected) "gpt-5.6-luna" &&
   ordinary_profile selected) configured with
 | Some selected => Some selected | None => fallback end.
Definition title_accepts (current : task) := negb (task_archived current).
Definition title_prompt (current : task) (before : world) :=
 Titles.prompt_with (F.title_agent_instructions (F.feature_title_settings (world_features before)))
   (Observation.first_request (task_history current)).

(** The plan keeps the observed task and profile. Eligibility proofs erase;
    issuing the request consumes these values without looking them up again. *)
Record resolved_title (before : world) := ResolvedTitle {
 title_reference : TaskScope.task_reference before;
 title_profile : profile;
 title_absent : title_entry (TaskScope.owner title_reference) before = None;
 title_eligible : title_accepts (TaskScope.selected title_reference) &&
   Utf8.nonblank (Observation.first_request (task_history (TaskScope.selected title_reference))) = true;
 title_chosen : selected_title_profile (TaskScope.selected title_reference) before = Some title_profile
}.
Arguments title_reference {before}.
Arguments title_profile {before}.
Arguments title_absent {before}.
Arguments title_eligible {before}.
Arguments title_chosen {before}.
Definition resolve_title owner before : option (resolved_title before) :=
 observe (title_entry owner before) (fun _ _ => None) (fun Absent =>
 observe (find_task owner before) (fun current Found =>
 match Bool.bool_dec (title_accepts current && Utf8.nonblank (Observation.first_request (task_history current))) true with
 | left Eligible => observe (selected_title_profile current before)
   (fun selected Chosen => Some (ResolvedTitle before (TaskScope.TaskReference before owner current Found)
      selected Absent Eligible Chosen)) (fun _ => None)
 | right _ => None end) (fun _ => None)).
