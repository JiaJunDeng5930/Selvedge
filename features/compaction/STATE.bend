import Base
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/equality.bend as Same
import ../../harness/compaction/MODEL.bend as Bounded
import ../../harness/compaction/PROGRAM.bend as Rebuild
import ./MODEL.bend as A
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/effects.bend as Effects
import ../../harness/tasks/PROGRAM.bend as T

def registry(+world: M.World()) -> A.State:
  F.compaction(C.rest(D.State, F.State(), world))

def store(+state: A.State, +world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_compaction(state, features), world)

def tasks(+world: M.World()) -> +List<D.Task>:
  D.state_tasks(C.local(D.State, F.State(), world))

def task(+id: Nat, +world: M.World()) -> Maybe<&2, D.Task>:
  T.find(tasks(world), id)

def ticket(+world: M.World()) -> Nat:
  D.state_next_ticket(C.local(D.State, F.State(), world))

def reserve_ticket(+world: M.World()) -> M.World():
  C.map_local(D.State, F.State(), +state => D.with_state_next_ticket(1n+D.state_next_ticket(state), state), world)

def effect(+effect: A.Effect) -> M.Effect():
  Effects.FeatureEffect{F.CompactionEffect{effect}}

def effects(+values: +List<A.Effect>) -> +List<M.Effect()>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}: effect(value) <> effects(rest)

def optional_ticket(+value: Maybe<&2, Nat>, +rest: +List<Nat>) -> +List<Nat>:
  match value:
    case None{}: rest
    case Some{+ticket}: ticket <> rest

def measurement_ticket(+value: A.Measurement) -> Maybe<&2, Nat>:
  match value:
    case A.Measuring{+ticket, +history, +model, +scope}: Some{ticket}
    case _: None{}

def pending(+values: +List<Sigma<&2, &2, Nat, (_ => A.Entry)>>) -> +List<Nat>:
  match values:
    case Nil{}: Nil{}
    case Con{(+id, +entry), +rest}:
      optional_ticket(measurement_ticket(A.measurement(entry)), optional_ticket(A.job_ticket(A.job(entry)), pending(rest)))

def effect_ticket(+effect: A.Effect) -> Maybe<&2, Nat>:
  match effect:
    case A.Scope{+id, +ticket, +model}: Some{ticket}
    case A.Measure{+id, +ticket, +model, +history, +tools, +context, +callable, +scope, +validating}: Some{ticket}
    case A.Compact{+id, +ticket, +model, +history, +tools, +context, +target, +progress, +scope}: Some{ticket}
    case _: None{}

def ticket_same(value: Maybe<&2, Nat>, expected: Nat) -> Bool:
  match value:
    case None{}: False{}
    case Some{+ticket}: Nat.is_eq(ticket, expected)

def scope_pending(job: A.Job, measurement: A.Measurement, ticket: Nat, +model: D.Model) -> Bool:
  match job measurement:
    case A.Preparing{+expected, +snapshot, +selected, +reason, None{}} _: Nat.is_eq(expected, ticket) && Same.model(selected, model)
    case A.Validating{+expected, +snapshot, +selected, +reason, +candidate, +preview, None{}} _: Nat.is_eq(expected, ticket) && Same.model(selected, model)
    case _ A.Measuring{+expected, +history, +selected, None{}}: Nat.is_eq(expected, ticket) && Same.model(selected, model)
    case _ _: False{}

def measure_pending(job: A.Job, measurement: A.Measurement, ticket: Nat, +model: D.Model, +history: D.History, +scope: String) -> Bool:
  match job measurement:
    case A.Preparing{+expected, +snapshot, +selected, +reason, Some{+current_scope}} _:
      Nat.is_eq(expected, ticket) && Same.model(selected, model) && Same.history(1048576n, snapshot, history) && String.eq(current_scope, scope)
    case A.Validating{+expected, +snapshot, +selected, +reason, +candidate, +preview, Some{+current_scope}} _:
      Nat.is_eq(expected, ticket) && Same.model(selected, model) && Same.history(1048576n, preview, history) && String.eq(current_scope, scope)
    case _ A.Measuring{+expected, +snapshot, +selected, Some{+current_scope}}:
      Nat.is_eq(expected, ticket) && Same.model(selected, model) && Same.history(1048576n, snapshot, history) && String.eq(current_scope, scope)
    case _ _: False{}

