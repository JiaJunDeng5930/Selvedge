import Base
import ./REASONING.bend as Reasoning
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./bendlib/operations.bend as Ops
import ./INVARIANTS.bend as I
import ./bendlib/stdlib.bend as Std
import ./WORKSPACE.bend as Workspace
import ./PROJECTS.bend as Projects
import ./bendlib/schema.bend as Schema
import ./APPROVALS.bend as Approvals
import ./BOARD.bend as B
import ./bendlib/board-resolution.bend as BoardResolution
import ./bendlib/board-state.bend as BoardState
import ./bendlib/board-spec.bend as BoardSpec

# A command denotes a resolved operation, not permission to make any safe change.
# Resolution owns every command precondition. The operation's meaning fixes the
# complete post-world, reply and effect list, before bounded scheduling/commit.
# The host cannot submit an Operation: only MODEL.Command crosses the wire.
type Operation is Data:
  Refuse{code: String, reason: String}
  Start{profile: M.Profile, reasoning: String, message: String, selection: Workspace.Selection}
  Deliver{task: M.Task, message: String}
  Steer{task: M.Task, message: String}
  Cancel{task: M.Task, operation: M.Operation()}
  Control{task: M.Task, request: M.Control, next: M.Status}
  Branch{parent: M.Task, count: Nat, messages: +List<String>, selection: Workspace.Selection}
  Summarize{task: M.Task}
  Checkpoint{task: M.Task, summary: String}
  Observe{query: M.Query}
  StoreProject{project_id: Nat, project: M.Project, next_id: U32}
  RemoveProject{project_id: Nat}
  Review{resolution: Approvals.Resolution}
  BoardChange{change: BoardResolution.Change}
  StartCard{id: Nat, card: B.Card, now: U32, profile: M.Profile, reasoning: String, message: String, selection: Workspace.Selection}

def admitted(operation: Operation) -> Bool:
  match operation:
    case Refuse{code, reason}: False{}
    case _: True{}

def entries(world: M.World) -> +List<M.Task>:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  tasks

def settings(world: M.World) -> M.Environment:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  environment

def configured(environment: M.Environment) -> +List<M.Profile>:
  M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  profiles

def require(valid: Bool, yes: Operation, code: String, reason: String) -> Operation:
  match valid:
    case True{}: yes
    case False{}: Refuse{code, reason}

def task_selection(+task: M.Task) -> Workspace.Selection:
  Workspace.Selection{M.task_context(task), M.model_guidance(T.task_model(M.task_contract(task)))}

def environment_selection(environment: M.Environment) -> Workspace.Selection:
  M.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins} = environment
  Workspace.Selection{Workspace.defaults(guidance), guidance}

def project_settings(base: Result<&2, &2, String, Workspace.Selection>, options: J.Json,
  profile: M.Profile, profiles: +List<M.Profile>) -> Result<&2, &2, String, Workspace.Selection>:
  match base:
    case Fail{reason}: Fail{reason}
    case Done{Workspace.Selection{context, guidance}}: Workspace.resolve(options, context, guidance, profile, profiles)

def selected_settings(+options: J.Json, base: Workspace.Selection, profile: M.Profile, +world: M.World) -> Result<&2, &2, String, Workspace.Selection>:
  Workspace.Selection{context, guidance} = base
  project_settings(Projects.select(J.get(options, "project_id"), context, guidance, Projects.registry(world)),
    options, profile, configured(settings(world)))

def start_selection(selection: Result<&2, &2, String, Workspace.Selection>, +profile: M.Profile,
  +reasoning: String, +message: String) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}:
      require(Reasoning.permitted(M.profile_reasoning(profile), reasoning) && M.nonempty(message), Start{profile, reasoning, message, selection},
        "invalid_arguments", "Create requires a nonempty message and a permitted reasoning effort. Adaptive endpoints accept only auto.")

