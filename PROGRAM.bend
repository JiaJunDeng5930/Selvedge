import Base
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./bendlib/schema.bend as Schema
import ./bendlib/theory.bend as Theory
import ./bendlib/presentation.bend as View

# Every admitted input passes through apply and schedule. This is the running
# program's state transition, and the object named by LAWS.bend and PROOF.bend.
# The host owns no task state, lifecycle table, fork rule, or recovery decision.

def tasks(world: M.World) -> +List<M.Task>:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  tasks

def environment(world: M.World) -> M.Environment:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  environment

def catalog(environment: M.Environment) -> +List<M.Tool>:
  M.Environment{catalog, profiles, max_fork, max_descendants} = environment
  catalog

def profiles(environment: M.Environment) -> +List<M.Profile>:
  M.Environment{catalog, profiles, max_fork, max_descendants} = environment
  profiles

def next_task(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  next_task

def fork_limit(contract: M.Contract) -> Nat:
  M.Contract{model, tools, max_fork, max_descendants} = contract
  max_fork

def store(task: M.Task, world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  M.World{T.replace(tasks, task), next_task, next_ticket, environment, limits}

def respond(world: M.World, result: J.Json) -> M.Decision:
  M.Decision{world, M.success(result), Nil{}}

def reject(world: M.World, code: String, message: String) -> M.Decision:
  M.Decision{world, M.failure(code, message), Nil{}}

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def create_checked(valid: Bool, profile: M.Profile, reasoning: String, message: String, world: M.World) -> M.Decision:
  match valid:
    case False{}:
      reject(world, "invalid_arguments", "Create requires a configured profile, a reasoning effort, and a nonempty message")
    case True{}:
      M.World{tasks, +next_task, next_ticket, +environment, limits} = world
      M.Environment{catalog, profiles, max_fork, max_descendants} = environment
      task : M.Task = M.Task{next_task, Nil{}, M.Contract{M.Model{profile, reasoning}, catalog, max_fork, max_descendants},
        M.Active{}, M.HistoryNode{M.EmptyHistory{}, M.UserMessage{message}}, Nil{}, M.Ready{Nil{}}}
      respond(M.World{List.append(&2, M.Task, tasks, [task]), 1n+next_task, next_ticket, environment, limits}, id_result(next_task))

def create_selected(selected: Maybe<&2, M.Profile>, +reasoning: String, +message: String, world: M.World) -> M.Decision:
  match selected:
    case None{}: reject(world, "unknown_profile", "Select a configured model profile")
    case Some{profile}: create_checked(M.nonempty(reasoning) && M.nonempty(message), profile, reasoning, message, world)

def create(profile: String, reasoning: String, message: String, +world: M.World) -> M.Decision:
  create_selected(M.find_profile(profiles(environment(world)), profile), reasoning, message, world)

def send_checked(allowed: Bool, text: String, +task: M.Task, world: M.World) -> M.Decision:
  match allowed:
    case False{}:
      reject(world, "invalid_arguments", "The message must be nonempty and the target must not be archived")
    case True{}:
      respond(store(T.receive(text, task), world), id_result(M.task_id(task)))

def send_found(found: Maybe<&2, M.Task>, +text: String, world: M.World) -> M.Decision:
  match found:
    case None{}: reject(world, "task_not_found", "The target task does not exist")
    case Some{+task}:
      send_checked(M.nonempty(text) && M.accepts_input(M.task_status(task)), text, task, world)

def send(+id: Nat, text: String, +world: M.World) -> M.Decision:
  send_found(T.find(tasks(world), id), text, world)

def change_to(next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match next:
    case M.Archived{}:
      M.Decision{store(M.with_phase(M.Idle{}, M.with_status(M.Archived{}, task)), world),
        M.success(id_result(M.task_id(task))), [M.CancelTask{M.task_id(task)}]}
    case other:
      respond(store(T.promote(M.with_status(other, task)), world), id_result(M.task_id(task)))

def change_checked(next: Maybe<&2, M.Status>, task: M.Task, world: M.World) -> M.Decision:
  match next:
    case None{}: reject(world, "invalid_transition", "This lifecycle transition is not permitted")
    case Some{status}: change_to(status, task, world)

def change_found(found: Maybe<&2, M.Task>, control: M.Control, world: M.World) -> M.Decision:
  match found:
    case None{}: reject(world, "task_not_found", "The target task does not exist")
    case Some{+task}: change_checked(M.control(M.task_status(task), control), task, world)

def change(id: Nat, control: M.Control, +world: M.World) -> M.Decision:
  change_found(T.find(tasks(world), id), control, world)

def read_checked(valid: Bool, task: M.Task, after: Nat, limit: Nat, world: M.World) -> M.Decision:
  match valid:
    case False{}: reject(world, "invalid_page", "The page requires 1..100 messages and an offset on the task history")
    case True{}: respond(world, T.page(task, after, limit))

def read_found(found: Maybe<&2, M.Task>, +after: Nat, +limit: Nat, world: M.World) -> M.Decision:
  match found:
    case None{}: reject(world, "task_not_found", "The target task does not exist")
    case Some{+task}:
      read_checked(Nat.is_le(1n, limit) && Nat.is_le(limit, 100n) && Nat.is_le(after, M.history_length(M.task_history(task))),
        task, after, limit, world)

def read(id: Nat, after: Nat, limit: Nat, +world: M.World) -> M.Decision:
  read_found(T.find(tasks(world), id), after, limit, world)

def list_environment(environment: M.Environment, +world: M.World) -> M.Decision:
  M.Environment{catalog, profiles, max_fork, max_descendants} = environment
  respond(world, J.Object{[
    J.Field{"tasks", J.Array{T.summaries(tasks(world))}},
    J.Field{"profiles", J.Array{M.profiles_json(profiles)}},
    J.Field{"tools", J.Array{M.tools_json(catalog)}},
    J.Field{"max_fork", J.nat(max_fork)},
    J.Field{"max_descendants", J.nat(max_descendants)}]})

def list(+world: M.World) -> M.Decision:
  list_environment(environment(world), world)

def add_initial(message: Maybe<&2, String>, history: M.History) -> M.History:
  match message:
    case None{}: history
    case Some{text}: M.HistoryNode{history, M.UserMessage{text}}

def child(id: Nat, parent: M.Task, call_id: String, branch: Nat, remaining: +List<M.Attempt>, message: Maybe<&2, String>) -> M.Task:
  M.Task{parent_id, lineage, contract, status, history, queued, phase} = parent
  M.Task{id, parent_id <> lineage, contract, M.Active{}, add_initial(message, M.branch_history(history, call_id, branch)),
    Nil{}, M.Ready{M.inherit_attempts(remaining)}}

type Children is Data:
  Children{tasks: +List<M.Task>, next_id: Nat}

def add_child(task: M.Task, children: Children) -> Children:
  Children{rest, end} = children
  Children{task <> rest, end}

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: M.Task, +call_id: String,
  +remaining: +List<M.Attempt>, +messages: +List<String>) -> Children:
  match count:
    case 0n: Children{Nil{}, next_id}
    case 1n+p:
      first = child(next_id, parent, call_id, branch, remaining, List.head(&2, String, messages))
      add_child(first, children(p, 1n+next_id, 1n+branch, parent, call_id, remaining, List.tail(&2, String, messages)))

def ids(tasks: +List<M.Task>) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: J.nat(M.task_id(task)) <> ids(rest)

def fork_fits(+count: Nat, messages: +List<String>, +parent: M.Task, +world: M.World) -> Bool:
  +message_count = List.length(&2, String, messages)
  Nat.is_le(1n, count) && Nat.is_le(count, fork_limit(M.task_contract(parent))) &&
    (Nat.is_eq(message_count, 0n) || Nat.is_eq(message_count, count)) &&
    T.ancestors_fit(M.task_id(parent) <> M.task_lineage(parent), tasks(world), count)

def commit_fork(built: Children, call: M.Call, remaining: +List<M.Attempt>, +parent: M.Task, world: M.World) -> M.Decision:
  match built world:
    case Children{+new_tasks, end} M.World{tasks, next_task, next_ticket, environment, limits}:
      caller = T.promote(M.with_phase(M.Ready{remaining}, M.with_history(M.branch_history(M.task_history(parent), T.call_id(call), 0n), parent)))
      respond(M.World{List.append(&2, M.Task, T.replace(tasks, caller), new_tasks), end, next_ticket, environment, limits},
        J.Object{[J.Field{"children", J.Array{ids(new_tasks)}}]})

def fork_checked(valid: Bool, count: Nat, messages: +List<String>, +call: M.Call,
  +remaining: +List<M.Attempt>, +parent: M.Task, +world: M.World) -> M.Decision:
  match valid:
    case False{}:
      +error = M.failure("resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid")
      M.Decision{store(T.complete_tool(call, remaining, error, True{}, parent), world), error, Nil{}}
    case True{}:
      commit_fork(children(count, next_task(world), 1n, parent, T.call_id(call), remaining, messages), call, remaining, parent, world)

def fork(count: Nat, +messages: +List<String>, call: M.Call, remaining: +List<M.Attempt>, +parent: M.Task, +world: M.World) -> M.Decision:
  +count_copy = count
  fork_checked(fork_fits(count_copy, messages, parent, world), count_copy, messages, call, remaining, parent, world)

def manual_fork_ready(status: M.Status, phase: M.Phase, +count: Nat, +messages: +List<String>, +task: M.Task, world: M.World) -> M.Decision:
  match status phase:
    case M.Active{} M.Idle{}:
      M.World{tasks, next_task, +next_ticket, environment, limits} = world
      +call : M.Call = M.Call{"manual-fork-" ++ Nat.show(next_ticket), "fork_task",
        J.Object{[J.Field{"child_count", J.nat(count)}, J.Field{"messages", J.Array{T.strings_json(messages)}}]}}
      parent = M.append_message(M.FunctionCall{call}, task)
      fork(count, messages, call, Nil{}, parent, M.World{tasks, next_task, 1n+next_ticket, environment, limits})
    case _ _:
      reject(world, "task_busy", "A manual fork requires an active, idle task")

def manual_fork_found(found: Maybe<&2, M.Task>, count: Nat, messages: +List<String>, world: M.World) -> M.Decision:
  match found:
    case None{}: reject(world, "task_not_found", "The target task does not exist")
    case Some{+task}:
      manual_fork_ready(M.task_status(task), M.task_phase(task), count, messages, task, world)

def manual_fork(id: Nat, count: Nat, messages: +List<String>, +world: M.World) -> M.Decision:
  manual_fork_found(T.find(tasks(world), id), count, messages, world)

def apply_command(command: M.Command, world: M.World) -> M.Decision:
  match command:
    case M.Create{profile, reasoning, message}: create(profile, reasoning, message, world)
    case M.Send{task_id, message}: send(task_id, message, world)
    case M.ChangeStatus{task_id, control}: change(task_id, control, world)
    case M.Fork{task_id, count, messages}: manual_fork(task_id, count, messages, world)
    case M.Read{task_id, after, limit}: read(task_id, after, limit, world)
    case M.ListTasks{}: list(world)
    case M.Describe{}: respond(world, M.description())

def accepted(yes: Bool) -> J.Json:
  J.Object{[J.Field{"accepted", J.Boolean{yes}}]}

def model_matched(same: Bool, outcome: M.Outcome, allowed: +List<String>, task: M.Task, world: M.World) -> M.Decision:
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.model_outcome(outcome, allowed, task), world), accepted(True{}))

