import Base
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as Reasoning
import ../../bendlib/json.bend as J
import ../transport/schema.bend as Schema

# A workspace is a finite set of canonical directory observations plus a member
# selected as cwd. Sandbox and approval are separate coordinates of TaskContext.
# The host observes real paths; these predicates own admission of those values.
def valid_path(+path: String) -> Bool:
  String.starts_with(path, "/") && Nat.is_le(J.utf8_length(path), 4096n) &&
    Bool.not(String.contains(path, SCon{Chr{0}, SNil{}})) &&
    Bool.not(String.contains(path ++ "/", "/../")) &&
    Bool.not(String.contains(path ++ "/", "/./")) &&
    (String.eq(path, "/") || Bool.not(String.contains(path ++ "/", "//")))

def valid_roots(roots: +List<String>) -> Bool:
  match roots:
    case Nil{}: True{}
    case Con{+root, +rest}:
      valid_path(root) && Bool.not(Schema.contains(rest, root)) && valid_roots(rest)

def primary_member(roots: +List<String>, primary: Maybe<&2, String>) -> Bool:
  match roots primary:
    case Nil{} None{}: True{}
    case Con{root, rest} Some{primary}: Schema.contains(root <> rest, primary)
    case _ _: False{}

def valid(workspace: D.Workspace) -> Bool:
  D.Workspace{+roots, primary} = workspace
  Nat.is_le(List.length(&2, String, roots), 32n) && valid_roots(roots) && primary_member(roots, primary)

def primary(workspace: D.Workspace) -> Maybe<&2, String>:
  D.Workspace{roots, primary} = workspace
  primary

def roots(workspace: D.Workspace) -> +List<String>:
  D.Workspace{roots, primary} = workspace
  roots

def workspace(context: D.TaskContext) -> D.Workspace:
  D.TaskContext{workspace, sandbox, approval, project_id} = context
  workspace

def sandbox(context: D.TaskContext) -> D.Sandbox:
  D.TaskContext{workspace, sandbox, approval, project_id} = context
  sandbox

def approval(context: D.TaskContext) -> D.ApprovalPolicy:
  D.TaskContext{workspace, sandbox, approval, project_id} = context
  approval

def project_id(context: D.TaskContext) -> Maybe<&2, Nat>:
  D.TaskContext{workspace, sandbox, approval, project_id} = context
  project_id

def valid_reviewer_profile(+profile: D.Profile) -> Bool:
  D.profile_valid(profile) && Bool.not(Reasoning.automatic(D.profile_reasoning(profile))) &&
    D.profile_permitted(profile, D.profile_default(profile))

def valid_approval(policy: D.ApprovalPolicy) -> Bool:
  match policy:
    case D.ApprovalForMe{profile}: valid_reviewer_profile(profile)
    case _: True{}

def valid_context(context: D.TaskContext) -> Bool:
  D.TaskContext{workspace, sandbox, approval, project_id} = context
  valid(workspace) && valid_approval(approval)

def valid_guidance(guidance: D.ProjectContext) -> Bool:
  match guidance:
    case D.NoProject{}: True{}
    case D.ProjectContext{+workspace, +revision, +instructions}:
      valid_path(workspace) && Nat.is_le(J.utf8_length(instructions), D.project_limit()) &&
        ((String.eq(revision, "absent") && String.eq(instructions, "")) || Nat.is_eq(J.utf8_length(revision), 64n))

def guidance_member(primary: Maybe<&2, String>, guidance: D.ProjectContext) -> Bool:
  match primary guidance:
    case _ D.NoProject{}: True{}
    case Some{primary} D.ProjectContext{root, revision, text}: String.eq(primary, root)
    case _ _: False{}

def default_workspace(guidance: D.ProjectContext) -> D.Workspace:
  match guidance:
    case D.NoProject{}: D.Workspace{Nil{}, None{}}
    case D.ProjectContext{+root, revision, text}: D.Workspace{[root], Some{root}}

def defaults(guidance: D.ProjectContext) -> D.TaskContext:
  D.TaskContext{default_workspace(guidance), D.Sandbox{D.WorkspaceWrite{}, False{}}, D.AskForApproval{}, None{}}

