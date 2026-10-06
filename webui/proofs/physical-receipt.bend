import Base
import ../physical-receipt-laws.bend as Rule
import ../physical-content.bend as Content

import ../physical-browser.bend as Browser
import ../browser.bend as Legacy
import ../focus.bend as Focus
import ../native-fields.bend as Native
import ../../core/interface.bend as UI
import ../../core/ui-world.bend as View

def publication(+world: Content.AllocatedWorld, capacity: View.Capacity, +legacy: Legacy.State, +semantic: UI.Surface) ->
  {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([Rule.world_source(world)], semantic), None{}} : Browser.Published}:
  match world:
    case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def Rule.evidence():
  Rule.Requirements{
    +world => capacity => +legacy => +semantic => publication(world, capacity, legacy, semantic),
    +source => +index => +capacity => +font => +viewport => +legacy => +serial => +anchors => +lifecycle => +displayed => +semantic => {==},
    generation => first => remaining => index => capacity => engine => state => semantic => {==},
    +legacy => +serial => +anchors => +index => +capacity => +engine => +displayed => +tokens => +semantic => {==},
    +legacy => +serial => +anchors => +index => +capacity => +engine => +displayed => +semantic => {==},
    world => index => capacity => engine => state => semantic => {==}}
