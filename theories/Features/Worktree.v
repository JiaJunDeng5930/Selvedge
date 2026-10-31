From Selvedge.Kernel Require InputRoute.
From Selvedge.Kernel Require CallbackDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Programming Require Receiver Completion.
From Selvedge.Kernel Require Import Numbers Domain State Codec Workspace Tasks CommandExecution.
From Selvedge.Kernel Require CommandResult DecisionComposition TaskScope.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Work WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition receiver := WorkspaceBinding.receiver.
Definition lookup := WorkspaceBinding.owned.
Definition store := Receiver.install receiver.
Definition completion_path owner := Receiver.field world_features
 (Receiver.field Selvedge.Features.Domain.feature_worktrees
   (Receiver.inject (Selvedge.Features.Domain.WorktreeEntry owner)
     (Receiver.keyed Selvedge.Features.Domain.worktree_task))).
Definition ignored value := Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [].
Definition primary (space:workspace) := match workspace_primary space with Some root=>root | None=>"" end.
Definition archived := WorkspaceBinding.archived.
Definition inside := WorkspaceBinding.inside.
Definition any_inside := WorkspaceBinding.any_inside.
Definition task_uses_root := WorkspaceBinding.task_uses_root.
Definition job_uses_root := WorkspaceBinding.job_uses_root.
Definition job_uses_resource := WorkspaceBinding.job_uses_resource.
Definition root_unused := WorkspaceBinding.root_unused.
Definition bound_tasks_unused := WorkspaceBinding.bound_tasks_unused.
Definition archive_allowed := WorkspaceBinding.archive_allowed.
Definition execution_ready := WorkspaceBinding.execution_ready.
Definition workspace_available := WorkspaceBinding.workspace_available.
Definition primary_workspace (space : workspace) :=
 match workspace_primary space with Some root=>Workspace [root] (Some root) | None=>default_workspace end.
Definition resource_settings (id : N) (backend : WorkspaceBackend.backend) (settings : task_settings) :=
 Settings (if WorkspaceBackend.cloud backend then primary_workspace (settings_workspace settings) else settings_workspace settings)
 (settings_project settings)
 (if WorkspaceBackend.cloud backend then Sandbox WorkspaceWrite true else settings_sandbox settings)
 (if WorkspaceBackend.cloud backend then FullAccess else settings_approval settings)
 (settings_guidance settings) (settings_worktree settings) (Some id).
Definition environment_notice : string :=
 "Bash runs in the task cloud environment with Full Access. MCP tools may return paths on the local host; these paths are not necessarily available in the cloud environment.".
Definition resource_task (id : N) (backend : WorkspaceBackend.backend) (task : task) :=
 let old:=task_contract task in
 let contract:=Contract (contract_profile old) (contract_tools old) (resource_settings id backend (contract_settings old))
  (contract_max_fork old) (contract_max_descendants old) (contract_plugins old) (contract_reviewers old) in
 let history:=if WorkspaceBackend.cloud backend then task_history task++[EnvironmentNotice environment_notice] else task_history task in
 Task contract (task_current_profile task) (resource_settings id backend (task_current_settings task))
 (match task_lifecycle task with Running activity operations=>Frozen activity operations | other=>other end)
 history (task_queued task) (task_lineage task) (task_side_parent task) (task_side_cursor task) (task_model_cursor task).
Definition project_primary_matches (settings : task_settings) (value : world) :=
 match settings_project settings with
 | None=>true
 | Some id=>match registry_at id (world_projects value) with
   | Some project=>String.eqb (primary (settings_workspace settings)) (primary (project_workspace project))
   | None=>false end
 end.
Definition effective := WorkspaceBinding.for_task.
Definition resolve_workspace (space : option (D.denote (D.nullable Codec.workspace_declaration))) (project_id : option N) (value : world) :=
 let selected := match space with
 | Some (inl source) => match Codec.workspace_of_values source with
   | Some space => WorkspaceBinding.select_resource space value | None => None end
 | None | Some (inr (inl _)) => match project_id with
   | Some id => match registry_at id (world_projects value) with
     | Some project => if negb (project_deleted project) &&
         WorkspaceBinding.resource_ready (project_workspace project) (project_resource project) value
       then Some (project_resource project) else None
     | None => None end
   | None => None end
 | Some (inr (inr impossible)) => match impossible with end end in
 match selected with
 | Some owner => Selvedge.Kernel.State.success (JObject [("resource",WorkspaceBinding.reference_execution owner value);("workspace_binding",workspace_binding_json owner)])
 | None => Selvedge.Kernel.State.failure "workspace_unavailable" "The workspace does not select one available execution environment"
 end.
Definition handle_resolve_workspace (payload:Selvedge.Generated.Commands.resolve_workspace_payload) (caller:option N) (value:world) :json :=
 resolve_workspace
   (Selvedge.Generated.Commands.resolve_workspace_workspace_admitted payload)
   (Selvedge.Generated.Commands.resolve_workspace_project_id payload) value.
Definition handle_list_worktrees (payload:Selvedge.Generated.Commands.list_worktrees_payload) (caller:option N) (value:world) :json :=
 Selvedge.Kernel.State.success (JObject [("worktrees",JArray (map Observation.worktree_json (Selvedge.Features.Domain.feature_worktrees (world_features value))))]).
Definition handle_read_worktree (payload:Selvedge.Generated.Commands.read_worktree_payload) (caller:option N) (value:world) :json :=
 match Selvedge.Kernel.State.find_task (Selvedge.Generated.Commands.read_worktree_task_id payload) value with None=>Selvedge.Kernel.State.failure "task_not_found" "Task does not exist." | Some _=>match effective (Selvedge.Generated.Commands.read_worktree_task_id payload) value with Some tree=>Selvedge.Kernel.State.success (Observation.worktree_json tree) | None=>Selvedge.Kernel.State.failure "not_found" "Task worktree does not exist." end end.
