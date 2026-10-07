import Base
import ../features/MODEL.bend as F
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../approval/HOOKS.bend as Hooks
import ../INVARIANTS.bend as I
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ./OPERATIONS.bend as Ops
import ../../bendlib/equality.bend as Same
import ../transport/presentation.bend as View
import ../protocol/PROGRAM.bend as Protocol

# Commit-scoped observation, never task authority. The native model identifies
# occurrences and recipients; the host adds the committed sequence and attempts
# bounded delivery. A projection cannot turn inherited history into new events.
def subscribed(kinds: +List<D.EventKind>, +kind: D.EventKind) -> Bool:
  match kinds:
    case Nil{}: False{}
    case Con{candidate, rest}: String.eq(D.event_name(candidate), D.event_name(kind)) || subscribed(rest, kind)

def recipient(include: Bool, reference: D.PluginRef, rest: +List<D.PluginRef>) -> +List<D.PluginRef>:
  match include:
    case True{}: reference <> rest
    case False{}: rest

def recipients(plugins: +List<D.Plugin>, +kind: D.EventKind) -> +List<D.PluginRef>:
  match plugins:
    case Nil{}: Nil{}
    case Con{D.Plugin{reference, before, after, events}, rest}:
      recipient(subscribed(events, kind), reference, recipients(rest, kind))

def listeners(plugins: +List<D.Plugin>) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{D.Plugin{reference, before, after, Nil{}}, rest}: listeners(rest)
    case Con{D.Plugin{reference, before, after, Con{kind, more}}, rest}: True{}

def bounded(fits: Bool, value: J.Json) -> Maybe<&2, J.Json>:
  match fits:
    case True{}: Some{value}
    case False{}: None{}

def rendered(rendered: Result<&2, &2, String, String>, value: J.Json) -> Maybe<&2, J.Json>:
  match rendered:
    case Fail{reason}: None{}
    case Done{text}: bounded(Nat.is_le(J.utf8_length(text), U32.to_nat(16384)), value)

def make(routes: +List<D.PluginRef>, kind: D.EventKind, owner: Maybe<&2, Nat>, cursor: Maybe<&2, Nat>, +value: J.Json) -> +List<D.Notice>:
  match routes:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [D.Notice{kind, owner, cursor, rendered(J.render(U32.to_nat(16384), J.One{value}), value), first <> rest}]

def event(+kind: D.EventKind, owner: Maybe<&2, Nat>, cursor: Maybe<&2, Nat>, value: J.Json, plugins: +List<D.Plugin>) -> +List<D.Notice>:
  make(recipients(plugins, kind), kind, owner, cursor, value)

def task_event(kind: D.EventKind, cursor: Maybe<&2, Nat>, value: J.Json, +task: D.Task) -> +List<D.Notice>:
  event(kind, Some{D.task_id(task)}, cursor, value, Hooks.plugins(D.task_contract(task)))

def effective(progress: Hooks.Progress) -> J.Json:
  match progress:
    case Hooks.Awaiting{call, pending}: T.call_json(call)
    case _: J.Null{}

def chosen(same: Bool, call: D.Call, rest: J.Json) -> J.Json:
  match same:
    case True{}: T.call_json(call)
    case False{}: rest

def requested(history: D.History, +id: String) -> J.Json:
  match history:
    case D.EmptyHistory{}: J.Null{}
    case D.HistoryNode{previous, D.FunctionCall{+call}}: chosen(String.eq(D.call_id(call), id), call, requested(previous, id))
    case D.HistoryNode{previous, other}: requested(previous, id)

def result(+id: String, value: J.Json, error: Bool, +task: D.Task) -> J.Json:
  J.Object{[J.Field{"call_id", J.Text{id}}, J.Field{"requested", requested(D.task_history(task), id)},
    J.Field{"authorized", effective(Hooks.progress(D.task_history(task), D.task_id(task), id, Hooks.before(Hooks.plugins(D.task_contract(task)))))},
    J.Field{"value", value}, J.Field{"error", J.Boolean{error}}]}

