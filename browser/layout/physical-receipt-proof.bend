import ../appearance/TYPOGRAPHY.bend as T
import ./GEOMETRY.bend as Spatial
import ./MODEL.bend as World
import ../document/SOURCE.bend as Source
import Base
import ./physical-receipt-laws.bend as Rule
import ./CONTENT.bend as Content

import ../runtime/MODEL.bend as Browser
import ../runtime/SEMANTICS.bend as Legacy
import ../focus/MODEL.bend as Focus
import ../runtime/native-fields.bend as Native
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View

def publication(+world: Content.AllocatedWorld, capacity: View.Capacity, +legacy: Legacy.State, +semantic: InterfaceView.Surface) ->
  {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([Rule.world_source(world)], semantic), None{}} : Browser.Published}:
  match world:
    case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def state_authored_evidence(+model_state: Browser.State, +source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: Spatial.Box, +semantic: InterfaceView.Surface) ->
  Rule.authored_claim(model_state, source, index, capacity, font, viewport, semantic):
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def state_measured_evidence(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +tokens: +List<String>, +semantic: InterfaceView.Surface, +round: Nat) ->
  Rule.measurement_claim(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), index, capacity, engine, tokens, semantic, round):
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def state_remeasure_evidence(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +semantic: InterfaceView.Surface, +round: Nat) ->
  {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.refreeze(index, capacity, engine, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic) : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def Rule.evidence():
  Rule.Requirements{
    +world => capacity => +legacy => +semantic => publication(world, capacity, legacy, semantic),
    state_authored_evidence,
    generation => first => remaining => index => capacity => engine => state => semantic => round => {==},
    state_measured_evidence,
    state_remeasure_evidence,
    world => index => capacity => engine => state => semantic => round => {==}}