def model_phase(status: M.Status, phase: M.Phase, ticket: Nat, outcome: M.Outcome, task: M.Task, world: M.World) -> M.Decision:
  match status phase:
    case M.Archived{} _: respond(world, accepted(False{}))
    case _ M.ModelPending{expected, allowed}:
      model_matched(Nat.is_eq(ticket, expected), outcome, allowed, task, world)
    case _ _: respond(world, accepted(False{}))

def model_found(found: Maybe<&2, M.Task>, ticket: Nat, outcome: M.Outcome, world: M.World) -> M.Decision:
  match found:
    case None{}: respond(world, accepted(False{}))
    case Some{+task}:
      model_phase(M.task_status(task), M.task_phase(task), ticket, outcome, task, world)

def tool_matched(same: Bool, call: M.Call, remaining: +List<M.Attempt>, value: J.Json, error: Bool, task: M.Task, world: M.World) -> M.Decision:
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.complete_tool(call, remaining, value, error, task), world), accepted(True{}))

def tool_phase(status: M.Status, phase: M.Phase, ticket: Nat, value: J.Json, error: Bool, task: M.Task, world: M.World) -> M.Decision:
  match status phase:
    case M.Archived{} _: respond(world, accepted(False{}))
    case _ M.ToolPending{expected, call, remaining}:
      tool_matched(Nat.is_eq(ticket, expected), call, remaining, value, error, task, world)
    case _ _: respond(world, accepted(False{}))

