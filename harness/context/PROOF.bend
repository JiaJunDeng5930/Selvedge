import Base
import ./MODEL.bend as C
import ./CONTRACT.bend as Spec
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ./patch-proof.bend as Patch
import ./constructor-proof.bend as Constructor

# Production history is retained verbatim. Replacement windows are additional
# records and cannot change source values reconstructed from that history.
def append(+context: D.HistoryContext, +task: D.Task) ->
  {D.task_history(D.append_context(context, task)) == D.HistoryNode{D.task_history(task), D.ContextMessage{context}} : D.History}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def replacement_bindings(+history: D.History, value: J.Json) ->
  {D.context_bindings(D.HistoryNode{history, D.ContextReplacement{value}}) == D.context_bindings(history) : +List<C.Snapshot>}:
  {==}

def context_reconstruction(+history: D.History, +change: C.Change) ->
  {D.context_bindings(D.HistoryNode{history, D.ContextMessage{D.ContextChange{change}}}) == C.apply_change(change, D.context_bindings(history)) : +List<C.Snapshot>}:
  {==}

def diagnostic_contract(known: Bool, message: String, +task: D.Task) ->
  {D.task_contract(D.context_diagnostic(known, message, task)) == D.task_contract(task) : D.Contract}:
  match known task:
    case True{} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}
    case False{} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def diagnose_contract(+message: String, +task: D.Task) ->
  {D.task_contract(D.diagnose_context(message, task)) == D.task_contract(task) : D.Contract}:
  diagnostic_contract(D.context_failure_seen(D.task_history(task), message), message, task)

def resolution_contract(resolution: C.ObservationResolution, +task: D.Task) ->
  {D.task_contract(D.apply_context_resolution(resolution, task)) == D.task_contract(task) : D.Contract}:
  match resolution task:
    case C.ObservationChanged{change} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}
    case C.ObservationUnchanged{} other: {==}
    case C.ObservationRejected{message} other: diagnose_contract(message, other)

def observation_contract(observation: C.Observation, +task: D.Task) ->
  {D.task_contract(D.apply_context_observation(observation, task)) == D.task_contract(task) : D.Contract}:
  resolution_contract(C.observation_resolution(D.context_bindings(D.task_history(task)), observation), task)

def observations_contract(+observations: +List<C.Observation>, +task: D.Task) ->
  {D.task_contract(D.context_observations_go(observations, task)) == D.task_contract(task) : D.Contract}:
  match observations:
    case Nil{}: {==}
    case Con{+observation, rest}:
      Equal.trans(D.Contract,
        D.task_contract(D.context_observations_go(rest, D.apply_context_observation(observation, task))),
        D.task_contract(D.apply_context_observation(observation, task)), D.task_contract(task),
        observations_contract(rest, D.apply_context_observation(observation, task)), observation_contract(observation, task))

def preserved_contract(+task: D.Task, observations: +List<C.Observation>) ->
  {D.task_contract(D.apply_context_observations(task, observations)) == D.task_contract(task) : D.Contract}:
  observations_contract(observations, task)

def instance() -> Spec.Evidence:
  Spec.Evidence{append, replacement_bindings, context_reconstruction,
    Patch.unchanged_observation, preserved_contract, Patch.observed_amendment_origin,
    Patch.apply_amendment, Patch.observed_amendment_patch, Patch.accepted_snapshot, Patch.invalid_snapshot_rejected, Constructor.family}