Definition archive_tree (tree:Selvedge.Features.Domain.worktree) (value:world) :decision :=
 let id:=Selvedge.Features.Domain.worktree_task tree in let source:=Selvedge.Features.Domain.worktree_source tree in
 match Selvedge.Features.Domain.worktree_root tree with None=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) value [] | Some root=>
 let target:=Selvedge.Features.Domain.worktree_target_primary tree in
 if root_unused id root value then
 Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (store (Selvedge.Features.Domain.with_worktree_phase (Selvedge.Features.Domain.TreeArchiving (RequestEnvelope.Owned (root,target))) tree) value) [Selvedge.Kernel.State.ArchiveWorktree id source root (Selvedge.Features.Domain.worktree_backend tree)]
 else Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (store (Selvedge.Features.Domain.with_worktree_phase (Selvedge.Features.Domain.TreeArchiveFailed root target "Worktree is still used by another task. Archive shared tasks before retrying.") tree) value) [] end.
Definition retry (id:N) (value:world) :=
 if negb (archive_allowed id value) then Selvedge.Kernel.State.reject "worktree_in_use" "This worktree is shared by other tasks. Archive those tasks before archiving its owner." value else
 match lookup id value,Selvedge.Kernel.State.find_task id value with
 | Some tree,Some task=>match Selvedge.Features.Domain.worktree_phase tree with
 | Selvedge.Features.Domain.TreeArchiveFailed _ _ _=>if archived task then archive_tree tree value
 else Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value
 | _=>Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value end
 | _,_=>Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value end.
Inductive creation_plan (before:world) (settings:task_settings) :=
 | UseWorkspace
 | ReuseBinding (owner:N) (tree:Selvedge.Features.Domain.worktree)
     (observed:lookup owner before=Some tree)
 | ProvisionLocal | ProvisionCloud.
Arguments UseWorkspace {before settings}.
Arguments ReuseBinding {before settings}.
Arguments ProvisionLocal {before settings}.
Arguments ProvisionCloud {before settings}.
Definition provision_plan (before:world) (backend:WorkspaceBackend.backend) (settings:task_settings)
 :option (creation_plan before settings) :=
 match WorkspaceBinding.resolve settings before with
 | Some tree=>if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) then None
   else Some (if WorkspaceBackend.cloud backend then ProvisionCloud else ProvisionLocal)
 | None=>Some (if WorkspaceBackend.cloud backend then ProvisionCloud else ProvisionLocal) end.
Definition reuse_plan (before:world) (settings:task_settings) (owner:N) :option (creation_plan before settings) :=
 match lookup owner before as found return lookup owner before=found -> option (creation_plan before settings) with
 | Some tree=>fun observed=>match Selvedge.Features.Domain.worktree_phase tree with
   | Selvedge.Features.Domain.TreeReady _ _ | Selvedge.Features.Domain.TreeCreating _=>Some (ReuseBinding owner tree observed)
   | _=>None end
 | None=>fun _=>None end eq_refl.
Definition select_creation_plan (before:world) (selected:task_settings)
 (managed:option bool) (backend:option WorkspaceBackend.backend) :option (creation_plan before selected) :=
 match backend with
 | Some backend=>provision_plan before backend selected
 | None=>match managed with
   | Some true=>provision_plan before WorkspaceBackend.Local selected
   | _=>match settings_resource selected with
     | Some owner=>reuse_plan before selected owner
     | None=>if match managed with Some false=>false | _=>settings_worktree selected end
       then provision_plan before WorkspaceBackend.Local selected else Some UseWorkspace end end end.
(* The entry identity controls failure projection; resource selection and ordinary
   start resolution still share one immutable plan. *)
Inductive creation_intent := ImplicitCreation | IdleTaskCreation | WorkTaskCreation
 | WorktreeTaskCreation | WorkspaceTaskCreation | GraphTaskCreation.
Definition creation_entry (intent:creation_intent) (caller:option N) :=
 match intent with
 | WorkspaceTaskCreation=>Tasks.WorkspaceCreation
 | WorktreeTaskCreation=>Tasks.WorktreeCreation
 | WorkTaskCreation=>match caller with Some _=>Tasks.NativeFeatureCreation | None=>Tasks.WorktreeCreation end
 | GraphTaskCreation=>match caller with Some _=>Tasks.NativeFeatureCreation | None=>Tasks.ManagedCreation end
 | IdleTaskCreation=>Tasks.IdleCreation
 | ImplicitCreation=>match caller with Some _=>Tasks.NativeCreation | None=>Tasks.OrdinaryCreation end end.
Definition resource_error (intent:creation_intent) (before:world)
 (selected:task_settings) (plan:creation_plan before selected) :option Tasks.failure_cause :=
 let backend:=match plan with ProvisionCloud=>Some WorkspaceBackend.TencentCvm
   | ProvisionLocal=>Some WorkspaceBackend.Local | _=>None end in
 match backend with None=>
   if WorkspaceBinding.selection_available selected before then None else Some Tasks.WorkspaceUnavailable
 | Some backend=>
 if WorkspaceBackend.cloud backend && negb (project_primary_matches selected before) then
 Some Tasks.ProjectPrimaryMismatch else
 match workspace_primary (settings_workspace selected) with
 | None=>Some Tasks.MissingPrimaryWorkspace
 | Some _=>if Workspace.valid_workspace (settings_workspace selected) &&
   Workspace.valid_path (primary (settings_workspace selected)) &&
   workspace_available (settings_workspace selected) before then None
   else Some Tasks.InvalidWorkspace end end.
