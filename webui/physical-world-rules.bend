import Base
import ./physical-content-rules.bend as ContentRules
import ./physical-source.bend as PhysicalSource
import ./physical-plan.bend as PhysicalPlan
import ./physical-world.bend as World
import ./physical-content.bend as Content
import ./physical-width-rules.bend as Width
import ./physical-height-rules.bend as Height
import ./physical-allocation-population-rules.bend as Population
import ./document.bend as Doc

def stale_claim(+generation: Nat, +receipts: +List<String>, +engine: World.Engine) -> Type:
  {World.receive(generation, receipts, engine) == engine : World.Engine}

def rejected_measurement_claim(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch) -> Type:
  {World.measurement_valid(valid, request, observation, batch)
    == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}

def production_claim(+engine: World.Engine) -> Type:
  World.Engine{+snapshot, +viewport, +observations, +viewports, status} = engine
  {World.plan(engine) == World.preparation(
    PhysicalSource.prepare(snapshot, observations), viewport, observations, viewports) : PhysicalPlan.Plan}


type Requirements is Type:
  Requirements{
    stale: @+generation:Nat -> @+receipts:+List<String> -> @+engine:World.Engine ->
      {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == False{} : Bool} ->
      stale_claim(generation, receipts, engine),
    rejection: @+valid:Bool -> @+request:Content.Request -> @+observation:Content.Observation -> @+batch:World.Batch ->
      {ContentRules.observation_matches(request, observation) == False{} : Bool} ->
      rejected_measurement_claim(valid, request, observation, batch),
    production: @+engine:World.Engine -> production_claim(engine),
    width: Width.Requirements<Content.Value, Doc.Event>,
    height: Height.Requirements<Content.Value, Doc.Event>,
    population: Population.Requirements<Content.Value, Doc.Event>}

law evidence:
  Requirements
