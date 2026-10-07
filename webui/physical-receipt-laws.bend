import Base
import ./physical-browser.bend as Browser
import ./browser.bend as Legacy
import ./physical-world.bend as World
import ./physical-content.bend as Content
import ./physical-plan.bend as Plan
import ./source.bend as Source
import ./authored-shell.bend as Shell
import ./typography.bend as T
import ./spatial.bend as Spatial
import ./focus.bend as Focus
import ./native-fields.bend as Native
import ../core/interface.bend as InterfaceView
import ../core/ui-world.bend as View

def world_source(world: Content.AllocatedWorld) -> Source.Node:
  Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies} = world
  source

def authored_claim(+source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation,
  +viewport: Spatial.Box, +legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>,
  +lifecycle: Browser.Lifecycle, +displayed: Maybe<&2, Browser.Published>, +semantic: InterfaceView.Surface) -> Type:
  {Browser.authored(Shell.Ready{source}, index, capacity, font, viewport,
    Browser.State{legacy, serial, anchors, lifecycle, displayed}, semantic) ==
    Browser.selected(World.plan(World.initial(Content.Snapshot{(serial + 1n : Nat), Browser.feedback_root(source, Browser.pending(legacy), font), font}, viewport)),
      index, capacity, World.initial(Content.Snapshot{(serial + 1n : Nat), Browser.feedback_root(source, Browser.pending(legacy), font), font}, viewport),
      Browser.State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed}, semantic, 0n) : Browser.Search}

def measurement_claim(+legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>,
  +index: Nat, +capacity: View.Capacity, +engine: World.Engine,
  +displayed: Maybe<&2, Browser.Published>, +tokens: +List<String>, +semantic: InterfaceView.Surface, +round: Nat) -> Type:
  {Browser.measured_pending(tokens, Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}) ==
    Browser.receipt_selection(World.receipt_status(World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine)),
      index, capacity, World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine),
      Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}, semantic, (round + 1n : Nat)) : Browser.Decision}

type Requirements is Type:
  Requirements{
    publication: @+world:Content.AllocatedWorld -> @capacity:View.Capacity -> @+legacy:Legacy.State -> @+semantic:InterfaceView.Surface ->
      {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([world_source(world)], semantic), None{}} : Browser.Published},
    authored: @+source:Source.Node -> @+index:Nat -> @+capacity:View.Capacity -> @+font:T.Presentation -> @+viewport:Spatial.Box ->
      @+legacy:Legacy.State -> @+serial:Nat -> @+anchors:+List<Shell.Anchor> -> @+lifecycle:Browser.Lifecycle ->
      @+displayed:Maybe<&2, Browser.Published> -> @+semantic:InterfaceView.Surface -> authored_claim(source, index, capacity, font, viewport, legacy, serial, anchors, lifecycle, displayed, semantic),
    awaiting: @generation:Nat -> @first:Plan.Job -> @remaining:+List<Plan.Job> -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:InterfaceView.Surface -> @round:Nat ->
      {Browser.selected(Plan.Awaiting{generation, first, remaining}, index, capacity, engine, state, semantic, round) ==
        Browser.Stopped{Browser.Decision{Browser.set_lifecycle(state, Browser.Measuring{index, capacity, engine, semantic, round}), Nil{}}} : Browser.Search},
    measured: @+legacy:Legacy.State -> @+serial:Nat -> @+anchors:+List<Shell.Anchor> -> @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+displayed:Maybe<&2, Browser.Published> ->
      @+tokens:+List<String> -> @+semantic:InterfaceView.Surface -> @+round:Nat ->
      measurement_claim(legacy, serial, anchors, index, capacity, engine, displayed, tokens, semantic, round),
    remeasure: @+legacy:Legacy.State -> @+serial:Nat -> @+anchors:+List<Shell.Anchor> -> @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+displayed:Maybe<&2, Browser.Published> -> @+semantic:InterfaceView.Surface -> @+round:Nat ->
      {Browser.remeasure(Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}) ==
        Browser.refreeze(index, capacity, engine, Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}, semantic) : Browser.Decision},
    ready: @world:Content.AllocatedWorld -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:InterfaceView.Surface -> @round:Nat ->
      {Browser.selected(Plan.Ready{world}, index, capacity, engine, state, semantic, round) == Browser.Stopped{Browser.admit(world, capacity, engine, state, semantic)} : Browser.Search}}

law evidence:
  Requirements
