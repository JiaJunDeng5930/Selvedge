import Base
import ../MODEL.bend as M
import ../HOOKS.bend as Hooks
import ../INVARIANTS.bend as I
import ./json.bend as J
import ./tasks.bend as T
import ./operations.bend as Ops
import ./equality.bend as Same
import ./presentation.bend as View
import ./protocol.bend as Protocol

# Commit-scoped observation, never task authority. The native model identifies
# occurrences and recipients; the host adds the committed sequence and attempts
# bounded delivery. A projection cannot turn inherited history into new events.
def entries(world: M.World) -> +List<M.Task>:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  tasks

def subscribed(kinds: +List<M.EventKind>, +kind: M.EventKind) -> Bool:
  match kinds:
    case Nil{}: False{}
    case Con{candidate, rest}: String.eq(M.event_name(candidate), M.event_name(kind)) || subscribed(rest, kind)

def recipient(include: Bool, reference: M.PluginRef, rest: +List<M.PluginRef>) -> +List<M.PluginRef>:
  match include:
    case True{}: reference <> rest
    case False{}: rest

def recipients(plugins: +List<M.Plugin>, +kind: M.EventKind) -> +List<M.PluginRef>:
  match plugins:
    case Nil{}: Nil{}
    case Con{M.Plugin{reference, before, after, events}, rest}:
      recipient(subscribed(events, kind), reference, recipients(rest, kind))

def listeners(plugins: +List<M.Plugin>) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{M.Plugin{reference, before, after, Nil{}}, rest}: listeners(rest)
    case Con{M.Plugin{reference, before, after, Con{kind, more}}, rest}: True{}

def bounded(fits: Bool, value: J.Json) -> Maybe<&2, J.Json>:
  match fits:
    case True{}: Some{value}
    case False{}: None{}

def rendered(rendered: Result<&2, &2, String, String>, value: J.Json) -> Maybe<&2, J.Json>:
  match rendered:
    case Fail{reason}: None{}
    case Done{text}: bounded(Nat.is_le(J.utf8_length(text), U32.to_nat(16384)), value)

def make(routes: +List<M.PluginRef>, kind: M.EventKind, owner: Maybe<&2, Nat>, cursor: Maybe<&2, Nat>, +value: J.Json) -> +List<M.Notice>:
  match routes:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [M.Notice{kind, owner, cursor, rendered(J.render(U32.to_nat(16384), J.One{value}), value), first <> rest}]

def event(+kind: M.EventKind, owner: Maybe<&2, Nat>, cursor: Maybe<&2, Nat>, value: J.Json, plugins: +List<M.Plugin>) -> +List<M.Notice>:
  make(recipients(plugins, kind), kind, owner, cursor, value)

def task_event(kind: M.EventKind, cursor: Maybe<&2, Nat>, value: J.Json, +task: M.Task) -> +List<M.Notice>:
  event(kind, Some{M.task_id(task)}, cursor, value, Hooks.plugins(M.task_contract(task)))

def effective(progress: Hooks.Progress) -> J.Json:
  match progress:
    case Hooks.Awaiting{call, pending}: T.call_json(call)
    case _: J.Null{}

def chosen(same: Bool, call: M.Call, rest: J.Json) -> J.Json:
  match same:
    case True{}: T.call_json(call)
    case False{}: rest

def requested(history: M.History, +id: String) -> J.Json:
  match history:
    case M.EmptyHistory{}: J.Null{}
    case M.HistoryNode{previous, M.FunctionCall{+call}}: chosen(String.eq(M.call_id(call), id), call, requested(previous, id))
    case M.HistoryNode{previous, other}: requested(previous, id)

def result(+id: String, value: J.Json, error: Bool, +task: M.Task) -> J.Json:
  J.Object{[J.Field{"call_id", J.Text{id}}, J.Field{"requested", requested(M.task_history(task), id)},
    J.Field{"authorized", effective(Hooks.progress(M.task_history(task), M.task_id(task), id, Hooks.before(Hooks.plugins(M.task_contract(task)))))},
    J.Field{"value", value}, J.Field{"error", J.Boolean{error}}]}

type Scan is Data:
  Scan{settled: +List<String>, notices: +List<M.Notice>}

def add(added: +List<M.Notice>, scan: Scan) -> Scan:
  Scan{settled, notices} = scan
  Scan{settled, List.append(&2, M.Notice, added, notices)}

def completion(suppressed: Bool, id: String, cursor: Nat, value: J.Json, task: M.Task, scan: Scan) -> Scan:
  match suppressed scan:
    case True{} Scan{settled, notices}: Scan{id <> settled, notices}
    case False{} Scan{settled, notices}:
      Scan{id <> settled, List.append(&2, M.Notice, task_event(M.ToolSettled{}, Some{cursor}, value, task), notices)}

