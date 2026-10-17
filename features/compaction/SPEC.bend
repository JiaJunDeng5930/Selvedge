import Base
import ./MODEL.bend as A
import ./CODEC.bend as Codec
import ../../bendlib/association-map.bend as Finite
import ./STATE.bend as State
import ../../harness/DOMAIN.bend as D
import ../../harness/MODEL.bend as M
import ../../harness/features/MODEL.bend as F
import ../../harness/tasks/PROGRAM.bend as T
import ../../harness/context/PROGRAM.bend as Context
import ../../harness/context/selection.bend as ContextModel
import ../../harness/compaction/MODEL.bend as Bounded
import ../../harness/compaction/PROGRAM.bend as Rebuild
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../bendlib/equality.bend as Same
import ../../bendlib/effects.bend as Effects

# Resolution produces a component-local write, an optional task write and the
# exact external work. The interpreter has no threshold or adoption policy.
type Change is Data:
  Unchanged{}
  Change{state: A.State, task: Maybe<&2, D.Task>, reserve_ticket: Bool, effects: +List<A.Effect>}

def model(+task: D.Task) -> D.Model:
  D.task_model(task)

def provider(+value: D.Model) -> String:
  D.Model{D.Profile{+key, +provider, +name, +policy, +options}, +effort} = value
  provider

def alive(+status: D.Status) -> Bool:
  match status:
    case D.Archived{}: False{}
    case _: True{}

def active(+status: D.Status) -> Bool:
  match status:
    case D.Active{}: True{}
    case _: False{}

def idle_phase(+phase: D.Phase, +operations: +List<D.Operation()>) -> Bool:
  match phase:
    case D.Idle{}: Bool.not(D.operations_pending(operations))
    case _: False{}

def idle(+task: D.Task) -> Bool:
  idle_phase(D.task_phase(task), D.task_operations(task))

def with_now(+now: Nat, +state: A.State) -> A.State:
  A.State{+policy, +entries, +previous, +timer} = state
  A.State{policy, entries, Nat.max(now, previous), timer}

def entry_change(+id: Nat, +entry: A.Entry, +task: Maybe<&2, D.Task>, +reserved: Bool, +effects: +List<A.Effect>, +state: A.State) -> Change:
  Change{A.with_entry(id, entry, state), task, reserved, effects}

def measured_snapshot(+current: Bool, +snapshot: D.History, +model: D.Model, +value: J.Json) -> A.Measurement:
  match current:
    case False{}: A.Unmeasured{}
    case True{}: A.Measured{snapshot, model, J.text(J.get(value, "scope")), A.number(J.get(value, "input_tokens")),
      A.number(J.get(value, "window_tokens")), A.number(J.get(value, "output_reserve_tokens"))}

def same_input(+snapshot: D.History, +expected: D.Model, +task: D.Task) -> Bool:
  Same.model(expected, model(task)) && Same.history(1048576n, snapshot, D.task_history(task))

def relevant(+snapshot: D.History, +expected: D.Model, +task: D.Task) -> Bool:
  alive(D.task_status(task)) && Same.model(expected, model(task)) && Same.history_extends(1048576n, snapshot, D.task_history(task))

def environment_callable(+environment: D.Environment, +task: D.Task) -> +List<String>:
  D.Environment{+catalog, +profiles, +forks, +descendants, +project, +plugins, +instructions} = environment
  T.callable(T.task_tools(D.task_contract(task)), catalog)

def callable(+task: D.Task, +world: M.World()) -> +List<String>:
  environment_callable(D.state_environment(C.local(D.State, F.State(), world)), task)

def measure_reason(+reason: Maybe<&2, A.Reason>, +task: D.Task, +entry: A.Entry, +ticket: Nat, +snapshot: D.History, +selected: D.Model, +world: M.World()) -> Change:
  match reason:
    case None{}:
      entry_change(D.task_id(task), A.with_measurement(A.Measuring{ticket, snapshot, selected, None{}}, entry), None{}, True{},
        [A.Scope{D.task_id(task), ticket, selected}], State.registry(world))
    case Some{+reason}:
      entry_change(D.task_id(task), A.with_measurement(A.Unmeasured{}, A.with_job(A.Preparing{ticket, snapshot, selected, reason, None{}}, entry)), None{}, True{},
        [A.Scope{D.task_id(task), ticket, selected}], State.registry(world))

def measure(+task: D.Task, +entry: A.Entry, +reason: Maybe<&2, A.Reason>, +world: M.World()) -> Change:
  measure_reason(reason, task, entry, State.ticket(world), D.task_history(task), model(task), world)

def stop_phase(+phase: D.Phase, +task: D.Task, +message: String) -> D.Task:
  match phase:
    case D.Ready{Nil{}}: D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Context compaction: " ++ message}, task))
    case _: D.append_message(D.FailureMessage{"Context compaction: " ++ message}, task)

def stopped_task(+task: D.Task, +message: String) -> D.Task:
  stop_phase(D.task_phase(task), task, message)

