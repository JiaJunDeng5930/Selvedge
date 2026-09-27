import Base
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/schema.bend as Schema

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

def valid(workspace: M.Workspace) -> Bool:
  M.Workspace{+roots, primary} = workspace
  Nat.is_le(List.length(&2, String, roots), 32n) && valid_roots(roots) && primary_member(roots, primary)

def primary(workspace: M.Workspace) -> Maybe<&2, String>:
  M.Workspace{roots, primary} = workspace
  primary

def roots(workspace: M.Workspace) -> +List<String>:
  M.Workspace{roots, primary} = workspace
  roots

def workspace(context: M.TaskContext) -> M.Workspace:
  M.TaskContext{workspace, sandbox, approval, project_id} = context
  workspace

def sandbox(context: M.TaskContext) -> M.Sandbox:
  M.TaskContext{workspace, sandbox, approval, project_id} = context
  sandbox

def approval(context: M.TaskContext) -> M.ApprovalPolicy:
  M.TaskContext{workspace, sandbox, approval, project_id} = context
  approval

def project_id(context: M.TaskContext) -> Maybe<&2, Nat>:
  M.TaskContext{workspace, sandbox, approval, project_id} = context
  project_id

def valid_profile(profile: M.Profile) -> Bool:
  M.Profile{key, provider, name} = profile
  M.nonempty(key) && M.nonempty(provider) && M.nonempty(name)

def valid_approval(policy: M.ApprovalPolicy) -> Bool:
  match policy:
    case M.ApprovalForMe{profile}: valid_profile(profile)
    case _: True{}

def valid_context(context: M.TaskContext) -> Bool:
  M.TaskContext{workspace, sandbox, approval, project_id} = context
  valid(workspace) && valid_approval(approval)

def valid_guidance(guidance: M.ProjectContext) -> Bool:
  match guidance:
    case M.NoProject{}: True{}
    case M.ProjectContext{+workspace, +revision, +instructions}:
      valid_path(workspace) && Nat.is_le(J.utf8_length(instructions), M.project_limit()) &&
        ((String.eq(revision, "absent") && String.eq(instructions, "")) || Nat.is_eq(J.utf8_length(revision), 64n))

def guidance_member(primary: Maybe<&2, String>, guidance: M.ProjectContext) -> Bool:
  match primary guidance:
    case _ M.NoProject{}: True{}
    case Some{primary} M.ProjectContext{root, revision, text}: String.eq(primary, root)
    case _ _: False{}

def default_workspace(guidance: M.ProjectContext) -> M.Workspace:
  match guidance:
    case M.NoProject{}: M.Workspace{Nil{}, None{}}
    case M.ProjectContext{+root, revision, text}: M.Workspace{[root], Some{root}}

def defaults(guidance: M.ProjectContext) -> M.TaskContext:
  M.TaskContext{default_workspace(guidance), M.Sandbox{M.WorkspaceWrite{}, False{}}, M.AskForApproval{}, None{}}