Record planned_start (before:world) := PlannedStart {
 planned_intent : creation_intent;
 planned_task : Tasks.resolved_start;
 planned_resource : creation_plan before (Tasks.start_settings planned_task);
 planned_admitted : resource_error planned_intent before (Tasks.start_settings planned_task) planned_resource = None
}.
Arguments PlannedStart {before}.
Arguments planned_task {before}.
Arguments planned_resource {before}.
Definition start_plan_result (before:world) := CommandResult.result (planned_start before).
Definition prepare_resolved (intent:creation_intent) (managed:option bool)
 (backend:option WorkspaceBackend.backend) (start:Tasks.resolved_start) (before:world)
 :start_plan_result before.
Proof.
 destruct (select_creation_plan before (Tasks.start_settings start) managed backend) as [plan|].
 - destruct (resource_error intent before (Tasks.start_settings start) plan) as [cause|] eqn:Admitted.
   + exact (CommandResult.refuse (Tasks.failure_code (creation_entry intent None) cause) (Tasks.failure_message cause)).
   + exact (CommandResult.Accepted (PlannedStart intent start plan Admitted)).
 - exact (CommandResult.refuse (Tasks.failure_code (creation_entry intent None) Tasks.WorkspaceUnavailable)
     (Tasks.failure_message Tasks.WorkspaceUnavailable)).
Defined.
(** The resource interpreter retains Task birth's actual fresh reference. The
    only decoration it may add is that reference's pending resource and effect. *)
Record born_start (before : world) := BornStart {
 born_task : Tasks.birth_result before;
 born_resource : option WorkspaceBackend.backend
}.
Arguments BornStart {before}.
Arguments born_task {before}.
Arguments born_resource {before}.
Definition born_identity {before} (birth : born_start before) := Tasks.birth_id (born_task birth).
Definition born_world {before} (birth : born_start before) :=
 let core := born_task birth in
 match born_resource birth with
 | None => Tasks.birth_world core
 | Some backend => let space := settings_workspace (task_current_settings (Tasks.birth_task core)) in
   store (Selvedge.Features.Domain.Worktree (Tasks.birth_id core) (primary space)
     (Selvedge.Features.Domain.TreeCreating (RequestEnvelope.Owned false)) backend) (Tasks.birth_world core)
 end.
Definition born_effects {before} (birth : born_start before) :=
 match born_resource birth with
 | None => []
 | Some backend => let space := settings_workspace (task_current_settings (Tasks.birth_task (born_task birth))) in
   [CreateWorktree (born_identity birth) (primary space) space backend]
 end.
Definition interpret_planned_birth {before : world} (plan : planned_start before) (current : world) :=
 let start := planned_task plan in
 let fresh := next_task current in
 let task := Tasks.start_task start in
 let '(prepared,resource) := match planned_resource plan with
 | UseWorkspace => (task,None)
 | ReuseBinding _ tree _ =>
   (if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) then
     append_history [EnvironmentNotice environment_notice] task else task,None)
 | ProvisionLocal => (resource_task fresh WorkspaceBackend.Local task,Some WorkspaceBackend.Local)
 | ProvisionCloud => (resource_task fresh WorkspaceBackend.TencentCvm task,Some WorkspaceBackend.TencentCvm) end in
 BornStart (Tasks.birth_prepared prepared current) resource.
Definition born_decision {before} (birth : born_start before) :=
 accept (JObject [("task_id",number (born_identity birth))]) (born_world birth) (born_effects birth).
(** This pure interpreter is the shared meaning used by the closed batch
    language below and by its proofs. Production consumes scoped plans. *)
Definition consume_planned_start {before : world} (plan : planned_start before) (current : world) :=
 born_decision (interpret_planned_birth plan current).
Lemma born_world_preserves_tasks : forall before (birth : born_start before),
 world_tasks (born_world birth) = world_tasks (Tasks.birth_world (born_task birth)).
Proof. intros before [birth resource]; destruct resource; reflexivity. Qed.
Lemma born_world_preserves_works : forall before (birth : born_start before),
 Selvedge.Features.Domain.feature_works (world_features (born_world birth)) =
 Selvedge.Features.Domain.feature_works (world_features before).
Proof.
 intros before [birth resource]; destruct resource;
 change (Selvedge.Features.Domain.feature_works (world_features (Tasks.birth_world birth)) =
   Selvedge.Features.Domain.feature_works (world_features before));
 rewrite (Tasks.birth_features before birth); reflexivity.
Qed.
Definition final_settings {before} (plan : planned_start before) :=
 let selected := Tasks.start_settings (planned_task plan) in
 match planned_resource plan with
 | ProvisionLocal => resource_settings (next_task before) WorkspaceBackend.Local selected
 | ProvisionCloud => resource_settings (next_task before) WorkspaceBackend.TencentCvm selected
 | _ => selected end.
Definition final_authority {before} (caller : option N) (plan : planned_start before) :=
 match caller with None => true | Some owner =>
 match find_task owner before with
 | Some task => Workspace.may_delegate (final_settings plan) (task_current_settings task)
 | None => false end end.
Record scoped_start (before : world) := ScopedStart {
 scoped_caller : option N;
 scoped_plan : planned_start before;
 scoped_authorized : final_authority scoped_caller scoped_plan = true
}.
Arguments ScopedStart {before}.
Arguments scoped_caller {before}.
Arguments scoped_plan {before}.
Definition scoped_plan_result (before : world) := CommandResult.result (scoped_start before).
Definition prepare_scoped (intent : creation_intent) (caller : option N)
 (managed : option bool) (backend : option WorkspaceBackend.backend)
 (start : Tasks.resolved_start) (before : world) : scoped_plan_result before.
