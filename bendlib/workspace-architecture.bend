import Base
import ../MODEL.bend as M
import ../WORKSPACE.bend as W
import ../PROJECTS.bend as Projects
import ../COMMANDS.bend as Commands
import ./protocol.bend as Protocol
import ./association-map.bend as Finite

# A product separates location from authority; a finite map owns project
# identities. The observations below refer to actual birth, delegation and
# registry operations, not an independently maintained workspace model.
type ContextBoundary is Type:
  ContextBoundary{
    coordinates: @+workspace:M.Workspace -> @sandbox:M.Sandbox -> @approval:M.ApprovalPolicy -> @project:Maybe<&2, Nat> ->
      {W.workspace(M.TaskContext{workspace, sandbox, approval, project}) == workspace : M.Workspace},
    inherited: @id:Nat -> @+parent:M.Task -> @call:String -> @branch:Nat -> @remaining:+List<M.Attempt> -> @message:Maybe<&2, String> ->
      {M.task_context(Commands.child(id, parent, call, branch, remaining, message)) == M.task_context(parent) : M.TaskContext},
    no_inherited_rights: @id:Nat -> @parent:M.Task -> @call:String -> @branch:Nat -> @remaining:+List<M.Attempt> -> @message:Maybe<&2, String> ->
      {M.task_operations(Commands.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<M.Operation()>},
    override_context: @+context:M.TaskContext -> @guidance:M.ProjectContext -> @task:M.Task ->
      {M.task_context(Commands.selected_parent(W.Selection{context, guidance}, task)) == context : M.TaskContext},
    project_frame: @registry:M.Projects -> @+world:M.World ->
      {Commands.entries(Projects.store(registry, world)) == Commands.entries(world) : +List<M.Task>},
    removal: @registry:M.Projects -> @+id:Nat ->
      {Projects.find(Projects.remove(id, registry), id) == None{} : Maybe<&2, M.Project>},
    protected_review: ({W.review_no_broader(M.FullAccess{}, M.AskForApproval{}) == False{} : Bool} &
      (@profile:M.Profile -> {W.review_no_broader(M.FullAccess{}, M.ApprovalForMe{profile}) == False{} : Bool})),
    refused_delegation: @+context:M.TaskContext -> @+guidance:M.ProjectContext -> @+parent:M.TaskContext -> @+count:Nat -> @+messages:+List<String> ->
      @rejected:{W.may_delegate(context, parent) == False{} : Bool} ->
      {Protocol.branch_selection(Done{W.Selection{context, guidance}}, count, messages, parent) ==
        Protocol.delegated(False{}, count, messages, W.Selection{context, guidance}) : Protocol.Invocation}
  }

law context_boundary:
  ContextBoundary