def texts(values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: J.text(value) <> texts(rest)

def absent(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case _: False{}

def selected_primary(value: J.Json, roots: +List<String>) -> Maybe<&2, String>:
  match value:
    case J.Text{text}: Some{text}
    case _: List.head(&2, String, roots)

def read_workspace(value: J.Json, fallback: M.Workspace) -> M.Workspace:
  match value:
    case J.Null{}: fallback
    case +value:
      +roots = texts(J.items(J.get(value, "roots")))
      M.Workspace{roots, selected_primary(J.get(value, "primary_root"), roots)}

def text_or(value: J.Json, fallback: String) -> String:
  match value:
    case J.Text{text}: text
    case _: fallback

def boolean_or(value: J.Json, fallback: Bool) -> Bool:
  match value:
    case J.Boolean{value}: value
    case _: fallback

def selected_sandbox(mode: String, network: Bool) -> Result<&2, &2, String, M.Sandbox>:
  match mode:
    case "workspace-write": Done{M.Sandbox{M.WorkspaceWrite{}, network}}
    case "read-only": Done{M.Sandbox{M.ReadOnly{}, network}}
    case _: Fail{"Sandbox mode must be workspace-write or read-only"}

def read_sandbox(value: J.Json, fallback: M.Sandbox) -> Result<&2, &2, String, M.Sandbox>:
  match value:
    case J.Null{}: Done{fallback}
    case +value:
      M.Sandbox{mode, network} = fallback
      selected_sandbox(text_or(J.get(value, "mode"), M.sandbox_mode_name(mode)),
        boolean_or(J.get(value, "network_access"), network))

def reviewer(found: Maybe<&2, M.Profile>) -> Result<&2, &2, String, M.ApprovalPolicy>:
  match found:
    case None{}: Fail{"Approval for me requires a configured reviewer profile"}
    case Some{profile}: Done{M.ApprovalForMe{profile}}

def selected_approval(mode: String, key: String, profiles: +List<M.Profile>) -> Result<&2, &2, String, M.ApprovalPolicy>:
  match mode:
    case "full-access": Done{M.FullAccess{}}
    case "ask-for-approval": Done{M.AskForApproval{}}
    case "approval-for-me": reviewer(M.find_profile(profiles, key))
    case _: Fail{"Approval mode must be full-access, ask-for-approval, or approval-for-me"}

def read_approval(value: J.Json, fallback: M.ApprovalPolicy, profile: M.Profile,
  profiles: +List<M.Profile>) -> Result<&2, &2, String, M.ApprovalPolicy>:
  match value:
    case J.Null{}: Done{fallback}
    case +value:
      M.Profile{key, provider, name} = profile
      selected_approval(J.text(J.get(value, "mode")), text_or(J.get(value, "reviewer_profile"), key), profiles)

def retained_guidance(same: Bool, guidance: M.ProjectContext) -> M.ProjectContext:
  match same:
    case True{}: guidance
    case False{}: M.NoProject{}

def read_guidance(value: J.Json, workspace: M.Workspace, +fallback: M.ProjectContext) -> M.ProjectContext:
  match value:
    case J.Null{}: retained_guidance(guidance_member(primary(workspace), fallback), fallback)
    case +value:
      M.ProjectContext{J.text(J.get(value, "workspace")), J.text(J.get(value, "revision")), J.text(J.get(value, "instructions"))}

type Selection is Data:
  Selection{context: M.TaskContext, guidance: M.ProjectContext}

def accepted(valid: Bool, selection: Selection) -> Result<&2, &2, String, Selection>:
  match valid:
    case True{}: Done{selection}
    case False{}: Fail{"Workspace roots must be canonical absolute directories with a member primary root and matching bounded guidance"}

def selected(sandbox: Result<&2, &2, String, M.Sandbox>, approval: Result<&2, &2, String, M.ApprovalPolicy>,
  +workspace: M.Workspace, project_id: Maybe<&2, Nat>, +guidance: M.ProjectContext) -> Result<&2, &2, String, Selection>:
  match sandbox approval:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{sandbox} Done{+approval}:
      accepted(valid(workspace) && valid_approval(approval) && valid_guidance(guidance) && guidance_member(primary(workspace), guidance),
        Selection{M.TaskContext{workspace, sandbox, approval, project_id}, guidance})

def resolve_checked(valid: Bool, +options: J.Json, base: M.TaskContext, guidance: M.ProjectContext,
  profile: M.Profile, profiles: +List<M.Profile>) -> Result<&2, &2, String, Selection>:
  match valid:
    case False{}: Fail{"Task settings do not satisfy the declared schema"}
    case True{}:
      M.TaskContext{workspace, sandbox, approval, project_id} = base
      +workspace = read_workspace(J.get(options, "workspace"), workspace)
      selected(read_sandbox(J.get(options, "sandbox"), sandbox),
        read_approval(J.get(options, "approval"), approval, profile, profiles), workspace, project_id,
        read_guidance(J.get(options, "guidance"), workspace, guidance))

def resolve(+options: J.Json, base: M.TaskContext, guidance: M.ProjectContext,
  profile: M.Profile, profiles: +List<M.Profile>) -> Result<&2, &2, String, Selection>:
  resolve_checked(absent(options) || Schema.valid(M.task_settings_schema(), options), options, base, guidance, profile, profiles)

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

def profile_same(a: M.Profile, b: M.Profile) -> Bool:
  M.Profile{key_a, provider_a, name_a} = a
  M.Profile{key_b, provider_b, name_b} = b
  String.eq(key_a, key_b) && String.eq(provider_a, provider_b) && String.eq(name_a, name_b)

def review_no_broader(child: M.ApprovalPolicy, parent: M.ApprovalPolicy) -> Bool:
  match child parent:
    case _ M.FullAccess{}: True{}
    case M.AskForApproval{} _: True{}
    case M.ApprovalForMe{a} M.ApprovalForMe{b}: profile_same(a, b)
    case _ _: False{}

def writes_no_broader(child: M.SandboxMode, parent: M.SandboxMode, child_roots: +List<String>, parent_roots: +List<String>) -> Bool:
  match child parent:
    case M.ReadOnly{} _: True{}
    case M.WorkspaceWrite{} M.WorkspaceWrite{}: roots_within(child_roots, parent_roots)
    case _ _: False{}

def delegated_policy(parent: M.ApprovalPolicy, child: M.TaskContext, parent_workspace: M.Workspace, parent_sandbox: M.Sandbox) -> Bool:
  match parent:
    case M.FullAccess{}: True{}
    case +parent:
      M.TaskContext{M.Workspace{child_roots, child_primary}, M.Sandbox{child_mode, child_network}, child_approval, project_id} = child
      M.Sandbox{parent_mode, parent_network} = parent_sandbox
      (Bool.not(child_network) || parent_network) &&
        writes_no_broader(child_mode, parent_mode, child_roots, roots(parent_workspace)) && review_no_broader(child_approval, parent)

def may_delegate(child: M.TaskContext, parent: M.TaskContext) -> Bool:
  M.TaskContext{workspace, sandbox, approval, project_id} = parent
  delegated_policy(approval, child, workspace, sandbox)

def full_access(policy: M.ApprovalPolicy) -> Bool:
  match policy:
    case M.FullAccess{}: True{}
    case _: False{}

def default_access(context: M.TaskContext) -> M.ExecutionAccess:
  match context:
    case M.TaskContext{workspace, sandbox, M.FullAccess{}, project_id}: M.Unrestricted{}
    case _: M.Sandboxed{}
