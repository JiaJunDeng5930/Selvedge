import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./LAWS.bend as Laws
import ./bendlib/tasks.bend as T
import ./bendlib/theory.bend as Theory
import ./bendlib/stdlib.bend as Std
import ./bendlib/json.bend as J
import ./bendlib/presentation.bend as View
import ./INVARIANTS.bend as I
import ./COMMANDS.bend as Commands
import ./bendlib/commit.bend as Commit
import ./bendlib/structures.bend as S
import ./CONCEPTS.bend as Concepts
import ./bendlib/execution.bend as Execution
import ./bendlib/protocol.bend as Protocol

def query_semantics(+query: M.Query, +world: M.World) ->
  {P.query(query, world) == Commands.query(query, world) : J.Json}:
  {==}

def branch_world(world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  M.World{tasks, next_task, 1n+next_ticket, environment, limits}

def branch_commit_semantics(+built: Commands.Children, +call: M.Call, +parent: M.Task, +world: M.World) ->
  {P.commit_fork(built, call, Nil{}, parent, branch_world(world)) ==
   Commands.branch_commit(built, parent, T.call_id(call), world) : M.Decision}:
  match built world:
    case Commands.Children{children, end} M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def status_semantics(+status: M.Status, +task: M.Task, +world: M.World) ->
  {P.change_to(status, task, world) == Commands.status_change(status, task, world) : M.Decision}:
  match status world:
    case M.Active{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case M.Frozen{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case M.Stopped{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case M.Archived{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def control_semantics(+request: M.Control, +status: M.Status, +task: M.Task, +world: M.World) ->
  {P.change_requested(request, status, task, world) == Commands.lifecycle(request, status, task, world) : M.Decision}:
  match request world:
    case M.Interrupt{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case M.Freeze{} _: status_semantics(status, task, world)
    case M.Unfreeze{} _: status_semantics(status, task, world)
    case M.Stop{} _: status_semantics(status, task, world)
    case M.Archive{} _: status_semantics(status, task, world)

def Laws.operation_semantics(operation, world):
  match operation world:
    case Commands.Refuse{code, reason} _: {==}
    case Commands.Start{profile, reasoning, message}
         M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits}: {==}
    case Commands.Deliver{task, message} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Commands.Control{task, request, next} _: control_semantics(request, next, task, world)
    case Commands.Branch{+task, +count, +messages} M.World{tasks, +next_task, +next_ticket, environment, limits}:
      +call = Commands.branch_call(next_ticket, count, messages)
      +parent = M.append_message(M.FunctionCall{call}, task)
      branch_commit_semantics(Commands.children(count, next_task, 1n, parent, T.call_id(call), Nil{}, messages),
        call, parent, M.World{tasks, next_task, next_ticket, environment, limits})
    case Commands.Summarize{task} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Commands.Checkpoint{task, summary} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Commands.Observe{+query} _:
      Equal.cong(J.Json, M.Decision, (reply => M.Decision{world, reply, Nil{}}),
        P.query(query, world), Commands.query(query, world), query_semantics(query, world))

def Laws.command_semantics(command, world):
  Laws.operation_semantics(Commands.resolve(command, world), world)

def Laws.event_semantics(event, world):
  match event world:
    case Protocol.User{operation} _: Laws.operation_semantics(operation, world)
    case Protocol.Ignore{} _: {==}
    case Protocol.ModelResult{task, outcome, allowed} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Protocol.SummaryResult{task, outcome, resume} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Protocol.ToolResult{task, call, remaining, value, error} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Protocol.Settings{settings} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Protocol.Restart{} M.World{tasks, next_task, next_ticket, environment, limits}: {==}
    case Protocol.Tick{} _: {==}

def Laws.input_semantics(input, world):
  Laws.event_semantics(Protocol.resolve(input, world), world)

def Concepts.recovery_batches():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(M.Task), {==},
    (first => second => Std.map_app(~M.Task, ~M.Task, ~Protocol.recover, first, second))}

def Concepts.task_views():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(J.Json), {==},
    (first => second => Std.map_app(~M.Task, ~J.Json, ~T.summary, first, second))}

def Concepts.branch_results():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(J.Json), {==},
    (first => second => Std.map_app(~M.Task, ~J.Json, ~Commands.identity, first, second))}

def Laws.recovery_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<M.Task>, Nil{}, S.append(M.Task), Nil{}, S.append(M.Task),
    Protocol.recovery, Concepts.recovery_batches(), first, second)

def Laws.task_view_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json),
    T.summaries, Concepts.task_views(), first, second)

