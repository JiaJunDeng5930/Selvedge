import Base
import ../bendlib/domain.bend as D
import ./user-context.bend as Context
import ./ui-world.bend as V
import ./interface.bend as InterfaceView

type Requirements is Type:
  Requirements{
    unrestricted_filesystem: @mode:D.SandboxMode -> {Context.filesystem_summary(D.Unrestricted{}, mode) == "Full access" : String},
    unrestricted_network: @network:Bool -> {Context.network_summary(D.Unrestricted{}, network) == "Available" : String},
    sandboxed_filesystem: @mode:D.SandboxMode -> {Context.filesystem_summary(D.Sandboxed{}, mode) == D.sandbox_mode_name(mode) : String},
    sandboxed_network: @network:Bool -> {Context.network_summary(D.Sandboxed{}, network) == V.execution_network_summary(network) : String},
    committed_permissions: @task:Nat -> @workspace:D.Workspace -> @mode:D.SandboxMode -> @network:Bool -> @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @profiles:+List<D.Profile> ->
      {V.observation_permissions(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}, profiles) == Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ V.policy_approval_summary(approval) : String},
    committed_facts: @task:Nat -> @workspace:D.Workspace -> @mode:D.SandboxMode -> @network:Bool -> @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @profiles:+List<D.Profile> ->
      {InterfaceView.observation_facts(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}, profiles) == Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ V.policy_approval_summary(approval) : String},
    configured_permissions: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @profiles:+List<D.Profile> ->
      {V.observation_permissions(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, profiles) == "Configured: " ++ V.execution_permissions_summary(Context.unwrap_sandbox(sandbox), V.value_approval_summary(approval, profiles)) : String},
    configured_facts: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @profiles:+List<D.Profile> ->
      {InterfaceView.observation_facts(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, profiles) == "Configured: " ++ InterfaceView.sandbox_facts(Context.unwrap_sandbox(sandbox)) ++ "; " ++ V.value_approval_summary(approval, profiles) : String}}

law evidence:
  Requirements