Proof.
 destruct (prepare_resolved intent managed backend start before) as [plan|reply].
 - destruct (Bool.bool_dec (final_authority caller plan) true) as [Authorized|Refused].
   + exact (CommandResult.Accepted (ScopedStart caller plan Authorized)).
   + exact (CommandResult.refuse (Tasks.failure_code (creation_entry intent caller) Tasks.AuthorityExpansion)
       (Tasks.failure_message Tasks.AuthorityExpansion)).
 - exact (CommandResult.Rejected reply).
Defined.
Definition attach_born {origin before} (owner : option (Work.owner_scope origin))
 (birth : born_start before)
 (works : Selvedge.Features.Domain.feature_works (world_features (born_world birth)) =
   Selvedge.Features.Domain.feature_works (world_features origin)) :=
 match owner with None => born_world birth
 | Some owner => Work.own_birth owner (born_task birth) (born_world birth)
   (born_world_preserves_tasks before birth) works end.
(** A batch frame is a closed sequence of admitted births. It can append several
    Graph tasks, but cannot replace an old task, change projects/environment,
    or inject an unrelated resource observation between plan and consumption. *)
Inductive birth_frame (origin : world) : world -> Type :=
 | InitialFrame : birth_frame origin origin
 | AdvanceFrame : forall current, birth_frame origin current ->
   forall (plan : scoped_start origin) (owner : option (Work.owner_scope origin))
   (works : Selvedge.Features.Domain.feature_works
      (world_features (born_world (interpret_planned_birth (scoped_plan plan) current))) =
      Selvedge.Features.Domain.feature_works (world_features origin)),
   birth_frame origin (attach_born owner (interpret_planned_birth (scoped_plan plan) current) works).
Arguments InitialFrame {origin}.
Arguments AdvanceFrame {origin current}.
Lemma frame_preserves_works : forall origin current (frame : birth_frame origin current),
 Selvedge.Features.Domain.feature_works (world_features current) =
 Selvedge.Features.Domain.feature_works (world_features origin).
Proof.
 intros origin current frame; destruct frame as [|current frame plan owner works]; [reflexivity|].
 destruct owner; exact works.
Qed.
Record start_transition (origin before : world) := StartTransition {
 transition_birth : born_start before;
 transition_owner : option (Work.owner_scope origin);
 transition_works : Selvedge.Features.Domain.feature_works (world_features (born_world transition_birth)) =
   Selvedge.Features.Domain.feature_works (world_features origin);
 transition_frame : birth_frame origin (attach_born transition_owner transition_birth transition_works)
}.
Arguments StartTransition {origin before}.
Arguments transition_birth {origin before}.
Arguments transition_owner {origin before}.
Arguments transition_works {origin before}.
Arguments transition_frame {origin before}.
Definition transition_world {origin before} (created : start_transition origin before) :=
 attach_born (transition_owner created) (transition_birth created) (transition_works created).
Definition transition_identity {origin before} (created : start_transition origin before) :=
 born_identity (transition_birth created).
Definition transition_effects {origin before} (created : start_transition origin before) :=
 born_effects (transition_birth created).
Definition transition_change {origin before} (created : start_transition origin before) :=
 CommandResult.Change (JObject [("task_id",number (transition_identity created))])
   (transition_world created) (transition_effects created).
Definition consume_scoped_start {origin current} (plan : scoped_start origin)
 (frame : birth_frame origin current) (owner : option (Work.owner_scope origin))
 : start_transition origin current.
Proof.
 pose (birth := interpret_planned_birth (scoped_plan plan) current).
 assert (works : Selvedge.Features.Domain.feature_works (world_features (born_world birth)) =
   Selvedge.Features.Domain.feature_works (world_features origin)).
 { rewrite born_world_preserves_works. exact (frame_preserves_works origin current frame). }
 exact (StartTransition birth owner works (AdvanceFrame frame plan owner works)).
Defined.
Theorem scoped_birth_uses_its_actual_identity : forall origin current
 (plan : scoped_start origin) (frame : birth_frame origin current) owner,
 transition_identity (consume_scoped_start plan frame owner) =
 Tasks.birth_id (born_task (transition_birth (consume_scoped_start plan frame owner))).
Proof. reflexivity. Qed.
Theorem transition_tasks_are_the_witnessed_birth : forall origin before
 (created : start_transition origin before),
 world_tasks (transition_world created) = world_tasks before ++
   [Tasks.birth_task (born_task (transition_birth created))].
Proof.
 intros origin before [birth owner works frame].
 unfold transition_world; cbn [transition_birth transition_owner transition_works].
 destruct owner;
 change (world_tasks (born_world birth) = world_tasks before ++ [Tasks.birth_task (born_task birth)]);
 rewrite born_world_preserves_tasks; apply Tasks.birth_tasks.
Qed.
Theorem transition_identity_is_fresh : forall origin before (created : start_transition origin before),
 transition_identity created = next_task before.
Proof. intros; apply Tasks.birth_fresh. Qed.
Theorem transition_preserves_board : forall origin before (created : start_transition origin before),
 Selvedge.Features.Domain.feature_board (world_features (transition_world created)) =
 Selvedge.Features.Domain.feature_board (world_features before).
Proof.
 intros origin before [[birth resource] owner works frame].
 unfold transition_world,attach_born,born_world; cbn [transition_birth transition_owner transition_works born_task born_resource].
 destruct owner; destruct resource;
 change (Selvedge.Features.Domain.feature_board (world_features (Tasks.birth_world birth)) =
   Selvedge.Features.Domain.feature_board (world_features before));
 rewrite (Tasks.birth_features before birth); reflexivity.
Qed.
Theorem scoped_plan_bounds_final_authority : forall before (plan : scoped_start before),
 final_authority (scoped_caller plan) (scoped_plan plan) = true.
Proof. intros before [caller plan Authorized]; exact Authorized. Qed.
Definition start_allowed (settings:option Codec.settings_request) (caller:option N) (before:world)
 (cached:Tasks.start_resolution) := match cached with
 | Tasks.StartRefused _=>true
 | Tasks.StartResolved start=>CommandExecution.creation_allowed settings (Tasks.start_settings start) caller before end.
