From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8 Registry.
From Selvedge.Kernel Require Import Domain State Codec Tasks Workspace ChatgptArguments.
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
   ChatgptArguments.valid_args (F.job_arguments_json job) &&
   negb (existsb (fun entry => N.eqb (F.job_connection job) (F.job_connection (snd entry)) &&
     String.eqb (F.job_request job) (F.job_request (snd entry))) (F.sharing_jobs state)) &&
   (N.of_nat (List.length (F.sharing_jobs state)) <? 128) &&
   (F.sharing_next state <? ChatgptArguments.identity_maximum)
 | _,_ => false end.