def tool_found(found: Maybe<&2, M.Task>, ticket: Nat, value: J.Json, error: Bool, world: M.World) -> M.Decision:
  match found:
    case None{}: respond(world, accepted(False{}))
    case Some{+task}:
      tool_phase(M.task_status(task), M.task_phase(task), ticket, value, error, task, world)

def recover_tasks(tasks: +List<M.Task>) -> +List<M.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: T.recover(M.task_status(task), task) <> recover_tasks(rest)

def apply(input: M.Input, +world: M.World) -> M.Decision:
  match input:
    case M.UserCommand{command}: apply_command(command, world)
    case M.ModelCompleted{task_id, ticket, outcome}:
      model_found(T.find(tasks(world), task_id), ticket, outcome, world)
    case M.ToolCompleted{task_id, ticket, value, error}:
      tool_found(T.find(tasks(world), task_id), ticket, value, error, world)
    case M.Configure{environment}:
      M.World{tasks, next_task, next_ticket, previous, limits} = world
      respond(M.World{tasks, next_task, next_ticket, environment, limits}, J.Null{})
    case M.Recover{}:
      M.World{tasks, next_task, next_ticket, environment, limits} = world
      respond(M.World{recover_tasks(tasks), next_task, next_ticket, environment, limits}, J.Null{})
    case M.Continue{}:
      respond(world, J.Null{})

