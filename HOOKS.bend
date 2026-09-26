import Base
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/equality.bend as Same
import ./bendlib/schema.bend as Schema

# The extension boundary is a sequential authorization protocol, not a callback
# inside Bash. A task freezes its chain; the host only answers committed tickets.
# The original FunctionCall is immutable. Checked attempts and operation rights
# must correspond to replaying the exact, append-only HookRecord certificates.
type Progress is Data:
  Absent{}
  Awaiting{call: M.Call, pending: +List<M.PluginRef>}
  Refused{}

def plugins(contract: M.Contract) -> +List<M.Plugin>:
  M.Contract{model, tools, max_fork, max_descendants, plugins} = contract
  plugins

def live(world: M.World) -> +List<M.Plugin>:
  M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits} = world
  plugins

def before(plugins: +List<M.Plugin>) -> +List<M.PluginRef>:
  match plugins:
    case Nil{}: Nil{}
    case Con{M.Plugin{reference, True{}, events}, rest}: reference <> before(rest)
    case Con{M.Plugin{reference, False{}, events}, rest}: before(rest)

def references(left: +List<M.PluginRef>, right: +List<M.PluginRef>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}: M.plugin_same(a, b) && references(rest_a, rest_b)
    case _ _: False{}

def present(plugins: +List<M.Plugin>, +reference: M.PluginRef) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{M.Plugin{candidate, before, events}, rest}:
      M.plugin_same(candidate, reference) || present(rest, reference)

def available(plugins: +List<M.Plugin>, +reference: M.PluginRef) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{M.Plugin{candidate, before, events}, rest}:
      (before && M.plugin_same(candidate, reference)) || available(rest, reference)

def member(strings: +List<String>, +value: String) -> Bool:
  match strings:
    case Nil{}: False{}
    case Con{item, rest}: String.eq(item, value) || member(rest, value)

def event_names() -> +List<String>:
  M.plugin_events()

def subscriptions(events: +List<M.EventKind>, +seen: +List<String>) -> Bool:
  match events:
    case Nil{}: True{}
    case Con{+event, rest}: Bool.not(member(seen, M.event_name(event))) && subscriptions(rest, M.event_name(event) <> seen)

def plugin_name(reference: M.PluginRef) -> String:
  M.PluginRef{name, revision} = reference
  name

def reference_valid(reference: M.PluginRef) -> Bool:
  M.PluginRef{+name, +revision} = reference
  M.nonempty(name) && M.nonempty(revision) && Nat.is_le(J.utf8_length(name), 128n) && Nat.is_le(J.utf8_length(revision), 128n)

def unique(plugins: +List<M.Plugin>, +seen: +List<String>) -> Bool:
  match plugins:
    case Nil{}: True{}
    case Con{M.Plugin{+reference, before, events}, rest}:
      reference_valid(reference) && Bool.not(member(seen, plugin_name(reference))) && subscriptions(events, Nil{}) &&
        unique(rest, plugin_name(reference) <> seen)

def valid(+plugins: +List<M.Plugin>) -> Bool:
  Nat.is_le(List.length(&2, M.Plugin, plugins), M.plugin_limit()) && unique(plugins, Nil{})

def routes(tools: +List<M.Tool>, +plugins: +List<M.Plugin>) -> Bool:
  match tools:
    case Nil{}: True{}
    case Con{M.Tool{name, description, schema, M.Extension{owner, remote}}, rest}:
      present(plugins, owner) && M.nonempty(remote) && Schema.supported(schema) && routes(rest, plugins)
    case Con{other, rest}: routes(rest, plugins)

# This fold interprets observed certificates only. No source-name label can
# replace a missing record, reorder the chain, change a call's identity, or turn
# a rejection into permission. Its result is checked again at effect admission.
def begin(state: Progress, call: M.Call, chain: +List<M.PluginRef>) -> Progress:
  match state:
    case Absent{}: Awaiting{call, chain}
    case _: Refused{}