def complete(+id: String, cursor: Nat, value: J.Json, error: Bool, +task: M.Task, scan: Scan) -> Scan:
  Scan{+settled, notices} = scan
  completion(Hooks.member(settled, id) || I.operation_call(M.task_operations(task), id), id, cursor,
    result(id, value, error, task), task, Scan{settled, notices})

def owned(same: Bool, added: +List<M.Notice>, scan: Scan) -> Scan:
  match same:
    case True{}: add(added, scan)
    case False{}: scan

def consume(message: M.Message, cursor: Nat, +task: M.Task, scan: Scan) -> Scan:
  match message:
    case M.FunctionCall{call}:
      add(task_event(M.ToolRequested{}, Some{cursor}, T.call_json(call), task), scan)
    case M.HookRecord{+owner, call_id, reference, outcome}:
      owned(Nat.is_eq(owner, M.task_id(task)), task_event(M.HookSettled{}, Some{cursor},
        T.message_json(M.HookRecord{owner, call_id, reference, outcome}), task), scan)
    case M.AfterRecord{+owner, operation, reference, outcome}:
      owned(Nat.is_eq(owner, M.task_id(task)), task_event(M.HookSettled{}, Some{cursor},
        T.message_json(M.AfterRecord{owner, operation, reference, outcome}), task), scan)
    case M.FunctionOutput{id, value, error}: complete(id, cursor, value, error, task, scan)
    case M.OperationResult{ticket, id, tool, value, error}: complete(id, cursor, value, error, task, scan)
    case M.ForkResult{+owner, +call_id, branch}:
      owned(Nat.is_eq(owner, M.task_id(task)), task_event(M.ToolSettled{}, Some{cursor},
        J.Object{[J.Field{"call_id", J.Text{call_id}}, J.Field{"value", J.nat(branch)}, J.Field{"error", J.Boolean{False{}}},
          J.Field{"origin", J.Text{"fork_return"}}]}, task), scan)
    case _: scan

def suffix(count: Nat, history: M.History, +cursor: Nat, +task: M.Task, scan: Scan) -> Scan:
  match count history:
    case 0n _: scan
    case 1n+p M.EmptyHistory{}: scan
    case 1n+p M.HistoryNode{previous, message}:
      suffix(p, previous, Nat.sub(cursor, 1n), task, consume(message, cursor, task, scan))

def scanned(scan: Scan) -> +List<M.Notice>:
  Scan{settled, notices} = scan
  notices

def birth_match(same: Bool, cursor: Nat, rest: Nat) -> Nat:
  match same:
    case True{}: cursor
    case False{}: rest

def birth(history: M.History, +id: Nat) -> Nat:
  match history:
    case M.EmptyHistory{}: 0n
    case M.HistoryNode{+previous, M.ForkResult{owner, call_id, branch}}:
      birth_match(Nat.is_eq(id, owner), M.history_length(previous), birth(previous, id))
    case M.HistoryNode{previous, other}: birth(previous, id)

def start(previous: Maybe<&2, M.Task>, +task: M.Task) -> Nat:
  match previous:
    case Some{prior}: M.history_length(M.task_history(prior))
    case None{}: birth(M.task_history(task), M.task_id(task))

def changed(same: Bool, +task: M.Task) -> +List<M.Notice>:
  match same:
    case True{}: Nil{}
    case False{}: task_event(M.TaskChanged{}, None{}, T.summary(task), task)

def lifecycle(previous: Maybe<&2, M.Task>, +task: M.Task) -> +List<M.Notice>:
  match previous:
    case None{}: task_event(M.TaskCreated{}, None{}, T.summary(task), task)
    case Some{prior}: changed(Same.json(U32.to_nat(65536), T.summary(prior), T.summary(task)), task)

def observed(interested: Bool, +previous: Maybe<&2, M.Task>, +task: M.Task) -> +List<M.Notice>:
  match interested:
    case False{}: Nil{}
    case True{}: List.append(&2, M.Notice, lifecycle(previous, task),
      scanned(suffix(Nat.sub(M.history_length(M.task_history(task)), start(previous, task)), M.task_history(task),
        M.history_length(M.task_history(task)), task, Scan{Nil{}, Nil{}})))

def tasks(after: +List<M.Task>, +before: +List<M.Task>) -> +List<M.Notice>:
  match after:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      List.append(&2, M.Notice, observed(listeners(Hooks.plugins(M.task_contract(task))), T.find(before, M.task_id(task)), task), tasks(rest, before))

def model_outcome(outcome: M.Outcome) -> J.Json:
  match outcome:
    case M.ModelReply{items}: J.Object{[J.Field{"ok", J.Boolean{True{}}}, J.Field{"items", J.nat(List.length(&2, M.ModelItem, items))}]}
    case M.ModelFailure{message}: J.Object{[J.Field{"ok", J.Boolean{False{}}}, J.Field{"error", J.Text{message}}]}
    case M.ContextLimit{}: J.Object{[J.Field{"ok", J.Boolean{False{}}}, J.Field{"error", J.Text{"context_limit"}}]}

