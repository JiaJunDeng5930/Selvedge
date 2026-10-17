import Base
import ../../harness/compaction/MODEL.bend as Bounded
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/equality.bend as Same

type Reason is Data:
  Background{}
  Blocking{}
  IdleMaintenance{}
  Manual{}

type Target is Data:
  Target{profile: String, window: Nat, reserve: Nat, cache_ttl: Nat, method: String}

type Policy is Data:
  Policy{enabled: Bool, background: Nat, blocking: Nat, idle_lead: Nat, targets: +List<Target>}

# A measured budget stores only the room above the method's legal minimums.
# There is no zero-window or undersized-reserve representation.
type TokenBudget is Data:
  TokenBudget{reserve_room: Nat, window_room: Nat}

def reserve_tokens(budget: TokenBudget) -> Nat:
  TokenBudget{reserve_room, window_room} = budget
  Nat.add(Bounded.minimum_reserve(), reserve_room)

def window_tokens(+budget: TokenBudget) -> Nat:
  TokenBudget{reserve_room, window_room} = budget
  Nat.add(Nat.max(Bounded.minimum_window(), Nat.mul(4n, reserve_tokens(budget))), window_room)

type InputCount is Data:
  InputCount{scope: String, tokens: Nat, budget: TokenBudget}

type Inspection is Data:
  ScopeObserved{scope: String}
  InputMeasured{count: InputCount}
  InspectionFailed{message: String}

def count_scope(count: InputCount) -> String:
  InputCount{scope, tokens, budget} = count
  scope

def count_tokens(count: InputCount) -> Nat:
  InputCount{scope, tokens, budget} = count
  tokens

def count_budget(count: InputCount) -> TokenBudget:
  InputCount{scope, tokens, budget} = count
  budget

type Measurement is Data:
  Unmeasured{}
  Oversized{history: D.History, model: D.Model, scope: String, window: Nat, reserve: Nat}
  MeasurementFailed{history: D.History, model: D.Model}
  Measuring{ticket: Nat, history: D.History, model: D.Model, scope: Maybe<&2, String>}
  Measured{history: D.History, model: D.Model, scope: String, tokens: Nat, window: Nat, reserve: Nat}

type Job is Data:
  NoJob{}
  Resuming{snapshot: D.History, model: D.Model, reason: Reason}
  Preparing{ticket: Nat, snapshot: D.History, model: D.Model, reason: Reason, scope: Maybe<&2, String>}
  Compacting{ticket: Nat, snapshot: D.History, model: D.Model, reason: Reason, progress: Bounded.State, scope: String}
  Validating{ticket: Nat, snapshot: D.History, model: D.Model, reason: Reason, candidate: J.Json, preview: D.History, scope: Maybe<&2, String>}

type Entry is Data:
  Entry{measurement: Measurement, job: Job, useful: Nat, maintained: Nat, attempted: Nat,
    last_activity: Nat, cache_deadline: Nat, cache_history: D.History, cache_scope: String}

type State is Data:
  State{policy: Policy, entries: +List<Finite.Entry(Entry)>, now: Nat, timer: Nat}

type Effect is Data:
  Scope{task_id: Nat, ticket: Nat, model: D.Model}
  Measure{task_id: Nat, ticket: Nat, model: D.Model, history: D.History, tools: +List<D.Tool>, context: D.TaskContext, callable: +List<String>, scope: String, validating: Bool}
  Compact{task_id: Nat, ticket: Nat, model: D.Model, history: D.History, tools: +List<D.Tool>, context: D.TaskContext, target: Target, progress: Bounded.State, scope: String}
  ArmClock{deadline: Nat}
  Cancel{task_id: Nat, ticket: Nat}

type Completion is Data:
  Configure{policy: Policy, now: Nat}
  Clock{now: Nat}
  Activity{task_id: Nat, source_length: Nat, now: Nat, scope: String}
  MeasuredInput{task_id: Nat, ticket: Nat, outcome: Inspection}
  Completed{task_id: Nat, ticket: Nat, value: J.Json, error: Bool}

def initial_policy() -> Policy:
  Policy{False{}, 65n, 90n, 60000n, Nil{}}

