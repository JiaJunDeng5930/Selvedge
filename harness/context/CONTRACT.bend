import Base
import ./MODEL.bend as C
import ../DOMAIN.bend as D

# The observation carries the new value separately from the proposed patch.
# Acceptance must establish that executing that patch produces the observation.
def amendment_patch(change: Maybe<&2, C.Change>, previous: C.Value, observed: C.Value) -> Bool:
  match change:
    case None{}: True{}
    case Some{C.Amend{key, base, revision, patch}}: C.patch_matches(C.apply_patch(previous, patch), observed)
    case _: False{}

def AmendmentOrigin(+change: Maybe<&2, C.Change>, +key: C.Key, +base: String, +revision: String, +patch: C.Patch) -> Type:
  match change:
    case None{}: Unit
    case Some{actual}: {actual == C.Amend{key, base, revision, patch} : C.Change}

type Evidence is Type:
  Evidence{
    append: @+context:D.HistoryContext -> @+task:D.Task ->
      {D.task_history(D.append_context(context, task)) == D.HistoryNode{D.task_history(task), D.ContextMessage{context}} : D.History},
    checkpoint_bindings: @+history:D.History -> @summary:String ->
      {D.context_bindings(D.HistoryNode{history, D.ContextCheckpoint{summary}}) == D.context_bindings(history) : +List<C.Snapshot>},
    context_reconstruction: @+history:D.History -> @+change:C.Change ->
      {D.context_bindings(D.HistoryNode{history, D.ContextMessage{D.ContextChange{change}}}) == C.apply_change(change, D.context_bindings(history)) : +List<C.Snapshot>},
    unchanged_observation: @+key:C.Key -> @+base:String -> @+value:C.Value -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      @same:{C.same_value(value, C.snapshot_value(observed)) == True{} : Bool} ->
      {C.observed_change(Some{C.Snapshot{key, base, value}}, observed, patch) == None{} : Maybe<&2, C.Change>},
    preserved_contract: @+task:D.Task -> @observations:+List<C.Observation> ->
      {D.task_contract(D.apply_context_observations(task, observations)) == D.task_contract(task) : D.Contract},
    accepted_origin: @+key:C.Key -> @+base:String -> @+value:C.Value -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      AmendmentOrigin(C.observed_change(Some{C.Snapshot{key, base, value}}, observed, patch), key, base, C.snapshot_revision(observed), patch),
    applied_amendment: @+bindings:+List<C.Snapshot> -> @+key:C.Key -> @+base:String -> @+previous_revision:String -> @+previous:C.Value -> @+revision:String -> @+patch:C.Patch -> @+value:C.Value ->
      @found:{C.find(bindings, key) == Some{C.Snapshot{key, previous_revision, previous}} : Maybe<&2, C.Snapshot>} ->
      @base_matches:{String.eq(previous_revision, base) == True{} : Bool} ->
      @patched:{C.apply_patch(previous, patch) == Some{value} : Maybe<&2, C.Value>} ->
      {C.apply_change(C.Amend{key, base, revision, patch}, bindings) == C.Snapshot{key, revision, value} <> C.remove_binding(bindings, key) : +List<C.Snapshot>},
    accepted_patch: @+key:C.Key -> @+base:String -> @+value:C.Value -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      {amendment_patch(C.observed_change(Some{C.Snapshot{key, base, value}}, observed, patch), value, C.snapshot_value(observed)) == True{} : Bool}
  }
