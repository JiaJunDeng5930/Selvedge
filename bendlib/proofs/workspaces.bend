import Base
import ../../MODEL.bend as M
import ../../WORKSPACE.bend as W
import ../../PROJECTS.bend as Projects
import ../../COMMANDS.bend as Commands
import ../workspace-architecture.bend as A
import ../association-map.bend as Finite
import ../protocol.bend as Protocol

def inherited(id:Nat, +parent:M.Task, call:String, branch:Nat, remaining:+List<M.Attempt>, message:Maybe<&2, String>) ->
  {M.task_context(Commands.child(id, parent, call, branch, remaining, message)) == M.task_context(parent) : M.TaskContext}:
  M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified} = parent
  {==}

def no_rights(id:Nat, parent:M.Task, call:String, branch:Nat, remaining:+List<M.Attempt>, message:Maybe<&2, String>) ->
  {M.task_operations(Commands.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<M.Operation()>}:
  M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified} = parent
  {==}

def override_context(+context:M.TaskContext, guidance:M.ProjectContext, task:M.Task) ->
  {M.task_context(Commands.selected_parent(W.Selection{context, guidance}, task)) == context : M.TaskContext}:
  M.Task{id, lineage, M.Contract{M.Model{profile, reasoning, previous}, tools, max_fork, max_descendants, plugins, old_context},
    status, history, queued, phase, operations, notified} = task
  {==}

def project_frame(registry:M.Projects, +world:M.World) ->
  {Commands.entries(Projects.store(registry, world)) == Commands.entries(world) : +List<M.Task>}:
  M.World{tasks, next_task, next_ticket, environment, limits, previous, board} = world
  {==}

def removal(registry:M.Projects, +id:Nat) ->
  {Projects.find(Projects.remove(id, registry), id) == None{} : Maybe<&2, M.Project>}:
  M.Projects{entries, next_id} = registry
  Finite.removal_absence(~M.Project, entries, id)

def A.context_boundary():
  A.ContextBoundary{
    (workspace => sandbox => approval => project => {==}),
    (id => parent => call => branch => remaining => message => inherited(id, parent, call, branch, remaining, message)),
    (id => parent => call => branch => remaining => message => no_rights(id, parent, call, branch, remaining, message)),
    (context => guidance => task => override_context(context, guidance, task)),
    (registry => world => project_frame(registry, world)),
    (registry => id => removal(registry, id)),
    ({==}, (profile => {==})),
    (context => guidance => parent => count => messages => rejected =>
      Equal.cong(Bool, Protocol.Invocation, (allowed => Protocol.delegated(allowed, count, messages, W.Selection{context, guidance})),
        W.may_delegate(context, parent), False{}, rejected))}