def selected(profile: Maybe<&2, M.Profile>, reasoning: String, message: String, options: J.Json, +world: M.World) -> Operation:
  match profile:
    case None{}: Refuse{"unknown_profile", "Select a configured model profile"}
    case Some{+profile}:
      start_selection(selected_settings(options, environment_selection(settings(world)), profile, world),
        profile, Reasoning.selection(reasoning, M.profile_reasoning(profile)), message)

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, parent: M.Task,
  count: Nat, messages: +List<String>) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}: Branch{parent, count, messages, selection}

def configure_branch(operation: Operation, options: J.Json, world: M.World) -> Operation:
  match operation:
    case Branch{+parent, count, messages, base}:
      branch_selection(selected_settings(options, base, M.model_profile(T.task_model(M.task_contract(parent))), world), parent, count, messages)
    case other: other

def selected_contract(selection: Workspace.Selection, contract: M.Contract) -> M.Contract:
  Workspace.Selection{context, guidance} = selection
  M.Contract{M.Model{profile, reasoning, previous_guidance}, tools, max_fork, max_descendants, plugins, previous_context} = contract
  M.Contract{M.Model{profile, reasoning, guidance}, tools, max_fork, max_descendants, plugins, context}

def selected_parent(selection: Workspace.Selection, +parent: M.Task) -> M.Task:
  M.with_contract(selected_contract(selection, M.task_contract(parent)), parent)

