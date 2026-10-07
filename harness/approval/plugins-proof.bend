import Base
import ../features/MODEL.bend as F
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ./HOOKS.bend as Hooks
import ../INVARIANTS.bend as I
import ../execution/notifications.bend as N
import ../transport/presentation.bend as View
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../../bendlib/stdlib.bend as Std
import ../CONTRACT.bend as A

def Laws.hook_gateway(tool, attempt, remaining, task, world):
  {==}

def Laws.hook_before_route(plugin, pending, tool, call, remaining, task, world):
  {==}

def Laws.hook_rewrite_identity(call, arguments):
  D.Call{id, name, original} = call
  ({==}, {==})

def Laws.hook_rejected_is_absorbing(plugin, outcome):
  {==}

def Laws.hook_deny(reason, call, pending):
  {==}

def Laws.hook_failure(reason, call, pending):
  {==}

def Laws.hook_foreign_owner(owner, other, id, plugin, outcome, pending, state, different):
  Equal.cong(Bool, Hooks.Progress,
    (same => Hooks.record_matching(same && String.eq(id, id), state, plugin, outcome)),
    Nat.is_eq(other, owner), False{}, different)

def Laws.hook_record_order(expected, actual, call, pending, outcome):
  {==}

def Laws.event_kind_roundtrip(kind):
  match kind:
    case D.TaskCreated{}: {==}
    case D.TaskChanged{}: {==}
    case D.ModelStarted{}: {==}
    case D.ModelSettled{}: {==}
    case D.ToolRequested{}: {==}
    case D.ToolDispatched{}: {==}
    case D.ToolSettled{}: {==}
    case D.HookSettled{}: {==}
    case D.Recovered{}: {==}
    case D.Configured{}: {==}

def Laws.child_return_serialization(owner, id, branch):
  {==}

def self(+decision: M.Decision()) -> Laws.ObservationExtension<decision, decision>:
  Laws.ObservationExtension{{==}, {==}, {==}}

def core_append(effects: +List<M.Effect()>, +events: +List<D.Notice>) ->
  {N.core(List.append(&2, M.Effect(), effects, [Effects.NotifyPlugins{events}])) == N.core(effects) : +List<M.Effect()>}:
  match effects:
    case Nil{}: {==}
    case Con{effect, +rest}:
      Equal.cong(+List<M.Effect()>, +List<M.Effect()>, (tail => N.keep_core(effect, tail)),
        N.core(List.append(&2, M.Effect(), rest, [Effects.NotifyPlugins{events}])), N.core(rest), core_append(rest, events))

def appended(events: +List<D.Notice>, +decision: M.Decision()) -> Laws.ObservationExtension<decision, N.append(events, decision)>:
  match events decision:
    case Nil{} _: self(decision)
    case Con{first, rest} C.Decision{world, reply, effects}:
      Laws.ObservationExtension{{==}, {==}, core_append(effects, first <> rest)}

def chosen(fits: Bool, +enriched: M.Decision(), +plain: M.Decision(), certificate: Laws.ObservationExtension<plain, enriched>) ->
  Laws.ObservationExtension<plain, N.choose(fits, enriched, plain)>:
  match fits:
    case True{}: certificate
    case False{}: self(plain)

def fitted(rendered: Result<&2, &2, String, String>, bytes: U32, +enriched: M.Decision(), +plain: M.Decision(),
  certificate: Laws.ObservationExtension<plain, enriched>) -> Laws.ObservationExtension<plain, N.fit(rendered, bytes, enriched, plain)>:
  match rendered:
    case Fail{reason}: self(plain)
    case Done{text}: chosen(Nat.is_le(J.utf8_length(text), U32.to_nat(bytes)), enriched, plain, certificate)

def admitted(+durable: Bool, previous: M.World(), +enriched: M.Decision(), +plain: M.Decision(),
  certificate: Laws.ObservationExtension<plain, enriched>) -> Laws.ObservationExtension<plain, N.admit(durable, previous, enriched, plain)>:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, D.ExecutionLimits{steps, render, +bytes}, projects}, +board} = previous
  fitted(J.render(render, J.One{View.envelope(durable, enriched)}), bytes, enriched, plain, certificate)

def enrichment(+source: M.Input, +before: M.World(), +decision: M.Decision()) -> Laws.ObservationExtension<decision, N.enrich(source, before, decision)>:
  C.Decision{+after, reply, +effects} = decision
  +events = List.append(&2, D.Notice, N.input(source, before, after), List.append(&2, D.Notice,
    N.tasks(D.state_tasks(C.local(D.State, F.State(), after)), D.state_tasks(C.local(D.State, F.State(), before))), N.dispatched(I.live_effects(effects, D.state_tasks(C.local(D.State, F.State(), after))), D.state_tasks(C.local(D.State, F.State(), after)))))
  admitted(M.durable(source), before, N.append(events, decision), decision, appended(events, decision))

def enabled(enabled: Bool, source: M.Input, before: M.World(), +decision: M.Decision()) ->
  Laws.ObservationExtension<decision, N.enabled(enabled, source, before, decision)>:
  match enabled:
    case False{}: self(decision)
    case True{}: enrichment(source, before, decision)

def Laws.plugin_observation_extension(source, before, decision):
  enabled(M.durable(source), source, before, decision)

def Laws.plugin_observation_budget_failure(reason, bytes, enriched, plain):
  {==}

def A.plugin_boundary():
  A.PluginBoundary{
    (tool => attempt => remaining => task => world => Laws.hook_gateway(tool, attempt, remaining, task, world)),
    (plugin => pending => tool => call => remaining => task => world => Laws.hook_before_route(plugin, pending, tool, call, remaining, task, world)),
    (call => arguments => Laws.hook_rewrite_identity(call, arguments)),
    (reason => call => pending => Laws.hook_deny(reason, call, pending)),
    (reason => call => pending => Laws.hook_failure(reason, call, pending)),
    (plugin => outcome => Laws.hook_rejected_is_absorbing(plugin, outcome)),
    (owner => other => id => plugin => outcome => pending => state => different =>
      Laws.hook_foreign_owner(owner, other, id, plugin, outcome, pending, state, different)),
    (source => before => decision => Laws.plugin_observation_extension(source, before, decision))}