Definition creation_result (before : world) := CommandResult.result (start_transition before before).
Definition creation_decision {before} (result : creation_result before) :=
 CommandResult.commit before transition_change result.
Definition prepare_selected_birth {before:world} (owner:option (Work.owner_scope before))
 (intent:creation_intent) (caller:option N) (managed:option bool) (backend:option WorkspaceBackend.backend)
 (start:Tasks.resolved_start) : creation_result before :=
 CommandResult.map (fun plan=>consume_scoped_start plan InitialFrame owner)
   (prepare_scoped intent caller managed backend start before).
Definition resolve_start_birth (intent:creation_intent) (settings:option Codec.settings_request)
 (caller:option N) (managed:option bool) (backend:option WorkspaceBackend.backend)
 (cached:Tasks.start_resolution) (before:world) : creation_result before :=
 let entry:=creation_entry intent caller in
 match cached with
 | Tasks.StartRefused cause=>CommandResult.refuse (Tasks.failure_code entry cause) (Tasks.failure_message cause)
 | Tasks.StartResolved start=>if start_allowed settings caller before cached then
   prepare_selected_birth None intent caller managed backend start
   else CommandResult.refuse (Tasks.failure_code entry Tasks.AuthorityExpansion)
     (Tasks.failure_message Tasks.AuthorityExpansion) end.
Definition consume_start_resolution (intent:creation_intent) (settings:option Codec.settings_request)
 (caller:option N) (managed:option bool) (backend:option WorkspaceBackend.backend)
 (cached:Tasks.start_resolution) (before:world) :=
 creation_decision (resolve_start_birth intent settings caller managed backend cached before).
Definition create_intent_result (intent:creation_intent) (name:string) (effort:option string)
 (contents:content) (settings:option Codec.settings_request) (idle:bool) (caller:option N)
 (managed:option bool) (backend:option WorkspaceBackend.backend) (value:world) :=
 let entry:=creation_entry intent caller in
 resolve_start_birth intent settings caller managed backend
 (CommandExecution.resolve_context_start entry name effort contents settings idle caller value) value.
Definition create_intent (intent:creation_intent) (name:string) (effort:option string)
 (contents:content) (settings:option Codec.settings_request) (idle:bool) (caller:option N)
 (managed:option bool) (backend:option WorkspaceBackend.backend) (value:world) :=
 creation_decision (create_intent_result intent name effort contents settings idle caller managed backend value).
Definition create_selected_result (name:string) (effort:option string) (contents:content) (settings:option Codec.settings_request)
 (idle:bool) (caller:option N) (managed:option bool) (value:world) :=
 create_intent_result (if idle then IdleTaskCreation else ImplicitCreation) name effort contents settings idle caller managed None value.
Definition create_selected (name:string) (effort:option string) (contents:content) (settings:option Codec.settings_request) (idle:bool) (caller:option N) (managed:option bool) (value:world) :=
 creation_decision (create_selected_result name effort contents settings idle caller managed value).
Definition create (name:string) (effort:option string) (contents:content) (settings:option Codec.settings_request) (caller:option N) (managed:bool) (value:world) :=
 create_intent WorktreeTaskCreation name effort contents settings false caller (Some managed) None value.
Definition consume_owned_start (owner:option N) (intent:creation_intent) (settings:option Codec.settings_request)
 (caller:option N) (managed:option bool) (backend:option WorkspaceBackend.backend)
 (cached:Tasks.start_resolution) (value:world) :=
 match owner with
 | Some id=>match Work.select_owner id value with None=>reject "work_not_found" "The Work does not exist." value
   | Some owner=>match cached with
     | Tasks.StartRefused cause=>Tasks.refuse_start (creation_entry intent caller) cause value
     | Tasks.StartResolved start=>creation_decision
       (prepare_selected_birth (Some owner) intent caller managed backend start) end end
 | None=>consume_start_resolution intent settings caller managed backend cached value end.
Definition create_owned_cached (owner:N) (intent:creation_intent) (settings:option Codec.settings_request)
 (caller:option N) (managed:option bool) (backend:option WorkspaceBackend.backend)
 (cached:Tasks.start_resolution) (value:world) :=
 if start_allowed settings caller value cached then
 consume_owned_start (Some owner) intent settings caller managed backend cached value
 else Tasks.refuse_start (creation_entry intent caller) Tasks.AuthorityExpansion value.
Definition create_idle_owned (owner:option N) (name:string) (effort:option string)
 (settings:option Codec.settings_request) (caller:option N) (managed:option bool) (value:world) :=
 let entry:=creation_entry IdleTaskCreation caller in
 let cached:=CommandExecution.resolve_context_start entry name effort [] settings true caller value in
 match cached with
 | Tasks.StartRefused cause=>Tasks.refuse_start entry cause value
 | Tasks.StartResolved start=>
   match match owner with None=>Some None | Some id=>option_map (@Some (Work.owner_scope value)) (Work.select_owner id value) end with
   | Some selected=>if start_allowed settings caller value cached then
       creation_decision (prepare_selected_birth selected IdleTaskCreation caller managed None start)
     else Tasks.refuse_start entry Tasks.AuthorityExpansion value
   | None=>reject "invalid_arguments" "The Work does not exist." value end end.

Definition configure_task_execution (payload : Selvedge.Generated.Commands.configure_task_execution_payload) (value : world) :=
 Tasks.configure_execution
   (Selvedge.Generated.Commands.configure_task_execution_task_id payload)
   (Selvedge.Generated.Commands.configure_task_execution_profile payload)
   (Selvedge.Generated.Commands.configure_task_execution_reasoning payload)
   (Selvedge.Generated.Commands.configure_task_execution_sandbox_admitted payload)
   (Selvedge.Generated.Commands.configure_task_execution_approval_admitted payload) value.
