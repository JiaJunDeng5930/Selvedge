import Base
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./INVARIANTS.bend as I
import ./bendlib/stdlib.bend as Std

# A command denotes a resolved operation, not permission to make any safe change.
# Resolution owns every command precondition. The operation's meaning fixes the
# complete post-world, reply and effect list, before bounded scheduling/commit.
# The host cannot submit an Operation: only MODEL.Command crosses the wire.
type Operation is Data:
  Refuse{code: String, reason: String}
  Start{profile: M.Profile, reasoning: String, message: String}
  Deliver{task: M.Task, message: String}
  Control{task: M.Task, request: M.Control, next: M.Status}
  Branch{parent: M.Task, count: Nat, messages: +List<String>}
  Summarize{task: M.Task}
  Checkpoint{task: M.Task, summary: String}
  Observe{query: M.Query}

def entries(world: M.World) -> +List<M.Task>:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  tasks

def settings(world: M.World) -> M.Environment:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  environment

def configured(environment: M.Environment) -> +List<M.Profile>:
  M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
  profiles

def require(valid: Bool, yes: Operation, code: String, reason: String) -> Operation:
  match valid:
    case True{}: yes
    case False{}: Refuse{code, reason}

def selected(profile: Maybe<&2, M.Profile>, +reasoning: String, +message: String) -> Operation:
  match profile:
    case None{}: Refuse{"unknown_profile", "Select a configured model profile"}
    case Some{profile}:
      require(M.nonempty(reasoning) && M.nonempty(message), Start{profile, reasoning, message},
        "invalid_arguments", "Create requires a configured profile, a reasoning effort, and a nonempty message")

def recipient(found: Maybe<&2, M.Task>, +message: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(M.nonempty(message) && M.accepts_input(M.task_status(task)), Deliver{task, message},
        "invalid_arguments", "The message must be nonempty and the target must not be archived")

def permitted(next: Maybe<&2, M.Status>, task: M.Task, request: M.Control) -> Operation:
  match next:
    case None{}: Refuse{"invalid_transition", "This lifecycle transition is not permitted"}
    case Some{status}: Control{task, request, status}

def controlled(found: Maybe<&2, M.Task>, +request: M.Control) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: permitted(M.control(M.task_status(task), request), task, request)

def per_fork(contract: M.Contract) -> Nat:
  M.Contract{model, tools, max_fork, max_descendants} = contract
  max_fork

def branch_fits(+count: Nat, messages: +List<String>, +parent: M.Task, world: M.World) -> Bool:
  +size = List.length(&2, String, messages)
  Nat.is_le(1n, count) && Nat.is_le(count, per_fork(M.task_contract(parent))) &&
    (Nat.is_eq(size, 0n) || Nat.is_eq(size, count)) &&
    T.ancestors_fit(M.task_id(parent) <> M.task_lineage(parent), entries(world), count)

def branch_ready(status: M.Status, phase: M.Phase, +parent: M.Task,
  +count: Nat, +messages: +List<String>, world: M.World) -> Operation:
  match status phase:
    case M.Active{} M.Idle{}:
      require(branch_fits(count, messages, parent, world), Branch{parent, count, messages},
        "resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid")
    case _ _: Refuse{"task_busy", "A manual fork requires an active, idle task"}

def branched(found: Maybe<&2, M.Task>, count: Nat, messages: +List<String>, world: M.World) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+parent}: branch_ready(M.task_status(parent), M.task_phase(parent), parent, count, messages, world)

def checkpoint_ready(status: M.Status, phase: M.Phase, +task: M.Task, summary: Maybe<&2, String>) -> Operation:
  match status phase summary:
    case M.Archived{} _ _: Refuse{"task_archived", "An archived task cannot be changed"}
    case M.Active{} M.Idle{} None{}: Summarize{task}
    case _ M.Idle{} Some{+text}:
      +context = M.context_history(M.task_history(task))
      require(M.valid_summary(text) && I.settled_calls(context, context), Checkpoint{task, text},
        "invalid_summary", "A checkpoint requires a nonempty bounded summary and settled tool calls")
    case _ _ _: Refuse{"task_busy", "Model compaction requires an active idle task; a supplied summary requires a nonarchived idle task"}