type Scan is Data:
  Scan{settled: +List<String>, notices: +List<D.Notice>}

def add(added: +List<D.Notice>, scan: Scan) -> Scan:
  Scan{settled, notices} = scan
  Scan{settled, List.append(&2, D.Notice, added, notices)}

def completion(suppressed: Bool, id: String, cursor: Nat, value: J.Json, task: D.Task, scan: Scan) -> Scan:
  match suppressed scan:
    case True{} Scan{settled, notices}: Scan{id <> settled, notices}
    case False{} Scan{settled, notices}:
      Scan{id <> settled, List.append(&2, D.Notice, task_event(D.ToolSettled{}, Some{cursor}, value, task), notices)}

def complete(+id: String, cursor: Nat, value: J.Json, error: Bool, +task: D.Task, scan: Scan) -> Scan:
  Scan{+settled, notices} = scan
  completion(Hooks.member(settled, id) || I.operation_call(D.task_operations(task), id), id, cursor,
    result(id, value, error, task), task, Scan{settled, notices})

def owned(same: Bool, added: +List<D.Notice>, scan: Scan) -> Scan:
  match same:
    case True{}: add(added, scan)
    case False{}: scan

def consume(message: D.Message, cursor: Nat, +task: D.Task, scan: Scan) -> Scan:
  match message:
    case D.FunctionCall{call}:
      add(task_event(D.ToolRequested{}, Some{cursor}, T.call_json(call), task), scan)
    case D.HookRecord{+owner, call_id, reference, outcome}:
      owned(Nat.is_eq(owner, D.task_id(task)), task_event(D.HookSettled{}, Some{cursor},
        T.message_json(D.HookRecord{owner, call_id, reference, outcome}), task), scan)
    case D.AfterRecord{+owner, operation, reference, outcome}:
      owned(Nat.is_eq(owner, D.task_id(task)), task_event(D.HookSettled{}, Some{cursor},
        T.message_json(D.AfterRecord{owner, operation, reference, outcome}), task), scan)
    case D.FunctionOutput{id, value, error}: complete(id, cursor, value, error, task, scan)
    case D.OperationResult{ticket, id, tool, value, error}: complete(id, cursor, value, error, task, scan)
    case D.ForkResult{+owner, +call_id, branch}:
      owned(Nat.is_eq(owner, D.task_id(task)), task_event(D.ToolSettled{}, Some{cursor},
        J.Object{[J.Field{"call_id", J.Text{call_id}}, J.Field{"value", J.nat(branch)}, J.Field{"error", J.Boolean{False{}}},
          J.Field{"origin", J.Text{"fork_return"}}]}, task), scan)
    case _: scan

def suffix(count: Nat, history: D.History, +cursor: Nat, +task: D.Task, scan: Scan) -> Scan:
  match count history:
    case 0n _: scan
    case 1n+p D.EmptyHistory{}: scan
    case 1n+p D.HistoryNode{previous, message}:
      suffix(p, previous, Nat.sub(cursor, 1n), task, consume(message, cursor, task, scan))

def scanned(scan: Scan) -> +List<D.Notice>:
  Scan{settled, notices} = scan
  notices

def birth_match(same: Bool, cursor: Nat, rest: Nat) -> Nat:
  match same:
    case True{}: cursor
    case False{}: rest

def birth(history: D.History, +id: Nat) -> Nat:
  match history:
    case D.EmptyHistory{}: 0n
    case D.HistoryNode{+previous, D.ForkResult{owner, call_id, branch}}:
      birth_match(Nat.is_eq(id, owner), D.history_length(previous), birth(previous, id))
    case D.HistoryNode{previous, other}: birth(previous, id)