def recipient(found: Maybe<&2, M.Task>, +message: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(M.nonempty(message) && M.accepts_input(M.task_status(task)), Deliver{task, message},
        "invalid_arguments", "The message must be nonempty and the target must not be archived")

def steering(found: Maybe<&2, M.Task>, +message: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(M.nonempty(message) && M.accepts_input(M.task_status(task)), Steer{task, message},
        "invalid_arguments", "Steering requires a nonempty instruction and a nonarchived task")

def cancellable(found: Maybe<&2, M.Operation()>, +task: M.Task) -> Operation:
  match found:
    case None{}: Refuse{"operation_not_found", "The operation is not in flight for this task"}
    case Some{operation}:
      require(M.accepts_input(M.task_status(task)), Cancel{task, operation}, "task_archived", "An archived task cannot be changed")

def cancellation(found: Maybe<&2, M.Task>, ticket: Nat) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: cancellable(Ops.find(M.task_operations(task), ticket), task)

def permitted(next: Maybe<&2, M.Status>, task: M.Task, request: M.Control) -> Operation:
  match next:
    case None{}: Refuse{"invalid_transition", "This lifecycle transition is not permitted"}
    case Some{status}: Control{task, request, status}

def controlled(found: Maybe<&2, M.Task>, +request: M.Control) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: permitted(M.control(M.task_status(task), request), task, request)

def per_fork(contract: M.Contract) -> Nat:
  M.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
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
      require(branch_fits(count, messages, parent, world), Branch{parent, count, messages, task_selection(parent)},
        "resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid")
    case _ _: Refuse{"task_busy", "A manual fork requires an active, idle task"}

def branched(found: Maybe<&2, M.Task>, count: Nat, messages: +List<String>, world: M.World) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+parent}: branch_ready(M.task_status(parent), M.task_phase(parent), parent, count, messages, world)

def checkpoint_ready(status: M.Status, phase: M.Phase, +task: M.Task, summary: Maybe<&2, String>) -> Operation:
  match status phase summary:
    case M.Archived{} _ _: Refuse{"task_archived", "An archived task cannot be changed"}
    case M.Active{} M.Idle{} None{}:
      require(Bool.not(M.operations_pending(M.task_operations(task))), Summarize{task},
        "task_busy", "Wait for in-flight operation results before summarizing the task")
    case _ M.Idle{} Some{+text}:
      +context = M.context_history(M.task_history(task))
      require(Bool.not(M.operations_pending(M.task_operations(task))) && M.valid_summary(text) && I.settled_calls(context, context), Checkpoint{task, text},
        "invalid_summary", "A checkpoint requires a nonempty bounded summary, settled tool calls, and no in-flight operations")
    case _ _ _: Refuse{"task_busy", "Model compaction requires an active idle task; a supplied summary requires a nonarchived idle task"}

def compacted(found: Maybe<&2, M.Task>, summary: Maybe<&2, String>) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: checkpoint_ready(M.task_status(task), M.task_phase(task), task, summary)

def project_fields(+workspace: J.Json, +guidance: J.Json) -> Bool:
  (Workspace.absent(workspace) || Schema.valid(M.workspace_schema(), workspace)) &&
    (Workspace.absent(guidance) || Schema.valid(M.guidance_schema(), guidance))

def create_project(name: String, +workspace: J.Json, +guidance: J.Json, +world: M.World) -> Operation:
  +project = Projects.proposal(Some{name}, workspace, guidance, M.Project{"", M.Workspace{Nil{}, None{}}, M.NoProject{}})
  +registry = Projects.registry(world)
  +id = Projects.next_id(registry)
  require(Schema.valid(M.workspace_schema(), workspace) && project_fields(workspace, guidance) && Projects.valid_project(project) &&
    Nat.is_lt(Projects.count(registry), 256n) && (Projects.next_word(registry) < 4294967295 : U32),
    StoreProject{id, project, (Projects.next_word(registry) + 1 : U32)}, "invalid_project", "A project requires a nonempty bounded name, valid workspace defaults, and available project capacity")

def update_project(found: Maybe<&2, M.Project>, id: Nat, name: Maybe<&2, String>, +workspace: J.Json,
  +guidance: J.Json, next_id: U32) -> Operation:
  match found:
    case None{}: Refuse{"project_not_found", "The project does not exist"}
    case Some{previous}:
      +project = Projects.proposal(name, workspace, guidance, previous)
      require(project_fields(workspace, guidance) && Projects.valid_project(project), StoreProject{id, project, next_id},
        "invalid_project", "Project defaults require a valid name, workspace and matching guidance")

def delete_project(+id: Nat, +world: M.World) -> Operation:
  require(Bool.not(Projects.missing(Projects.find(Projects.registry(world), id))) && Nat.is_eq(Projects.task_count(entries(world), id), 0n) &&
    Bool.not(BoardState.project_used(B.cards(BoardState.registry(world)), id)),
    RemoveProject{id}, "project_not_empty", "The project must exist and have no tasks or board cards before it can be deleted")

def card_start(operation: Operation, id: Nat, card: B.Card, now: U32) -> Operation:
  match operation:
    case Start{profile, reasoning, message, selection}: StartCard{id, card, now, profile, reasoning, message, selection}
    case Refuse{code, reason}: Refuse{code, reason}
    case _: Refuse{"invalid_card_start", "A board launch must resolve through ordinary task creation"}

def without_project(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"project_id", value}, rest}: without_project(rest)
    case Con{field, rest}: field <> without_project(rest)

def with_project(project: Maybe<&2, Nat>, fields: +List<J.Field>) -> J.Json:
  match project:
    case None{}: J.Object{fields}
    case Some{id}: J.Object{J.Field{"project_id", J.nat(id)} <> fields}

def card_options(project: Maybe<&2, Nat>, options: J.Json) -> J.Json:
  match options:
    case J.Object{fields}: with_project(project, without_project(fields))
    case _: with_project(project, Nil{})

def board_resolution(resolution: BoardResolution.Resolution, +world: M.World) -> Operation:
  match resolution:
    case BoardResolution.Refuse{code, reason}: Refuse{code, reason}
    case BoardResolution.Mutate{change}: BoardChange{change}
    case BoardResolution.Launch{+id, +card, now, B.AgentProfile{revision, name, profile, reasoning, instructions, options, concurrency}}:
      card_start(selected(M.find_profile(configured(settings(world)), profile), reasoning,
        B.prompt(id, B.draft(card), instructions), card_options(B.project(B.draft(card)), options), world), id, card, now)

