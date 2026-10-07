import Base
import ./bendlib/component.bend as C
import ./bendlib/domain.bend as D
import ./bendlib/json.bend as J
import ./bendlib/equality.bend as Same
import ./bendlib/schema.bend as Schema

# The extension boundary is a sequential authorization protocol, not a callback
# inside Bash. A task freezes its chain; the host only answers committed tickets.
# The original FunctionCall is immutable. Checked attempts and operation rights
# must correspond to replaying the exact, append-only HookRecord certificates.
type Progress is Data:
  Absent{}
  Awaiting{call: D.Call, pending: +List<D.PluginRef>}
  Refused{}

def plugins(contract: D.Contract) -> +List<D.Plugin>:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  plugins

def environment_plugins(environment: D.Environment) -> +List<D.Plugin>:
  D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  plugins

def live(-StateRest: Data, world: C.Frame<D.State, StateRest>) -> +List<D.Plugin>:
  environment_plugins(D.state_environment(C.local(D.State, StateRest, world)))

def before(plugins: +List<D.Plugin>) -> +List<D.PluginRef>:
  match plugins:
    case Nil{}: Nil{}
    case Con{D.Plugin{reference, True{}, after, events}, rest}: reference <> before(rest)
    case Con{D.Plugin{reference, False{}, after, events}, rest}: before(rest)

def after(plugins: +List<D.Plugin>) -> +List<D.PluginRef>:
  match plugins:
    case Nil{}: Nil{}
    case Con{D.Plugin{reference, before, True{}, events}, rest}: reference <> after(rest)
    case Con{D.Plugin{reference, before, False{}, events}, rest}: after(rest)

def after_available(plugins: +List<D.Plugin>, +reference: D.PluginRef) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{D.Plugin{candidate, before, after, events}, rest}:
      (after && D.plugin_same(candidate, reference)) || after_available(rest, reference)

def references(left: +List<D.PluginRef>, right: +List<D.PluginRef>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}: D.plugin_same(a, b) && references(rest_a, rest_b)
    case _ _: False{}

def present(plugins: +List<D.Plugin>, +reference: D.PluginRef) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{D.Plugin{candidate, before, after, events}, rest}:
      D.plugin_same(candidate, reference) || present(rest, reference)

def available(plugins: +List<D.Plugin>, +reference: D.PluginRef) -> Bool:
  match plugins:
    case Nil{}: False{}
    case Con{D.Plugin{candidate, before, after, events}, rest}:
      (before && D.plugin_same(candidate, reference)) || available(rest, reference)

def member(strings: +List<String>, +value: String) -> Bool:
  match strings:
    case Nil{}: False{}
    case Con{item, rest}: String.eq(item, value) || member(rest, value)

def event_names() -> +List<String>:
  D.plugin_events()

def subscriptions(events: +List<D.EventKind>, +seen: +List<String>) -> Bool:
  match events:
    case Nil{}: True{}
    case Con{+event, rest}: Bool.not(member(seen, D.event_name(event))) && subscriptions(rest, D.event_name(event) <> seen)

def plugin_name(reference: D.PluginRef) -> String:
  D.PluginRef{name, revision} = reference
  name

def reference_valid(reference: D.PluginRef) -> Bool:
  D.PluginRef{+name, +revision} = reference
  D.nonempty(name) && D.nonempty(revision) && Nat.is_le(J.utf8_length(name), 128n) && Nat.is_le(J.utf8_length(revision), 128n)

def unique(plugins: +List<D.Plugin>, +seen: +List<String>) -> Bool:
  match plugins:
    case Nil{}: True{}
    case Con{D.Plugin{+reference, before, after, events}, rest}:
      reference_valid(reference) && Bool.not(member(seen, plugin_name(reference))) && subscriptions(events, Nil{}) &&
        unique(rest, plugin_name(reference) <> seen)

def valid(+plugins: +List<D.Plugin>) -> Bool:
  Nat.is_le(List.length(&2, D.Plugin, plugins), D.plugin_limit()) && unique(plugins, Nil{})

def routes(tools: +List<D.Tool>, +plugins: +List<D.Plugin>) -> Bool:
  match tools:
    case Nil{}: True{}
    case Con{D.Tool{name, description, schema, D.Extension{owner, remote}}, rest}:
      present(plugins, owner) && D.nonempty(remote) && Schema.supported(schema) && routes(rest, plugins)
    case Con{other, rest}: routes(rest, plugins)