def Laws.branch_result_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json),
    Commands.identities, Concepts.branch_results(), first, second)

def Laws.recovery_view_composition(tasks):
  S.map_composition(~M.Task, ~M.Task, ~J.Json, ~Protocol.recover, ~T.summary, tasks)

def finish_status_semantics(+status: M.Status, +task: M.Task) ->
  {P.finish_archived(status, task) == Protocol.finish_status(status, task) : M.Task}:
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def internal_result_semantics(+found: Maybe<&2, M.Task>, +call: M.Call, +remaining: +List<M.Attempt>, +decision: M.Decision) ->
  {P.internal_result(found, call, remaining, decision) == Protocol.result(found, call, remaining, decision) : M.Decision}:
  match found decision:
    case None{} _: {==}
    case Some{+task} M.Decision{M.World{+tasks, +next_task, +next_ticket, +environment, +limits}, +reply, +effects}:
      +next = T.complete_tool(call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task)
      +status = M.task_status(task)
      Equal.cong(M.Task, M.Decision,
        (value => M.Decision{M.World{T.replace(tasks, value), next_task, next_ticket, environment, limits}, J.Null{}, effects}),
        P.finish_archived(status, next), Protocol.finish_status(status, next), finish_status_semantics(status, next))

def finish_internal_semantics(+id: Nat, +call: M.Call, +remaining: +List<M.Attempt>, +decision: M.Decision) ->
  {P.finish_internal(id, call, remaining, decision) == Protocol.finish(id, call, remaining, decision) : M.Decision}:
  match decision:
    case M.Decision{M.World{+tasks, +next_task, +next_ticket, +environment, +limits}, +reply, +effects}:
      internal_result_semantics(T.find(tasks, id), call, remaining,
        M.Decision{M.World{tasks, next_task, next_ticket, environment, limits}, reply, effects})

def branched_semantics(+built: Commands.Children, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) ->
  {P.commit_fork(built, call, remaining, task, world) == Protocol.branched(built, call, remaining, task, world) : M.Decision}:
  match built world:
    case Commands.Children{children, end} M.World{tasks, next_task, next_ticket, environment, limits}: {==}

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
    case Protocol.Branch{count, messages} M.World{tasks, next_task, next_ticket, environment, limits}:
      branched_semantics(Commands.children(count, next_task, 1n, task, T.call_id(call), remaining, messages),
        call, remaining, task, M.World{tasks, next_task, next_ticket, environment, limits})

def Laws.builtin_semantics(tool, arguments, call, remaining, task, world):
  Laws.invocation_semantics(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world)