def absent(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case _: False{}

def selected_primary(value: J.Json, roots: +List<String>) -> Maybe<&2, String>:
  match value:
    case J.Text{text}: Some{text}
    case _: List.head(&2, String, roots)

def read_workspace(value: J.Json, fallback: D.Workspace) -> D.Workspace:
  match value:
    case J.Null{}: fallback
    case +value:
      +roots = J.text_values(J.items(J.get(value, "roots")))
      D.Workspace{roots, selected_primary(J.get(value, "primary_root"), roots)}

def boolean_or(value: J.Json, fallback: Bool) -> Bool:
  match value:
    case J.Boolean{value}: value
    case _: fallback

def selected_sandbox(mode: String, network: Bool) -> Result<&2, &2, String, D.Sandbox>:
  match mode:
    case "workspace-write": Done{D.Sandbox{D.WorkspaceWrite{}, network}}
    case "read-only": Done{D.Sandbox{D.ReadOnly{}, network}}
    case _: Fail{"Sandbox mode must be workspace-write or read-only"}

def read_sandbox(value: J.Json, fallback: D.Sandbox) -> Result<&2, &2, String, D.Sandbox>:
  match value:
    case J.Null{}: Done{fallback}
    case +value:
      D.Sandbox{mode, network} = fallback
      selected_sandbox(J.text_or(J.get(value, "mode"), D.sandbox_mode_name(mode)),
        boolean_or(J.get(value, "network_access"), network))

def ordinary_reviewer(automatic: Bool, profile: D.Profile) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match automatic:
    case True{}: Fail{"An approval reviewer requires an ordinary profile; automatic reasoning is configured for task generations, not approval judgments"}
    case False{}: Done{D.ApprovalForMe{profile}}

def reviewer(found: Maybe<&2, D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match found:
    case None{}: Fail{"Approval for me requires a configured reviewer profile"}
    case Some{+profile}: ordinary_reviewer(Reasoning.automatic(D.profile_reasoning(profile)), profile)

def selected_approval(mode: String, key: String, profiles: +List<D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match mode:
    case "full-access": Done{D.FullAccess{}}
    case "ask-for-approval": Done{D.AskForApproval{}}
    case "approval-for-me": reviewer(D.find_profile(profiles, key))
    case _: Fail{"Approval mode must be full-access, ask-for-approval, or approval-for-me"}

def read_approval(value: J.Json, fallback: D.ApprovalPolicy, profile: D.Profile,
  profiles: +List<D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match value:
    case J.Null{}: Done{fallback}
    case +value:
      D.Profile{key, provider, name, reasoning, options} = profile
      selected_approval(J.text(J.get(value, "mode")), J.text_or(J.get(value, "reviewer_profile"), key), profiles)

def retained_guidance(same: Bool, guidance: D.ProjectContext) -> D.ProjectContext:
  match same:
    case True{}: guidance
    case False{}: D.NoProject{}

def read_guidance(value: J.Json, workspace: D.Workspace, +fallback: D.ProjectContext) -> D.ProjectContext:
  match value:
    case J.Null{}: retained_guidance(guidance_member(primary(workspace), fallback), fallback)
    case +value:
      D.ProjectContext{J.text(J.get(value, "workspace")), J.text(J.get(value, "revision")), J.text(J.get(value, "instructions"))}

type Selection is Data:
  Selection{context: D.TaskContext, guidance: D.ProjectContext}

def accepted(valid: Bool, selection: Selection) -> Result<&2, &2, String, Selection>:
  match valid:
    case True{}: Done{selection}
    case False{}: Fail{"Workspace roots must be canonical absolute directories with a member primary root and matching bounded guidance"}

def selected(sandbox: Result<&2, &2, String, D.Sandbox>, approval: Result<&2, &2, String, D.ApprovalPolicy>,
  +workspace: D.Workspace, project_id: Maybe<&2, Nat>, +guidance: D.ProjectContext) -> Result<&2, &2, String, Selection>:
  match sandbox approval:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{sandbox} Done{+approval}:
      accepted(valid(workspace) && valid_approval(approval) && valid_guidance(guidance) && guidance_member(primary(workspace), guidance),
        Selection{D.TaskContext{workspace, sandbox, approval, project_id}, guidance})

def resolve_checked(valid: Bool, +options: J.Json, base: D.TaskContext, guidance: D.ProjectContext,
  profile: D.Profile, profiles: +List<D.Profile>) -> Result<&2, &2, String, Selection>:
  match valid:
    case False{}: Fail{"Task settings do not satisfy the declared schema"}
    case True{}:
      D.TaskContext{workspace, sandbox, approval, project_id} = base
      +workspace = read_workspace(J.get(options, "workspace"), workspace)
      selected(read_sandbox(J.get(options, "sandbox"), sandbox),
        read_approval(J.get(options, "approval"), approval, profile, profiles), workspace, project_id,
        read_guidance(J.get(options, "guidance"), workspace, guidance))

def resolve(+options: J.Json, base: D.TaskContext, guidance: D.ProjectContext,
  profile: D.Profile, profiles: +List<D.Profile>) -> Result<&2, &2, String, Selection>:
  resolve_checked(absent(options) || Schema.valid(D.task_settings_schema(), options), options, base, guidance, profile, profiles)

# Directory inclusion is used only on admitted canonical observations. A model
# may delegate equal or narrower authority, never gain permissions through fork.
def below(+child: String, +parent: String) -> Bool:
  String.eq(parent, "/") || String.eq(child, parent) || String.starts_with(child, parent ++ "/")

def covered(+child: String, parents: +List<String>) -> Bool:
  match parents:
    case Nil{}: False{}
    case Con{parent, rest}: below(child, parent) || covered(child, rest)

def roots_within(children: +List<String>, +parents: +List<String>) -> Bool:
  match children:
    case Nil{}: True{}
    case Con{child, rest}: covered(child, parents) && roots_within(rest, parents)

def profile_same(a: D.Profile, b: D.Profile) -> Bool:
  D.Profile{key_a, provider_a, name_a, reasoning_a, options_a} = a
  D.Profile{key_b, provider_b, name_b, reasoning_b, options_b} = b
  String.eq(key_a, key_b) && String.eq(provider_a, provider_b) && String.eq(name_a, name_b) && Reasoning.same(reasoning_a, reasoning_b) && D.reasoning_options_same(options_a, options_b)

def review_no_broader(child: D.ApprovalPolicy, parent: D.ApprovalPolicy) -> Bool:
  match child parent:
    case _ D.FullAccess{}: True{}
    case D.AskForApproval{} _: True{}
    case D.ApprovalForMe{a} D.ApprovalForMe{b}: profile_same(a, b)
    case _ _: False{}

def writes_no_broader(child: D.SandboxMode, parent: D.SandboxMode, child_roots: +List<String>, parent_roots: +List<String>) -> Bool:
  match child parent:
    case D.ReadOnly{} _: True{}
    case D.WorkspaceWrite{} D.WorkspaceWrite{}: roots_within(child_roots, parent_roots)
    case _ _: False{}

def delegated_policy(parent: D.ApprovalPolicy, child: D.TaskContext, parent_workspace: D.Workspace, parent_sandbox: D.Sandbox) -> Bool:
  match parent:
    case D.FullAccess{}: True{}
    case +parent:
      D.TaskContext{D.Workspace{child_roots, child_primary}, D.Sandbox{child_mode, child_network}, child_approval, project_id} = child
      D.Sandbox{parent_mode, parent_network} = parent_sandbox
      (Bool.not(child_network) || parent_network) &&
        writes_no_broader(child_mode, parent_mode, child_roots, roots(parent_workspace)) && review_no_broader(child_approval, parent)

def may_delegate(child: D.TaskContext, parent: D.TaskContext) -> Bool:
  D.TaskContext{workspace, sandbox, approval, project_id} = parent
  delegated_policy(approval, child, workspace, sandbox)

def full_access(policy: D.ApprovalPolicy) -> Bool:
  match policy:
    case D.FullAccess{}: True{}
    case _: False{}

def default_access(context: D.TaskContext) -> D.ExecutionAccess:
  match context:
    case D.TaskContext{workspace, sandbox, D.FullAccess{}, project_id}: D.Unrestricted{}
    case _: D.Sandboxed{}
