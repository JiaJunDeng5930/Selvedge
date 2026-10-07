import Base
import ../physical-content-rules.bend as ContentRules
import ../../bendlib/stdlib.bend as Std
import ../physical-world.bend as World
import ../physical-world-rules.bend as Rule
import ../physical-content.bend as Content
import ../physical-width-rules.bend as Width
import ../physical-height-rules.bend as Height
import ../physical-allocation-population-rules.bend as Population
import ./physical-width.bend as WidthProof
import ./physical-height.bend as HeightProof
import ./physical-allocation-population.bend as PopulationProof
import ../document.bend as Doc

def stale(+generation: Nat, +receipts: +List<String>, +engine: World.Engine,
  proof: {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == False{} : Bool}) ->
  Rule.stale_claim(generation, receipts, engine):
  Std.transport(Bool, False{},
    (current => {World.receive_current(current, receipts, engine) == engine : World.Engine}),
    {==}, Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))),
    proof)

def rejected_member(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch) ->
  {World.measurement_valid_member(False{}, valid, request, observation, batch)
    == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}:
  match batch:
    case World.Batch{observations, viewports}: {==}


def rejection(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch,
  proof: {ContentRules.observation_matches(request, observation) == False{} : Bool}) ->
  Rule.rejected_measurement_claim(valid, request, observation, batch):
  Std.transport(Bool, False{},
    (member => {World.measurement_valid_member(member, valid, request, observation, batch)
      == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}),
    rejected_member(valid, request, observation, batch), ContentRules.observation_matches(request, observation),
    proof)


def production(+engine: World.Engine) -> Rule.production_claim(engine):
  match engine:
    case World.Engine{snapshot, viewport, observations, viewports, status}: {==}

def Rule.evidence():
  Rule.Requirements{+generation => +receipts => +engine => proof => stale(generation, receipts, engine, proof),
    +valid => +request => +observation => +batch => proof => rejection(valid, request, observation, batch, proof),
    +engine => production(engine), Width.evidence(~Content.Value, ~Doc.DOMEvent),
    Height.evidence(~Content.Value, ~Doc.DOMEvent), Population.evidence(~Content.Value, ~Doc.DOMEvent)}