def failed(+task: D.Task, +entry: A.Entry, +message: String, +state: A.State) -> Change:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  entry_change(D.task_id(task), A.Entry{A.MeasurementFailed{D.task_history(stopped_task(task, message)), model(task)}, A.NoJob{}, useful, maintained, A.useful(D.task_history(task)), activity, 0n, cache, scope},
    Some{stopped_task(task, message)}, False{}, Nil{}, state)

def commit_compact(fits: Bool, +progress: Bounded.State, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +scope: String, +target: A.Target, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match fits:
    case False{}: failed(task, entry, "The configured compaction request exceeds the transport budget", State.registry(world))
    case True{}:
      +ticket = State.ticket(world)
      entry_change(D.task_id(task), A.with_job(A.Compacting{ticket, snapshot, selected, reason, progress, scope}, entry), None{}, True{},
        [A.Compact{D.task_id(task), ticket, selected, snapshot, T.task_tools(D.task_contract(task)), D.task_context(task), target, progress, scope}], State.registry(world))

def frame_limit(limits: D.ExecutionLimits) -> Nat:
  D.ExecutionLimits{steps, render, bytes} = limits
  Nat.div(U32.to_nat(bytes), 4n)

def dispatch_compact(+progress: Bounded.State, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +scope: String, +target: A.Target, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  +limit = frame_limit(D.state_limits(C.local(D.State, F.State(), world)))
  +available = Nat.sub(limit, Codec.compact_metadata_bytes(D.task_id(task), State.ticket(world), selected, scope, target, limit))
  +fitted = Rebuild.fit_transport(progress, available)
  commit_compact(Rebuild.transport_fits(fitted, available), fitted, snapshot, selected, reason, scope, target, task, entry, world)

def start(+task: D.Task, +entry: A.Entry, +snapshot: D.History, +selected: D.Model, +reason: A.Reason, +target: A.Target, +value: J.Json, +world: M.World()) -> Change:
  A.Target{+profile, +window, +reserve, +ttl, +method} = target
  +scope = J.text(J.get(value, "scope"))
  +messages = Context.history_json(snapshot)
  +progress = Rebuild.start(J.Array{Context.dialogue(Context.target_messages(messages, scope))}, J.Array{Context.dialogue(Context.raw_messages(messages))}, provider(selected), method,
    A.number(J.get(value, "input_tokens")), window, reserve)
  dispatch_compact(progress, snapshot, selected, reason, scope, A.Target{profile, window, reserve, ttl, method}, task, entry, world)

def current_target(+task: D.Task, +state: A.State) -> Maybe<&2, A.Target>:
  A.configured_target(A.settings(state), model(task))

def must_wait(+policy: A.Policy, +tokens: Nat, +window: Nat, +reserve: Nat) -> Bool:
  A.blocking(policy, tokens, window) || Bool.not(Nat.is_le(Nat.add(tokens, reserve), window))

def selected_reason(+policy: A.Policy, +tokens: Nat, +window: Nat, +reserve: Nat) -> Maybe<&2, A.Reason>:
  A.branch(Maybe<&2, A.Reason>, must_wait(policy, tokens, window, reserve),
    (unused =>
      Some{A.Blocking{}}),
    (unused =>
      A.branch(Maybe<&2, A.Reason>, A.background(policy, tokens, window),
        (unused =>
          Some{A.Background{}}),
        (unused =>
          None{}))))

def attempted(+entry: A.Entry) -> Nat:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  attempted

def eligible(+task: D.Task, +entry: A.Entry) -> Bool:
  Nat.is_lt(attempted(entry), A.useful(D.task_history(task))) && Bool.not(A.job_pending(A.job(entry))) && Context.settled_calls(D.task_history(task), D.task_history(task))

def start_if(+reason: Maybe<&2, A.Reason>, +target: Maybe<&2, A.Target>, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match reason target:
    case Some{+reason} Some{+target}: start(task, entry, D.task_history(task), model(task), reason, target, value, world)
    case _ _: entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, State.registry(world))

def finish_measure(+snapshot: D.History, +selected: D.Model, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  +current = same_input(snapshot, selected, task)
  +entry = A.with_measurement(measured_snapshot(current, snapshot, selected, value), entry)
  A.branch(~Change, current && Bool.not(A.job_pending(A.job(entry))) && Context.settled_calls(snapshot, snapshot) &&
    (eligible(task, entry) || must_wait(A.settings(State.registry(world)), A.number(J.get(value, "input_tokens")), A.number(J.get(value, "window_tokens")), A.number(J.get(value, "output_reserve_tokens")))),
    (unused =>
      start_if(selected_reason(A.settings(State.registry(world)), A.number(J.get(value, "input_tokens")), A.number(J.get(value, "window_tokens")), A.number(J.get(value, "output_reserve_tokens"))),
      current_target(task, State.registry(world)), task, entry, value, world)),
    (unused =>
      entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, State.registry(world))))

def validate(+snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  +preview = Context.adopt(snapshot, candidate, D.task_history(task))
  +ticket = State.ticket(world)
  entry_change(D.task_id(task), A.with_measurement(A.Unmeasured{}, A.with_job(A.Validating{ticket, snapshot, selected, reason, candidate, preview, None{}}, entry)), None{}, True{},
    [A.Scope{D.task_id(task), ticket, selected}], State.registry(world))

def validate_candidate(+snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  A.branch(~Change, relevant(snapshot, selected, task) && Context.adoptable(snapshot, candidate, D.task_history(task)),
    (unused =>
      validate(snapshot, selected, reason, candidate, task, entry, world)),
    (unused =>
      entry_change(D.task_id(task), A.with_job(A.NoJob{}, entry), None{}, False{}, Nil{}, State.registry(world))))

def mark_finished(+snapshot: D.History, +entry: A.Entry, +measurement: A.Measurement) -> A.Entry:
  A.Entry{+previous, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  +captured = A.useful(snapshot)
  A.Entry{measurement, A.NoJob{}, useful, Nat.max(captured, maintained), Nat.max(captured, attempted), activity, deadline, cache, scope}

def capacity_job(job: A.Job) -> A.Job:
  match job:
    case A.Compacting{ticket, snapshot, selected, reason, progress, scope}: A.Compacting{ticket, snapshot, selected, reason, progress, scope}
    case _: A.NoJob{}

def portable_target(target: Maybe<&2, A.Target>, +scope: String, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match target:
    case None{}: Unchanged{}
    case Some{A.Target{+profile, +window, +reserve, +ttl, method}}:
      +snapshot = D.task_history(task)
      +selected = model(task)
      +entry = A.with_measurement(A.Oversized{snapshot, selected, scope, window, reserve}, A.with_job(capacity_job(A.job(entry)), entry))
      A.branch(~Change, A.job_pending(A.job(entry)),
        (unused => entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, State.registry(world))),
        (unused =>
          A.branch(~Change, Context.settled_calls(snapshot, snapshot),
            (unused => start(task, entry, snapshot, selected, A.Blocking{}, A.Target{profile, window, reserve, ttl, "summary"},
              J.Object{[J.Field{"scope", J.Text{scope}}, J.Field{"input_tokens", J.nat(window)}]}, world)),
            (unused => entry_change(D.task_id(task), A.with_job(A.Resuming{snapshot, selected, A.Blocking{}}, entry), None{}, False{}, Nil{}, State.registry(world))))))

def adopt_fits(+fits: Bool, +snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +preview: D.History,
  +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match fits:
    case False{}: portable_target(current_target(task, State.registry(world)), J.text(J.get(value, "scope")), task, entry, world)
    case True{}:
      +observation = measured_snapshot(True{}, preview, selected, value)
      entry_change(D.task_id(task), mark_finished(snapshot, entry, observation), Some{D.with_history(preview, task)}, False{}, Nil{}, State.registry(world))

def finish_validation(+snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +preview: D.History,
  +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  A.branch(~Change, relevant(snapshot, selected, task) && Context.adoptable(snapshot, candidate, D.task_history(task)),
    (unused =>
      A.branch(~Change, Same.history(1048576n, preview, Context.adopt(snapshot, candidate, D.task_history(task))),
        (unused =>
          adopt_fits(Nat.is_le(Nat.add(A.number(J.get(value, "input_tokens")), A.number(J.get(value, "output_reserve_tokens"))), A.number(J.get(value, "window_tokens"))) &&
          Bool.not(String.eq(J.text(J.get(candidate, "format")), "native") && A.blocking(A.settings(State.registry(world)), A.number(J.get(value, "input_tokens")), A.number(J.get(value, "window_tokens")))),
          snapshot, selected, reason, candidate, preview, task, entry, value, world)),
        (unused =>
          validate(snapshot, selected, reason, candidate, task, entry, world)))),
    (unused =>
      entry_change(D.task_id(task), A.with_job(A.NoJob{}, entry), None{}, False{}, Nil{}, State.registry(world))))

def prepared_target(+target: Maybe<&2, A.Target>, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match target:
    case None{}: failed(task, entry, "The selected profile does not support compaction", State.registry(world))
    case Some{+target}: start(task, A.with_measurement(measured_snapshot(same_input(snapshot, selected, task), snapshot, selected, value), entry), snapshot, selected, reason, target, value, world)

def rendered_bytes(result: Result<&2, &2, String, String>, limit: Nat) -> Nat:
  match result:
    case Fail{message}: 1n+limit
    case Done{text}: J.utf8_length(text)

def measure_fits(fits: Bool, +history: D.History, +selected: D.Model, +scope: String, validating: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match fits:
    case False{}: portable_target(current_target(task, State.registry(world)), scope, task, entry, world)
    case True{}:
      +ticket = State.ticket(world)
      entry_change(D.task_id(task), entry, None{}, True{},
        [A.Measure{D.task_id(task), ticket, selected, history, T.task_tools(D.task_contract(task)), D.task_context(task), callable(task, world), scope, validating}], State.registry(world))

def measured_call(+history: D.History, +selected: D.Model, +scope: String, +validating: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  +limit = frame_limit(D.state_limits(C.local(D.State, F.State(), world)))
  +bytes = rendered_bytes(J.show(J.Object{[J.Field{"history", J.Array{Context.target_messages(Context.history_json(history), scope)}}, J.Field{"tools", J.Array{D.tools_json(T.task_tools(D.task_contract(task)))}}]}), limit)
  measure_fits(Nat.is_le(bytes, limit), history, selected, scope, validating, task, entry, world)

def ordinary_input(+snapshot: D.History, +selected: D.Model, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  +scope = J.text(J.get(value, "scope"))
  measured_call(snapshot, selected, scope, False{}, task,
    A.with_measurement(A.Measuring{State.ticket(world), snapshot, selected, Some{scope}}, entry), world)

def ordinary_inspected(scope: Maybe<&2, String>, +snapshot: D.History, +selected: D.Model, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match scope:
    case Some{scope}:
      A.branch(~Change, String.eq(scope, J.text(J.get(value, "scope"))),
        (unused => finish_measure(snapshot, selected, task, entry, value, world)),
        (unused => ordinary_input(snapshot, selected, task, entry, value, world)))
    case None{}: ordinary_input(snapshot, selected, task, entry, value, world)

def ordinary_measurement(+observation: A.Measurement, +ticket: Nat, +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match observation:
    case A.Measuring{+expected, +snapshot, +selected, +scope}:
      A.branch(~Change, Nat.is_eq(ticket, expected),
        (unused =>
          A.branch(~Change, error,
            (unused =>
              failed(task, entry, J.text(J.get(value, "message")), State.registry(world))),
            (unused =>
              ordinary_inspected(scope, snapshot, selected, task, entry, value, world)),))
        (unused =>
          Unchanged{}))
    case _: Unchanged{}

def preparing_input(+snapshot: D.History, +selected: D.Model, +reason: A.Reason, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  +scope = J.text(J.get(value, "scope"))
  measured_call(snapshot, selected, scope, False{}, task,
    A.with_job(A.Preparing{State.ticket(world), snapshot, selected, reason, Some{scope}}, entry), world)

def preparing_inspected(scope: Maybe<&2, String>, +snapshot: D.History, +selected: D.Model, +reason: A.Reason, +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match scope:
    case Some{scope}:
      A.branch(~Change, String.eq(scope, J.text(J.get(value, "scope"))),
        (unused => prepared_target(current_target(task, State.registry(world)), snapshot, selected, reason, task, entry, value, world)),
        (unused => preparing_input(snapshot, selected, reason, task, entry, value, world)))
    case None{}: preparing_input(snapshot, selected, reason, task, entry, value, world)

def validation_input(+snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +preview: D.History,
  +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  +scope = J.text(J.get(value, "scope"))
  A.branch(~Change, ContextModel.compatible(candidate, scope),
    (unused => measured_call(preview, selected, scope, True{}, task,
      A.with_job(A.Validating{State.ticket(world), snapshot, selected, reason, candidate, preview, Some{scope}}, entry), world)),
    (unused => measure(task, A.with_job(A.NoJob{}, entry), Some{reason}, world)))

def validation_inspected(scope: Maybe<&2, String>, +snapshot: D.History, +selected: D.Model, +reason: A.Reason, +candidate: J.Json, +preview: D.History,
  +task: D.Task, +entry: A.Entry, +value: J.Json, +world: M.World()) -> Change:
  match scope:
    case Some{scope}:
      A.branch(~Change, String.eq(scope, J.text(J.get(value, "scope"))),
        (unused => finish_validation(snapshot, selected, reason, candidate, preview, task, entry, value, world)),
        (unused => validation_input(snapshot, selected, reason, candidate, preview, task, entry, value, world)))
    case None{}: validation_input(snapshot, selected, reason, candidate, preview, task, entry, value, world)

def measurement_job(+job: A.Job, +ticket: Nat, +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match job:
    case A.Validating{+expected, +snapshot, +selected, +reason, +candidate, +preview, +scope}:
      A.branch(~Change, Nat.is_eq(ticket, expected),
        (unused =>
          A.branch(~Change, error,
            (unused =>
              failed(task, entry, J.text(J.get(value, "message")), State.registry(world))),
            (unused =>
              validation_inspected(scope, snapshot, selected, reason, candidate, preview, task, entry, value, world)),))
        (unused =>
          Unchanged{}))
    case A.Preparing{+expected, +snapshot, +selected, +reason, +scope}:
      A.branch(~Change, Nat.is_eq(ticket, expected),
        (unused =>
          A.branch(~Change, error,
            (unused =>
              failed(task, entry, J.text(J.get(value, "message")), State.registry(world))),
            (unused =>
              A.branch(~Change, relevant(snapshot, selected, task),
                (unused =>
                  preparing_inspected(scope, snapshot, selected, reason, task, entry, value, world)),
                (unused =>
                  entry_change(D.task_id(task), A.with_job(A.NoJob{}, entry), None{}, False{}, Nil{}, State.registry(world))))),))
        (unused =>
          Unchanged{}))
    case _: ordinary_measurement(A.measurement(entry), ticket, value, error, task, entry, world)

def measurement_result(+ticket: Nat, +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  measurement_job(A.job(entry), ticket, value, error, task, entry, world)

def continue_target(+target: Maybe<&2, A.Target>, +progress: Bounded.State, +scope: String, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match target:
    case None{}: entry_change(D.task_id(task), A.with_job(A.NoJob{}, entry), None{}, False{}, Nil{}, State.registry(world))
    case Some{target}: dispatch_compact(progress, snapshot, selected, reason, scope, target, task, entry, world)

def compact_step(+step: Bounded.Step, +scope: String, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match step:
    case Bounded.Failed{+message}: failed(task, entry, message, State.registry(world))
    case Bounded.Compacted{+candidate}: validate_candidate(snapshot, selected, reason, candidate, task, entry, world)
    case Bounded.Next{+progress}: continue_target(current_target(task, State.registry(world)), progress, scope, snapshot, selected, reason, task, entry, world)

def compact_observed(+progress: Bounded.State, +scope: String, +value: J.Json, +snapshot: D.History, +selected: D.Model, +reason: A.Reason,
  +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  A.branch(~Change, J.boolean(J.get(value, "scope_changed")),
    (unused => measure(task, A.with_job(A.NoJob{}, entry), Some{reason}, world)),
    (unused => compact_step(Rebuild.receive(progress, value), scope, snapshot, selected, reason, task, entry, world)))

def compact_matched(+same: Bool, +scope: String, +snapshot: D.History, +selected: D.Model, +reason: A.Reason, +progress: Bounded.State,
  +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match same:
    case False{}: Unchanged{}
    case True{}:
      A.branch(~Change, relevant(snapshot, selected, task),
        (unused =>
          A.branch(~Change, error,
            (unused =>
              failed(task, entry, J.text(J.get(value, "message")), State.registry(world))),
            (unused =>
              compact_observed(progress, scope, value, snapshot, selected, reason, task, entry, world)),))
        (unused =>
          entry_change(D.task_id(task), A.with_job(A.NoJob{}, entry), None{}, False{}, Nil{}, State.registry(world))))

def compact_job(+job: A.Job, +ticket: Nat, +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match job:
    case A.Compacting{+expected, +snapshot, +selected, +reason, +progress, +scope}:
      compact_matched(Nat.is_eq(ticket, expected), scope, snapshot, selected, reason, progress, value, error, task, entry, world)
    case _: Unchanged{}

def compact_result(+ticket: Nat, +value: J.Json, +error: Bool, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  compact_job(A.job(entry), ticket, value, error, task, entry, world)

def with_activity(+snapshot: D.History, +now: Nat, +scope: String, +deadline: Nat, +entry: A.Entry) -> A.Entry:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +previous_deadline, +cache, +previous_scope} = entry
  A.Entry{measurement, job, useful, maintained, attempted, now, deadline, snapshot, scope}

def activity_target(+target: Maybe<&2, A.Target>, +snapshot: D.History, +now: Nat, +scope: String, +entry: A.Entry) -> A.Entry:
  match target:
    case None{}: with_activity(snapshot, now, scope, 0n, entry)
    case Some{A.Target{+profile, +window, +reserve, +ttl, +method}}:
      A.branch(~A.Entry, Nat.is_eq(ttl, 0n),
        (unused => with_activity(snapshot, now, scope, 0n, entry)),
        (unused => with_activity(snapshot, now, scope, Nat.add(now, ttl), entry)))

def active_completion(+completion: A.Completion, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match completion:
    case A.MeasuredInput{+id, +ticket, +value, +error}: measurement_result(ticket, value, error, task, entry, world)
    case A.Completed{+id, +ticket, +value, +error}: compact_result(ticket, value, error, task, entry, world)
    case A.Activity{+id, +source_length, +now, +scope}:
      entry_change(id, activity_target(current_target(task, State.registry(world)), Same.drop_history(Nat.sub(D.history_length(D.task_history(task)), source_length), D.task_history(task)), now, scope, entry), None{}, False{}, Nil{}, with_now(now, State.registry(world)))
    case _: Unchanged{}

def status_completion(status: D.Status, completion: A.Completion, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  match status completion:
    case _ A.Activity{+id, +source_length, +now, +scope}: active_completion(A.Activity{id, source_length, now, scope}, task, entry, world)
    case D.Active{} other: active_completion(other, task, entry, world)
    case D.Archived{} _: Unchanged{}
    case _ _: entry_change(D.task_id(task), A.recover_entry(entry), None{}, False{}, Nil{}, State.registry(world))

def task_completion(+completion: A.Completion, +task: D.Task, +entry: A.Entry, +world: M.World()) -> Change:
  status_completion(D.task_status(task), completion, task, entry, world)

def task_result(+found: Maybe<&2, D.Task>, +completion: A.Completion, +id: Nat, +world: M.World()) -> Change:
  match found:
    case None{}: Unchanged{}
    case Some{+task}: task_completion(completion, task, A.entry(id, State.registry(world)), world)

def configure(+policy: A.Policy, +now: Nat, +state: A.State) -> Change:
  A.State{+previous, +entries, +before, +timer} = state
  Change{A.State{policy, A.recover_entries(entries), Nat.max(now, before), 0n}, None{}, False{}, Nil{}}

def clock(+now: Nat, +state: A.State) -> Change:
  A.State{+policy, +entries, +before, +timer} = state
  Change{A.State{policy, entries, Nat.max(now, before), 0n}, None{}, False{}, Nil{}}

def resolve(+completion: A.Completion, +world: M.World()) -> Change:
  match completion:
    case A.Configure{+policy, +now}: configure(policy, now, State.registry(world))
    case A.Clock{+now}: clock(now, State.registry(world))
    case A.Activity{+id, +source_length, +now, +scope}: task_result(State.task(id, world), A.Activity{id, source_length, now, scope}, id, world)
    case A.MeasuredInput{+id, +ticket, +value, +error}: task_result(State.task(id, world), A.MeasuredInput{id, ticket, value, error}, id, world)
    case A.Completed{+id, +ticket, +value, +error}: task_result(State.task(id, world), A.Completed{id, ticket, value, error}, id, world)

def pending_measurement(+value: A.Measurement) -> Bool:
  match value:
    case A.Measuring{+ticket, +history, +model, +scope}: True{}
    case _: False{}

def validating(+job: A.Job) -> Bool:
  match job:
    case A.Resuming{snapshot, model, A.Manual{}}: True{}
    case A.Compacting{ticket, snapshot, model, A.Manual{}, progress, scope}: True{}
    case A.Preparing{+ticket, +snapshot, +model, +reason, +scope}: True{}
    case A.Validating{+ticket, +snapshot, +model, +reason, +candidate, +preview, +scope}: True{}
    case _: False{}

def hard_wait(+observation: A.Measurement, +job: A.Job, +policy: A.Policy) -> Bool:
  match observation:
    case A.Measured{+history, +model, +scope, +tokens, +window, +reserve}: must_wait(policy, tokens, window, reserve) && A.job_pending(job)
    case A.Oversized{+history, +model, +scope, +window, +reserve}: True{}
    case _: False{}

def failed_measurement(+value: A.Measurement) -> Bool:
  match value:
    case A.MeasurementFailed{+history, +model}: True{}
    case _: False{}

def target_blocked(+target: Maybe<&2, A.Target>, +task: D.Task, +state: A.State) -> Bool:
  match target:
    case None{}: False{}
    case Some{+target}:
      +entry = A.entry(D.task_id(task), state)
      failed_measurement(A.measurement(entry)) || validating(A.job(entry)) || pending_measurement(A.measurement(entry)) ||
        Bool.not(A.fresh(A.measurement(entry), D.task_history(task), model(task))) ||
        hard_wait(A.measurement(entry), A.job(entry), A.settings(state))

def blocked(+task: D.Task, +state: A.State) -> Bool:
  validating(A.job(A.entry(D.task_id(task), state))) || target_blocked(A.target(A.settings(state), model(task)), task, state)

def runnable(+values: +List<D.Task>, +state: A.State) -> Maybe<&2, D.Task>:
  match values:
    case Nil{}: None{}
    case Con{+task, +rest}:
      T.choose_task(D.has_work(D.task_work(task)) && Bool.not(D.is_model_request(D.task_work(task)) && blocked(task, state)), task, runnable(rest, state))

def cancellation(+id: Nat, +ticket: Maybe<&2, Nat>, +rest: +List<A.Effect>) -> +List<A.Effect>:
  match ticket:
    case None{}: rest
    case Some{+ticket}: A.Cancel{id, ticket} <> rest

def cancel_entry(+entry: A.Entry, +task: D.Task, +world: M.World()) -> Change:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  entry_change(D.task_id(task), A.Entry{A.Unmeasured{}, A.NoJob{}, useful, maintained, A.useful(D.task_history(task)), activity, 0n, cache, scope}, None{}, False{},
    cancellation(D.task_id(task), State.measurement_ticket(measurement), cancellation(D.task_id(task), A.job_ticket(job), Nil{})), State.registry(world))

def cancel(+task: D.Task, +world: M.World()) -> Change:
  cancel_entry(A.entry(D.task_id(task), State.registry(world)), task, world)

def idle_policy(+policy: A.Policy, +entry: A.Entry, +task: D.Task, +state: A.State) -> Bool:
  match policy entry:
    case A.Policy{+enabled, +background, +blocking, +lead, +targets} A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope}:
      enabled && idle(task) && alive(D.task_status(task)) && Bool.not(A.job_pending(job)) &&
        Nat.is_lt(maintained, A.useful(D.task_history(task))) && Nat.is_lt(attempted, A.useful(D.task_history(task))) &&
        Context.settled_calls(D.task_history(task), D.task_history(task)) && Nat.is_lt(0n, deadline) && Nat.is_le(Nat.sub(deadline, lead), A.now(state)) &&
        Same.history_extends(1048576n, cache, D.task_history(task))


def idle_due(+entry: A.Entry, +task: D.Task, +state: A.State) -> Bool:
  idle_policy(A.settings(state), entry, task, state)

def synchronized_entry(+task: D.Task, +entry: A.Entry, +state: A.State) -> A.Entry:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  +current = A.useful(D.task_history(task))
  A.branch(~A.Entry, Nat.is_lt(useful, current),
    (unused =>
      A.Entry{measurement, job, current, maintained, attempted, A.now(state), deadline, cache, scope}),
    (unused =>
      A.Entry{measurement, job, useful, maintained, attempted, activity, deadline, cache, scope}))

def synchronize_target(+target: Maybe<&2, A.Target>, +task: D.Task, +entry: A.Entry, +state: A.State, +world: M.World()) -> Change:
  match target:
    case None{}: A.branch(~Change, Maybe.is_some(&2, A.Entry, Finite.find(~A.Entry, A.entries(state), D.task_id(task))),
      (unused => entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, state)), (unused => Unchanged{}))
    case Some{+target}:
      A.branch(~Change, validating(A.job(entry)) || pending_measurement(A.measurement(entry)),
        (unused => entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, state)),
        (unused =>
          A.branch(~Change, idle_due(entry, task, state),
            (unused => measure(task, entry, Some{A.IdleMaintenance{}}, world)),
            (unused =>
              A.branch(~Change, A.fresh(A.measurement(entry), D.task_history(task), model(task)),
                (unused => entry_change(D.task_id(task), entry, None{}, False{}, Nil{}, state)),
                (unused => measure(task, entry, None{}, world)))))))

def dispatch_status(status: D.Status, +task: D.Task, +entry: A.Entry, +state: A.State, +world: M.World()) -> Change:
  match status:
    case D.Active{}: synchronize_target(A.target(A.settings(state), model(task)), task, entry, state, world)
    case D.Archived{}: cancel(task, world)
    case _: Unchanged{}

def synchronize_active(+task: D.Task, +world: M.World()) -> Change:
  +state = State.registry(world)
  +entry = synchronized_entry(task, A.entry(D.task_id(task), state), state)
  dispatch_status(D.task_status(task), task, entry, state, world)

def resume_job(+job: A.Job, +task: D.Task, +world: M.World()) -> Change:
  match job:
    case A.Resuming{+snapshot, +selected, +reason}:
      A.branch(~Change, relevant(snapshot, selected, task),
        (unused =>
          A.branch(~Change, active(D.task_status(task)) && Context.settled_calls(D.task_history(task), D.task_history(task)),
            (unused => measure(task, A.with_job(A.NoJob{}, A.entry(D.task_id(task), State.registry(world))), Some{reason}, world)),
            (unused => Unchanged{}))),
        (unused =>
          cancel(task, world)))
    case _: synchronize_active(task, world)

def synchronize(+task: D.Task, +world: M.World()) -> Change:
  resume_job(A.job(A.entry(D.task_id(task), State.registry(world))), task, world)

def entry_deadline(+entry: A.Entry, +now: Nat, +lead: Nat) -> Nat:
  A.Entry{+measurement, +job, +useful, +maintained, +attempted, +activity, +deadline, +cache, +scope} = entry
  +due = Nat.sub(deadline, lead)
  A.branch(~Nat, Nat.is_lt(maintained, useful) && Nat.is_lt(attempted, useful) && Bool.not(A.job_pending(job)) && Nat.is_lt(now, due),
    (unused =>
      due),
    (unused =>
      0n))

def earlier(+left: Nat, +right: Nat) -> Nat:
  A.branch(~Nat, Nat.is_eq(left, 0n) || (Nat.is_lt(0n, right) && Nat.is_lt(right, left)),
    (unused =>
      right),
    (unused =>
      left))

def next_deadline(+values: +List<Sigma<&2, &2, Nat, (_ => A.Entry)>>, +now: Nat, +lead: Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{(+id, entry), +rest}: earlier(entry_deadline(entry, now, lead), next_deadline(rest, now, lead))

def arm(+state: A.State) -> Change:
  A.State{+policy, +entries, +now, +previous} = state
  A.Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  +deadline = next_deadline(entries, now, lead)
  A.branch(~Change, Nat.is_eq(deadline, previous) || Nat.is_eq(deadline, 0n),
    (unused =>
      Unchanged{}),
    (unused =>
      Change{A.State{policy, entries, now, deadline}, None{}, False{}, [A.ArmClock{deadline}]}))

def manual(+task: D.Task, +world: M.World()) -> Change:
  +entry = A.entry(D.task_id(task), State.registry(world))
  A.branch(~Change, A.job_pending(A.job(entry)),
    (unused => Unchanged{}),
    (unused =>
      A.branch(~Change, Context.settled_calls(D.task_history(task), D.task_history(task)),
        (unused => measure(task, entry, Some{A.Manual{}}, world)),
        (unused => entry_change(D.task_id(task), A.with_job(A.Resuming{D.task_history(task), model(task), A.Manual{}}, entry), None{}, False{}, Nil{}, State.registry(world))))))

def supplied_entry(+snapshot: D.History, entry: A.Entry) -> A.Entry:
  A.Entry{measurement, job, useful, +maintained, +attempted, activity, deadline, cache, scope} = entry
  +captured = A.useful(snapshot)
  A.Entry{A.Unmeasured{}, A.NoJob{}, captured, Nat.max(captured, maintained), Nat.max(captured, attempted), activity, 0n, cache, scope}

def supplied(+summary: String, +task: D.Task, +world: M.World()) -> Change:
  +snapshot = D.task_history(task)
  +state = State.registry(world)
  +entry = A.entry(D.task_id(task), state)
  entry_change(D.task_id(task), supplied_entry(snapshot, entry),
    Some{D.with_history(Context.adopt(snapshot, Context.portable(summary), snapshot), task)}, False{},
    cancellation(D.task_id(task), State.measurement_ticket(A.measurement(entry)),
      cancellation(D.task_id(task), A.job_ticket(A.job(entry)), Nil{})), state)

# This independent interpreter specifies which component and task fields a
# resolved change may write, including ticket allocation and exact effects.

def reserved_world(+reserve: Bool, +world: M.World()) -> M.World():
  match reserve:
    case False{}: world
    case True{}: State.reserve_ticket(world)

def task_world(+task: Maybe<&2, D.Task>, +world: M.World()) -> M.World():
  match task:
    case None{}: world
    case Some{+task}: T.update_world(F.State(), task, world)

def meaning(+change: Change, +world: M.World()) -> M.Decision():
  match change:
    case Unchanged{}: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case Change{+state, +task, +reserve, +effects}:
      C.Decision{task_world(task, reserved_world(reserve, State.store(state, world))),
        D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), State.effects(effects)}

def cancellation_world(+change: Change, +world: M.World()) -> M.World():
  match change:
    case Unchanged{}: world
    case Change{+state, +task, +reserved, +effects}: State.store(state, world)

def cancelled_world(+task: D.Task, +world: M.World()) -> M.World():
  cancellation_world(cancel(task, world), world)

def selected_request(observation: A.Measurement, id: Nat, ticket: Nat, model: D.Model, history: D.History,
  tools: +List<D.Tool>, callable: +List<String>, context: D.TaskContext, fallback_scope: String, fallback_reserve: Nat) -> M.Effect():
  match observation:
    case A.Measured{previous, expected, scope, tokens, window, reserve}:
      Effects.RequestModel{id, ticket, model, history, tools, callable, context, scope, reserve}
    case A.Oversized{previous, expected, scope, window, reserve}:
      Effects.RequestModel{id, ticket, model, history, tools, callable, context, scope, reserve}
    case _: Effects.RequestModel{id, ticket, model, history, tools, callable, context, fallback_scope, fallback_reserve}

def selected_effects(effects: +List<M.Effect()>, +state: A.State) -> +List<M.Effect()>:
  match effects:
    case Nil{}: Nil{}
    case Con{Effects.RequestModel{+id, ticket, model, history, tools, callable, context, scope, reserve}, rest}:
      selected_request(A.measurement(A.entry(id, state)), id, ticket, model, history, tools, callable, context, scope, reserve) <> selected_effects(rest, state)
    case Con{other, rest}: other <> selected_effects(rest, state)

def attach(decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Decision{world, reply, selected_effects(effects, State.registry(world))}

def decision_world(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def combine(before: M.Decision(), after: M.Decision()) -> M.Decision():
  C.Decision{previous, reply, effects} = before
  C.Decision{world, ignored, added} = after
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}

def synchronize_all(tasks: +List<D.Task>, +decision: M.Decision()) -> M.Decision():
  match tasks:
    case Nil{}: decision
    case Con{task, rest}:
      +advanced = combine(decision, meaning(synchronize(task, decision_world(decision)), decision_world(decision)))
      synchronize_all(rest, advanced)

def required_prepare(+decision: M.Decision()) -> M.Decision():
  +advanced = synchronize_all(State.tasks(decision_world(decision)), decision)
  combine(advanced, meaning(arm(State.registry(decision_world(advanced))), decision_world(advanced)))
