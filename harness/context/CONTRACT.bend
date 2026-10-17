import Base
import ./MODEL.bend as C
import ../DOMAIN.bend as D
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J

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

def AcceptedObservation(change: Maybe<&2, C.Change>, +observed: C.Snapshot) -> Type:
  match change:
    case None{}: Unit
    case Some{actual}: {C.valid_snapshot(observed) == True{} : Bool}

type SnapshotConstruction<-definition: C.Definition, -identity: +List<C.FieldValue>, -revision: String, -fields: +List<C.FieldValue>, -snapshot: C.Snapshot> is Type:
  SnapshotConstruction{
    origin: {snapshot == C.Snapshot{C.ContextKey{definition, identity}, revision, C.Record{C.definition_kind(definition), fields}} : C.Snapshot},
    valid: {C.valid_snapshot(snapshot) == True{} : Bool}
  }

def ConstructedSnapshot(result: Maybe<&2, C.Snapshot>, +definition: C.Definition, +identity: +List<C.FieldValue>, +revision: String, +fields: +List<C.FieldValue>) -> Type:
  match result:
    case None{}: Unit
    case Some{snapshot}: SnapshotConstruction<definition, identity, revision, fields, snapshot>

def ValidSnapshot(result: Maybe<&2, C.Snapshot>) -> Type:
  match result:
    case None{}: Unit
    case Some{snapshot}: {C.valid_snapshot(snapshot) == True{} : Bool}

def FieldNames(result: Maybe<&2, +List<C.FieldValue>>, +fields: +List<C.FieldValue>) -> Type:
  match result:
    case None{}: Unit
    case Some{updated}: {C.value_field_names(updated) == C.value_field_names(fields) : +List<String>}

type ValueSchema<-kind: String, -fields: +List<C.FieldValue>, -updated: C.Value> is Type:
  ValueSchema{
    kind: {C.Record{kind, C.value_fields(updated)} == updated : C.Value},
    fields: {C.value_field_names(C.value_fields(updated)) == C.value_field_names(fields) : +List<String>}
  }

def PatchedSchema(result: Maybe<&2, C.Value>, +value: C.Value) -> Type:
  match result value:
    case None{} _: Unit
    case Some{updated} C.Record{kind, fields}: ValueSchema<kind, fields, updated>

# A declaration instantiates these laws over the exact production constructors
# and interpreters. No law below enumerates the installed context kinds.
type DefinitionEvidence<-definition: C.Definition> is Type:
  DefinitionEvidence{
    construction: @+identity:+List<C.FieldValue> -> @+revision:String -> @+fields:+List<C.FieldValue> ->
      ConstructedSnapshot(C.construct_snapshot(definition, identity, revision, fields), definition, identity, revision, fields),
    value_roundtrip: @+value:C.Value -> {C.value(C.value_json(value)) == Some{value} : Maybe<&2, C.Value>},
    decoded_snapshot: @+registry:+List<C.Definition> -> @+item:J.Json -> ValidSnapshot(C.snapshot(registry, item)),
    patch_schema: @+value:C.Value -> @+patch:C.Patch -> PatchedSchema(C.apply_patch(value, patch), value),
    accepted_snapshot: @+previous:Maybe<&2, C.Snapshot> -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      AcceptedObservation(C.observed_change(previous, observed, patch), observed),
    accepted_patch: @+identity:+List<C.FieldValue> -> @+base:String -> @+value:C.Value -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      {amendment_patch(C.observed_change(Some{C.Snapshot{C.ContextKey{definition, identity}, base, value}}, observed, patch), value, C.snapshot_value(observed)) == True{} : Bool},
    applied_amendment: @+bindings:+List<C.Snapshot> -> @+identity:+List<C.FieldValue> -> @+base:String -> @+previous_revision:String -> @+previous:C.Value -> @+revision:String -> @+patch:C.Patch -> @+value:C.Value ->
      @found:{C.find(bindings, C.ContextKey{definition, identity}) == Some{C.Snapshot{C.ContextKey{definition, identity}, previous_revision, previous}} : Maybe<&2, C.Snapshot>} ->
      @base_matches:{String.eq(previous_revision, base) == True{} : Bool} ->
      @patched:{C.apply_patch(previous, patch) == Some{value} : Maybe<&2, C.Value>} ->
      {C.apply_change(C.Amend{C.ContextKey{definition, identity}, base, revision, patch}, bindings) == C.Snapshot{C.ContextKey{definition, identity}, revision, value} <> C.remove_binding(bindings, C.ContextKey{definition, identity}) : +List<C.Snapshot>}
  }

type Evidence is Type:
  Evidence{
    append: @+context:D.HistoryContext -> @+task:D.Task ->
      {D.task_history(D.append_context(context, task)) == D.HistoryNode{D.task_history(task), D.ContextMessage{context}} : D.History},
    replacement_bindings: @+history:D.History -> @value:J.Json ->
      {D.context_bindings(D.HistoryNode{history, D.ContextReplacement{value}}) == D.context_bindings(history) : +List<C.Snapshot>},
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
      {amendment_patch(C.observed_change(Some{C.Snapshot{key, base, value}}, observed, patch), value, C.snapshot_value(observed)) == True{} : Bool},
    accepted_snapshot: @+previous:Maybe<&2, C.Snapshot> -> @+observed:C.Snapshot -> @+patch:C.Patch ->
      AcceptedObservation(C.observed_change(previous, observed, patch), observed),
    definition_family: @+definition:C.Definition -> Categories.Membership<C.Definition, (definition => DefinitionEvidence<definition>)>
  }
