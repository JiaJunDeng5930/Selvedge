import Base
import ./features/STATE.bend as FeatureState
import ./features/execution.bend as FeatureExec
import ../bendlib/effects.bend as Effects
import ./features/MODEL.bend as F
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./MODEL.bend as M
import ../bendlib/json.bend as J
import ./tasks/PROGRAM.bend as T
import ./execution/OPERATIONS.bend as Ops
import ./protocol/RESULTS.bend as Results
import ../bendlib/theory.bend as Theory
import ./transport/presentation.bend as View
import ./INVARIANTS.bend as I
import ./COMMANDS.bend as Commands
import ./protocol/COMMIT.bend as Commit
import ./protocol/PROGRAM.bend as Protocol
import ./execution/PROGRAM.bend as Execution
import ./execution/notifications.bend as Notifications
import ./workspace/WORKSPACE.bend as Workspace
import ./workspace/PROJECTS.bend as Projects
import ./approval/MODEL.bend as Approvals
import ./reasoning/PROGRAM.bend as Reasoning
import ../features/board/scheduling.bend as BoardScheduling
import ../features/board/scheduling-spec.bend as BoardSchedulingSpec

# Accepted updates pass through resolution, realization and bounded scheduling.
# program's state transition, and the object named by LAWS.bend and PROOF.bend.
# The host owns no task state, lifecycle table, fork rule, or recovery decision.
def tasks(world: M.World()) -> +List<D.Task>:
  Commands.entries(world)

def environment(world: M.World()) -> D.Environment:
  C.Frame{+task_state, +board} = world
  environment = D.state_environment(task_state)
  environment

def catalog(environment: D.Environment) -> +List<D.Tool>:
  D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  catalog

def next_task(world: M.World()) -> Nat:
  C.Frame{+task_state, +board} = world
  next_task = D.state_next_task(task_state)
  next_task

def store(task: D.Task, world: M.World()) -> M.World():
  T.update_world(F.State(), task, world)

def respond(world: M.World(), result: J.Json) -> M.Decision():
  C.Decision{world, D.success(result), Nil{}}

def reject(world: M.World(), code: String, message: String) -> M.Decision():
  C.Decision{world, D.failure(code, message), Nil{}}

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def execute_start_environment(profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection, world: M.World(), environment_value: D.Environment) -> M.Decision():
  match selection world environment_value:
    case Workspace.Selection{context, guidance} C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}:
      tasks = D.state_tasks(task_state)
      +next_task = D.state_next_task(task_state)
      task : D.Task = D.Task{next_task, Nil{}, D.Contract{D.Model{profile, reasoning, guidance}, catalog, max_fork, max_descendants, plugins, context},
        D.Active{}, D.HistoryNode{D.EmptyHistory{}, D.UserMessage{message}}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}}
      respond(C.Frame{D.with_state_next_task(1n+next_task, D.with_state_tasks(List.append(&2, D.Task, tasks, [task]), task_state)), board}, id_result(next_task))

def execute_start(profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  execute_start_environment(profile, reasoning, message, selection, world, D.state_environment(C.local(D.State, F.State(), world)))

def execute_delivery(text: String, +task: D.Task, world: M.World()) -> M.Decision():
  respond(store(T.receive(text, task), world), id_result(D.task_id(task)))

def change_to(next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match next:
    case D.Archived{}:
      C.Decision{store(T.archive(task), world),
        D.success(id_result(D.task_id(task))), [Effects.CancelTask{D.task_id(task)}]}
    case other:
      respond(store(T.promote(D.with_status(other, task)), world), id_result(D.task_id(task)))

def change_requested(control: D.Control, next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match control:
    case D.Interrupt{}:
      C.Decision{store(T.interrupt(task), world), D.success(id_result(D.task_id(task))), [Effects.CancelTask{D.task_id(task)}]}
    case _: change_to(next, task, world)

def query(request: M.Query, world: M.World()) -> J.Json:
  Commands.query(request, world)

def observe(request: M.Query, +world: M.World()) -> M.Decision():
  C.Decision{world, query(request, world), Nil{}}

def child(id: Nat, parent: D.Task, call_id: String, branch: Nat, remaining: +List<D.Attempt>, message: Maybe<&2, String>) -> D.Task:
  Commands.child(id, parent, call_id, branch, remaining, message)

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: D.Task, +call_id: String,
  +remaining: +List<D.Attempt>, +messages: +List<String>) -> Commands.Children:
  Commands.children(count, next_id, branch, parent, call_id, remaining, messages)

def ids(tasks: +List<D.Task>) -> +List<J.Json>:
  Commands.identities(tasks)

def commit_fork(built: Commands.Children, call: D.Call, remaining: +List<D.Attempt>, +parent: D.Task, world: M.World()) -> M.Decision():
  match built world:
    case Commands.Children{+new_tasks, end} C.Frame{+task_state, +board}:
      tasks = D.state_tasks(task_state)
      caller = T.promote(D.with_notified(True{}, D.with_phase(D.Ready{remaining}, D.with_history(D.branch_history(D.task_history(parent), T.call_id(call), 0n), parent))))
      respond(C.Frame{D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, T.replace(tasks, caller), new_tasks), task_state)), board},
        J.Object{[J.Field{"children", J.Array{ids(new_tasks)}}]})