def number(+value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def target_json(+value: J.Json) -> Target:
  Target{J.text(J.get(value, "profile")), number(J.get(value, "window_tokens")),
    number(J.get(value, "output_reserve_tokens")), number(J.get(value, "cache_ttl_ms")), J.text(J.get(value, "method"))}

def targets_json(+values: +List<J.Json>) -> +List<Target>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}: target_json(value) <> targets_json(rest)

def policy_json(+value: J.Json) -> Policy:
  Policy{J.boolean(J.get(value, "enabled")), number(J.get(value, "background_percent")),
    number(J.get(value, "blocking_percent")), number(J.get(value, "idle_lead_ms")), targets_json(J.items(J.get(value, "targets")))}

def target_key(+target: Target) -> String:
  Target{+profile, +window, +reserve, +ttl, +method} = target
  profile

def profile_key(+model: D.Model) -> String:
  D.Model{D.Profile{+key, +provider, +name, +policy, +options}, +effort} = model
  key

def branch(~S: Data, +condition: Bool, yes: Unit -> S, no: Unit -> S) -> S:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def find_target(+values: +List<Target>, +key: String) -> Maybe<&2, Target>:
  match values:
    case Nil{}: None{}
    case Con{+target, +rest}:
      branch(Maybe<&2, Target>, String.eq(target_key(target), key),
        (unused =>
          Some{target}),
        (unused =>
          find_target(rest, key)))

def configured_target(+policy: Policy, +model: D.Model) -> Maybe<&2, Target>:
  Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  find_target(targets, profile_key(model))

def target(+policy: Policy, +model: D.Model) -> Maybe<&2, Target>:
  Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  match enabled:
    case False{}: None{}
    case True{}: find_target(targets, profile_key(model))

def threshold(+tokens: Nat, +window: Nat, +percentage: Nat) -> Bool:
  Nat.is_le(Nat.mul(window, percentage), Nat.mul(tokens, 100n))

def background(+policy: Policy, +tokens: Nat, +window: Nat) -> Bool:
  Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  enabled && threshold(tokens, window, background)

def blocking(+policy: Policy, +tokens: Nat, +window: Nat) -> Bool:
  Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  enabled && threshold(tokens, window, blocking)

# The observation is about one immutable input, rather than a task-wide count.

def empty_entry() -> Entry:
  Entry{Unmeasured{}, NoJob{}, 0n, 0n, 0n, 0n, 0n, D.EmptyHistory{}, ""}

def initial() -> State:
  State{initial_policy(), Nil{}, 0n, 0n}

def entries(+state: State) -> +List<Finite.Entry(Entry)>:
  State{+policy, +entries, +now, +timer} = state
  entries

def settings(+state: State) -> Policy:
  State{+policy, +entries, +now, +timer} = state
  policy

def now(+state: State) -> Nat:
  State{+policy, +entries, +now, +timer} = state
  now

def timer(+state: State) -> Nat:
  State{+policy, +entries, +now, +timer} = state
  timer

def with_entry(+id: Nat, +entry: Entry, +state: State) -> State:
  State{+policy, +entries, +now, +timer} = state
  State{policy, (id, entry) <> Finite.remove(~Entry, entries, id), now, timer}

def found_entry(+found: Maybe<&2, Entry>) -> Entry:
  match found:
    case None{}: empty_entry()
    case Some{+entry}: entry

def entry(+id: Nat, +state: State) -> Entry:
  found_entry(Finite.find(~Entry, entries(state), id))

def measurement(+entry: Entry) -> Measurement:
  Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  measurement

def job(+entry: Entry) -> Job:
  Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  job

def with_measurement(+value: Measurement, +entry: Entry) -> Entry:
  Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  Entry{value, job, useful, maintained, attempted, activity, deadline, cache, scope}

def with_job(+value: Job, +entry: Entry) -> Entry:
  Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  Entry{measurement, value, useful, maintained, attempted, activity, deadline, cache, scope}

def useful(+history: D.History) -> Nat:
  match history:
    case D.EmptyHistory{}: 0n
    case D.HistoryNode{+previous, D.ContextReplacement{+value}}: useful(previous)
    case D.HistoryNode{+previous, D.ReasoningRecord{+owner, +effort, +remaining, +sampling}}: useful(previous)
    case D.HistoryNode{+previous, D.FailureMessage{+text}}: useful(previous)
    case D.HistoryNode{+previous, +message}: 1n+useful(previous)

