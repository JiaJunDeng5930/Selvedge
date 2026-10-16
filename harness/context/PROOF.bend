import Base
import ./MODEL.bend as C
import ./CONTRACT.bend as Spec
import ../DOMAIN.bend as D
import ./patch-proof.bend as Patch

# Production history is retained verbatim. Checkpoints are additional records and
# cannot change the source values reconstructed from that history.
def append(+context: D.HistoryContext, +task: D.Task) ->
  {D.task_history(D.append_context(context, task)) == D.HistoryNode{D.task_history(task), D.ContextMessage{context}} : D.History}:
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def checkpoint_bindings(+history: D.History, summary: String) ->
  {D.context_bindings(D.HistoryNode{history, D.ContextCheckpoint{summary}}) == D.context_bindings(history) : +List<C.Snapshot>}:
  {==}

def context_reconstruction(+history: D.History, +change: C.Change) ->
  {D.context_bindings(D.HistoryNode{history, D.ContextMessage{D.ContextChange{change}}}) == C.apply_change(change, D.context_bindings(history)) : +List<C.Snapshot>}:
  {==}

def diagnostic_contract(known: Bool, message: String, +task: D.Task) ->
  {D.task_contract(D.context_diagnostic(known, message, task)) == D.task_contract(task) : D.Contract}:
  match known task:
    case True{} D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}
    case False{} D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def diagnose_contract(+message: String, +task: D.Task) ->
  {D.task_contract(D.diagnose_context(message, task)) == D.task_contract(task) : D.Contract}:
  diagnostic_contract(D.context_failure_seen(D.task_history(task), message), message, task)

def changed_contract(change: Maybe<&2, C.Change>, unchanged: Bool, +task: D.Task) ->
  {D.task_contract(D.append_context_change(change, unchanged, task)) == D.task_contract(task) : D.Contract}:
  match change unchanged task:
    case Some{change} _ D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}
    case None{} True{} D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}
    case None{} False{} other: diagnose_contract("Context update rejected: invalid revision or patch for tracked source.", other)

def observation_contract(observation: C.Observation, +task: D.Task) ->
  {D.task_contract(D.apply_context_observation(observation, task)) == D.task_contract(task) : D.Contract}:
  match observation:
    case C.Present{+snapshot, +patch}: changed_contract(
      C.observation_change(D.context_bindings(D.task_history(task)), C.Present{snapshot, patch}),
      D.same_observation(C.find(D.context_bindings(D.task_history(task)), C.snapshot_key(snapshot)), snapshot), task)
    case C.Absent{key}: changed_contract(C.observation_change(D.context_bindings(D.task_history(task)), C.Absent{key}), True{}, task)
    case C.ObservationFailure{key, message}: diagnose_contract(String.concat(["Context source observation failed: ", message]), task)

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
  Spec.Evidence{append, checkpoint_bindings, context_reconstruction,
    Patch.unchanged_observation, preserved_contract, Patch.observed_amendment_origin,
    Patch.apply_amendment, Patch.observed_amendment_patch}