def summary_request(+task: D.Task, resume: Bool, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  next = D.with_notified(False{}, D.with_phase(D.SummaryPending{next_ticket, resume}, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), board}, D.success(id_result(D.task_id(task))),
    [Effects.RequestSummary{D.task_id(task), next_ticket, T.task_model(D.task_contract(task)), D.context_history(D.task_history(task)), D.task_context(task)}]}

def execute_checkpoint(summary: String, +task: D.Task, world: M.World()) -> M.Decision():
  respond(store(D.append_message(D.ContextCheckpoint{summary}, task), world), id_result(D.task_id(task)))

def execute_branch(+task: D.Task, +count: Nat, +messages: +List<String>, selection: Workspace.Selection, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  +next_task = D.state_next_task(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  +call = Commands.branch_call(next_ticket, count, messages)
  +parent = D.append_message(D.FunctionCall{call}, task)
  commit_fork(children(count, next_task, 1n, Commands.selected_parent(selection, parent), T.call_id(call), Nil{}, messages), call, Nil{}, parent,
    C.Frame{D.with_state_next_ticket(1n+next_ticket, task_state), board})

# PROGRAM realizes the resolved operation. The refinement proof compares the
# entire decision with COMMANDS.meaning, including replies and requested work.

def review_result(resolution: Approvals.Resolution, world: M.World()) -> M.Decision():
  match resolution:
    case Approvals.Ignore{}: respond(world, J.Object{[J.Field{"accepted", J.Boolean{False{}}}]})
    case Approvals.Refuse{code, reason}: reject(world, code, reason)
    case Approvals.Grant{+operation, +task, +reviewer, reason}:
      audited = D.append_message(D.ApprovalRecord{D.task_id(task), Ops.ticket(operation), Ops.call(operation),
        reviewer, D.ApprovalAllowed{reason}}, task)
      respond(store(Ops.permitted(reviewer, operation, audited), world), J.Object{[J.Field{"accepted", J.Boolean{True{}}}]})
    case Approvals.Deny{+operation, +task, +reviewer, +outcome}:
      audited = D.append_message(D.ApprovalRecord{D.task_id(task), Ops.ticket(operation), Ops.call(operation), reviewer, outcome}, task)
      Results.begin(F.State(), F.Effect, operation, Approvals.denial_value(outcome), True{}, audited, world)

def realize(operation: Commands.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case Commands.Refuse{code, reason}: reject(world, code, reason)
    case Commands.Review{resolution}: review_result(resolution, world)
    case Commands.Start{profile, reasoning, message, selection}: execute_start(profile, reasoning, message, selection, world)
    case Commands.FeatureOperation{operation}: FeatureExec.realize(execute_start, operation, world)
    case Commands.Deliver{task, message}: execute_delivery(message, task, world)
    case Commands.Steer{+task, message}:
      C.Decision{store(T.steer(message, task), world), D.success(id_result(D.task_id(task))),
        T.steering_effects(F.Effect, D.task_phase(task), D.task_id(task))}
    case Commands.Cancel{+task, +operation}:
      C.Decision{store(T.promote(Ops.cancelled(operation, task)), world),
        D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}, J.Field{"operation_id", J.nat(Ops.ticket(operation))}]}),
        [Effects.CancelTicket{D.task_id(task), Ops.callback(operation)}]}
    case Commands.Control{task, request, next}: change_requested(request, next, task, world)
    case Commands.Branch{task, count, messages, selection}: execute_branch(task, count, messages, selection, world)
    case Commands.Summarize{task}: summary_request(task, False{}, world)
    case Commands.Checkpoint{task, summary}: execute_checkpoint(summary, task, world)
    case Commands.Observe{query}: observe(query, world)
    case Commands.StoreProject{+id, project, next_id}:
      respond(Projects.store(F.State(), Projects.put(id, project, Projects.registry(F.State(), world), next_id), world), J.Object{[J.Field{"project_id", J.nat(id)}]})
    case Commands.RemoveProject{+id}:
      respond(Projects.store(F.State(), Projects.remove(id, Projects.registry(F.State(), world)), world), J.Object{[J.Field{"project_id", J.nat(id)}]})

