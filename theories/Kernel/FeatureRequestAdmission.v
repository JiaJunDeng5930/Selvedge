From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs Schema Utf8 Registry OptionList.
From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import Domain State Codec Tasks TaskScope Workspace ChatgptArguments.
From Selvedge.Features Require Import Domain BoardFacts BoardParameters Observation Titles WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.

(** Receiver eligibility is one shared rule consumed by scoped request
    construction. A proposed request cannot supply its own task, card revision,
    project workspace, connection grant or provider registration. *)
Definition profile_snapshot (selected : profile) := JObject [
 ("model",Codec.model_json selected);("metadata",profile_metadata selected);
 ("reasoning_options",JArray (map JString (profile_reasoning_options selected)))].
Definition registered_profile (selected : profile) (before : world) :=
 existsb (fun current => Json.equal (profile_snapshot selected) (profile_snapshot current))
   (environment_profiles (world_environment before)).
Definition ordinary_profile (selected : profile) :=
 negb (String.eqb (profile_provider selected) "echo") &&
 match profile_policy selected with FixedReasoning => true | _ => false end.
Definition title (owner : N) (selected : profile) (prompt : string) (before : world) :=
 match find_task owner before with
 | None => false
 | Some current =>
   negb (task_archived current) &&
   negb (existsb (fun entry => N.eqb owner (F.title_task entry))
     (F.feature_titles (world_features before))) &&
   registered_profile selected before &&
   negb (String.eqb (profile_provider selected) "echo") &&
   Utf8.nonblank (Observation.first_request (task_history current)) &&
   String.eqb prompt (Titles.prompt_with
     (F.title_agent_prompt (F.feature_title_settings (world_features before)))
     (Observation.first_request (task_history current)))
 end.
Definition card_snapshot (owner : N) (card : F.card) := Observation.card_json owner card.
Definition new_card (card : F.card) :=
 N.eqb (F.card_revision card) 0 && BoardFacts.unlinked card &&
 negb (F.card_archived card) && negb (F.card_pinned card) &&
 N.eqb (F.card_created card) (F.card_updated card) &&
 String.eqb (F.card_start_error card) "" &&
 match F.card_enrichment card with F.NoEnrichment => true | _ => false end.
Definition card (owner : N) (proposed : F.card) (selected : profile)
 (prompt : string) (retitle : bool) (before : world) :=
 let cards := F.board_cards (F.feature_board (world_features before)) in
 registered_profile selected before && ordinary_profile selected &&
 (F.card_updated proposed <=? 4294967295) &&
 String.eqb prompt (Titles.board_prompt
   (F.title_task_prompt (F.feature_title_settings (world_features before)))
   (F.draft_title (F.card_contents proposed)) (F.draft_description (F.card_contents proposed)) retitle) &&
 if N.eqb owner (N.of_nat (List.length cards)) then
   BoardFacts.valid_draft (F.card_contents proposed) before &&
   forallb (fun attachment => match BoardParameters.attachment (Observation.attachment_json attachment) with
     | Some _ => true | None => false end) (F.draft_attachments (F.card_contents proposed)) &&
   negb retitle && new_card proposed && (owner <? 4294967295) &&
   Nat.ltb (List.length (filter (fun entry => match entry with Some _ => true | None => false end) cards)) 512
 else match registry_at owner cards with
 | Some (Some current) => retitle && BoardFacts.mutable current before &&
   Json.equal (card_snapshot owner proposed)
     (card_snapshot owner (BoardFacts.revised (F.card_contents current) (F.card_updated proposed) current))
 | _ => false end.
Definition connection (job : F.connection_job) (before : world) :=
 let state := F.feature_sharing (world_features before) in
 match find (fun grant => N.eqb (F.job_connection job) (F.connection_id grant)) (F.sharing_grants state),
   registry_at (F.job_project job) (world_projects before) with
 | Some grant,Some project =>
   negb (project_deleted project) &&
   existsb (N.eqb (F.job_project job)) (F.connection_projects grant) &&
   Json.equal (workspace_json (F.job_workspace job)) (workspace_json (project_workspace project)) &&
   Workspace.same_resource (F.job_resource job) (project_resource project) &&
   Json.equal (sandbox_json (F.job_sandbox job)) (sandbox_json (F.connection_sandbox grant)) &&
   (match workspace_primary (project_workspace project) with Some _ => true | None => false end) &&
   WorkspaceBinding.workspace_available (project_workspace project) before &&
   WorkspaceBinding.resource_ready (project_workspace project) (project_resource project) before &&
   negb (String.eqb (F.job_request job) "") && Utf8.well_formed (F.job_request job) &&
   (N.of_nat (String.length (F.job_request job)) <=? 128) &&
   ChatgptArguments.arguments_valid (F.job_arguments job) &&
   negb (existsb (fun entry => N.eqb (F.job_connection job) (F.job_connection (snd entry)) &&
     String.eqb (F.job_request job) (F.job_request (snd entry))) (F.sharing_jobs state)) &&
   (N.of_nat (List.length (F.sharing_jobs state)) <? 128) &&
   (F.sharing_next state <? ChatgptArguments.identity_maximum)
 | _,_ => false end.