def model_settled(event: Protocol.Event, ticket: Nat) -> +List<M.Notice>:
  match event:
    case Protocol.ModelResult{task, outcome, allowed}:
      task_event(M.ModelSettled{}, None{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{"model"}}, J.Field{"outcome", model_outcome(outcome)}]}, task)
    case Protocol.SummaryResult{task, outcome, resume}:
      task_event(M.ModelSettled{}, None{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{"summary"}}, J.Field{"outcome", model_outcome(outcome)}]}, task)
    case _: Nil{}

def input(source: M.Input, +before: M.World, +after: M.World) -> +List<M.Notice>:
  match source:
    case M.ModelCompleted{+id, +ticket, +outcome}: model_settled(Protocol.resolve(M.ModelCompleted{id, ticket, outcome}, before), ticket)
    case M.Recover{}: event(M.Recovered{}, None{}, None{}, J.Null{}, Hooks.live(after))
    case M.Configure{environment}: event(M.Configured{}, None{}, None{}, M.plugins_json(Hooks.live(after)), Hooks.live(after))
    case _: Nil{}

def found_event(found: Maybe<&2, M.Task>, kind: M.EventKind, value: J.Json) -> +List<M.Notice>:
  match found:
    case None{}: Nil{}
    case Some{task}: task_event(kind, None{}, value, task)

def model_started(id: Nat, ticket: Nat, model: M.Model, kind: String, tasks: +List<M.Task>) -> +List<M.Notice>:
  M.Model{profile, reasoning, project} = model
  found_event(T.find(tasks, id), M.ModelStarted{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{kind}},
    J.Field{"model", View.model_json(M.Model{profile, reasoning, M.NoProject{}})}]})

def dispatched(effects: +List<M.Effect>, +tasks: +List<M.Task>) -> +List<M.Notice>:
  match effects:
    case Nil{}: Nil{}
    case Con{M.RequestModel{id, ticket, model, history, tools, callable, context}, rest}:
      List.append(&2, M.Notice, model_started(id, ticket, model, "model", tasks), dispatched(rest, tasks))
    case Con{M.RequestSummary{id, ticket, model, history, context}, rest}:
      List.append(&2, M.Notice, model_started(id, ticket, model, "summary", tasks), dispatched(rest, tasks))
    case Con{M.ExecuteTool{id, ticket, tool, call, context, access}, rest}:
      List.append(&2, M.Notice, found_event(T.find(tasks, id), M.ToolDispatched{}, J.Object{[J.Field{"ticket", J.nat(ticket)},
        J.Field{"tool", M.tool_json(tool)}, J.Field{"call", T.call_json(call)}]}), dispatched(rest, tasks))
    case Con{other, rest}: dispatched(rest, tasks)

def append(notices: +List<M.Notice>, decision: M.Decision) -> M.Decision:
  match notices decision:
    case Nil{} _: decision
    case Con{first, rest} M.Decision{world, reply, effects}:
      M.Decision{world, reply, List.append(&2, M.Effect, effects, [M.NotifyPlugins{first <> rest}])}

def choose(fits: Bool, enriched: M.Decision, plain: M.Decision) -> M.Decision:
  match fits:
    case True{}: enriched
    case False{}: plain

def fit(rendered: Result<&2, &2, String, String>, bytes: U32, enriched: M.Decision, plain: M.Decision) -> M.Decision:
  match rendered:
    case Fail{reason}: plain
    case Done{text}: choose(Nat.is_le(J.utf8_length(text), U32.to_nat(bytes)), enriched, plain)

# Notification payloads and queueing are optional observations. Full-envelope
# pressure can omit the entire optional batch, never reject the underlying work.
def admit(+durable: Bool, previous: M.World, +enriched: M.Decision, plain: M.Decision) -> M.Decision:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, +bytes}, projects, board} = previous
  fit(J.render(render, J.One{View.envelope(durable, enriched)}), bytes, enriched, plain)

def enrich(+source: M.Input, +before: M.World, +decision: M.Decision) -> M.Decision:
  M.Decision{+after, reply, +effects} = decision
  admit(M.durable(source), before,
    append(List.append(&2, M.Notice, input(source, before, after), List.append(&2, M.Notice,
      tasks(entries(after), entries(before)), dispatched(I.live_effects(effects, entries(after)), entries(after)))), decision), decision)

def enabled(enabled: Bool, source: M.Input, before: M.World, decision: M.Decision) -> M.Decision:
  match enabled:
    case False{}: decision
    case True{}: enrich(source, before, decision)

def decorate(+source: M.Input, before: M.World, decision: M.Decision) -> M.Decision:
  enabled(M.durable(source), source, before, decision)

def keep_core(effect: M.Effect, rest: +List<M.Effect>) -> +List<M.Effect>:
  match effect:
    case M.NotifyPlugins{events}: rest
    case other: other <> rest

def core(effects: +List<M.Effect>) -> +List<M.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: keep_core(effect, core(rest))