def compacted(found: Maybe<&2, M.Task>, summary: Maybe<&2, String>) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: checkpoint_ready(M.task_status(task), M.task_phase(task), task, summary)

# Exhaustiveness is checked by Bend. Client schemas describe MODEL.Command;
# these clauses give each decoded constructor its operational meaning.
def resolve(command: M.Command, +world: M.World) -> Operation:
  match command:
    case M.Create{profile, reasoning, message}:
      selected(M.find_profile(configured(settings(world)), profile), reasoning, message)
    case M.Send{id, message}: recipient(T.find(entries(world), id), message)
    case M.ChangeStatus{id, control}: controlled(T.find(entries(world), id), control)
    case M.Fork{id, count, messages}: branched(T.find(entries(world), id), count, messages, world)
    case M.Compact{id, summary}: compacted(T.find(entries(world), id), summary)
    case M.Observe{query}: Observe{query}

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def replace(task: M.Task, world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  M.World{T.replace(tasks, task), next_task, next_ticket, environment, limits}

def changed(id: Nat, task: M.Task, world: M.World, effects: +List<M.Effect>) -> M.Decision:
  M.Decision{replace(task, world), M.success(id_result(id)), effects}

def start(profile: M.Profile, reasoning: String, message: String, world: M.World) -> M.Decision:
  M.World{tasks, +next_task, next_ticket, +environment, limits} = world
  M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
  task : M.Task = M.Task{next_task, Nil{}, M.Contract{M.Model{profile, reasoning, project}, catalog, max_fork, max_descendants},
    M.Active{}, M.HistoryNode{M.EmptyHistory{}, M.UserMessage{message}}, Nil{}, M.Ready{Nil{}}}
  M.Decision{M.World{List.append(&2, M.Task, tasks, [task]), 1n+next_task, next_ticket, environment, limits},
    M.success(id_result(next_task)), Nil{}}

def status_change(next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match next:
    case M.Archived{}:
      changed(M.task_id(task), M.with_phase(M.Idle{}, M.with_status(M.Archived{}, task)), world, [M.CancelTask{M.task_id(task)}])
    case status: changed(M.task_id(task), T.promote(M.with_status(status, task)), world, Nil{})

def lifecycle(request: M.Control, next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match request:
    case M.Interrupt{}: changed(M.task_id(task), T.interrupt(task), world, [M.CancelTask{M.task_id(task)}])
    case _: status_change(next, task, world)

def initial_message(message: Maybe<&2, String>, history: M.History) -> M.History:
  match message:
    case None{}: history
    case Some{text}: M.HistoryNode{history, M.UserMessage{text}}

def child(id: Nat, parent: M.Task, call_id: String, branch: Nat, remaining: +List<M.Attempt>, message: Maybe<&2, String>) -> M.Task:
  M.Task{parent_id, lineage, contract, status, history, queued, phase} = parent
  M.Task{id, parent_id <> lineage, contract, M.Active{}, initial_message(message, M.branch_history(history, call_id, branch)),
    Nil{}, M.Ready{M.inherit_attempts(remaining)}}

type Children is Data:
  Children{tasks: +List<M.Task>, next_id: Nat}

def prepend(task: M.Task, children: Children) -> Children:
  Children{rest, end} = children
  Children{task <> rest, end}

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: M.Task, +call_id: String,
  +remaining: +List<M.Attempt>, +messages: +List<String>) -> Children:
  match count:
    case 0n: Children{Nil{}, next_id}
    case 1n+p:
      prepend(child(next_id, parent, call_id, branch, remaining, List.head(&2, String, messages)),
        children(p, 1n+next_id, 1n+branch, parent, call_id, remaining, List.tail(&2, String, messages)))

def identity(task: M.Task) -> J.Json:
  J.nat(M.task_id(task))

def identities(tasks: +List<M.Task>) -> +List<J.Json>:
  Std.map(~M.Task, ~J.Json, ~identity, tasks)

def branch_call(ticket: Nat, count: Nat, messages: +List<String>) -> M.Call:
  M.Call{"manual-fork-" ++ Nat.show(ticket), "fork_task",
    J.Object{[J.Field{"child_count", J.nat(count)}, J.Field{"messages", J.Array{T.strings_json(messages)}}]}}

def branch_commit(built: Children, +parent: M.Task, call_id: String, world: M.World) -> M.Decision:
  Children{+spawned, end} = built
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  caller = T.promote(M.with_phase(M.Ready{Nil{}}, M.with_history(M.branch_history(M.task_history(parent), call_id, 0n), parent)))
  M.Decision{M.World{List.append(&2, M.Task, T.replace(tasks, caller), spawned), end, 1n+next_ticket, environment, limits},
    M.success(J.Object{[J.Field{"children", J.Array{identities(spawned)}}]}), Nil{}}

def branch(+task: M.Task, +count: Nat, +messages: +List<String>, +world: M.World) -> M.Decision:
  M.World{tasks, +next_task, +next_ticket, environment, limits} = world
  +call = branch_call(next_ticket, count, messages)
  +parent = M.append_message(M.FunctionCall{call}, task)
  branch_commit(children(count, next_task, 1n, parent, T.call_id(call), Nil{}, messages), parent, T.call_id(call), world)

def summarize(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, environment, limits} = world
  next = M.with_phase(M.SummaryPending{next_ticket, False{}}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, M.success(id_result(M.task_id(task))),
    [M.RequestSummary{M.task_id(task), next_ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(task))}]}

def page_checked(valid: Bool, task: M.Task, after: Nat, limit: Nat) -> J.Json:
  match valid:
    case False{}: M.failure("invalid_page", "The page requires 1..100 messages and an offset on the task history")
    case True{}: M.success(T.page(task, after, limit))

def page(found: Maybe<&2, M.Task>, +after: Nat, +limit: Nat) -> J.Json:
  match found:
    case None{}: M.failure("task_not_found", "The target task does not exist")
    case Some{+task}:
      page_checked(Nat.is_le(1n, limit) && Nat.is_le(limit, 100n) && Nat.is_le(after, M.history_length(M.task_history(task))), task, after, limit)

def listing(world: M.World) -> J.Json:
  M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits} = world
  M.success(J.Object{[J.Field{"tasks", J.Array{T.summaries(tasks)}},
    J.Field{"profiles", J.Array{M.profiles_json(profiles)}}, J.Field{"tools", J.Array{M.tools_json(catalog)}},
    J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]})

def query(query: M.Query, world: M.World) -> J.Json:
  match query:
    case M.Read{id, after, limit}: page(T.find(entries(world), id), after, limit)
    case M.ListTasks{}: listing(world)
    case M.Describe{}: M.success(M.description())

def meaning(operation: Operation, +world: M.World) -> M.Decision:
  match operation:
    case Refuse{code, reason}: M.Decision{world, M.failure(code, reason), Nil{}}
    case Start{profile, reasoning, message}: start(profile, reasoning, message, world)
    case Deliver{+task, message}:
      M.Decision{replace(T.receive(message, task), world), M.success(id_result(M.task_id(task))), Nil{}}
    case Control{task, request, next}: lifecycle(request, next, task, world)
    case Branch{task, count, messages}: branch(task, count, messages, world)
    case Summarize{task}: summarize(task, world)
    case Checkpoint{+task, summary}:
      M.Decision{replace(M.append_message(M.ContextCheckpoint{summary}, task), world), M.success(id_result(M.task_id(task))), Nil{}}
    case Observe{request}: M.Decision{world, query(request, world), Nil{}}

def command(+request: M.Command, +world: M.World) -> M.Decision:
  meaning(resolve(request, world), world)