def start(previous: Maybe<&2, D.Task>, +task: D.Task) -> Nat:
  match previous:
    case Some{prior}: D.history_length(D.task_history(prior))
    case None{}: birth(D.task_history(task), D.task_id(task))

def changed(same: Bool, +task: D.Task) -> +List<D.Notice>:
  match same:
    case True{}: Nil{}
    case False{}: task_event(D.TaskChanged{}, None{}, T.summary(task), task)

def lifecycle(previous: Maybe<&2, D.Task>, +task: D.Task) -> +List<D.Notice>:
  match previous:
    case None{}: task_event(D.TaskCreated{}, None{}, T.summary(task), task)
    case Some{prior}: changed(Same.json(U32.to_nat(65536), T.summary(prior), T.summary(task)), task)

def observed(interested: Bool, +previous: Maybe<&2, D.Task>, +task: D.Task) -> +List<D.Notice>:
  match interested:
    case False{}: Nil{}
    case True{}: List.append(&2, D.Notice, lifecycle(previous, task),
      scanned(suffix(Nat.sub(D.history_length(D.task_history(task)), start(previous, task)), D.task_history(task),
        D.history_length(D.task_history(task)), task, Scan{Nil{}, Nil{}})))

def tasks(after: +List<D.Task>, +before: +List<D.Task>) -> +List<D.Notice>:
  match after:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      List.append(&2, D.Notice, observed(listeners(Hooks.plugins(D.task_contract(task))), T.find(before, D.task_id(task)), task), tasks(rest, before))

def model_outcome(outcome: D.Outcome) -> J.Json:
  match outcome:
    case D.ModelReply{items}: J.Object{[J.Field{"ok", J.Boolean{True{}}}, J.Field{"items", J.nat(List.length(&2, D.ModelItem, items))}]}
    case D.ModelFailure{message}: J.Object{[J.Field{"ok", J.Boolean{False{}}}, J.Field{"error", J.Text{message}}]}
    case D.ContextLimit{}: J.Object{[J.Field{"ok", J.Boolean{False{}}}, J.Field{"error", J.Text{"context_limit"}}]}

def model_settled(event: Protocol.ResolvedEvent, ticket: Nat) -> +List<D.Notice>:
  match event:
    case Protocol.ModelResult{task, outcome, allowed}:
      task_event(D.ModelSettled{}, None{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{"model"}}, J.Field{"outcome", model_outcome(outcome)}]}, task)
    case Protocol.SummaryResult{task, outcome, resume}:
      task_event(D.ModelSettled{}, None{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{"summary"}}, J.Field{"outcome", model_outcome(outcome)}]}, task)
    case _: Nil{}

def input(source: M.Input, +before: M.World(), +after: M.World()) -> +List<D.Notice>:
  match source:
    case M.ModelCompleted{+id, +ticket, +outcome}: model_settled(Protocol.resolve(M.ModelCompleted{id, ticket, outcome}, before), ticket)
    case M.Recover{}: event(D.Recovered{}, None{}, None{}, J.Null{}, Hooks.live(F.State(), after))
    case M.Configure{environment}: event(D.Configured{}, None{}, None{}, D.plugins_json(Hooks.live(F.State(), after)), Hooks.live(F.State(), after))
    case _: Nil{}

def found_event(found: Maybe<&2, D.Task>, kind: D.EventKind, value: J.Json) -> +List<D.Notice>:
  match found:
    case None{}: Nil{}
    case Some{task}: task_event(kind, None{}, value, task)

def model_started(id: Nat, ticket: Nat, model: D.Model, kind: String, tasks: +List<D.Task>) -> +List<D.Notice>:
  D.Model{profile, reasoning, project} = model
  found_event(T.find(tasks, id), D.ModelStarted{}, J.Object{[J.Field{"ticket", J.nat(ticket)}, J.Field{"kind", J.Text{kind}},
    J.Field{"model", View.model_json(D.Model{profile, reasoning, D.NoProject{}})}]})