Definition sharing_registry before := F.feature_sharing (world_features before).
Definition connection_grant identity state :=
 find (fun grant => N.eqb identity (F.connection_id grant)) (F.sharing_grants state).
Definition connection_authority identity project state := match connection_grant identity state with
 | Some grant => if existsb (N.eqb project) (F.connection_projects grant) then Some grant else None
 | None => None end.
Definition connection_project identity before := match registry_at identity (world_projects before) with
 | Some project => if project_deleted project then None else Some project | None => None end.
Definition connection_retry identity request state := find (fun entry =>
 N.eqb identity (F.job_connection (snd entry)) && String.eqb request (F.job_request (snd entry))) (F.sharing_jobs state).
Definition bounded_text maximum text := negb (String.eqb text "") && Utf8.well_formed text &&
 (N.of_nat (String.length text) <=? maximum).
Definition ids_valid ids := forallb (fun id => id <=? ChatgptArguments.identity_maximum) ids.
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
 resolved_job : F.connection_job;
 resolved_identity : F.job_connection resolved_job = identity;
 resolved_project : F.job_project resolved_job = project;
 resolved_request : F.job_request resolved_job = request;
 resolved_running : F.job_state resolved_job = F.JobRunning;
 resolved_admitted : connection resolved_job before = true
}.
Arguments resolved_job {before identity project request}.
Arguments resolved_identity {before identity project request}.
Arguments resolved_project {before identity project request}.
Arguments resolved_request {before identity project request}.
Arguments resolved_running {before identity project request}.
Arguments resolved_admitted {before identity project request}.

Lemma no_matching_member : forall A (test : A -> bool) values,
 find test values = None -> existsb test values = false.
Proof. intros A test values; induction values as [|value rest IH]; cbn; [reflexivity|].
 destruct (test value); [discriminate|exact IH]. Qed.

(* These are the facts produced by the actual resolver below. Their combination
   is erased; a resolved request never re-runs the domain admission predicate. *)
Lemma connection_from_observations : forall identity project request arguments grant target before,
 bounded_text 128 request = true -> ChatgptArguments.arguments_valid arguments = true ->
 connection_authority identity project (sharing_registry before) = Some grant ->
 connection_project project before = Some target -> connection_has_primary target = true ->
 connection_retry identity request (sharing_registry before) = None ->
 connection_workspace target before = true -> connection_capacity before = true ->
 connection (connection_job identity project request arguments grant target) before = true.
Proof.
 intros identity project request arguments grant target before Bounded Arguments Authority Project Primary Retry Workspace Capacity.
 unfold connection_authority,connection_grant in Authority.
 destruct (find _ (F.sharing_grants (sharing_registry before))) as [registered|] eqn:Grant; [|discriminate].
 destruct (existsb (N.eqb project) (F.connection_projects registered)) eqn:Member; [|discriminate].
 inversion Authority; subst registered.
 unfold connection_project in Project.
 destruct (registry_at project (world_projects before)) as [current|] eqn:Found; [|discriminate].
 destruct (project_deleted current) eqn:Deleted; [discriminate|]. inversion Project; subst current.
 unfold connection_retry in Retry; apply no_matching_member in Retry.
 assert (Resource : Workspace.same_resource (project_resource target) (project_resource target) = true).
 { unfold Workspace.same_resource; destruct (project_resource target); [apply N.eqb_refl|reflexivity]. }
 unfold connection,connection_job; cbn [F.job_connection F.job_project F.job_request F.job_workspace F.job_resource F.job_sandbox F.job_arguments].
 fold (sharing_registry before); rewrite Grant,Found,Deleted,Member,!JsonProofs.equal_is_reflexive,Resource.
 unfold connection_has_primary in Primary; rewrite Primary.
 unfold connection_workspace in Workspace; apply andb_true_iff in Workspace as [Available Ready].
 unfold bounded_text in Bounded; apply andb_true_iff in Bounded as [Text Length].
 apply andb_true_iff in Text as [Nonempty Encoding].
 unfold connection_capacity in Capacity; apply andb_true_iff in Capacity as [Room Next].
 rewrite Available,Ready,Nonempty,Encoding,Length,Arguments,Retry,Room,Next; reflexivity.