def Laws.execution_semantics(action, world):
  match action world:
    case Execution.Rest{} _: {==}
    case Execution.Idle{task} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.Model{task} M.World{tasks, next_task, ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits}: {==}
    case Execution.Summary{task, resume} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.External{tool, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.Internal{operation, call, remaining, task} _:
      Laws.invocation_semantics(operation, call, remaining, task, world)
    case Execution.Failure{code, reason, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits}: {==}

def Laws.work_semantics(work, task, world):
  Laws.execution_semantics(Execution.resolve(work, task, world), world)

def combination_semantics(+before: M.Decision, +after: M.Decision) ->
  {P.combine(before, after) == Execution.combine(before, after) : M.Decision}:
  match before after:
    case M.Decision{old, reply, effects} M.Decision{world, ignored, added}: {==}

def combined_work_semantics(+task: M.Task, +decision: M.Decision) ->
  {P.combine(decision, P.work(M.work(M.task_status(task), M.task_phase(task)), task, P.decision_world(decision))) ==
    Execution.combine(decision, Execution.work(M.work(M.task_status(task), M.task_phase(task)), task, Execution.world(decision))) : M.Decision}:
  +work = M.work(M.task_status(task), M.task_phase(task))
  +world = P.decision_world(decision)
  +actual = P.work(work, task, world)
  +expected = Execution.work(work, task, world)
  Equal.trans(M.Decision, P.combine(decision, actual), Execution.combine(decision, actual), Execution.combine(decision, expected),
    combination_semantics(decision, actual),
    Equal.cong(M.Decision, M.Decision, (value => Execution.combine(decision, value)), actual, expected, Laws.work_semantics(work, task, world)))

def Scheduling(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, M.Task> -> @+decision:M.Decision ->
    {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision}

def scheduling_zero(+candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(0n, candidate, decision) == Execution.schedule(0n, candidate, decision) : M.Decision}:
  match candidate decision:
    case None{} _: {==}
    case Some{task} M.Decision{world, reply, effects}: {==}

def scheduling_successor(+fuel: Nat, induction: Scheduling(fuel), +candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(1n+fuel, candidate, decision) == Execution.schedule(1n+fuel, candidate, decision) : M.Decision}:
  match candidate:
    case None{}: {==}
    case Some{+task}:
      +work = M.work(M.task_status(task), M.task_phase(task))
      +world = P.decision_world(decision)
      +actual = P.combine(decision, P.work(work, task, world))
      +expected = Execution.combine(decision, Execution.work(work, task, world))
      +following = T.runnable(P.tasks(P.decision_world(actual)))
      Equal.trans(M.Decision, P.schedule(fuel, following, actual), Execution.schedule(fuel, following, actual),
        Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(expected))), expected), induction(following, actual),
        Equal.cong(M.Decision, M.Decision,
          (+value => Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(value))), value)),
          actual, expected, combined_work_semantics(task, decision)))