# Exhaustiveness is checked by Bend. Client schemas describe MODEL.Command;
# these clauses give each decoded constructor its operational meaning.
def resolve(command: M.Command, +world: M.World) -> Operation:
  match command:
    case M.Create{profile, reasoning, message, options}:
      selected(M.find_profile(configured(settings(world)), profile), reasoning, message, options, world)
    case M.Send{id, message}: recipient(T.find(entries(world), id), message)
    case M.Steer{id, message}: steering(T.find(entries(world), id), message)
    case M.Cancel{id, ticket}: cancellation(T.find(entries(world), id), ticket)
    case M.ChangeStatus{id, control}: controlled(T.find(entries(world), id), control)
    case M.Fork{id, count, messages, options}: configure_branch(branched(T.find(entries(world), id), count, messages, world), options, world)
    case M.Compact{id, summary}: compacted(T.find(entries(world), id), summary)
    case M.Observe{query}: Observe{query}
    case M.CreateProject{name, workspace, guidance}: create_project(name, workspace, guidance, world)
    case M.UpdateProject{+id, name, workspace, guidance}:
      update_project(Projects.find(Projects.registry(world), id), id, name, workspace, guidance, Projects.next_word(Projects.registry(world)))
    case M.DeleteProject{id}: delete_project(id, world)
    case M.ReviewApproval{id, operation, outcome}:
      Review{Approvals.resolve(T.find(entries(world), id), Approvals.HumanDecision{}, operation, outcome)}
    case M.BoardCommand{command}: board_resolution(BoardResolution.resolve(command, world), world)

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def replace(task: M.Task, world: M.World) -> M.World:
  T.update_world(task, world)

def changed(id: Nat, task: M.Task, world: M.World, effects: +List<M.Effect>) -> M.Decision:
  M.Decision{replace(task, world), M.success(id_result(id)), effects}

def start(profile: M.Profile, reasoning: String, message: String, selection: Workspace.Selection, world: M.World) -> M.Decision:
  Workspace.Selection{context, guidance} = selection
  M.World{tasks, +next_task, next_ticket, +environment, limits, projects, board} = world
  M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  task : M.Task = M.Task{next_task, Nil{}, M.Contract{M.Model{profile, reasoning, guidance}, catalog, max_fork, max_descendants, plugins, context},
    M.Active{}, M.HistoryNode{M.EmptyHistory{}, M.UserMessage{message}}, Nil{}, M.Ready{Nil{}}, Nil{}, True{}}
  M.Decision{M.World{List.append(&2, M.Task, tasks, [task]), 1n+next_task, next_ticket, environment, limits, projects, board},
    M.success(id_result(next_task)), Nil{}}

def status_change(next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match next:
    case M.Archived{}:
      changed(M.task_id(task), T.archive(task), world, [M.CancelTask{M.task_id(task)}])
    case status: changed(M.task_id(task), T.promote(M.with_status(status, task)), world, Nil{})

def lifecycle(request: M.Control, next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match request:
    case M.Interrupt{}: changed(M.task_id(task), T.interrupt(task), world, [M.CancelTask{M.task_id(task)}])
    case _: status_change(next, task, world)

def initial_message(message: Maybe<&2, String>, history: M.History) -> M.History:
  match message:
    case None{}: history
    case Some{text}: M.HistoryNode{history, M.UserMessage{text}}

def child(+id: Nat, +parent: M.Task, call_id: String, branch: Nat, remaining: +List<M.Attempt>, message: Maybe<&2, String>) -> M.Task:
  M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified} = parent
  M.Task{id, parent_id <> lineage, contract, M.Active{}, initial_message(message, M.child_history(Ops.inherited(parent), id, call_id, branch)),
    Nil{}, M.Ready{M.inherit_attempts(remaining)}, Nil{}, True{}}

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
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  caller = T.promote(M.with_notified(True{}, M.with_phase(M.Ready{Nil{}}, M.with_history(M.branch_history(M.task_history(parent), call_id, 0n), parent))))
  M.Decision{M.World{List.append(&2, M.Task, T.replace(tasks, caller), spawned), end, 1n+next_ticket, environment, limits, projects, board},
    M.success(J.Object{[J.Field{"children", J.Array{identities(spawned)}}]}), Nil{}}

def branch(+task: M.Task, +count: Nat, +messages: +List<String>, selection: Workspace.Selection, +world: M.World) -> M.Decision:
  M.World{tasks, +next_task, +next_ticket, environment, limits, projects, board} = world
  +call = branch_call(next_ticket, count, messages)
  +parent = M.append_message(M.FunctionCall{call}, task)
  branch_commit(children(count, next_task, 1n, selected_parent(selection, parent), T.call_id(call), Nil{}, messages), parent, T.call_id(call), world)

def summarize(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, environment, limits, projects, board} = world
  next = M.with_notified(False{}, M.with_phase(M.SummaryPending{next_ticket, False{}}, task))
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits, projects, board}, M.success(id_result(M.task_id(task))),
    [M.RequestSummary{M.task_id(task), next_ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(task)), M.task_context(task)}]}

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
  M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects, board} = world
  M.success(J.Object{[J.Field{"tasks", J.Array{T.summaries(tasks)}},
    J.Field{"profiles", J.Array{M.profiles_json(profiles)}}, J.Field{"tools", J.Array{M.tools_json(catalog)}},
    J.Field{"plugins", M.plugins_json(plugins)},
    J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]})

