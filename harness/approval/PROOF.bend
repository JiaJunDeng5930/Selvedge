import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./MODEL.bend as A
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ./CONTRACT.bend as Boundary
import ../protocol/PROOF.bend as ProtocolProof
import ../features/MODEL.bend as F
import ../../bendlib/effects.bend as Effects
import ./HOOKS.bend as Hooks
import ../INVARIANTS.bend as I
import ../execution/notifications.bend as N
import ../transport/presentation.bend as View
import ../../bendlib/json.bend as J
import ../CONTRACT.bend as AContract

def checked_calculation_checked(+reference: D.PluginRef, +expected: D.PluginRef, +outcome: D.HookOutcome, +call: D.Call, +pending: +List<D.PluginRef>, accepted: Bool,
  observed: {Hooks.checked_accepts(Hooks.CheckedRequest{reference, expected, outcome, call, pending}) == accepted : Bool}) ->
  {Hooks.checked_admitted(Categories.admit_checked(Hooks.CheckedRequest, Hooks.checked_accepts, Hooks.CheckedRequest{reference, expected, outcome, call, pending}, accepted, observed), Hooks.CheckedRequest{reference, expected, outcome, call, pending}) ==
    Hooks.checked_calculation(accepted, outcome, call, pending) : Hooks.Progress}:
  match accepted:
    case False{}: {==}
    case True{}: {==}

def checked_calculation_semantics(+reference: D.PluginRef, +expected: D.PluginRef, +outcome: D.HookOutcome, +call: D.Call, +pending: +List<D.PluginRef>) ->
  {Hooks.checked(reference, expected, outcome, call, pending) == Hooks.checked_calculation(Hooks.checked_accepts(Hooks.CheckedRequest{reference, expected, outcome, call, pending}), outcome, call, pending) : Hooks.Progress}:
  checked_calculation_checked(reference, expected, outcome, call, pending, Hooks.checked_accepts(Hooks.CheckedRequest{reference, expected, outcome, call, pending}), {==})

def record_matching_calculation_checked(+task_id: Nat, +owner: Nat, +call_id: String, +id: String, +state: Hooks.Progress, +reference: D.PluginRef, +outcome: D.HookOutcome, accepted: Bool,
  observed: {Hooks.record_matching_accepts(Hooks.RecordMatchingRequest{task_id, owner, call_id, id, state, reference, outcome}) == accepted : Bool}) ->
  {Hooks.record_matching_admitted(Categories.admit_checked(Hooks.RecordMatchingRequest, Hooks.record_matching_accepts, Hooks.RecordMatchingRequest{task_id, owner, call_id, id, state, reference, outcome}, accepted, observed), Hooks.RecordMatchingRequest{task_id, owner, call_id, id, state, reference, outcome}) ==
    Hooks.record_matching_calculation(accepted, state, reference, outcome) : Hooks.Progress}:
  match accepted:
    case False{}: {==}
    case True{}: {==}

def record_matching_calculation_semantics(+task_id: Nat, +owner: Nat, +call_id: String, +id: String, +state: Hooks.Progress, +reference: D.PluginRef, +outcome: D.HookOutcome) ->
  {Hooks.record_matching(task_id, owner, call_id, id, state, reference, outcome) == Hooks.record_matching_calculation(Hooks.record_matching_accepts(Hooks.RecordMatchingRequest{task_id, owner, call_id, id, state, reference, outcome}), state, reference, outcome) : Hooks.Progress}:
  record_matching_calculation_checked(task_id, owner, call_id, id, state, reference, outcome, Hooks.record_matching_accepts(Hooks.RecordMatchingRequest{task_id, owner, call_id, id, state, reference, outcome}), {==})


def human_waits(call:D.Call, remaining:+List<D.Attempt>, task:D.Task, world:M.World()) ->
  {P.decision_effects(P.approval_request(D.HumanReviewer{}, call, remaining, task, world)) == Nil{} : +List<M.Effect()>}:
  C.Frame{core, +board} = world
  {==}

