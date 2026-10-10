import Base
import ../features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./WORKSPACE.bend as W
import ./PROJECTS.bend as Projects
import ../COMMANDS.bend as Commands
import ./CONTRACT.bend as A
import ../../bendlib/association-map.bend as Finite
import ../protocol/PROGRAM.bend as Protocol
import ../../bendlib/json-proof.bend as JsonProof
import ../../bendlib/equality-proof.bend as EqualityProof

def inherited(id:Nat, +parent:D.Task, call:String, branch:Nat, remaining:+List<D.Attempt>, message:Maybe<&2, String>) ->
  {D.task_context(Commands.child(id, parent, call, branch, remaining, message)) == D.task_context(parent) : D.TaskContext}:
  D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified} = parent
  {==}

def no_rights(id:Nat, parent:D.Task, call:String, branch:Nat, remaining:+List<D.Attempt>, message:Maybe<&2, String>) ->
  {D.task_operations(Commands.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<D.Operation()>}:
  D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified} = parent
  {==}

def override_context(+context:D.TaskContext, guidance:D.ProjectContext, task:D.Task) ->
  {D.task_context(Commands.selected_parent(W.Selection{context, guidance}, task)) == context : D.TaskContext}:
  D.Task{id, lineage, D.Contract{D.Model{profile, reasoning, previous}, tools, max_fork, max_descendants, plugins, old_context},
    status, history, queued, phase, operations, notified} = task
  {==}

def project_frame(registry:D.Projects, +world:M.World()) ->
  {Commands.entries(Projects.store(F.State(), registry, world)) == Commands.entries(world) : +List<D.Task>}:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, previous}, +board} = world
  {==}

def removal(registry:D.Projects, +id:Nat) ->
  {Projects.find(Projects.remove(id, registry), id) == None{} : Maybe<&2, D.Project>}:
  D.Projects{entries, next_id} = registry
  Finite.removal_absence(~D.Project, entries, id)

def A.context_boundary():
  A.ContextBoundary{
    EqualityProof.public_refines,
    JsonProof.public_refines,
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
