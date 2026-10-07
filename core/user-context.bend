import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../WORKSPACE.bend as W
import ../PROJECTS.bend as Projects
import ../FEATURES.bend as F
import ../bendlib/domain.bend as D
import ../bendlib/tasks.bend as Tasks
import ../bendlib/json.bend as J
import ../bendlib/schema.bend as Schema

# User input is not an execution fact. Directories become facts only after the
# host observes canonical paths and root guidance; tasks freeze the admitted result.
type Origin is Data:
  EnvironmentDefaults{}
  ProjectDefaults{project: Nat}
  ParentTask{task: Nat}
  ProjectForParent{task: Nat, project: Nat}

type ApprovalChoice is Data:
  Ask{}
  Unrestricted{}
  AutomaticReview{profile: String}

type Configuration is Data:
  Configuration{origin: Origin, workspace: Maybe<&2, D.Workspace>,
    sandbox: Maybe<&2, D.Sandbox>, approval: Maybe<&2, ApprovalChoice>}

type Change is Data:
  ChooseOrigin{origin: Origin}
  SetWorkspace{workspace: D.Workspace}
  UseDefaultWorkspace{}
  SetSandbox{sandbox: D.Sandbox}
  UseDefaultSandbox{}
  SetApproval{approval: ApprovalChoice}
  UseDefaultApproval{}

type WorkspaceValue is Data:
  InheritedWorkspace{value: D.Workspace}
  EnteredWorkspace{value: D.Workspace}

type SandboxValue is Data:
  InheritedSandbox{value: D.Sandbox}
  ChosenSandbox{value: D.Sandbox}

def unwrap_sandbox(value: SandboxValue) -> D.Sandbox:
  match value:
    case InheritedSandbox{sandbox}: sandbox
    case ChosenSandbox{sandbox}: sandbox

type ApprovalValue is Data:
  InheritedApproval{value: D.ApprovalPolicy}
  ChosenApproval{value: ApprovalChoice}

# This is the information visible while composing. Entered paths are deliberately
# not described as the actual workspace or as successfully observed directories.
type Preview is Data:
  ContextUnavailable{reason: String}
  ProspectiveContext{origin: Origin, project: Maybe<&2, Nat>, workspace: WorkspaceValue,
    sandbox: SandboxValue, approval: ApprovalValue, guidance: GuidancePreview}

type EffectiveContext is Data:
  EffectiveContext{task: Nat, context: D.TaskContext, guidance: D.ProjectContext, default_access: D.ExecutionAccess}

type Observation is Data:
  DraftExecution{preview: Preview}
  CommittedExecution{context: EffectiveContext}

def filesystem_summary(access: D.ExecutionAccess, mode: D.SandboxMode) -> String:
  match access:
    case D.Unrestricted{}: "Full access"
    case D.Sandboxed{}: D.sandbox_mode_name(mode)

def network_summary(access: D.ExecutionAccess, allowed: Bool) -> String:
  match access:
    case D.Unrestricted{}: "Available"
    case D.Sandboxed{}:
      match allowed:
        case True{}: "Network enabled"
        case False{}: "Network disabled"

def approval_choice(policy: D.ApprovalPolicy) -> ApprovalChoice:
  match policy:
    case D.AskForApproval{}: Ask{}
    case D.FullAccess{}: Unrestricted{}
    case D.ApprovalForMe{D.Profile{key, provider, name, reasoning, options}}: AutomaticReview{key}

def observed_approval(value: ApprovalValue) -> ApprovalChoice:
  match value:
    case InheritedApproval{policy}: approval_choice(policy)
    case ChosenApproval{choice}: choice

def approval_option(choice: ApprovalChoice) -> String:
  match choice:
    case Ask{}: "ask"
    case Unrestricted{}: "full-access"
    case AutomaticReview{profile}: "automatic"

type DirectoryObservation is Data:
  DirectoryObservation{workspace: D.Workspace, guidance: D.ProjectContext}

type WorkspaceEdit is Data:
  AddRoot{path: String}
  RemoveRoot{path: String}
  ChoosePrimary{path: String}

type GuidancePreview is Data:
  InheritedGuidance{guidance: D.ProjectContext}
  AwaitingDirectoryGuidance{}

def added_roots(exists: Bool, roots: +List<String>, path: String) -> +List<String>:
  match exists:
    case True{}: roots
    case False{}: List.append(&2, String, roots, [path])

def surviving_primary(present: Bool, primary: Maybe<&2, String>, roots: +List<String>) -> Maybe<&2, String>:
  match present:
    case True{}: primary
    case False{}: List.head(&2, String, roots)