def apply_command(command: M.Command, +world: M.World()) -> M.Decision():
  realize(Commands.resolve(command, world), world)

def accepted(yes: Bool) -> J.Json:
  J.Object{[J.Field{"accepted", J.Boolean{yes}}]}

def model_matched(same: Bool, outcome: D.Outcome, allowed: +List<String>, task: D.Task, world: M.World()) -> M.Decision():
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.model_outcome(outcome, allowed, task), world), accepted(True{}))

def summary_matched(same: Bool, outcome: D.Outcome, resume: Bool, task: D.Task, world: M.World()) -> M.Decision():
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.summary_outcome(outcome, resume, task), world), accepted(True{}))

def tool_matched(same: Bool, operation: D.Operation(), value: J.Json, error: Bool, task: D.Task, world: M.World()) -> M.Decision():
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: Results.begin(F.State(), F.Effect, operation, value, error, task, world)

def recover_tasks(tasks: +List<D.Task>) -> +List<D.Task>:
  Protocol.recovery(tasks)

def realize_event(event: Protocol.ResolvedEvent, world: M.World()) -> M.Decision():
  match event:
    case Protocol.User{operation}: realize(operation, world)
    case Protocol.Ignore{}: respond(world, accepted(False{}))
    case Protocol.ModelResult{task, outcome, allowed}: model_matched(True{}, outcome, allowed, task, world)
    case Protocol.ReasoningResult{task, revision, outcome}:
      respond(store(Reasoning.complete(revision, outcome, task), world), accepted(True{}))
    case Protocol.FeatureEvent{event}: FeatureExec.event(event, world)
    case Protocol.SummaryResult{task, outcome, resume}: summary_matched(True{}, outcome, resume, task, world)
    case Protocol.ToolResult{task, operation, value, error}: tool_matched(True{}, operation, value, error, task, world)
    case Protocol.HookResult{task, outcome}: respond(store(T.complete_hook(outcome, task), world), accepted(True{}))
    case Protocol.AfterResult{task, +operation, outcome}: Results.complete(F.State(), F.Effect, Ops.stage(operation), outcome, operation, task, world)
    case Protocol.Settings{environment}:
      C.Frame{+task_state, +board} = world
      tasks = D.state_tasks(task_state)
      next_task = D.state_next_task(task_state)
      next_ticket = D.state_next_ticket(task_state)
      limits = D.state_limits(task_state)
      projects = D.state_projects(task_state)
      respond(C.Frame{D.with_state_environment(environment, task_state), board}, J.Null{})
    case Protocol.Restart{}:
      C.Frame{+task_state_2, +board} = world
      tasks = D.state_tasks(task_state_2)
      next_task = D.state_next_task(task_state_2)
      next_ticket = D.state_next_ticket(task_state_2)
      environment = D.state_environment(task_state_2)
      limits = D.state_limits(task_state_2)
      projects = D.state_projects(task_state_2)
      respond(C.Frame{D.with_state_tasks(recover_tasks(tasks), task_state_2), FeatureState.recover(board)}, J.Null{})
    case Protocol.Tick{}: respond(world, J.Null{})
    case Protocol.Review{resolution}: review_result(resolution, world)

def apply(input: M.Input, +world: M.World()) -> M.Decision():
  realize_event(Protocol.resolve(input, world), world)

def decision_world(decision: M.Decision()) -> M.World():
  Execution.world(decision)

def decision_reply(decision: M.Decision()) -> J.Json:
  C.Decision{world, reply, effects} = decision
  reply

def decision_effects(decision: M.Decision()) -> +List<M.Effect()>:
  C.Decision{world, reply, effects} = decision
  effects

def model_request_direct(task: D.Task, world: M.World()) -> M.Decision():
  Reasoning.start(F.State(), F.Effect, task, world)