Definition handle_configure_task_execution (payload:Selvedge.Generated.Commands.configure_task_execution_payload) (caller:option N) (value:world) :decision :=
 configure_task_execution payload value.
Definition handle_create_result (payload:Selvedge.Generated.Commands.create_payload) (caller:option N) (value:world) :=
 CommandResult.bind (CommandExecution.content_result (Selvedge.Generated.Commands.create_message_admitted payload)
   (Selvedge.Generated.Commands.create_images_admitted payload))
   (fun contents=>create_selected_result (Selvedge.Generated.Commands.create_profile payload)
     (Selvedge.Generated.Commands.create_reasoning payload) contents
     (option_map (Codec.settings_request_of_values true) (Selvedge.Generated.Commands.create_settings_admitted payload)) false caller None value).
Definition handle_create (payload:Selvedge.Generated.Commands.create_payload) (caller:option N) (value:world) :decision :=
 creation_decision (handle_create_result payload caller value).
Definition handle_create_idle (payload:Selvedge.Generated.Commands.create_idle_payload) (caller:option N) (value:world) :decision :=
 create_idle_owned
   (Selvedge.Generated.Commands.create_idle_work_id payload) (Selvedge.Generated.Commands.create_idle_profile payload)
   (Selvedge.Generated.Commands.create_idle_reasoning payload) (option_map (Codec.settings_request_of_values true) (Selvedge.Generated.Commands.create_idle_settings_admitted payload))
   caller (Selvedge.Generated.Commands.create_idle_create_worktree payload) value.
Definition handle_create_workspace_task (payload:Selvedge.Generated.Commands.create_workspace_task_payload) (caller:option N) (value:world) :decision :=
 CommandExecution.with_content
   (Selvedge.Generated.Commands.create_workspace_task_message_admitted payload) (Selvedge.Generated.Commands.create_workspace_task_images_admitted payload)
   (fun contents=>let settings:=option_map (Codec.settings_request_of_values true) (Selvedge.Generated.Commands.create_workspace_task_settings_admitted payload) in
     let cached:=CommandExecution.resolve_context_start (creation_entry WorkspaceTaskCreation caller)
       (Selvedge.Generated.Commands.create_workspace_task_profile payload) (Selvedge.Generated.Commands.create_workspace_task_reasoning payload)
       contents settings false caller value in
     if start_allowed settings caller value cached then
       consume_owned_start (Selvedge.Generated.Commands.create_workspace_task_work_id payload) WorkspaceTaskCreation settings caller None
         (Some (WorkspaceBackend.of_value (Selvedge.Generated.Commands.create_workspace_task_backend payload))) cached value
     else Tasks.refuse_start (creation_entry WorkspaceTaskCreation caller) Tasks.AuthorityExpansion value) value.
Definition handle_create_worktree_task (payload:Selvedge.Generated.Commands.create_worktree_task_payload) (caller:option N) (value:world) :decision :=
 CommandExecution.with_content (Selvedge.Generated.Commands.create_worktree_task_message_admitted payload) (Selvedge.Generated.Commands.create_worktree_task_images_admitted payload)
   (fun contents=>create (Selvedge.Generated.Commands.create_worktree_task_profile payload) (Selvedge.Generated.Commands.create_worktree_task_reasoning payload) contents (option_map (Codec.settings_request_of_values true) (Selvedge.Generated.Commands.create_worktree_task_settings_admitted payload)) caller true value) value.
Definition handle_create_work_task (payload:Selvedge.Generated.Commands.create_work_task_payload) (caller:option N) (value:world) :decision :=
 CommandExecution.with_content
   (Selvedge.Generated.Commands.create_work_task_message_admitted payload) (Selvedge.Generated.Commands.create_work_task_images_admitted payload)
   (fun contents=>let settings:=option_map (Codec.settings_request_of_values true) (Selvedge.Generated.Commands.create_work_task_settings_admitted payload) in
   create_owned_cached (Selvedge.Generated.Commands.create_work_task_work_id payload) WorkTaskCreation settings caller
   (Selvedge.Generated.Commands.create_work_task_create_worktree payload) None
   (CommandExecution.resolve_context_start (creation_entry WorkTaskCreation caller)
     (Selvedge.Generated.Commands.create_work_task_profile payload) (Selvedge.Generated.Commands.create_work_task_reasoning payload)
     contents settings false caller value) value) value.
Definition handle_retry_worktree_archive (payload:Selvedge.Generated.Commands.retry_worktree_archive_payload) (caller:option N) (value:world) :decision :=
 retry (Selvedge.Generated.Commands.retry_worktree_archive_task_id payload) value.
Definition selected_workspace (target:string) (space:workspace) := match workspace_primary space with
 | None=>space | Some source=>Workspace (map (fun root=>if String.eqb root source then target else root) (workspace_roots space)) (Some target) end.
Definition selected_settings (space:workspace) (guidance:Guidance.t) (settings:task_settings) := Settings space (settings_project settings)
 (settings_sandbox settings) (settings_approval settings) guidance (settings_worktree settings) (settings_resource settings).
Definition install_workspace (phase : lifecycle) (space:workspace) (guidance:Guidance.t) (task:task) :=
 let old:=task_contract task in
 let frozen:=selected_settings (selected_workspace (primary space) (settings_workspace (contract_settings old))) guidance (contract_settings old) in
 let chosen:=selected_settings space guidance (task_current_settings task) in
 let contract:=Contract (contract_profile old) (contract_tools old) frozen (contract_max_fork old) (contract_max_descendants old) (contract_plugins old) (contract_reviewers old) in
 Tasks.promote (Task contract (task_current_profile task) chosen phase
 (task_history task ++ [SettingsMessage chosen (profile_key (task_current_profile task)) (profile_reasoning (task_current_profile task))])
 (task_queued task) (task_lineage task) (task_side_parent task) (task_side_cursor task) (task_model_cursor task)).