def Laws.schedule_semantics(fuel, candidate, decision):
  Std.nat_ind(~Scheduling, ~scheduling_zero,
    ~(fuel => induction => +candidate => +decision => scheduling_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

def Laws.scheduling_semantics(enabled, decision):
  match enabled:
    case False{}: {==}
    case True{}:
      Laws.schedule_semantics(P.scheduling_budget(P.decision_world(decision)), T.runnable(P.tasks(P.decision_world(decision))), decision)

def guard_semantics(+state_valid: Bool, +change_valid: Bool, +decision: M.Decision, +previous: M.World) ->
  {P.admitted(state_valid, change_valid, decision, previous) == Commit.guard(state_valid, change_valid, decision, previous) : M.Decision}:
  match state_valid change_valid:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def validate_semantics(+decision: M.Decision, +previous: M.World) ->
  {P.check_live(decision, previous) == Commit.validate(decision, previous) : M.Decision}:
  match decision:
    case M.Decision{+world, +reply, +effects}:
      +decision : M.Decision = M.Decision{world, reply, effects}
      guard_semantics(I.world(world), I.decision(previous, decision), decision, previous)

def live_semantics(+decision: M.Decision) -> {P.live_decision(decision) == Commit.live(decision) : M.Decision}:
  match decision:
    case M.Decision{M.World{tasks, next_task, next_ticket, environment, limits}, reply, effects}: {==}

def Laws.commit_semantics(decision, previous):
  +live = P.live_decision(decision)
  Equal.trans(M.Decision, P.checked(decision, previous), Commit.validate(live, previous), Commit.checked(decision, previous),
    validate_semantics(live, previous),
    Equal.cong(M.Decision, M.Decision, (value => Commit.validate(value, previous)),
      live, Commit.live(decision), live_semantics(decision)))

def sized_semantics(+fits: Bool, +decision: M.Decision, +previous: M.World) ->
  {P.output_admitted(fits, decision, previous) == Commit.sized(fits, decision, previous) : M.Decision}:
  match fits:
    case True{}: {==}
    case False{}: {==}

def rendered_semantics(+rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World) ->
  {P.admission(rendered, decision, previous) == Commit.rendered(rendered, decision, previous) : M.Decision}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      sized_semantics(Nat.is_le(J.utf8_length(text), U32.to_nat(Commit.frame_bytes(previous))), decision, previous)

def Laws.output_semantics(durable, decision, previous):
  rendered_semantics(J.render(Commit.render_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous)

def after_apply_semantics(+input: M.Input, +decision: M.Decision, +previous: M.World) ->
  {P.after_apply(input, decision, previous) == Commit.update(~Execution.scheduled, input, decision, previous) : M.Decision}:
  +durable = M.durable(input)
  +candidate = P.scheduled(Commit.schedules(input, decision), decision)
  first = Equal.trans(M.Decision, P.after_apply(input, decision, previous), Commit.deliver(durable, P.checked(candidate, previous), previous),
    Commit.update(~P.scheduled, input, decision, previous), Laws.output_semantics(durable, P.checked(candidate, previous), previous),
    Equal.cong(M.Decision, M.Decision, (value => Commit.deliver(durable, value, previous)),
      P.checked(candidate, previous), Commit.checked(candidate, previous), Laws.commit_semantics(candidate, previous)))
  Equal.trans(M.Decision, P.after_apply(input, decision, previous), Commit.update(~P.scheduled, input, decision, previous),
    Commit.update(~Execution.scheduled, input, decision, previous), first,
    Equal.cong(M.Decision, M.Decision, (value => Commit.finish(durable, value, previous)),
      candidate, Execution.scheduled(Commit.schedules(input, decision), decision), Laws.scheduling_semantics(Commit.schedules(input, decision), decision)))

def updated_command_semantics(+command: M.Command, +world: M.World) ->
  {P.update(M.UserCommand{command}, world) == Commit.update(~Execution.scheduled, M.UserCommand{command}, Commands.command(command, world), world) : M.Decision}:
  +input : M.Input = M.UserCommand{command}
  +meaning = Commands.command(command, world)
  Equal.trans(M.Decision, P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision, M.Decision, (decision => P.after_apply(input, decision, world)),
      P.apply_command(command, world), meaning, Laws.command_semantics(command, world)), after_apply_semantics(input, meaning, world))

def Laws.command_transition(command, world):
  match command:
    case M.Observe{query}: Laws.output_semantics(False{}, P.observe(query, world), world)
    case M.Create{profile, reasoning, message}: updated_command_semantics(M.Create{profile, reasoning, message}, world)
    case M.Send{id, message}: updated_command_semantics(M.Send{id, message}, world)
    case M.ChangeStatus{id, control}: updated_command_semantics(M.ChangeStatus{id, control}, world)
    case M.Fork{id, count, messages}: updated_command_semantics(M.Fork{id, count, messages}, world)
    case M.Compact{id, summary}: updated_command_semantics(M.Compact{id, summary}, world)

def updated_input_semantics(+input: M.Input, +world: M.World) ->
  {P.update(input, world) == Commit.update(~Execution.scheduled, input, Protocol.input(input, world), world) : M.Decision}:
  +meaning = Protocol.input(input, world)
  Equal.trans(M.Decision, P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision, M.Decision, (decision => P.after_apply(input, decision, world)),
      P.apply(input, world), meaning, Laws.input_semantics(input, world)), after_apply_semantics(input, meaning, world))

def Laws.interaction_transition(input, world):
  match input:
    case M.UserCommand{command}: Laws.command_transition(command, world)
    case M.ModelCompleted{id, ticket, outcome}: updated_input_semantics(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ToolCompleted{id, ticket, value, error}: updated_input_semantics(M.ToolCompleted{id, ticket, value, error}, world)
    case M.Configure{environment}: updated_input_semantics(M.Configure{environment}, world)
    case M.Recover{}: updated_input_semantics(M.Recover{}, world)
    case M.Continue{}: updated_input_semantics(M.Continue{}, world)

def Laws.scheduling_disabled(decision):
  {==}

def Laws.scheduling_enabled(decision):
  {==}

def Laws.scheduling_idle(fuel, decision):
  match fuel:
    case 0n: {==}
    case 1n+p: {==}

def Laws.scheduling_exhausted(task, world, reply, effects):
  {==}

def Laws.scheduling_progress(fuel, task, decision):
  {==}

def Laws.scheduling_combines_outputs(old, reply, effects, next, ignored, added):
  {==}

def Laws.model_work(task, world):
  {==}

def Laws.tool_work(task, world):
  {==}

def Laws.idle_work(task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def Laws.no_work(task, world):
  {==}

def Laws.model_dispatch(task, tasks, next_task, ticket, catalog, profiles, max_fork, max_descendants, project, limits):
  {==}

def Laws.tool_dispatch(tool, call, remaining, task, tasks, next_task, ticket, environment, limits):
  {==}

def Laws.small_context_dispatch(task, world):
  {==}

def Laws.large_context_dispatch(task, world):
  {==}

def Laws.accepted_model_settlement(outcome, allowed, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def Laws.accepted_tool_settlement(call, remaining, value, error, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def Laws.accepted_summary_settlement(outcome, resume, task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def Laws.context_recovery_work(task, world):
  {==}

def Laws.context_recovery_ready(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase}: {==}

def Laws.recover_resumable_summary(ticket):
  {==}

def Laws.checkpoint_consumes_compaction(history, summary):
  {==}

def Laws.checkpoint_is_not_recompacted(id, lineage, contract, status, history, summary, queued, phase, world):
  {==}

def Laws.context_limit_after_checkpoint_stops(allowed, id, lineage, contract, status, history, summary, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.summary_context_limit_stops(resume, id, lineage, contract, status, history, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.checkpoint_preserves_project_contract(task, summary):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase}: {==}

def Laws.read_file_recovery_safe(attempt):
  match attempt:
    case M.InitialAttempt{call}: {==}
    case M.RecoveryAttempt{call}: {==}

def Laws.write_file_recovery_blocked(call):
  {==}

def Laws.edit_file_recovery_blocked(call):
  {==}

def Laws.initial_world_valid():
  {==}

def admitted_certificate(+state_valid: Bool, +change_valid: Bool, +decision: M.Decision, +previous: M.World,
  state_checked: {P.valid_world(decision) == state_valid : Bool},
  change_checked: {I.decision(previous, decision) == change_valid : Bool}) ->
  Laws.Admitted(previous, P.admitted(state_valid, change_valid, decision, previous)):
  match state_valid change_valid:
    case True{} True{}: Done{(state_checked, change_checked)}
    case True{} False{}: Fail{({==}, {==})}
    case False{} _: Fail{({==}, {==})}

def live_certificate(+decision: M.Decision, +previous: M.World) ->
  Laws.Admitted(previous, P.check_live(decision, previous)):
  admitted_certificate(P.valid_world(decision), I.decision(previous, decision), decision, previous, {==}, {==})

def checked_certificate(decision: M.Decision, +previous: M.World) ->
  Laws.Admitted(previous, P.checked(decision, previous)):
  live_certificate(P.live_decision(decision), previous)

def output_certificate(fits: Bool, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.output_admitted(fits, decision, previous)):
  match fits:
    case True{}: certificate
    case False{}: Fail{({==}, {==})}

def admission_certificate(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.admission(rendered, decision, previous)):
  match rendered:
    case Fail{error}: Fail{({==}, {==})}
    case Done{text}:
      output_certificate(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, certificate)

def deliver_certificate(+durable: Bool, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.deliver(durable, decision, previous)):
  admission_certificate(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}),
    decision, previous, certificate)

def update_certificate(+input: M.Input, +world: M.World) -> Laws.Admitted(world, P.update(input, world)):
  +raw = P.apply(input, world)
  +candidate = P.scheduled(Commit.schedules(input, raw), raw)
  deliver_certificate(M.durable(input), P.checked(candidate, world), world, checked_certificate(candidate, world))

def observe_certificate(query: M.Query, +world: M.World) ->
  Laws.Admitted(world, P.deliver(False{}, P.observe(query, world), world)):
  deliver_certificate(False{}, P.observe(query, world), world, Fail{({==}, {==})})

def Laws.transition_admitted(world, input):
  match input:
    case M.UserCommand{M.Observe{query}}: observe_certificate(query, world)
    case M.UserCommand{M.Create{profile, reasoning, message}}:
      update_certificate(M.UserCommand{M.Create{profile, reasoning, message}}, world)
    case M.UserCommand{M.Send{id, message}}:
      update_certificate(M.UserCommand{M.Send{id, message}}, world)
    case M.UserCommand{M.ChangeStatus{id, control}}:
      update_certificate(M.UserCommand{M.ChangeStatus{id, control}}, world)
    case M.UserCommand{M.Fork{id, count, messages}}:
      update_certificate(M.UserCommand{M.Fork{id, count, messages}}, world)
    case M.UserCommand{M.Compact{id, summary}}:
      update_certificate(M.UserCommand{M.Compact{id, summary}}, world)
    case M.ModelCompleted{id, ticket, outcome}:
      update_certificate(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ToolCompleted{id, ticket, value, error}:
      update_certificate(M.ToolCompleted{id, ticket, value, error}, world)
    case M.Configure{settings}: update_certificate(M.Configure{settings}, world)
    case M.Recover{}: update_certificate(M.Recover{}, world)
    case M.Continue{}: update_certificate(M.Continue{}, world)

def certificate_world(+previous: M.World, +decision: M.Decision,
  evidence: {I.world(previous) == True{} : Bool}, certificate: Laws.Admitted(previous, decision)) ->
  {P.valid_world(decision) == True{} : Bool}:
  match certificate:
    case Fail{(unchanged, no_effects)}:
      Equal.trans(Bool, P.valid_world(decision), I.world(previous), True{},
        Equal.cong(M.World, Bool, I.world, P.decision_world(decision), previous, unchanged), evidence)
    case Done{(valid, retained)}: valid

def transition_preserves(+world: M.World, +input: M.Input,
  evidence: {I.world(world) == True{} : Bool}) -> {I.world(P.next(world, input)) == True{} : Bool}:
  certificate_world(world, P.transition(input, world), evidence, Laws.transition_admitted(world, input))

def Laws.transition_preserves_world(world, input, evidence):
  transition_preserves(world, input, evidence)

def Laws.replay_preserves_world(events, world, evidence):
  Theory.replay_invariant(~M.World, ~M.Input, ~P.next, ~I.world,
    ~Laws.transition_preserves_world, events, world, evidence)

def Laws.archived_terminal(request):
  match request:
    case M.Freeze{}: {==}
    case M.Unfreeze{}: {==}
    case M.Stop{}: {==}
    case M.Interrupt{}: {==}
    case M.Archive{}: {==}

def Laws.archived_input_unchanged(id, lineage, contract, history, queue, phase, text):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{Nil{}}: {==}
    case M.Ready{Con{call, rest}}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, resume}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.interrupt_preserves_contract(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_preserves_queue(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_settles_phase(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_idempotent(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case M.Task{id, lineage, contract, old, history, queued, phase}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, old}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case M.Task{id, lineage, contract, status, history, +queued, phase}:
      S.monoid_associative(+List<String>, Nil{}, S.append(String), Concepts.inbox(), queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{calls}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, True{}}: {==}
    case M.SummaryPending{ticket, False{}}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(call, remaining, value, error, task, world):
  {==}

def Laws.history_append_composition(first, second, history):
  S.action_composition(M.History, +List<M.Message>, Nil{}, S.append(M.Message), S.act(~M.History, ~M.Message, ~M.history_step),
    Concepts.history(), history, first, second)

def Laws.replay_composition(first, second, world):
  S.action_composition(M.World, +List<M.Input>, Nil{}, S.append(M.Input), S.act(~M.World, ~M.Input, ~P.next),
    Concepts.journal(), world, first, second)

def Laws.replay_empty(world):
  {==}

def output_admitted_world(fits: Bool, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.output_admitted(fits, decision, previous)) == previous : M.World}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_world(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.admission(rendered, decision, previous)) == previous : M.World}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_world(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def deliver_world(+durable: Bool, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.deliver(durable, decision, previous)) == previous : M.World}:
  admission_world(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, evidence)

def Laws.observation_preserves_world(query, world):
  deliver_world(False{}, P.observe(query, world), world, {==})

def output_admitted_no_effects(fits: Bool, +decision: M.Decision, previous: M.World,
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect>}) ->
  {P.decision_effects(P.output_admitted(fits, decision, previous)) == Nil{} : +List<M.Effect>}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_no_effects(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect>}) ->
  {P.decision_effects(P.admission(rendered, decision, previous)) == Nil{} : +List<M.Effect>}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_no_effects(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def Laws.observation_has_no_effects(query, world):
  admission_no_effects(J.render(P.rendering_budget(world), J.One{View.envelope(False{}, P.observe(query, world))}),
    P.observe(query, world), world, {==})

def Laws.observation_not_durable(query):
  {==}

def Laws.observation_replay(query, first, second, world):
  Theory.replay_insert_identity(~M.World, ~M.Input, ~P.next, first, second,
    M.UserCommand{M.Observe{query}}, world, Laws.observation_preserves_world(query, P.replay(first, world)))

def Laws.rejected_delivery_unchanged(decision, world):
  {==}

def Laws.rejected_delivery_no_effects(decision, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

def project_node_idempotent(+previous: M.History, +message: M.Message,
  evidence: {M.context_history(M.context_history(previous)) == M.context_history(previous) : M.History}) ->
  {M.context_history(M.context_node(M.context_history(previous), message)) == M.context_node(M.context_history(previous), message) : M.History}:
  match message:
    case M.ContextCheckpoint{summary}: {==}
    case M.UserMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.UserMessage{text}} == M.HistoryNode{_, M.UserMessage{text}} : M.History}
      {==}
    case M.AssistantMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.AssistantMessage{text}} == M.HistoryNode{_, M.AssistantMessage{text}} : M.History}
      {==}
    case M.FailureMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FailureMessage{text}} == M.HistoryNode{_, M.FailureMessage{text}} : M.History}
      {==}
    case M.FunctionCall{+call}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FunctionCall{call}} == M.HistoryNode{_, M.FunctionCall{call}} : M.History}
      {==}
    case M.FunctionOutput{+id, +value, +error}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FunctionOutput{id, value, error}} == M.HistoryNode{_, M.FunctionOutput{id, value, error}} : M.History}
      {==}
    case M.ModelContext{+value}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.ModelContext{value}} == M.HistoryNode{_, M.ModelContext{value}} : M.History}
      {==}

