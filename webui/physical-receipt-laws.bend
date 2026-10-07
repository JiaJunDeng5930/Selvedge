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

def authored_claim(+model_state: Browser.State, +source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: Spatial.Box, +semantic: InterfaceView.Surface) -> Type:
  {Browser.authored(Shell.Ready{source}, index, capacity, font, viewport,
    model_state, semantic) ==
    Browser.selected(World.plan(World.initial(Content.Snapshot{(Browser.generation(model_state) + 1n : Nat), Browser.feedback_root(source, Browser.pending(Browser.legacy(model_state)), font), font}, viewport)),
      index, capacity, World.initial(Content.Snapshot{(Browser.generation(model_state) + 1n : Nat), Browser.feedback_root(source, Browser.pending(Browser.legacy(model_state)), font), font}, viewport),
      Browser.with_generation((Browser.generation(model_state) + 1n : Nat), model_state), semantic, 0n) : Browser.Search}

def measurement_claim(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +tokens: +List<String>, +semantic: InterfaceView.Surface, +round: Nat) -> Type:
  {Browser.measured_pending(tokens, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
    Browser.receipt_selection(World.receipt_status(World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine)),
      index, capacity, World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine),
      Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic, (round + 1n : Nat)) : Browser.Decision}

type Requirements is Type:
  Requirements{
    publication: @+world:Content.AllocatedWorld -> @capacity:View.Capacity -> @+legacy:Legacy.State -> @+semantic:InterfaceView.Surface ->
      {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([world_source(world)], semantic), None{}} : Browser.Published},
    authored: @+model_state:Browser.State ->  @+source:Source.Node -> @+index:Nat -> @+capacity:View.Capacity -> @+font:T.Presentation -> @+viewport:Spatial.Box ->
      @+semantic:InterfaceView.Surface -> authored_claim(model_state, source, index, capacity, font, viewport, semantic),
    awaiting: @generation:Nat -> @first:Plan.Job -> @remaining:+List<Plan.Job> -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:InterfaceView.Surface -> @round:Nat ->
      {Browser.selected(Plan.Awaiting{generation, first, remaining}, index, capacity, engine, state, semantic, round) ==
        Browser.Stopped{Browser.Decision{Browser.set_lifecycle(state, Browser.Measuring{index, capacity, engine, semantic, round}), Nil{}}} : Browser.Search},
    measured: @+model_state:Browser.State ->  @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+tokens:+List<String> -> @+semantic:InterfaceView.Surface -> @+round:Nat ->
      measurement_claim(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), index, capacity, engine, tokens, semantic, round),
    remeasure: @+model_state:Browser.State ->  @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+semantic:InterfaceView.Surface -> @+round:Nat ->
      {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.refreeze(index, capacity, engine, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic) : Browser.Decision},
    ready: @world:Content.AllocatedWorld -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:InterfaceView.Surface -> @round:Nat ->
      {Browser.selected(Plan.Ready{world}, index, capacity, engine, state, semantic, round) == Browser.Stopped{Browser.admit(world, capacity, engine, state, semantic)} : Browser.Search}}
law evidence:
  Requirements