Definition completed_task (space : workspace) (guidance : Guidance.t) (task : task) :=
 install_workspace (match task_lifecycle task with Frozen activity operations=>Running activity operations
  | other=>other end) space guidance task.
(* A side or native child can inherit the pending environment before its
   physical root exists. Setup selects that root for every live binding before
   the scheduler captures any of their first model requests. *)
Definition complete_binding (owner id : N) (space : workspace) (guidance : Guidance.t) (task : task) :=
 if N.eqb owner id || archived task then task else
 if Workspace.same_resource (settings_resource (contract_settings (task_contract task))) (Some owner)
 then install_workspace (task_lifecycle task) space guidance task else task.
Definition complete_bindings (owner : N) (space : workspace) (guidance : Guidance.t) (value : world) :=
 Selvedge.Kernel.State.with_tasks
  (indexed (fun id task => complete_binding owner id space guidance task) 0 (world_tasks value)) value.
Definition failed_task (message:string) (task:task) := with_lifecycle (if archived task then task_lifecycle task else Stopped Idle []) (append_history [FailureMessage message] task).
Definition created_valid (root:string) (space:workspace) (task:task) :=
 inside root (primary space) &&
 Json.equal (workspace_json space) (workspace_json (selected_workspace (primary space) (settings_workspace (task_current_settings task)))).
Inductive creation_observation := CreatedWorkspace (root:string) (space:workspace) (guidance:Guidance.t)
 | CreationFailure (root:option string) (message:string).
Definition creation_contract (task:task) (observed:creation_observation) := match observed with
 | CreatedWorkspace root space _ => created_valid root space task | CreationFailure _ _ => true end.
Definition admit_creation (task:task) (observed:creation_observation)
 : ArgumentDeclaration.checked (creation_contract task) := match observed with
 | CreatedWorkspace root space guidance =>
   match ArgumentDeclaration.admit (fun space=>created_valid root space task) space with
   | Some accepted => exist _ (CreatedWorkspace root (proj1_sig accepted) guidance) (proj2_sig accepted)
   | None => exist _ (CreationFailure (Some root) "Worktree creation returned an invalid workspace or guidance") eq_refl end
 | CreationFailure root message => exist _ (CreationFailure root message) eq_refl end.
Definition creation_finished (observed:creation_observation)
 : Completion.Row.amendment Selvedge.Features.Domain.worktree_contents Selvedge.Features.Domain.TreeCreating :=
 Completion.Row.Amend [] (match observed with
 | CreatedWorkspace root space _ => Completion.done (Selvedge.Features.Domain.TreeReady root (primary space))
 | CreationFailure root message => Completion.done (Selvedge.Features.Domain.TreeCreateFailed root message) end).
Definition finish_creation {before} (reference:TaskScope.task_reference before)
 (observed:ArgumentDeclaration.checked (creation_contract (TaskScope.selected reference)))
 (received:Completion.Row.receipt (completion_path (TaskScope.owner reference))
   Selvedge.Features.Domain.contents_phase Selvedge.Features.Domain.TreeCreating Completion.Owner tt
   (fun _ _=>Some (creation_finished (proj1_sig observed))) before) : decision :=
 let id:=TaskScope.owner reference in let task:=TaskScope.selected reference in
 let ready:=Completion.Row.after received in
 let updated:=match proj1_sig observed with
 | CreatedWorkspace _ space guidance => if archived task then ready else
   Selvedge.Kernel.State.put_task id (completed_task space guidance task) (complete_bindings id space guidance ready)
 | CreationFailure _ message => Selvedge.Kernel.State.put_task id (failed_task message task) ready end in
 if archived task then archive_tree (Selvedge.Features.Domain.WorktreeEntry id (Completion.Row.updated received)) updated
 else Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) updated [].
Definition created (owner:N) (observed:creation_observation) (value:world) : decision :=
 match TaskScope.select owner value with
 | Some reference =>
   let selected:=admit_creation (TaskScope.selected reference) observed in
   match Completion.Row.consume (completion_path (TaskScope.owner reference)) Selvedge.Features.Domain.contents_phase
     Selvedge.Features.Domain.TreeCreating Completion.Owner tt (fun _ _=>Some (creation_finished (proj1_sig selected))) value with
   | Some received => finish_creation reference selected received
   | None => ignored value end
 | None => ignored value end.
Inductive archive_outcome := ArchivedAt (root : string)
 | ReservationReleased (previous_root reservation_id : string).
Definition reservation_id_declaration := ArgumentDeclaration.Text
 (ArgumentDeclaration.TextConstraints 1 ArgumentDeclaration.maximum_natural ArgumentDeclaration.maximum_natural false false false None).
Definition archive_outcome_decoders : list (DeclarationFields.decoder archive_outcome) := [
 DeclarationFields.Decoder (DeclarationFields.declare "kind" (JString "archived_at")
   [DeclarationFields.required "root" Workspace.path_declaration])
   (fun values=>let root:=proj1_sig (fst values) in
     if Workspace.canonical_path root then Some (ArchivedAt root) else None);
 DeclarationFields.Decoder (DeclarationFields.declare "kind" (JString "reservation_released")
   [DeclarationFields.required "previous_root" Workspace.path_declaration;
    DeclarationFields.required "reservation_id" reservation_id_declaration])
   (fun values=>let root:=proj1_sig (fst values) in
     if Workspace.canonical_path root then Some (ReservationReleased root (proj1_sig (fst (snd values)))) else None)].