def context_frame(operation:D.Operation(), reviewer:D.ApprovalReviewer, reason:String, +task:D.Task) ->
  {D.task_context(A.permitted(operation, reviewer, reason, task)) == D.task_context(task) : D.TaskContext}:
  D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified} = task
  {==}

def Boundary.approval_boundary():
  Boundary.ApprovalBoundary{
    (resolution => world => Laws.review_semantics(resolution, world)),
    (call => remaining => task => world => human_waits(call, remaining, task, world)),
    (profile => call => remaining => task => state => board => {==}),
    (operation => reviewer => reason => task => context_frame(operation, reviewer, reason, task)),
    ((profile => operation => task => outcome => {==}), (operation => task => outcome => {==})),
    (reviewer => origin => operation => task => outcome => {==}),
    (id => call => announced => reviewer => task => value => error => {==}),
    (id => lineage => contract => current => history => queued => phase => operations => notified => {==})}

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
  Equal.trans(Hooks.Progress,
    Hooks.record_matching(other, owner, id, id, state, plugin, outcome),
    Hooks.record_matching_calculation(Nat.is_eq(other, owner) && String.eq(id, id), state, plugin, outcome), state,
    record_matching_calculation_semantics(other, owner, id, id, state, plugin, outcome),
    Equal.cong(Bool, Hooks.Progress,
      (same => Hooks.record_matching_calculation(same && String.eq(id, id), state, plugin, outcome)),
      Nat.is_eq(other, owner), False{}, different))

def Laws.hook_record_order(expected, actual, call, pending, outcome):
  checked_calculation_semantics(actual, expected, outcome, call, pending)

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

def AContract.plugin_boundary():
  AContract.PluginBoundary{
    (tool => attempt => remaining => task => world => Laws.hook_gateway(tool, attempt, remaining, task, world)),
    (plugin => pending => tool => call => remaining => task => world => Laws.hook_before_route(plugin, pending, tool, call, remaining, task, world)),
    (call => arguments => Laws.hook_rewrite_identity(call, arguments)),
    (reason => call => pending => Laws.hook_deny(reason, call, pending)),
    (reason => call => pending => Laws.hook_failure(reason, call, pending)),
    (plugin => outcome => Laws.hook_rejected_is_absorbing(plugin, outcome)),
    (owner => other => id => plugin => outcome => pending => state => different =>
      Laws.hook_foreign_owner(owner, other, id, plugin, outcome, pending, state, different)),
    (source => before => decision => Laws.plugin_observation_extension(source, before, decision))}


def Boundary.review_construction_meaning(StateRest, EffectRest, request):
  A.ReviewRequest{origin, task_id, operation_id, outcome, world} = request
  {==}


def review_consumer_calculation(-StateRest: Data, -EffectRest: Data, +request: A.ReviewRequest<StateRest>, +resolution: A.Resolution,
  evidence: {resolution == A.review_resolution(StateRest, request) : A.Resolution}) ->
  {A.meaning_calculation(StateRest, EffectRest, resolution, Boundary.review_world(StateRest, request)) ==
    A.meaning_calculation(StateRest, EffectRest, A.review_resolution(StateRest, request), Boundary.review_world(StateRest, request)) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  A.ReviewRequest{origin, task_id, operation_id, outcome, +world} = request
  Equal.cong(A.Resolution, C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>,
    (value => A.meaning_calculation(StateRest, EffectRest, value, world)), resolution, A.review_resolution(StateRest, request), evidence)

def Boundary.review_consumer_correspondence(StateRest, EffectRest, member):
  Categories.Membership{Categories.Construction{request, resolution}, evidence} = member
  A.ReviewRequest{origin, task_id, operation_id, outcome, world} = request
  review_consumer_calculation(StateRest, EffectRest, A.ReviewRequest{origin, task_id, operation_id, outcome, world}, resolution, evidence)
