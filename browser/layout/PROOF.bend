import ./activity-proof.bend as ActivityProof
import ./activity-contract.bend as ActivityRules
import Base
import ./adaptation-proof.bend as AdaptationProof
import ./ADAPTATION.bend as Adaptation
import ./measurement-contract.bend as RulePhysicalContentRules
import ./CONTENT.bend as Content
import ../../interaction/presentation/MODEL.bend as View
import ../runtime/SEMANTICS.bend as Legacy
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../runtime/MODEL.bend as Browser
import ../focus/MODEL.bend as Focus
import ../runtime/native-fields.bend as Native
import ../document/SOURCE.bend as Source
import ../appearance/TYPOGRAPHY.bend as T
import ./GEOMETRY.bend as SpatialModel
import ./MODEL.bend as World
import ./CONTRACT.bend as RuleContract
import ../../bendlib/stdlib.bend as Std
import ./physical-content-measurement.bend as RulePhysicalContentRules2
import ./sizing-proof.bend as ProofSizingProof
import ./allocation-contract.bend as RulePhysicalSourceRules
import ../document/MODEL.bend as Doc

def RulePhysicalContentRules.rich_local_value_preserves_focus_owner(key, style, content, attachments, native_owner, font): {==}

def publication(+world: Content.AllocatedWorld, capacity: View.Capacity, +legacy: Legacy.State, +semantic: SurfaceTypes.Surface) ->
  {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([RulePhysicalContentRules.world_source(world)], semantic), None{}} : Browser.Published}:
  match world:
    case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def state_remeasure_evidence(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +semantic: SurfaceTypes.Surface, +round: Nat) ->
  {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.Decision{Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), Nil{}} : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed, +attention, +updates} = model_state
  {==}

def RulePhysicalContentRules.evidence():
  RulePhysicalContentRules.Requirements{
    +world => capacity => +legacy => +semantic => publication(world, capacity, legacy, semantic),
    generation => first => remaining => index => capacity => engine => state => semantic => round => {==},
    state_remeasure_evidence}

def stale(+generation: Nat, +receipts: +List<String>, +engine: World.Engine,
  proof: {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == False{} : Bool}) ->
  RuleContract.stale_claim(generation, receipts, engine):
  Std.transport(Bool, False{},
    (current => {World.receive_current(current, receipts, engine) == engine : World.Engine}),
    {==}, Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))),
    proof)

def rejected_member(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch) ->
  {World.measurement_member_calculation(False{}, valid, request, observation, batch)
    == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}:
  match batch:
    case World.Batch{observations, viewports}: {==}

def rejection(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch,
  proof: {RulePhysicalContentRules2.observation_matches(request, observation) == False{} : Bool}) ->
  RuleContract.rejected_measurement_claim(valid, request, observation, batch):
  Std.transport(Bool, False{},
    (member => {World.measurement_member_calculation(member, valid, request, observation, batch)
      == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}),
    rejected_member(valid, request, observation, batch), RulePhysicalContentRules2.observation_matches(request, observation),
    proof)

def RuleContract.evidence():
  RuleContract.Requirements{ActivityRules.evidence(), Adaptation.evidence(),+generation => +receipts => +engine => proof => stale(generation, receipts, engine, proof),
    +valid => +request => +observation => +batch => proof => rejection(valid, request, observation, batch, proof),
    +engine => ProofSizingProof.production(engine), RulePhysicalSourceRules.width_evidence(~Content.Value, ~Doc.DOMEvent),
    RulePhysicalSourceRules.height_evidence(~Content.Value, ~Doc.DOMEvent), RulePhysicalSourceRules.allocation_population_evidence(~Content.Value, ~Doc.DOMEvent)}

# The partial source observes only fields consumed by production. A failed or
# pending child makes the enclosing computation incapable of a ready result.
