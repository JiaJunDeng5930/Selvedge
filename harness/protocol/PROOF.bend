import Base
import ../features/laws.bend as FeatureLaws
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../reasoning/CONTRACT.bend as Reasoning
import ../reasoning/PROGRAM.bend as ActualReasoning
import ../reasoning/SPEC.bend as RequiredReasoning
import ../reasoning/PROOF.bend as ReasoningProof
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ../tasks/PROGRAM.bend as T
import ../../bendlib/json.bend as J
import ../COMMANDS.bend as Commands
import ./PROGRAM.bend as Protocol
import ../workspace/WORKSPACE.bend as Workspace
import ../approval/MODEL.bend as Approvals
import ../CONTRACT.bend as A
import ../execution/OPERATIONS.bend as Ops

# Local proof obligations for the protocol boundary. No runtime policy lives here.

def query_semantics(+query: M.Query, +world: M.World()) ->
  {P.query(query, world) == Commands.query(query, world) : J.Json}:
  {==}

def branch_world(world: M.World()) -> M.World():
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  C.Frame{D.State{tasks, next_task, 1n+next_ticket, environment, limits, projects}, board}

def branch_commit_semantics(+built: Commands.Children, +call: D.Call, +parent: D.Task, +world: M.World()) ->
  {P.commit_fork(built, call, Nil{}, parent, branch_world(world)) ==
   Commands.branch_commit(built, parent, T.call_id(call), world) : M.Decision()}:
  match built world:
    case Commands.Children{children, end} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def status_semantics(+status: D.Status, +task: D.Task, +world: M.World()) ->
  {P.change_to(status, task, world) == Commands.status_change(status, task, world) : M.Decision()}:
  match status world:
    case D.Active{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case D.Frozen{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case D.Stopped{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case D.Archived{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def control_semantics(+request: D.Control, +status: D.Status, +task: D.Task, +world: M.World()) ->
  {P.change_requested(request, status, task, world) == Commands.lifecycle(request, status, task, world) : M.Decision()}:
  match request world:
    case D.Interrupt{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case D.Freeze{} _: status_semantics(status, task, world)
    case D.Unfreeze{} _: status_semantics(status, task, world)
    case D.Stop{} _: status_semantics(status, task, world)
    case D.Archive{} _: status_semantics(status, task, world)

def Laws.review_semantics(resolution, world):
  match resolution world:
    case Approvals.Ignore{} _: {==}
    case Approvals.Refuse{code, reason} _: {==}
    case Approvals.Grant{operation, task, reviewer, reason} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Approvals.Deny{operation, task, reviewer, outcome} _: {==}

def spawn_semantics(+profile: D.Profile, +reasoning: String, +message: String, +selection: Workspace.Selection, +world: M.World()) ->
  {P.execute_start(profile, reasoning, message, selection, world) == Commands.start(profile, reasoning, message, selection, world) : M.Decision()}:
  match selection world:
    case Workspace.Selection{context, guidance}
      C.Frame{D.State{tasks, next_task, next_ticket, D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects}, rest}: {==}

def Laws.operation_semantics(operation, world):
  match operation world:
    case Commands.FeatureOperation{operation} _:
      FeatureLaws.meaning(P.execute_start, Commands.start,
        +profile => +reasoning => +message => +selection => +state => spawn_semantics(profile, reasoning, message, selection, state), operation, world)
    case Commands.Refuse{code, reason} _: {==}
    case Commands.Start{profile, reasoning, message, Workspace.Selection{context, guidance}}
         C.Frame{D.State{tasks, next_task, next_ticket, D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects}, +board}: {==}
    case Commands.Deliver{task, message} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Commands.Steer{task, message} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Commands.Cancel{task, operation} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Commands.Control{task, request, next} _: control_semantics(request, next, task, world)
    case Commands.Branch{+task, +count, +messages, selection} C.Frame{D.State{tasks, +next_task, +next_ticket, environment, limits, projects}, +board}:
      +call = Commands.branch_call(next_ticket, count, messages)
      +parent = D.append_message(D.FunctionCall{call}, task)
      branch_commit_semantics(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, parent), T.call_id(call), Nil{}, messages),
        call, parent, C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, board})
    case Commands.Summarize{task} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Commands.Checkpoint{task, summary} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Commands.Observe{+query} _:
      Equal.cong(J.Json, M.Decision(), (reply => C.Decision{world, reply, Nil{}}),
        P.query(query, world), Commands.query(query, world), query_semantics(query, world))
    case Commands.StoreProject{id, project, next_id} _: {==}
    case Commands.RemoveProject{id} _: {==}
    case Commands.Review{resolution} _: Laws.review_semantics(resolution, world)

def Laws.command_semantics(command, world):
  Laws.operation_semantics(Commands.resolve(command, world), world)

def Laws.event_semantics(event, world):
  match event world:
    case Protocol.FeatureEvent{event} _: FeatureLaws.event(event, world)
    case Protocol.User{operation} _: Laws.operation_semantics(operation, world)
    case Protocol.Ignore{} _: {==}
    case Protocol.Review{resolution} _: Laws.review_semantics(resolution, world)
    case Protocol.ModelResult{task, outcome, allowed} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.ReasoningResult{+task, +revision, +outcome} _:
      Equal.cong(D.Task, M.Decision(), (next => C.Decision{
        P.store(next, world), Protocol.acknowledgement(True{}), Nil{}}),
        ActualReasoning.complete(revision, outcome, task), RequiredReasoning.complete(revision, outcome, task), Reasoning.completion_meaning(revision, outcome, task))
    case Protocol.SummaryResult{task, outcome, resume} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.ToolResult{task, operation, value, error} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.HookResult{task, outcome} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.AfterResult{task, operation, outcome} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.Settings{settings} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.Restart{} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}
    case Protocol.Tick{} _: {==}

def Laws.input_semantics(input, world):
  Laws.event_semantics(Protocol.resolve(input, world), world)

def internal_result_semantics(+found: Maybe<&2, D.Task>, +call: D.Call, +remaining: +List<D.Attempt>, +decision: M.Decision()) ->
  {P.internal_result(found, call, remaining, decision) == Protocol.result(found, call, remaining, decision) : M.Decision()}:
  match found decision:
    case None{} _: {==}
    case Some{task} C.Decision{world, reply, effects}: {==}

def finish_internal_semantics(+id: Nat, +call: D.Call, +remaining: +List<D.Attempt>, +decision: M.Decision()) ->
  {P.finish_internal(id, call, remaining, decision) == Protocol.finish(id, call, remaining, decision) : M.Decision()}:
  match decision:
    case C.Decision{C.Frame{D.State{+tasks, +next_task, +next_ticket, +environment, +limits, projects}, +board}, +reply, +effects}:
      internal_result_semantics(T.find(tasks, id), call, remaining,
        C.Decision{C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, board}, reply, effects})