# This fold interprets observed certificates only. No source-name label can
# replace a missing record, reorder the chain, change a call's identity, or turn
# a rejection into permission. Its result is checked again at effect admission.
def begin(state: Progress, call: D.Call, chain: +List<D.PluginRef>) -> Progress:
  match state:
    case Absent{}: Awaiting{call, chain}
    case _: Refused{}

def advance(outcome: D.HookOutcome, call: D.Call, pending: +List<D.PluginRef>) -> Progress:
  match outcome:
    case D.AllowTool{}: Awaiting{call, pending}
    case D.RewriteTool{arguments}: Awaiting{D.rewritten(call, arguments), pending}
    case D.DenyTool{reason}: Refused{}
    case D.HookFailure{reason}: Refused{}

def checked(same: Bool, outcome: D.HookOutcome, call: D.Call, pending: +List<D.PluginRef>) -> Progress:
  match same:
    case True{}: advance(outcome, call, pending)
    case False{}: Refused{}

def record(state: Progress, reference: D.PluginRef, outcome: D.HookOutcome) -> Progress:
  match state:
    case Awaiting{call, Con{expected, pending}}: checked(D.plugin_same(reference, expected), outcome, call, pending)
    case _: Refused{}

def start_matching(same: Bool, state: Progress, call: D.Call, chain: +List<D.PluginRef>) -> Progress:
  match same:
    case True{}: begin(state, call, chain)
    case False{}: state

def record_matching(same: Bool, state: Progress, reference: D.PluginRef, outcome: D.HookOutcome) -> Progress:
  match same:
    case True{}: record(state, reference, outcome)
    case False{}: state

def history_step(message: D.Message, owner: Nat, id: String, chain: +List<D.PluginRef>, state: Progress) -> Progress:
  match message:
    case D.FunctionCall{+call}: start_matching(String.eq(D.call_id(call), id), state, call, chain)
    case D.HookRecord{task_id, call_id, reference, outcome}: record_matching(Nat.is_eq(task_id, owner) && String.eq(call_id, id), state, reference, outcome)
    case _: state

def progress(history: D.History, +owner: Nat, +id: String, +chain: +List<D.PluginRef>) -> Progress:
  match history:
    case D.EmptyHistory{}: Absent{}
    case D.HistoryNode{previous, message}: history_step(message, owner, id, chain, progress(previous, owner, id, chain))

def matches(state: Progress, call: D.Call, pending: +List<D.PluginRef>, budget: Nat) -> Bool:
  match state:
    case Awaiting{actual, remaining}: Same.call(budget, call, actual) && references(pending, remaining)
    case _: False{}

def corresponds(history: D.History, owner: Nat, +call: D.Call, pending: +List<D.PluginRef>, contract: D.Contract, budget: Nat) -> Bool:
  matches(progress(history, owner, D.call_id(call), before(plugins(contract))), call, pending, budget)

def queued(attempt: D.Attempt, contract: D.Contract) -> +List<D.PluginRef>:
  match attempt:
    case D.CheckedAttempt{call, pending}: pending
    case _: before(plugins(contract))

def retry(outcome: D.HookOutcome, +call: D.Call, pending: +List<D.PluginRef>, remaining: +List<D.Attempt>, task: D.Task) -> D.Task:
  match outcome:
    case D.AllowTool{}: D.with_phase(D.Ready{D.CheckedAttempt{call, pending} <> remaining}, task)
    case D.RewriteTool{arguments}: D.with_phase(D.Ready{D.CheckedAttempt{D.rewritten(call, arguments), pending} <> remaining}, task)
    case D.DenyTool{reason}:
      D.notify(D.with_phase(D.Ready{remaining}, D.append_message(D.FunctionOutput{D.call_id(call), D.failure("hook_denied", reason), True{}}, task)))
    case D.HookFailure{reason}:
      D.notify(D.with_phase(D.Ready{remaining}, D.append_message(D.FunctionOutput{D.call_id(call), D.failure("hook_failed", reason), True{}}, task)))

def complete(phase: D.Phase, +outcome: D.HookOutcome, +task: D.Task) -> D.Task:
  match phase:
    case D.HookPending{ticket, reference, +call, pending, remaining}:
      retry(outcome, call, pending, remaining, D.append_message(D.HookRecord{D.task_id(task), D.call_id(call), reference, outcome}, task))
    case _: task

def recovered(+task: D.Task) -> D.Task:
  complete(D.task_phase(task), D.HookFailure{"Hook outcome unknown after restart; its callback is not repeated and this tool was not dispatched"}, task)