def decision_world(decision: M.Decision) -> M.World:
  M.Decision{world, reply, effects} = decision
  world

def decision_reply(decision: M.Decision) -> J.Json:
  M.Decision{world, reply, effects} = decision
  reply

def decision_effects(decision: M.Decision) -> +List<M.Effect>:
  M.Decision{world, reply, effects} = decision
  effects

def model_request(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, +environment, limits} = world
  +contract = M.task_contract(task)
  +tools = T.task_tools(contract)
  +allowed = T.callable(tools, catalog(environment))
  next = M.with_phase(M.ModelPending{next_ticket, allowed}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, J.Null{},
    [M.RequestModel{M.task_id(task), next_ticket, T.task_model(contract), M.task_history(task), tools, allowed}]}

def external_tool(tool: M.Tool, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, environment, limits} = world
  next = M.with_phase(M.ToolPending{next_ticket, call, remaining}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, J.Null{},
    [M.ExecuteTool{M.task_id(task), next_ticket, tool, call}]}

def tool_error(code: String, message: String, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  respond(store(T.complete_tool(call, remaining, M.failure(code, message), True{}, task), world), J.Null{})

def decode_messages(values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: J.text(value) <> decode_messages(rest)

def argument_nat(+arguments: J.Json, name: String, fallback: Nat) -> Nat:
  J.natural_or(J.natural(J.get(arguments, name)), fallback)

def finish_archived(status: M.Status, task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: M.with_phase(M.Idle{}, task)
    case _: task

# Internal effects and their calling-task output are one pure transition and one
# durable commit. Looking the caller up again preserves self-send/self-archive.
def internal_result(found: Maybe<&2, M.Task>, call: M.Call, remaining: +List<M.Attempt>, +result: M.Decision) -> M.Decision:
  match found:
    case None{}:
      result
    case Some{+task}:
      +reply = decision_reply(result)
      next = finish_archived(M.task_status(task), T.complete_tool(call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task))
      M.Decision{store(next, decision_world(result)), J.Null{}, decision_effects(result)}

def finish_internal(id: Nat, call: M.Call, remaining: +List<M.Attempt>, +result: M.Decision) -> M.Decision:
  internal_result(T.find(tasks(decision_world(result)), id), call, remaining, result)

def builtin(tool: M.Builtin, +arguments: J.Json, +call: M.Call, remaining: +List<M.Attempt>, +task: M.Task, world: M.World) -> M.Decision:
  match tool:
    case M.ForkTask{}:
      fork(argument_nat(arguments, "child_count", 0n), decode_messages(J.items(J.get(arguments, "messages"))), call, remaining, task, world)
    case M.ReadTask{}:
      finish_internal(M.task_id(task), call, remaining,
        read(argument_nat(arguments, "task_id", 0n), argument_nat(arguments, "after", 0n), argument_nat(arguments, "limit", 100n), world))
    case M.SendMessage{}:
      finish_internal(M.task_id(task), call, remaining,
        send(argument_nat(arguments, "task_id", 0n), J.text(J.get(arguments, "message")), world))
    case M.ArchiveTask{}:
      finish_internal(M.task_id(task), call, remaining,
        change(argument_nat(arguments, "task_id", 0n), M.Archive{}, world))
    case M.Bash{}:
      tool_error("internal_error", "Bash must cross the external-effect boundary", call, remaining, task, world)

def dispatch_source(source: M.Source, tool: M.Tool, +call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match source:
    case M.Harness{M.Bash{}}:
      external_tool(tool, call, remaining, task, world)
    case M.Mcp{server, remote}:
      external_tool(tool, call, remaining, task, world)
    case M.Harness{builtin_tool}:
      builtin(builtin_tool, T.call_arguments(call), call, remaining, task, world)

def tool_schema(tool: M.Tool) -> J.Json:
  M.Tool{name, description, schema, source} = tool
  schema

def valid_arguments(source: M.Source, schema: J.Json, +arguments: J.Json) -> Bool:
  match source:
    case M.Mcp{server, remote}:
      J.is_object(arguments)
    case M.Harness{M.Bash{}}:
      Schema.valid(schema, arguments) && M.nonempty(J.text(J.get(arguments, "command")))
    case M.Harness{other}:
      Schema.valid(schema, arguments)

def tool_valid(valid: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match valid:
    case False{}:
      tool_error("invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task, world)
    case True{}:
      dispatch_source(M.tool_source(tool), tool, call, remaining, task, world)

def tool_available(available: Bool, +tool: M.Tool, +call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match available:
    case False{}:
      tool_error("tool_unavailable", "The task's frozen tool route is unavailable", call, remaining, task, world)
    case True{}:
      tool_valid(valid_arguments(M.tool_source(tool), tool_schema(tool), T.call_arguments(call)), tool, call, remaining, task, world)

def tool_retry(permitted: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, +world: M.World) -> M.Decision:
  match permitted:
    case False{}:
      tool_error("outcome_unknown", "The effect may already have happened; automatic repetition is forbidden", call, remaining, task, world)
    case True{}:
      tool_available(T.available(catalog(environment(world)), tool), tool, call, remaining, task, world)

def tool_found_for_work(found: Maybe<&2, M.Tool>, +attempt: M.Attempt, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match found:
    case None{}:
      tool_error("unknown_tool", "The call does not name a tool in the task contract", M.attempt_call(attempt), remaining, task, world)
    case Some{+tool}:
      tool_retry(M.may_execute(M.recovery(M.tool_source(tool)), attempt), tool, M.attempt_call(attempt), remaining, task, world)

def run_tool(phase: M.Phase, +task: M.Task, world: M.World) -> M.Decision:
  match phase:
    case M.Ready{Con{+attempt, remaining}}:
      tool_found_for_work(T.find_tool(T.task_tools(M.task_contract(task)), T.call_name(M.attempt_call(attempt))), attempt, remaining, task, world)
    case _: respond(world, J.Null{})

def work(work: M.Work, +task: M.Task, world: M.World) -> M.Decision:
  match work:
    case M.NoWork{}: respond(world, J.Null{})
    case M.BecomeIdle{}: respond(store(M.with_phase(M.Idle{}, task), world), J.Null{})
    case M.RequestNextModel{}: model_request(task, world)
    case M.RunNextTool{}: run_tool(M.task_phase(task), task, world)

def combine(before: M.Decision, after: M.Decision) -> M.Decision:
  match before after:
    case M.Decision{old, reply, effects} M.Decision{world, ignored, added}:
      M.Decision{world, reply, List.append(&2, M.Effect, effects, added)}

def defer(decision: M.Decision) -> M.Decision:
  M.Decision{world, reply, effects} = decision
  M.Decision{world, reply, List.append(&2, M.Effect, effects, [M.ContinueScheduling{}])}

# A finite input transition cannot promise that an agent will finish. It makes
# bounded progress and explicitly requests another turn if internal work remains.
def schedule(fuel: Nat, candidate: Maybe<&2, M.Task>, +decision: M.Decision) -> M.Decision:
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = combine(decision, work(M.work(M.task_status(task), M.task_phase(task)), task, decision_world(decision)))
      schedule(p, T.runnable(tasks(decision_world(next))), next)

def should_schedule(input: M.Input) -> Bool:
  match input:
    case M.UserCommand{M.Read{task_id, after, limit}}: False{}
    case M.UserCommand{M.ListTasks{}}: False{}
    case M.UserCommand{M.Describe{}}: False{}
    case M.Configure{environment}: False{}
    case _: True{}

def scheduling_budget(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  steps

def rendering_budget(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  render

def frame_limit(world: M.World) -> U32:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  bytes

def scheduled(enabled: Bool, +decision: M.Decision) -> M.Decision:
  match enabled:
    case False{}: decision
    case True{}: schedule(scheduling_budget(decision_world(decision)), T.runnable(tasks(decision_world(decision))), decision)

def output_admitted(fits: Bool, decision: M.Decision, previous: M.World) -> M.Decision:
  match fits:
    case True{}: decision
    case False{}: reject(previous, "output_limit", "The complete decision exceeds the native output bound; no state change or effect was committed")

def admission(rendered: Result<&2, &2, String, String>, decision: M.Decision, +previous: M.World) -> M.Decision:
  match rendered:
    case Fail{error}: reject(previous, "output_limit", error)
    case Done{text}:
      output_admitted(Nat.is_le(J.utf8_length(text), U32.to_nat(frame_limit(previous))), decision, previous)

def deliver(durable: Bool, +decision: M.Decision, +previous: M.World) -> M.Decision:
  admission(J.render(rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous)

# Delivery admission is part of the executable transition. An oversized reply
# must not leave an advanced in-memory world behind a failed external request.
def transition(+input: M.Input, +world: M.World) -> M.Decision:
  deliver(M.durable(input), scheduled(should_schedule(input), apply(input, world)), world)

def next(world: M.World, input: M.Input) -> M.World:
  decision_world(transition(input, world))

def replay(events: +List<M.Input>, world: M.World) -> M.World:
  Theory.replay(~M.World, ~M.Input, ~next, events, world)