Qed.

Definition observe := @OptionList.observe.
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
Definition resolve_connection identity project request raw before : CommandResult.result (connection_resolution before identity project request) :=
 require (ids_valid [identity;project] && bounded_text 128 request) (fun Input =>
 match ChatgptArguments.admit_arguments raw with
 | None => CommandResult.refuse "invalid_command" "A bounded request_id and valid Bash arguments are required"
 | Some (exist _ arguments Arguments) =>
 observe (connection_authority identity project (sharing_registry before)) (fun grant Authority =>
 observe (connection_project project before) (fun target Project =>
 require (connection_has_primary target) (fun Primary =>
 observe (connection_retry identity request (sharing_registry before)) (fun pair _ =>
   let '(id,job) := pair in
   if N.eqb identity (F.job_connection job) && N.eqb project (F.job_project job) &&
      Json.equal (Schema.encode ChatgptArguments.argument_declaration arguments) (F.job_arguments_json job)
   then CommandResult.Accepted (ExistingConnection id job)
   else CommandResult.refuse "request_conflict" "This request_id already names a different command; do not retry with new arguments")
 (fun Retry =>
   (* DEFENSE: Only a new physical execution needs an available managed root;
      replaying its retained receipt must remain possible while archiving. *)
   require (connection_workspace target before) (fun Workspace =>
   require (connection_capacity before) (fun Capacity =>
     CommandResult.Accepted (NewConnection (ResolvedConnection before identity project request
       (connection_job identity project request arguments grant target) eq_refl eq_refl eq_refl eq_refl
       (connection_from_observations identity project request arguments grant target before
         (proj2 (proj1 (andb_true_iff _ _) Input)) Arguments Authority Project Primary Retry Workspace Capacity))))
   "operation_capacity" "Forget a completed operation before starting more work")
   "worktree_unavailable" "The Project workspace belongs to an unavailable managed worktree"))
 "empty_workspace" "The project needs a primary Workspace root")
 (fun _ => CommandResult.refuse "project_not_found" "The project is unavailable"))
 (fun _ => CommandResult.refuse "project_forbidden" "This connection has no grant for that project")
 end)
 "invalid_command" "A bounded request_id and valid Bash arguments are required".

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
 Titles.prompt_with (F.title_agent_prompt (F.feature_title_settings (world_features before)))
   (Observation.first_request (task_history current)).

Lemma registered_profile_from_membership : forall selected before,
 In selected (environment_profiles (world_environment before)) -> registered_profile selected before = true.
Proof.
 intros selected before Member; unfold registered_profile.
 apply existsb_exists; exists selected; split; [exact Member|apply equal_is_reflexive].
Qed.
Lemma selected_title_profile_is_registered_and_capable : forall current before selected,
 selected_title_profile current before = Some selected ->
 In selected (environment_profiles (world_environment before)) /\ capable_profile selected = true.
Proof.
 intros current before selected Chosen; unfold selected_title_profile in Chosen.
 destruct (find _ (environment_profiles (world_environment before))) as [preferred|] eqn:Preferred.
 - inversion Chosen; subst preferred; apply find_some in Preferred as [Member Condition].
   unfold ordinary_profile in Condition; repeat rewrite andb_true_iff in Condition; unfold capable_profile; tauto.
 - apply find_some in Chosen as [Member Condition]; apply andb_true_iff in Condition as [Key Capable]; tauto.
Qed.
Lemma title_from_observations : forall owner current before selected,
 find_task owner before = Some current -> title_entry owner before = None ->
 title_accepts current = true -> Utf8.nonblank (Observation.first_request (task_history current)) = true ->
 selected_title_profile current before = Some selected -> title owner selected (title_prompt current before) before = true.
Proof.
 intros owner current before selected Found Absent Live Nonblank Chosen.
 pose proof (selected_title_profile_is_registered_and_capable current before selected Chosen) as [Member Capable].
 pose proof (registered_profile_from_membership selected before Member) as Registered.
 unfold title_entry in Absent; apply no_matching_member in Absent.
 unfold title,title_prompt; rewrite Found,Absent,Registered.
 unfold title_accepts in Live; unfold capable_profile in Capable.
 rewrite Live,Capable,Nonblank,String.eqb_refl; reflexivity.
Qed.

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