def advance(outcome: M.HookOutcome, call: M.Call, pending: +List<M.PluginRef>) -> Progress:
  match outcome:
    case M.AllowTool{}: Awaiting{call, pending}
    case M.RewriteTool{arguments}: Awaiting{M.rewritten(call, arguments), pending}
    case M.DenyTool{reason}: Refused{}
    case M.HookFailure{reason}: Refused{}

def checked(same: Bool, outcome: M.HookOutcome, call: M.Call, pending: +List<M.PluginRef>) -> Progress:
  match same:
    case True{}: advance(outcome, call, pending)
    case False{}: Refused{}

def record(state: Progress, reference: M.PluginRef, outcome: M.HookOutcome) -> Progress:
  match state:
    case Awaiting{call, Con{expected, pending}}: checked(M.plugin_same(reference, expected), outcome, call, pending)
    case _: Refused{}

def start_matching(same: Bool, state: Progress, call: M.Call, chain: +List<M.PluginRef>) -> Progress:
  match same:
    case True{}: begin(state, call, chain)
    case False{}: state

def record_matching(same: Bool, state: Progress, reference: M.PluginRef, outcome: M.HookOutcome) -> Progress:
  match same:
    case True{}: record(state, reference, outcome)
    case False{}: state

def history_step(message: M.Message, owner: Nat, id: String, chain: +List<M.PluginRef>, state: Progress) -> Progress:
  match message:
    case M.FunctionCall{+call}: start_matching(String.eq(M.call_id(call), id), state, call, chain)
    case M.HookRecord{task_id, call_id, reference, outcome}: record_matching(Nat.is_eq(task_id, owner) && String.eq(call_id, id), state, reference, outcome)
    case _: state

def progress(history: M.History, +owner: Nat, +id: String, +chain: +List<M.PluginRef>) -> Progress:
  match history:
    case M.EmptyHistory{}: Absent{}
    case M.HistoryNode{previous, message}: history_step(message, owner, id, chain, progress(previous, owner, id, chain))

def matches(state: Progress, call: M.Call, pending: +List<M.PluginRef>, budget: Nat) -> Bool:
  match state:
    case Awaiting{actual, remaining}: Same.call(budget, call, actual) && references(pending, remaining)
    case _: False{}

def corresponds(history: M.History, owner: Nat, +call: M.Call, pending: +List<M.PluginRef>, contract: M.Contract, budget: Nat) -> Bool:
  matches(progress(history, owner, M.call_id(call), before(plugins(contract))), call, pending, budget)

def queued(attempt: M.Attempt, contract: M.Contract) -> +List<M.PluginRef>:
  match attempt:
    case M.CheckedAttempt{call, pending}: pending
    case _: before(plugins(contract))

def retry(outcome: M.HookOutcome, +call: M.Call, pending: +List<M.PluginRef>, remaining: +List<M.Attempt>, task: M.Task) -> M.Task:
  match outcome:
    case M.AllowTool{}: M.with_phase(M.Ready{M.CheckedAttempt{call, pending} <> remaining}, task)
    case M.RewriteTool{arguments}: M.with_phase(M.Ready{M.CheckedAttempt{M.rewritten(call, arguments), pending} <> remaining}, task)
    case M.DenyTool{reason}:
      M.notify(M.with_phase(M.Ready{remaining}, M.append_message(M.FunctionOutput{M.call_id(call), M.failure("hook_denied", reason), True{}}, task)))
    case M.HookFailure{reason}:
      M.notify(M.with_phase(M.Ready{remaining}, M.append_message(M.FunctionOutput{M.call_id(call), M.failure("hook_failed", reason), True{}}, task)))

def complete(phase: M.Phase, +outcome: M.HookOutcome, +task: M.Task) -> M.Task:
  match phase:
    case M.HookPending{ticket, reference, +call, pending, remaining}:
      retry(outcome, call, pending, remaining, M.append_message(M.HookRecord{M.task_id(task), M.call_id(call), reference, outcome}, task))
    case _: task

def recovered(+task: M.Task) -> M.Task:
  complete(M.task_phase(task), M.HookFailure{"Hook outcome unknown after restart; its callback is not repeated and this tool was not dispatched"}, task)