def Laws.context_projection_idempotent(history):
  match history:
    case M.EmptyHistory{}: {==}
    case M.HistoryNode{+previous, message}:
      project_node_idempotent(previous, message, Laws.context_projection_idempotent(previous))

def Laws.checkpoint_cuts_context(history, summary):
  {==}

def Laws.summary_rejects_invocations(call, rest, resume, task):
  {==}

def Laws.summary_failure_promotes_fifo(message, id, lineage, contract, history, first, rest, phase):
  {==}

def Laws.summary_failure_empty_stops(message, id, lineage, contract, status, history, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def decision_associativity(+first: M.Decision, +second: M.Decision, +third: M.Decision) ->
  {P.combine(P.combine(first, second), third) == P.combine(first, P.combine(second, third)) : M.Decision}:
  match first second third:
    case M.Decision{old, +reply, +a} M.Decision{middle, ignored, +b} M.Decision{+last, also_ignored, +c}:
      Equal.cong(+List<M.Effect>, M.Decision, (effects => M.Decision{last, reply, effects}),
        List.append(&2, M.Effect, List.append(&2, M.Effect, a, b), c),
        List.append(&2, M.Effect, a, List.append(&2, M.Effect, b, c)),
        S.monoid_associative(+List<M.Effect>, Nil{}, S.append(M.Effect), Concepts.effects(), a, b, c))

def Concepts.commands():
  S.Refinement{(command => world => Laws.command_transition(command, world))}

def Concepts.interactions():
  S.Refinement{(input => world => Laws.interaction_transition(input, world))}

def Concepts.task_machine():
  S.InvariantSystem{Laws.initial_world_valid(),
    (state => input => evidence => Laws.transition_preserves_world(state, input, evidence))}

def Concepts.journal_interpretation(world, inputs):
  {==}

def Concepts.history_interpretation(history, messages):
  {==}

def Concepts.decisions():
  S.Associative{(first => second => third => decision_associativity(first, second, third))}

def Concepts.context():
  S.Projection{(history => Laws.context_projection_idempotent(history))}

def Concepts.recovery():
  S.Projection{(phase => Laws.recover_phase_idempotent(phase))}

def Concepts.interruption():
  S.Projection{(task => Laws.interrupt_idempotent(task))}

def Concepts.observations():
  S.ReadOnly{(query => world => Laws.observation_preserves_world(query, world)),
    (query => world => Laws.observation_has_no_effects(query, world))}

def Concepts.harness():
  Concepts.Harness{Concepts.commands(), Concepts.interactions(), Concepts.task_machine(),
    Concepts.journal(), Concepts.observations(), Concepts.recovery_batches(),
    Concepts.decisions(), Concepts.context(), Concepts.interruption()}