Definition archive_outcome_of := DeclarationFields.decode_cases archive_outcome_decoders.
Definition archived_root (outcome : archive_outcome) : option string :=
 match outcome with ArchivedAt root => Some root | ReservationReleased _ _ => None end.
Record creation_completion := CreationCompletion {
 creation_owner : N; creation_observed : creation_observation
}.
Definition completed_workspace (values : ArgumentDeclaration.denote CallbackDeclarations.created_workspace) :=
 let fields := proj1_sig values in
 Workspace (map (@proj1_sig _ _) (proj1_sig (fst fields))) (Some (proj1_sig (fst (snd fields)))).
Definition creation_from_values (ok : bool) (address : Schema.fields (CallbackDeclarations.coordinates (ModelDeclarations.Worktree true)))
 : DeclarationFields.values (CallbackDeclarations.payload (ModelDeclarations.Worktree true) ok) -> option creation_completion :=
 if ok as outcome return DeclarationFields.values (CallbackDeclarations.payload (ModelDeclarations.Worktree true) outcome) -> option creation_completion
 then fun values =>
   let root := proj1_sig (fst values) in let space := completed_workspace (fst (snd values)) in
   match Guidance.of_values (fst (snd (snd values))) with
   | Some guidance =>
     if Workspace.canonical_path root && forallb Workspace.canonical_path (workspace_roots space) &&
        Workspace.valid_selection space && Codec.guidance_member space guidance
     then Some (CreationCompletion (head address) (CreatedWorkspace root space guidance)) else None
   | None => None end
 else fun values => let root := option_map (@proj1_sig _ _) (fst values) in
   if match root with Some root => Workspace.valid_path root | None => true end
   then Some (CreationCompletion (head address) (CreationFailure root (proj1_sig (fst (snd values))))) else None.
Definition decode_creation_completion (received : CallbackDeclarations.decoded (ModelDeclarations.Worktree true)) :=
 let '(existT _ ok (address,values)) := received in creation_from_values ok address values.
Inductive archive_observation := ArchiveSucceeded (outcome:archive_outcome) | ArchiveFailure (message:string).
Definition archive_from_values (ok : bool) (address : Schema.fields (CallbackDeclarations.coordinates (ModelDeclarations.Worktree false)))
 : DeclarationFields.values (CallbackDeclarations.payload (ModelDeclarations.Worktree false) ok) -> option (N * archive_observation) :=
 if ok as outcome return DeclarationFields.values (CallbackDeclarations.payload (ModelDeclarations.Worktree false) outcome) -> option (N * archive_observation)
 then fun values => option_map (fun outcome => (head address,ArchiveSucceeded outcome)) (archive_outcome_of (fst values))
 else fun values => Some (head address,ArchiveFailure (proj1_sig (fst values))).
Definition decode_archive_completion (received : CallbackDeclarations.decoded (ModelDeclarations.Worktree false)) :=
 let '(existT _ ok (address,values)) := received in archive_from_values ok address values.
Definition archive_choice (observed:archive_observation) (contents:Selvedge.Features.Domain.worktree_contents)
 (request:RequestEnvelope.owned (string*string))
 : option (Completion.Row.amendment Selvedge.Features.Domain.worktree_contents Selvedge.Features.Domain.TreeArchiving) :=
 let '(root,target):=RequestEnvelope.owned_input request in
 match observed with
 | ArchiveSucceeded outcome =>
   if match outcome with ArchivedAt _=>true | ReservationReleased previous _=>
     negb (WorkspaceBackend.cloud (Selvedge.Features.Domain.contents_backend contents)) && String.eqb previous root end
   then Some (Completion.Row.Amend [] (Completion.done (Selvedge.Features.Domain.TreeArchived (archived_root outcome) target)))
   else None
 | ArchiveFailure message => Some (Completion.Row.Amend [] (Completion.done
     (Selvedge.Features.Domain.TreeArchiveFailed root target message))) end.
Definition archived_result id observed value :=
 match Completion.Row.consume (completion_path id) Selvedge.Features.Domain.contents_phase
   Selvedge.Features.Domain.TreeArchiving Completion.Owner tt (archive_choice observed) value with
 | Some received => Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (Completion.Row.after received) []
 | None => ignored value end.
Definition completion_inputs := [
 InputRoute.callback (ModelDeclarations.Worktree true) (fun received =>
   option_map (fun payload => fun value =>
     (true,true,created (creation_owner payload) (creation_observed payload) value))
     (decode_creation_completion received));
 InputRoute.callback (ModelDeclarations.Worktree false) (fun received =>
   option_map (fun '(id,observed) => fun value => (true,true,archived_result id observed value))
     (decode_archive_completion received))].
Definition archive_after (tree:Selvedge.Features.Domain.worktree) : DecisionComposition.step := fun value _ =>
 match Selvedge.Kernel.State.find_task (Selvedge.Features.Domain.worktree_task tree) value with Some task=>if archived task then
 match Selvedge.Features.Domain.worktree_phase tree with
 | Selvedge.Features.Domain.TreeCreating (RequestEnvelope.Owned false)=>DecisionComposition.unchanged (store (Selvedge.Features.Domain.with_worktree_phase (Selvedge.Features.Domain.TreeCreating (RequestEnvelope.Owned true)) tree) value)
 | Selvedge.Features.Domain.TreeReady _ _ | Selvedge.Features.Domain.TreeCreateFailed _ _=>DecisionComposition.from_decision (archive_tree tree value)
 | _=>DecisionComposition.unchanged value end else DecisionComposition.unchanged value | None=>DecisionComposition.unchanged value end.
Definition after_transition (_before:world) : DecisionComposition.step := fun value effects =>
 DecisionComposition.each (Selvedge.Features.Domain.feature_worktrees (world_features value)) archive_after value effects.
Definition recover (value:world) := value.