def compact_pending(job: A.Job, ticket: Nat, model: D.Model, history: D.History, progress: Bounded.State, +scope: String) -> Bool:
  match job:
    case A.Compacting{+expected, +snapshot, +selected, +reason, +previous, +job_scope}:
      Nat.is_eq(expected, ticket) && Same.model(selected, model) && Same.history(1048576n, snapshot, history) &&
        String.eq(job_scope, scope) && Same.json(1048576n, Rebuild.plan_json(previous), Rebuild.plan_json(progress))
    case _: False{}

def effect_entry(effect: A.Effect, +entry: A.Entry, state: A.State) -> Bool:
  match effect:
    case A.Scope{+id, +ticket, +model}: scope_pending(A.job(entry), A.measurement(entry), ticket, model)
    case A.Measure{+id, +ticket, +model, +history, +tools, +context, +callable, +scope, +validating}:
      measure_pending(A.job(entry), A.measurement(entry), ticket, model, history, scope)
    case A.Compact{+id, +ticket, +model, +history, +tools, +context, +target, +progress, +scope}: compact_pending(A.job(entry), ticket, model, history, progress, scope)
    case A.ArmClock{+deadline}: Nat.is_eq(deadline, A.timer(state))
    case A.Cancel{+id, +ticket}: Bool.not(ticket_same(A.job_ticket(A.job(entry)), ticket)) && Bool.not(ticket_same(measurement_ticket(A.measurement(entry)), ticket))

def effect_valid(effect: A.Effect, +state: A.State) -> Bool:
  match effect:
    case A.Scope{+id, +ticket, +model}: effect_entry(A.Scope{id, ticket, model}, A.entry(id, state), state)
    case A.Measure{+id, +ticket, +model, +history, +tools, +context, +callable, +scope, +validating}:
      effect_entry(A.Measure{id, ticket, model, history, tools, context, callable, scope, validating}, A.entry(id, state), state)
    case A.Compact{+id, +ticket, +model, +history, +tools, +context, +target, +progress, +scope}:
      effect_entry(A.Compact{id, ticket, model, history, tools, context, target, progress, scope}, A.entry(id, state), state)
    case A.ArmClock{+deadline}: Nat.is_eq(deadline, A.timer(state))
    case A.Cancel{+id, +ticket}: effect_entry(A.Cancel{id, ticket}, A.entry(id, state), state)

def source_valid(job: A.Job, +history: D.History) -> Bool:
  match job:
    case A.NoJob{}: True{}
    case A.Resuming{snapshot, model, reason}: Same.history_extends(1048576n, snapshot, history)
    case A.Preparing{snapshot_ticket, snapshot, model, reason, scope}: Same.history_extends(1048576n, snapshot, history)
    case A.Compacting{ticket, snapshot, model, reason, progress, scope}: Same.history_extends(1048576n, snapshot, history)
    case A.Validating{ticket, snapshot, model, reason, candidate, preview, scope}: Same.history_extends(1048576n, snapshot, history)

def entry_valid(found: Maybe<&2, D.Task>, +entry: A.Entry) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}: Nat.is_le(A.maintained_revision(entry), A.current_revision(entry)) &&
      Nat.is_le(A.attempted_revision(entry), A.useful(D.task_history(task))) && Nat.is_le(A.current_revision(entry), A.useful(D.task_history(task))) && source_valid(A.job(entry), D.task_history(task))

def entries_valid(entries: +List<Sigma<&2, &2, Nat, (_ => A.Entry)>>, +tasks: +List<D.Task>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, entry), +rest}: Bool.not(Maybe.is_some(&2, A.Entry, Finite.find(~A.Entry, rest, id))) && entry_valid(T.find(tasks, id), entry) && entries_valid(rest, tasks)

def valid(+world: M.World()) -> Bool:
  +state = registry(world)
  A.valid_policy(A.settings(state)) && entries_valid(A.entries(state), tasks(world))