def fresh(+observation: Measurement, +history: D.History, +model: D.Model) -> Bool:
  match observation:
    case Measured{+previous, +expected, +scope, +tokens, +window, +reserve}:
      Same.model(model, expected) && Same.history(1048576n, previous, history)
    case Oversized{+previous, +expected, +scope, +window, +reserve}: Same.model(model, expected) && Same.history(1048576n, previous, history)
    case MeasurementFailed{+previous, +expected}: Same.model(model, expected) && Same.history(1048576n, previous, history)
    case _: False{}

def job_pending(+job: Job) -> Bool:
  match job:
    case NoJob{}: False{}
    case _: True{}

def job_ticket(+job: Job) -> Maybe<&2, Nat>:
  match job:
    case NoJob{}: None{}
    case Resuming{+snapshot, +model, +reason}: None{}
    case Preparing{+ticket, +snapshot, +model, +reason, +scope}: Some{ticket}
    case Compacting{+ticket, +snapshot, +model, +reason, +progress, +scope}: Some{ticket}
    case Validating{+ticket, +snapshot, +model, +reason, +candidate, +preview, +scope}: Some{ticket}

def resume(+job: Job) -> Job:
  match job:
    case NoJob{}: NoJob{}
    case Resuming{+snapshot, +model, +reason}: Resuming{snapshot, model, reason}
    case Preparing{+ticket, +snapshot, +model, +reason, +scope}: Resuming{snapshot, model, reason}
    case Compacting{+ticket, +snapshot, +model, +reason, +progress, +scope}: Resuming{snapshot, model, reason}
    case Validating{+ticket, +snapshot, +model, +reason, +candidate, +preview, +scope}: Resuming{snapshot, model, reason}

def recover_entry(+entry: Entry) -> Entry:
  Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  Entry{Unmeasured{}, resume(job), useful, maintained, attempted, activity, deadline, cache, scope}

def recover_entries(+values: +List<Finite.Entry(Entry)>) -> +List<Finite.Entry(Entry)>:
  match values:
    case Nil{}: Nil{}
    case Con{(+id, entry), +rest}: (id, recover_entry(entry)) <> recover_entries(rest)

def recover(+state: State) -> State:
  State{+policy, +entries, +now, +timer} = state
  State{policy, recover_entries(entries), now, 0n}

def current_revision(+entry: Entry) -> Nat:
  Entry{measurement, job, useful, maintained, attempted, activity, deadline, cache, scope} = entry
  useful

def maintained_revision(+entry: Entry) -> Nat:
  Entry{measurement, job, useful, maintained, attempted, activity, deadline, cache, scope} = entry
  maintained

def valid_target(target: Target) -> Bool:
  Target{profile, window, reserve, ttl, +method} = target
  D.nonempty(profile) && Bounded.legal_budget(window, reserve) && (String.eq(method, "auto") || String.eq(method, "summary"))

def valid_targets(targets: +List<Target>) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{target, rest}: valid_target(target) && valid_targets(rest)

def valid_policy(policy: Policy) -> Bool:
  Policy{enabled, +background, +blocking, lead, targets} = policy
  Nat.is_lt(0n, background) && Nat.is_lt(background, blocking) && Nat.is_le(blocking, 100n) && valid_targets(targets)

def attempted_revision(entry: Entry) -> Nat:
  Entry{measurement, job, useful, maintained, attempted, activity, deadline, cache, scope} = entry
  attempted

def evolved_entry(found: Maybe<&2, Entry>, +previous: Entry) -> Bool:
  match found:
    case None{}: False{}
    case Some{+candidate}: Nat.is_le(current_revision(previous), current_revision(candidate)) &&
      Nat.is_le(maintained_revision(previous), maintained_revision(candidate)) && Nat.is_le(attempted_revision(previous), attempted_revision(candidate))

def evolved_entries(previous: +List<Finite.Entry(Entry)>, +candidate: +List<Finite.Entry(Entry)>) -> Bool:
  match previous:
    case Nil{}: True{}
    case Con{(+id, entry), rest}: evolved_entry(Finite.find(~Entry, candidate, id), entry) && evolved_entries(rest, candidate)

def evolution(+previous: State, +candidate: State) -> Bool:
  Nat.is_le(now(previous), now(candidate)) && evolved_entries(entries(previous), entries(candidate))