def branched_semantics(+built: Commands.Children, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) ->
  {P.commit_invoked_fork(built, call, remaining, task, world) == Protocol.branched_invocation(built, call, remaining, task, world) : M.Decision()}:
  match built world:
    case Commands.Children{children, end} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def Laws.invocation_semantics(operation, call, remaining, task, world):
  match operation world:
    case Protocol.Internal{+operation} _:
      +id = D.task_id(task)
      +realized = P.realize(operation, world)
      +meaning = Commands.meaning(operation, world)
      Equal.trans(M.Decision(), P.finish_internal(id, call, remaining, realized), Protocol.finish(id, call, remaining, realized),
        Protocol.finish(id, call, remaining, meaning), finish_internal_semantics(id, call, remaining, realized),
        Equal.cong(M.Decision(), M.Decision(), (value => Protocol.finish(id, call, remaining, value)),
          realized, meaning, Laws.operation_semantics(operation, world)))
    case Protocol.Branch{count, messages, selection} C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}:
      branched_semantics(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, messages),
        call, remaining, task, C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, board})

def Laws.builtin_semantics(tool, arguments, call, remaining, task, world):
  Laws.invocation_semantics(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world)

def Laws.accepted_model_settlement(outcome, allowed, task, world):
  match world:
    case C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def Laws.accepted_tool_settlement(operation, value, error, task, world):
  match world:
    case C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def Laws.accepted_summary_settlement(outcome, resume, task, world):
  match world:
    case C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def control_frame(+task: D.Task, operation: D.Operation()) ->
  {D.task_phase(D.with_operations(Ops.replace(D.task_operations(task), operation), task)) == D.task_phase(task) : D.Phase}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def A.result_boundary():
  A.ResultBoundary{
    (plugin => pending => operation => value => error => task => world => {==}),
    (plugin => pending => operation => value => error => task => state => board => {==}),
    (call => current => replacement => error => pending => {==}),
    (reason => call => value => error => pending => ({==}, {==})),
    (plugin => outcome => {==}),
    (expected => ticket => plugin => pending => value => error => task => operation => outcome => different =>
      Equal.cong(Bool, Protocol.ResolvedEvent, (same => Protocol.matching(same, Protocol.AfterResult{task, operation, outcome})),
        Nat.is_eq(ticket, expected), False{}, different)),
    (id => call => announced => ticket => plugin => pending => value => error => task => duplicate => duplicate_error => {==}),
    (history => owner => operation => call => value => error => plugin => outcome => ({==}, {==})),
    (task => operation => control_frame(task, operation)),
    (outcome => plugin => pending => operation => value => error => task => world => {==}),
    (value => error => pending => operation => task => world => {==}),
    (code => reason => pending => operation => task => world => {==}),
    (operation => value => error => task => world => {==}),
    (operation => value => error => task => world => {==}),
    (operation => value => error => task => world => ({==}, {==})),
    (plugin => pending => operation => value => error => task => world => {==}),
    (ticket => plugin => pending => value => error => outcome => operation => task => world => {==}),
    (call => remaining => value => error => task => world => {==}),
    (plugin => pending => call => remaining => value => error => task => state => board => {==})}
