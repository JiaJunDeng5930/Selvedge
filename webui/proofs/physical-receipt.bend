import ../typography.bend as T
import ../spatial.bend as Spatial
import ../physical-world.bend as World
import ../source.bend as Source
import Base
import ../physical-receipt-laws.bend as Rule
import ../physical-content.bend as Content

import ../physical-browser.bend as Browser
import ../browser.bend as Legacy
import ../focus.bend as Focus
import ../native-fields.bend as Native
import ../../core/interface.bend as InterfaceView
import ../../core/ui-world.bend as View

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
