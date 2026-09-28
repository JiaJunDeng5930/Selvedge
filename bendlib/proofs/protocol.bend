import Base
import ../board-architecture.bend as BoardBoundary
import ../board.bend as BoardActual
import ../board-spec.bend as BoardSpec
import ../board-state.bend as BoardState
import ./board.bend as BoardProof
import ../reasoning-architecture.bend as Reasoning
import ../reasoning.bend as ActualReasoning
import ../reasoning-spec.bend as RequiredReasoning
import ./reasoning.bend as ReasoningProof
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../tasks.bend as T
import ../json.bend as J
import ../../COMMANDS.bend as Commands
import ../protocol.bend as Protocol
import ../../WORKSPACE.bend as Workspace
import ../../APPROVALS.bend as Approvals

# Local proof obligations for the protocol boundary. No runtime policy lives here.

def query_semantics(+query: M.Query, +world: M.World) ->
  {P.query(query, world) == Commands.query(query, world) : J.Json}:
  {==}

def branch_world(world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  M.World{tasks, next_task, 1n+next_ticket, environment, limits, projects, board}

def branch_commit_semantics(+built: Commands.Children, +call: M.Call, +parent: M.Task, +world: M.World) ->
  {P.commit_fork(built, call, Nil{}, parent, branch_world(world)) ==
   Commands.branch_commit(built, parent, T.call_id(call), world) : M.Decision}:
  match built world:
    case Commands.Children{children, end} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def status_semantics(+status: M.Status, +task: M.Task, +world: M.World) ->
  {P.change_to(status, task, world) == Commands.status_change(status, task, world) : M.Decision}:
  match status world:
    case M.Active{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case M.Frozen{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case M.Stopped{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case M.Archived{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def control_semantics(+request: M.Control, +status: M.Status, +task: M.Task, +world: M.World) ->
  {P.change_requested(request, status, task, world) == Commands.lifecycle(request, status, task, world) : M.Decision}:
  match request world:
    case M.Interrupt{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case M.Freeze{} _: status_semantics(status, task, world)
    case M.Unfreeze{} _: status_semantics(status, task, world)
    case M.Stop{} _: status_semantics(status, task, world)
    case M.Archive{} _: status_semantics(status, task, world)

def Laws.review_semantics(resolution, world):
  match resolution world:
    case Approvals.Ignore{} _: {==}
    case Approvals.Refuse{code, reason} _: {==}
    case Approvals.Grant{operation, task, reviewer, reason} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Approvals.Deny{operation, task, reviewer, outcome} _: {==}

def Laws.operation_semantics(operation, world):
  match operation world:
    case Commands.BoardChange{change} _: BoardBoundary.change_meaning(change, world)
    case Commands.StartCard{+id, +card, +now, profile, reasoning, message, Workspace.Selection{context, guidance}}
         M.World{tasks, +next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects, board}:
      BoardBoundary.birth_meaning(id, next_task, card, now,
        Commands.start(profile, reasoning, message, Workspace.Selection{context, guidance},
          M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects, board}))
    case Commands.Refuse{code, reason} _: {==}
    case Commands.Start{profile, reasoning, message, Workspace.Selection{context, guidance}}
         M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects, board}: {==}
    case Commands.Deliver{task, message} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Commands.Steer{task, message} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Commands.Cancel{task, operation} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Commands.Control{task, request, next} _: control_semantics(request, next, task, world)
    case Commands.Branch{+task, +count, +messages, selection} M.World{tasks, +next_task, +next_ticket, environment, limits, projects, board}:
      +call = Commands.branch_call(next_ticket, count, messages)
      +parent = M.append_message(M.FunctionCall{call}, task)
      branch_commit_semantics(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, parent), T.call_id(call), Nil{}, messages),
        call, parent, M.World{tasks, next_task, next_ticket, environment, limits, projects, board})
    case Commands.Summarize{task} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Commands.Checkpoint{task, summary} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Commands.Observe{+query} _:
      Equal.cong(J.Json, M.Decision, (reply => M.Decision{world, reply, Nil{}}),
        P.query(query, world), Commands.query(query, world), query_semantics(query, world))
    case Commands.StoreProject{id, project, next_id} _: {==}
    case Commands.RemoveProject{id} _: {==}
    case Commands.Review{resolution} _: Laws.review_semantics(resolution, world)

def Laws.command_semantics(command, world):
  Laws.operation_semantics(Commands.resolve(command, world), world)

def Laws.event_semantics(event, world):
  match event world:
    case Protocol.BoardTextResult{id, card, outcome, retitle} _: BoardBoundary.completion_meaning(id, card, outcome, retitle, world)
    case Protocol.User{operation} _: Laws.operation_semantics(operation, world)
    case Protocol.Ignore{} _: {==}
    case Protocol.Review{resolution} _: Laws.review_semantics(resolution, world)
    case Protocol.ModelResult{task, outcome, allowed} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.ReasoningResult{+task, +revision, +outcome} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      Equal.cong(M.Task, M.Decision, (next => M.Decision{
        M.World{T.replace(tasks, next), next_task, next_ticket, environment, limits, projects, board}, Protocol.acknowledgement(True{}), Nil{}}),
        ActualReasoning.complete(revision, outcome, task), RequiredReasoning.complete(revision, outcome, task), Reasoning.completion_meaning(revision, outcome, task))
    case Protocol.SummaryResult{task, outcome, resume} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.ToolResult{task, operation, value, error} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.HookResult{task, outcome} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.AfterResult{task, operation, outcome} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.Settings{settings} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.Restart{} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
    case Protocol.Tick{} _: {==}

def Laws.input_semantics(input, world):
  Laws.event_semantics(Protocol.resolve(input, world), world)

def internal_result_semantics(+found: Maybe<&2, M.Task>, +call: M.Call, +remaining: +List<M.Attempt>, +decision: M.Decision) ->
  {P.internal_result(found, call, remaining, decision) == Protocol.result(found, call, remaining, decision) : M.Decision}:
  match found decision:
    case None{} _: {==}
    case Some{task} M.Decision{world, reply, effects}: {==}

def finish_internal_semantics(+id: Nat, +call: M.Call, +remaining: +List<M.Attempt>, +decision: M.Decision) ->
  {P.finish_internal(id, call, remaining, decision) == Protocol.finish(id, call, remaining, decision) : M.Decision}:
  match decision:
    case M.Decision{M.World{+tasks, +next_task, +next_ticket, +environment, +limits, projects, board}, +reply, +effects}:
      internal_result_semantics(T.find(tasks, id), call, remaining,
        M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, board}, reply, effects})