# The after protocol interprets the immutable execution receipt and its ordered
# certificates. An operation can own execution OR a result callback, never both.
# The raw error flag is not a plugin-editable field.
type ResultProgress is Data:
  MissingResult{}
  AwaitingResult{call: D.Call, value: J.Json, error: Bool, pending: +List<D.PluginRef>}
  RefusedResult{}

def result_begin(state: ResultProgress, call: D.Call, value: J.Json, error: Bool, chain: +List<D.PluginRef>) -> ResultProgress:
  match state:
    case MissingResult{}: AwaitingResult{call, value, error, chain}
    case _: RefusedResult{}

type ResultAction is Data:
  ResultValue{value: J.Json, error: Bool}
  ResultError{code: String, reason: String}

# One interpretation of a plugin outcome is shared by authorization replay and
# actual delivery. In particular, value replacement cannot clear execution error.
def result_action(outcome: D.AfterOutcome, value: J.Json, error: Bool) -> ResultAction:
  match outcome:
    case D.KeepResult{}: ResultValue{value, error}
    case D.RewriteResult{rewritten}: ResultValue{rewritten, error}
    case D.DenyResult{reason}: ResultError{"after_hook_denied", reason}
    case D.AfterFailure{reason}: ResultError{"after_hook_failed", reason}

def result_action_progress(action: ResultAction, call: D.Call, pending: +List<D.PluginRef>) -> ResultProgress:
  match action:
    case ResultValue{value, error}: AwaitingResult{call, value, error, pending}
    case ResultError{code, reason}: RefusedResult{}

def result_advance(outcome: D.AfterOutcome, call: D.Call, value: J.Json, error: Bool, pending: +List<D.PluginRef>) -> ResultProgress:
  result_action_progress(result_action(outcome, value, error), call, pending)

def result_checked(same: Bool, outcome: D.AfterOutcome, call: D.Call, value: J.Json, error: Bool, pending: +List<D.PluginRef>) -> ResultProgress:
  match same:
    case True{}: result_advance(outcome, call, value, error, pending)
    case False{}: RefusedResult{}

def result_record(state: ResultProgress, reference: D.PluginRef, outcome: D.AfterOutcome) -> ResultProgress:
  match state:
    case AwaitingResult{call, value, error, Con{expected, pending}}:
      result_checked(D.plugin_same(reference, expected), outcome, call, value, error, pending)
    case _: RefusedResult{}

def result_start_matching(same: Bool, state: ResultProgress, call: D.Call, value: J.Json, error: Bool, chain: +List<D.PluginRef>) -> ResultProgress:
  match same:
    case True{}: result_begin(state, call, value, error, chain)
    case False{}: state

def result_record_matching(same: Bool, state: ResultProgress, reference: D.PluginRef, outcome: D.AfterOutcome) -> ResultProgress:
  match same:
    case True{}: result_record(state, reference, outcome)
    case False{}: state

def result_step(message: D.Message, owner: Nat, operation: Nat, chain: +List<D.PluginRef>, state: ResultProgress) -> ResultProgress:
  match message:
    case D.ToolReceipt{task_id, id, call, value, error}:
      result_start_matching(Nat.is_eq(task_id, owner) && Nat.is_eq(id, operation), state, call, value, error, chain)
    case D.AfterRecord{task_id, id, reference, outcome}:
      result_record_matching(Nat.is_eq(task_id, owner) && Nat.is_eq(id, operation), state, reference, outcome)
    case _: state

def result_progress(history: D.History, +owner: Nat, +operation: Nat, +chain: +List<D.PluginRef>) -> ResultProgress:
  match history:
    case D.EmptyHistory{}: MissingResult{}
    case D.HistoryNode{previous, message}:
      result_step(message, owner, operation, chain, result_progress(previous, owner, operation, chain))

def result_matches(state: ResultProgress, call: D.Call, value: J.Json, error: Bool, pending: +List<D.PluginRef>, +budget: Nat) -> Bool:
  match state:
    case AwaitingResult{original, current, original_error, remaining}:
      Same.call(budget, call, original) && Same.json(budget, value, current) && Same.booleans(error, original_error) && references(pending, remaining)
    case _: False{}

def result_corresponds(history: D.History, owner: Nat, operation: Nat, call: D.Call, value: J.Json, error: Bool,
  pending: +List<D.PluginRef>, contract: D.Contract, budget: Nat) -> Bool:
  result_matches(result_progress(history, owner, operation, after(plugins(contract))), call, value, error, pending, budget)