def rendering_budget(world: M.World()) -> Nat:
  D.state_render_budget(C.local(D.State, F.State(), world))

def external_tool(tool: D.Tool, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  next = T.promote(Ops.started(next_ticket, call, remaining, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), board}, J.Null{},
    [Effects.ExecuteTool{D.task_id(task), next_ticket, tool, call, D.task_context(task), Workspace.default_access(D.task_context(task))}]}

def approval_request(+reviewer: D.ApprovalReviewer, +call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  +ticket = D.state_next_ticket(task_state)
  +pending = T.promote(Ops.awaiting(ticket, reviewer, call, remaining, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, pending), task_state)), board}, J.Null{},
    Approvals.review_effects(F.Effect, reviewer, pending, ticket, call)}

def elevated_tool(reviewer: D.ApprovalReviewer, tool: D.Tool, +operation: D.Operation(), +task: D.Task, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  +ticket = D.state_next_ticket(task_state)
  next = Ops.elevated(ticket, reviewer, operation, task)
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), board}, J.Null{},
    [Effects.ExecuteTool{D.task_id(task), ticket, tool, Ops.call(operation), D.task_context(task), D.Unrestricted{}}]}

def check_tool(+plugin: D.PluginRef, pending: +List<D.PluginRef>, tool: D.Tool, +call: D.Call, remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  next = D.with_phase(D.HookPending{next_ticket, plugin, call, pending, remaining}, task)
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), board}, J.Null{},
    [Effects.CheckTool{D.task_id(task), next_ticket, plugin, tool, call}]}

def tool_error(code: String, message: String, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> M.Decision():
  respond(store(T.complete_tool(call, remaining, D.failure(code, message), True{}, task), world), J.Null{})

def internal_result(found: Maybe<&2, D.Task>, call: D.Call, remaining: +List<D.Attempt>, +result: M.Decision()) -> M.Decision():
  match found:
    case None{}:
      result
    case Some{+task}:
      +reply = decision_reply(result)
      Results.attached(F.State(), F.Effect, Results.internal(F.State(), F.Effect, call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task, decision_world(result)),
        J.Null{}, decision_effects(result))

def finish_internal(id: Nat, call: D.Call, remaining: +List<D.Attempt>, +result: M.Decision()) -> M.Decision():
  internal_result(T.find(tasks(decision_world(result)), id), call, remaining, result)

def commit_invoked_fork(built: Commands.Children, call: D.Call, remaining: +List<D.Attempt>, parent: D.Task, world: M.World()) -> M.Decision():
  match built world:
    case Commands.Children{+new_tasks, end} C.Frame{+task_state, +board}:
      tasks = D.state_tasks(task_state)
      Results.attached(F.State(), F.Effect, Results.internal(F.State(), F.Effect, call, remaining, J.nat(0n), False{}, parent,
        C.Frame{D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, tasks, new_tasks), task_state)), board}),
        D.success(J.Object{[J.Field{"children", J.Array{ids(new_tasks)}}]}), Nil{})

def realize_invocation(operation: Protocol.Invocation, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> M.Decision():
  match operation:
    case Protocol.Internal{operation}:
      finish_internal(D.task_id(task), call, remaining, realize(operation, world))
    case Protocol.Branch{count, messages, selection}:
      commit_invoked_fork(children(count, next_task(world), 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, messages), call, remaining, task, world)

def builtin(tool: D.Builtin, arguments: J.Json, call: D.Call, remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> M.Decision():
  realize_invocation(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world)

def realize_action(action: Execution.Action, world: M.World()) -> M.Decision():
  match action:
    case Execution.Rest{}: respond(world, J.Null{})
    case Execution.Idle{task}: respond(store(D.with_phase(D.Idle{}, task), world), J.Null{})
    case Execution.Model{task}: model_request_direct(task, world)
    case Execution.Summary{task, resume}: summary_request(task, resume, world)
    case Execution.External{tool, call, remaining, task}: external_tool(tool, call, remaining, task, world)
    case Execution.Review{reviewer, call, remaining, task}: approval_request(reviewer, call, remaining, task, world)
    case Execution.Granted{reviewer, tool, operation, task}: elevated_tool(reviewer, tool, operation, task, world)
    case Execution.GrantFailure{operation, task}: Results.begin(F.State(), F.Effect, operation, Execution.grant_failure_value(), True{}, task, world)
    case Execution.Hook{plugin, pending, tool, call, remaining, task}: check_tool(plugin, pending, tool, call, remaining, task, world)
    case Execution.Internal{operation, call, remaining, task}: realize_invocation(operation, call, remaining, task, world)
    case Execution.Failure{code, reason, call, remaining, task}: tool_error(code, reason, call, remaining, task, world)

def model_request(task: D.Task, +world: M.World()) -> M.Decision():
  realize_action(Execution.model(task, world), world)

def run_tool(phase: D.Phase, task: D.Task, +world: M.World()) -> M.Decision():
  realize_action(Execution.tool(phase, task, world), world)

def work(work: D.Work, task: D.Task, +world: M.World()) -> M.Decision():
  realize_action(Execution.resolve(work, task, world), world)

def combine(before: M.Decision(), after: M.Decision()) -> M.Decision():
  match before after:
    case C.Decision{old, reply, effects} C.Decision{world, ignored, added}:
      C.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}

def defer(decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.ContinueScheduling{}])}