def branched_semantics(+built: Commands.Children, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) ->
  {P.commit_invoked_fork(built, call, remaining, task, world) == Protocol.branched_invocation(built, call, remaining, task, world) : M.Decision}:
  match built world:
    case Commands.Children{children, end} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def Laws.invocation_semantics(operation, call, remaining, task, world):
  match operation world:
    case Protocol.Internal{+operation} _:
      +id = M.task_id(task)
      +realized = P.realize(operation, world)
      +meaning = Commands.meaning(operation, world)
      Equal.trans(M.Decision, P.finish_internal(id, call, remaining, realized), Protocol.finish(id, call, remaining, realized),
        Protocol.finish(id, call, remaining, meaning), finish_internal_semantics(id, call, remaining, realized),
        Equal.cong(M.Decision, M.Decision, (value => Protocol.finish(id, call, remaining, value)),
          realized, meaning, Laws.operation_semantics(operation, world)))
    case Protocol.Branch{count, messages, selection} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      branched_semantics(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, messages),
        call, remaining, task, M.World{tasks, next_task, next_ticket, environment, limits, projects, board})

def Laws.builtin_semantics(tool, arguments, call, remaining, task, world):
  Laws.invocation_semantics(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world)

def Laws.accepted_model_settlement(outcome, allowed, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def Laws.accepted_tool_settlement(operation, value, error, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def Laws.accepted_summary_settlement(outcome, resume, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}