def dispatched(effects: +List<M.Effect()>, +tasks: +List<D.Task>) -> +List<D.Notice>:
  match effects:
    case Nil{}: Nil{}
    case Con{Effects.RequestModel{id, ticket, model, history, tools, callable, context}, rest}:
      List.append(&2, D.Notice, model_started(id, ticket, model, "model", tasks), dispatched(rest, tasks))
    case Con{Effects.RequestSummary{id, ticket, model, history, context}, rest}:
      List.append(&2, D.Notice, model_started(id, ticket, model, "summary", tasks), dispatched(rest, tasks))
    case Con{Effects.ExecuteTool{id, ticket, tool, call, context, access}, rest}:
      List.append(&2, D.Notice, found_event(T.find(tasks, id), D.ToolDispatched{}, J.Object{[J.Field{"ticket", J.nat(ticket)},
        J.Field{"tool", D.tool_json(tool)}, J.Field{"call", T.call_json(call)}]}), dispatched(rest, tasks))
    case Con{other, rest}: dispatched(rest, tasks)

def append(notices: +List<D.Notice>, decision: M.Decision()) -> M.Decision():
  match notices decision:
    case Nil{} _: decision
    case Con{first, rest} C.Decision{world, reply, effects}:
      C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.NotifyPlugins{first <> rest}])}

def choose(fits: Bool, enriched: M.Decision(), plain: M.Decision()) -> M.Decision():
  match fits:
    case True{}: enriched
    case False{}: plain

def fit(rendered: Result<&2, &2, String, String>, bytes: U32, enriched: M.Decision(), plain: M.Decision()) -> M.Decision():
  match rendered:
    case Fail{reason}: plain
    case Done{text}: choose(Nat.is_le(J.utf8_length(text), U32.to_nat(bytes)), enriched, plain)

# Notification payloads and queueing are optional observations. Full-envelope
# pressure can omit the entire optional batch, never reject the underlying work.
def admit_limits(+durable: Bool, previous: M.World(), +enriched: M.Decision(), plain: M.Decision(), limits_value: D.ExecutionLimits) -> M.Decision():
  match previous limits_value:
    case C.Frame{+task_state, +board} D.ExecutionLimits{steps, render, +bytes}:
      fit(J.render(render, J.One{View.envelope(durable, enriched)}), bytes, enriched, plain)

def admit(+durable: Bool, +previous: M.World(), +enriched: M.Decision(), plain: M.Decision()) -> M.Decision():
  admit_limits(durable, previous, enriched, plain, D.state_limits(C.local(D.State, F.State(), previous)))

def enrich(+source: M.Input, +before: M.World(), +decision: M.Decision()) -> M.Decision():
  C.Decision{+after, reply, +effects} = decision
  admit(M.durable(source), before,
    append(List.append(&2, D.Notice, input(source, before, after), List.append(&2, D.Notice,
      tasks(D.state_tasks(C.local(D.State, F.State(), after)), D.state_tasks(C.local(D.State, F.State(), before))), dispatched(I.live_effects(effects, D.state_tasks(C.local(D.State, F.State(), after))), D.state_tasks(C.local(D.State, F.State(), after))))), decision), decision)

def enabled(enabled: Bool, source: M.Input, before: M.World(), decision: M.Decision()) -> M.Decision():
  match enabled:
    case False{}: decision
    case True{}: enrich(source, before, decision)

def decorate(+source: M.Input, before: M.World(), decision: M.Decision()) -> M.Decision():
  enabled(M.durable(source), source, before, decision)

def keep_core(effect: M.Effect(), rest: +List<M.Effect()>) -> +List<M.Effect()>:
  match effect:
    case Effects.NotifyPlugins{events}: rest
    case other: other <> rest

def core(effects: +List<M.Effect()>) -> +List<M.Effect()>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: keep_core(effect, core(rest))