def query(query: M.Query, +world: M.World) -> J.Json:
  match query:
    case M.Read{id, after, limit}: page(T.find(entries(world), id), after, limit)
    case M.ListTasks{}: listing(world)
    case M.Describe{}: M.success(M.description())
    case M.ListProjects{}: M.success(J.Array{Projects.summaries(Projects.entries(Projects.registry(world)), entries(world))})
    case M.ReadProject{+id}: Projects.detail(id, Projects.find(Projects.registry(world), id))
    case M.BoardQuery{query}: BoardState.query(query, world)

def meaning(operation: Operation, +world: M.World) -> M.Decision:
  match operation:
    case Refuse{code, reason}: M.Decision{world, M.failure(code, reason), Nil{}}
    case Review{resolution}: Approvals.meaning(resolution, world)
    case Start{profile, reasoning, message, selection}: start(profile, reasoning, message, selection, world)
    case BoardChange{change}: BoardSpec.change(change, world)
    case StartCard{id, card, now, profile, reasoning, message, selection}:
      BoardSpec.started(id, BoardState.task_id(world), card, now, start(profile, reasoning, message, selection, world))
    case Deliver{+task, message}:
      M.Decision{replace(T.receive(message, task), world), M.success(id_result(M.task_id(task))), Nil{}}
    case Steer{+task, message}:
      M.Decision{replace(T.steer(message, task), world), M.success(id_result(M.task_id(task))),
        T.steering_effects(M.task_phase(task), M.task_id(task))}
    case Cancel{+task, +operation}:
      M.Decision{replace(T.promote(Ops.cancelled(operation, task)), world),
        M.success(J.Object{[J.Field{"task_id", J.nat(M.task_id(task))}, J.Field{"operation_id", J.nat(Ops.ticket(operation))}]}),
        [M.CancelTicket{M.task_id(task), Ops.callback(operation)}]}
    case Control{task, request, next}: lifecycle(request, next, task, world)
    case Branch{task, count, messages, selection}: branch(task, count, messages, selection, world)
    case Summarize{task}: summarize(task, world)
    case Checkpoint{+task, summary}:
      M.Decision{replace(M.append_message(M.ContextCheckpoint{summary}, task), world), M.success(id_result(M.task_id(task))), Nil{}}
    case Observe{request}: M.Decision{world, query(request, world), Nil{}}
    case StoreProject{+id, project, next_id}:
      M.Decision{Projects.store(Projects.put(id, project, Projects.registry(world), next_id), world),
        M.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}
    case RemoveProject{+id}:
      M.Decision{Projects.store(Projects.remove(id, Projects.registry(world)), world),
        M.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}

def command(+request: M.Command, +world: M.World) -> M.Decision:
  meaning(resolve(request, world), world)
