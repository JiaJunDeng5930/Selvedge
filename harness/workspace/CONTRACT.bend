import Base
import ../features/MODEL.bend as F
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./WORKSPACE.bend as W
import ./PROJECTS.bend as Projects
import ../COMMANDS.bend as Commands
import ../protocol/PROGRAM.bend as Protocol
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/json.bend as J
import ../../bendlib/equality.bend as Same

# A product separates location from authority; a finite map owns project
# identities. The observations below refer to actual birth, delegation and
# registry operations, not an independently maintained workspace model.
type ContextBoundary is Type:
  ContextBoundary{
    guidance_text_equality: @+left:String -> @+right:String -> {Same.string_equal(left, right) == String.eq(left, right) : Bool},
    guidance_byte_length: @+text:String -> {J.utf8_length(text) == J.utf8_length_spec(text) : Nat},
    coordinates: @+workspace:D.Workspace -> @sandbox:D.Sandbox -> @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> ->
      {W.workspace(D.TaskContext{workspace, sandbox, approval, project}) == workspace : D.Workspace},
    inherited: @id:Nat -> @+parent:D.Task -> @call:String -> @branch:Nat -> @remaining:+List<D.Attempt> -> @message:Maybe<&2, String> ->
      {D.task_context(Commands.child(id, parent, call, branch, remaining, message)) == D.task_context(parent) : D.TaskContext},
    no_inherited_rights: @id:Nat -> @parent:D.Task -> @call:String -> @branch:Nat -> @remaining:+List<D.Attempt> -> @message:Maybe<&2, String> ->
      {D.task_operations(Commands.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<D.Operation()>},
    override_context: @+context:D.TaskContext -> @guidance:D.ProjectContext -> @task:D.Task ->
      {D.task_context(Commands.selected_parent(W.Selection{context, guidance}, task)) == context : D.TaskContext},
    project_frame: @registry:D.Projects -> @+world:M.World() ->
      {Commands.entries(Projects.store(F.State(), registry, world)) == Commands.entries(world) : +List<D.Task>},
    removal: @registry:D.Projects -> @+id:Nat ->
      {Projects.find(Projects.remove(id, registry), id) == None{} : Maybe<&2, D.Project>},
    protected_review: ({W.review_no_broader(D.FullAccess{}, D.AskForApproval{}) == False{} : Bool} &
      (@profile:D.Profile -> {W.review_no_broader(D.FullAccess{}, D.ApprovalForMe{profile}) == False{} : Bool})),
    refused_delegation: @+context:D.TaskContext -> @+guidance:D.ProjectContext -> @+parent:D.TaskContext -> @+count:Nat -> @+messages:+List<String> ->
      @rejected:{W.may_delegate(context, parent) == False{} : Bool} ->
      {Protocol.branch_selection(Done{W.Selection{context, guidance}}, count, messages, parent) ==
        Protocol.delegated(False{}, count, messages, W.Selection{context, guidance}) : Protocol.Invocation}
  }

law context_boundary:
  ContextBoundary