def member_primary(primary: Maybe<&2, String>, roots: +List<String>) -> Bool:
  match primary:
    case None{}: False{}
    case Some{path}: Schema.contains(roots, path)

def workspace_roots(+roots: +List<String>, +primary: Maybe<&2, String>) -> D.Workspace:
  D.Workspace{roots, surviving_primary(member_primary(primary, roots), primary, roots)}

def choose_primary(member: Bool, roots: +List<String>, path: String, previous: Maybe<&2, String>) -> D.Workspace:
  match member:
    case True{}: D.Workspace{roots, Some{path}}
    case False{}: D.Workspace{roots, previous}

def keep_path(same: Bool, root: String, rest: +List<String>) -> +List<String>:
  match same:
    case True{}: rest
    case False{}: root <> rest

def remove_path(roots: +List<String>, +path: String) -> +List<String>:
  match roots:
    case Nil{}: Nil{}
    case Con{+root, rest}: keep_path(String.eq(root, path), root, remove_path(rest, path))

def edit_workspace(change: WorkspaceEdit, workspace: D.Workspace) -> D.Workspace:
  match change:
    case AddRoot{+path}:
      D.Workspace{+roots, primary} = workspace
      workspace_roots(added_roots(Schema.contains(roots, path), roots, path), primary)
    case RemoveRoot{+path}:
      D.Workspace{roots, primary} = workspace
      workspace_roots(remove_path(roots, path), primary)
    case ChoosePrimary{+path}:
      D.Workspace{+roots, previous} = workspace
      choose_primary(Schema.contains(roots, path), roots, path, previous)

def selected_workspace(value: WorkspaceValue) -> D.Workspace:
  match value:
    case InheritedWorkspace{workspace}: workspace
    case EnteredWorkspace{workspace}: workspace

def edit(config: Configuration, change: Change) -> Configuration:
  Configuration{origin, workspace, sandbox, approval} = config
  match change:
    case ChooseOrigin{next}: Configuration{next, workspace, sandbox, approval}
    case SetWorkspace{next}: Configuration{origin, Some{next}, sandbox, approval}
    case UseDefaultWorkspace{}: Configuration{origin, None{}, sandbox, approval}
    case SetSandbox{next}: Configuration{origin, workspace, Some{next}, approval}
    case UseDefaultSandbox{}: Configuration{origin, workspace, None{}, approval}
    case SetApproval{next}: Configuration{origin, workspace, sandbox, Some{next}}
    case UseDefaultApproval{}: Configuration{origin, workspace, sandbox, None{}}

def edit_preview(value: Preview, change: WorkspaceEdit, config: Configuration) -> Result<&2, &2, String, Configuration>:
  match value:
    case ContextUnavailable{reason}: Fail{reason}
    case ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}:
      Done{edit(config, SetWorkspace{edit_workspace(change, selected_workspace(workspace))})}

def parent(found: Maybe<&2, D.Task>) -> Result<&2, &2, String, W.Selection>:
  match found:
    case None{}: Fail{"The parent task no longer exists"}
    case Some{task}: Done{Commands.task_selection(task)}

def inherited_project(selection: W.Selection, +id: Nat, world: M.World()) -> Result<&2, &2, String, W.Selection>:
  W.Selection{context, guidance} = selection
  Projects.selected(Projects.find(Projects.registry(F.State(), world), id), id, context)

def project_on_parent(base: Result<&2, &2, String, W.Selection>, id: Nat, world: M.World()) -> Result<&2, &2, String, W.Selection>:
  match base:
    case Fail{reason}: Fail{reason}
    case Done{selection}: inherited_project(selection, id, world)

def inherited(origin: Origin, +world: M.World()) -> Result<&2, &2, String, W.Selection>:
  match origin:
    case EnvironmentDefaults{}: Done{Commands.environment_selection(Commands.settings(world))}
    case ProjectDefaults{id}: inherited_project(Commands.environment_selection(Commands.settings(world)), id, world)
    case ParentTask{id}: parent(Tasks.find(Commands.entries(world), id))
    case ProjectForParent{task, id}: project_on_parent(parent(Tasks.find(Commands.entries(world), task)), id, world)

def guidance_preview(workspace: Maybe<&2, D.Workspace>, guidance: D.ProjectContext) -> GuidancePreview:
  match workspace:
    case None{}: InheritedGuidance{guidance}
    case Some{value}: AwaitingDirectoryGuidance{}

def workspace_value(input: Maybe<&2, D.Workspace>, base: D.Workspace) -> WorkspaceValue:
  match input:
    case None{}: InheritedWorkspace{base}
    case Some{value}: EnteredWorkspace{value}