# A finite input transition cannot promise that an agent will finish. It makes
# bounded progress and explicitly requests another turn if internal work remains.

def schedule(fuel: Nat, candidate: Maybe<&2, D.Task>, +decision: M.Decision()) -> M.Decision():
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = combine(decision, work(D.task_work(task), task, decision_world(decision)))
      schedule(p, T.runnable(tasks(decision_world(next))), next)

def scheduling_budget(world: M.World()) -> Nat:
  Execution.budget(world)

def frame_limit(world: M.World()) -> U32:
  Commit.frame_bytes(world)

def board_dispatch(command: M.Command, world: M.World()) -> M.Decision():
  apply_command(command, world)

def scheduled_prepared(+decision: M.Decision()) -> M.Decision():
  BoardSchedulingSpec.finish(schedule(scheduling_budget(decision_world(decision)), T.runnable(tasks(decision_world(decision))), decision))

def scheduled(enabled: Bool, +decision: M.Decision()) -> M.Decision():
  match enabled:
    case False{}: decision
    case True{}: scheduled_prepared(BoardScheduling.prepare(~board_dispatch, decision))

def output_admitted(fits: Bool, decision: M.Decision(), previous: M.World()) -> M.Decision():
  match fits:
    case True{}: decision
    case False{}: reject(previous, "output_limit", "The complete decision exceeds the native output bound; no state change or effect was committed")

def admission(rendered: Result<&2, &2, String, String>, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  match rendered:
    case Fail{error}: reject(previous, "output_limit", error)
    case Done{text}:
      output_admitted(Nat.is_le(J.utf8_length(text), U32.to_nat(frame_limit(previous))), decision, previous)

def deliver(durable: Bool, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  admission(J.render(rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous)

def live_decision(decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Decision{world, reply, I.live_effects(effects, tasks(world))}

def valid_world(decision: M.Decision()) -> Bool:
  I.world(decision_world(decision))

def admitted(state_valid: Bool, change_valid: Bool, decision: M.Decision(), previous: M.World()) -> M.Decision():
  Theory.admit(~M.Decision(), state_valid, change_valid, decision,
    reject(previous, "invariant_violation", "The candidate violates a world invariant, task retention, or effect authority"))

def check_live(+decision: M.Decision(), +previous: M.World()) -> M.Decision():
  admitted(valid_world(decision), I.decision(previous, decision), decision, previous)

# Reflection checks the declared predicates on the actual candidate. Rejection
# retains the old state and emits no effects; output admission has the same rule.

def checked(decision: M.Decision(), previous: M.World()) -> M.Decision():
  check_live(live_decision(decision), previous)

def after_apply(+input: M.Input, +decision: M.Decision(), +world: M.World()) -> M.Decision():
  deliver(M.durable(input), checked(Notifications.decorate(input, world, scheduled(Commit.schedules(input, decision), decision)), world), world)

def update(+input: M.Input, +world: M.World()) -> M.Decision():
  after_apply(input, apply(input, world), world)

def transition(input: M.Input, +world: M.World()) -> M.Decision():
  match input:
    case M.UserCommand{M.Observe{request}}: deliver(False{}, observe(request, world), world)
    case other: update(other, world)

def next(world: M.World(), input: M.Input) -> M.World():
  decision_world(transition(input, world))

def replay(events: +List<M.Input>, world: M.World()) -> M.World():
  Theory.replay(~M.World(), ~M.Input, ~next, events, world)