def sandbox_value(input: Maybe<&2, D.Sandbox>, base: D.Sandbox) -> SandboxValue:
  match input:
    case None{}: InheritedSandbox{base}
    case Some{value}: ChosenSandbox{value}

def approval_value(input: Maybe<&2, ApprovalChoice>, base: D.ApprovalPolicy) -> ApprovalValue:
  match input:
    case None{}: InheritedApproval{base}
    case Some{value}: ChosenApproval{value}

def preview_selected(base: Result<&2, &2, String, W.Selection>, config: Configuration) -> Preview:
  match base:
    case Fail{reason}: ContextUnavailable{reason}
    case Done{W.Selection{D.TaskContext{workspace, sandbox, approval, project}, guidance}}:
      Configuration{origin, +entered_workspace, entered_sandbox, entered_approval} = config
      ProspectiveContext{origin, project, workspace_value(entered_workspace, workspace),
        sandbox_value(entered_sandbox, sandbox), approval_value(entered_approval, approval), guidance_preview(entered_workspace, guidance)}

def preview(+config: Configuration, world: M.World()) -> Preview:
  Configuration{origin, workspace, sandbox, approval} = config
  preview_selected(inherited(origin, world), config)

# A task's observation uses its contract, never the project's current defaults.
def modify_workspace(+config: Configuration, change: WorkspaceEdit, world: M.World()) -> Result<&2, &2, String, Configuration>:
  edit_preview(preview(config, world), change, config)

def defaults(origin: Origin) -> Configuration:
  Configuration{origin, None{}, None{}, None{}}

def approval_json(choice: ApprovalChoice) -> J.Json:
  match choice:
    case Ask{}: J.Object{[J.Field{"mode", J.Text{"ask-for-approval"}}]}
    case Unrestricted{}: J.Object{[J.Field{"mode", J.Text{"full-access"}}]}
    case AutomaticReview{profile}: J.Object{[J.Field{"mode", J.Text{"approval-for-me"}}, J.Field{"reviewer_profile", J.Text{profile}}]}

def origin_fields(origin: Origin) -> +List<J.Field>:
  match origin:
    case ProjectDefaults{id}: [J.Field{"project_id", J.nat(id)}]
    case ProjectForParent{task, id}: [J.Field{"project_id", J.nat(id)}]
    case _: Nil{}

def workspace_fields(workspace: Maybe<&2, D.Workspace>) -> +List<J.Field>:
  match workspace:
    case None{}: Nil{}
    case Some{value}: [J.Field{"workspace", D.workspace_json(value)}]

def sandbox_fields(sandbox: Maybe<&2, D.Sandbox>) -> +List<J.Field>:
  match sandbox:
    case None{}: Nil{}
    case Some{value}: [J.Field{"sandbox", D.sandbox_json(value)}]

def approval_fields(approval: Maybe<&2, ApprovalChoice>) -> +List<J.Field>:
  match approval:
    case None{}: Nil{}
    case Some{value}: [J.Field{"approval", approval_json(value)}]

def settings(config: Configuration) -> J.Json:
  Configuration{origin, workspace, sandbox, approval} = config
  J.Object{List.append(&2, J.Field, origin_fields(origin), List.append(&2, J.Field,
    workspace_fields(workspace), List.append(&2, J.Field, sandbox_fields(sandbox), approval_fields(approval))))}

def required_workspace(config: Configuration) -> Maybe<&2, D.Workspace>:
  Configuration{origin, workspace, sandbox, approval} = config
  workspace

def effective_contract(contract: D.Contract, task: Nat) -> EffectiveContext:
  D.Contract{model, tools, max_fork, max_descendants, plugins, +context} = contract
  EffectiveContext{task, context, D.model_guidance(model), W.default_access(context)}

def effective(+task: D.Task) -> EffectiveContext:
  effective_contract(D.task_contract(task), D.task_id(task))

def observation_valid(observation: DirectoryObservation) -> Bool:
  DirectoryObservation{+workspace, +guidance} = observation
  W.valid(workspace) && W.valid_guidance(guidance) && W.guidance_member(W.primary(workspace), guidance)

def observed_settings(config: Configuration, observation: DirectoryObservation) -> J.Json:
  Configuration{origin, previous, sandbox, approval} = config
  DirectoryObservation{workspace, guidance} = observation
  J.Object{List.append(&2, J.Field, origin_fields(origin), List.append(&2, J.Field,
    [J.Field{"workspace", D.workspace_json(workspace)}, J.Field{"guidance", D.project_json(guidance)}],
    List.append(&2, J.Field, sandbox_fields(sandbox), approval_fields(approval))))}
