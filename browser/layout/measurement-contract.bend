import Base
import ../runtime/MODEL.bend as Browser
import ../runtime/SEMANTICS.bend as Legacy
import ./MODEL.bend as World
import ./CONTENT.bend as Content
import ./physical-plan.bend as Plan
import ../document/SOURCE.bend as Source
import ../controls/SHELL.bend as Shell
import ../appearance/TYPOGRAPHY.bend as T
import ./GEOMETRY.bend as Spatial
import ../focus/MODEL.bend as Focus
import ../runtime/native-fields.bend as Native
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/IDENTITY.bend as UIIdentity

def world_source(world: Content.AllocatedWorld) -> Source.Node:
  Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies} = world
  source

def authored_claim(+model_state: Browser.State, +source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: Spatial.Box, +semantic: SurfaceTypes.Surface) -> Type:
  {Browser.authored(Shell.Ready{source}, index, capacity, font, viewport,
    model_state, semantic) ==
    Browser.selected(World.plan(World.initial(Content.Snapshot{(Browser.generation(model_state) + 1n : Nat), Browser.feedback_root(source, Browser.pending(Browser.legacy(model_state)), font), font}, viewport)),
      index, capacity, World.initial(Content.Snapshot{(Browser.generation(model_state) + 1n : Nat), Browser.feedback_root(source, Browser.pending(Browser.legacy(model_state)), font), font}, viewport),
      Browser.with_generation((Browser.generation(model_state) + 1n : Nat), model_state), semantic, 0n) : Browser.Search}

def measurement_claim(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +tokens: +List<String>, +semantic: SurfaceTypes.Surface, +round: Nat) -> Type:
  {Browser.measured_pending(tokens, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
    Browser.receipt_selection(World.receipt_status(World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine)),
      index, capacity, World.receive(World.snapshot_generation(World.snapshot(engine)), tokens, engine),
      Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic, (round + 1n : Nat)) : Browser.Decision}

type Requirements is Type:
  Requirements{
    publication: @+world:Content.AllocatedWorld -> @capacity:View.Capacity -> @+legacy:Legacy.State -> @+semantic:SurfaceTypes.Surface ->
      {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([world_source(world)], semantic), None{}} : Browser.Published},
    authored: @+model_state:Browser.State ->  @+source:Source.Node -> @+index:Nat -> @+capacity:View.Capacity -> @+font:T.Presentation -> @+viewport:Spatial.Box ->
      @+semantic:SurfaceTypes.Surface -> authored_claim(model_state, source, index, capacity, font, viewport, semantic),
    awaiting: @generation:Nat -> @first:Plan.Job -> @remaining:+List<Plan.Job> -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:SurfaceTypes.Surface -> @round:Nat ->
      {Browser.selected(Plan.Awaiting{generation, first, remaining}, index, capacity, engine, state, semantic, round) ==
        Browser.Stopped{Browser.Decision{Browser.set_lifecycle(state, Browser.Measuring{index, capacity, engine, semantic, round}), Nil{}}} : Browser.Search},
    measured: @+model_state:Browser.State ->  @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+tokens:+List<String> -> @+semantic:SurfaceTypes.Surface -> @+round:Nat ->
      measurement_claim(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), index, capacity, engine, tokens, semantic, round),
    remeasure: @+model_state:Browser.State ->  @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+semantic:SurfaceTypes.Surface -> @+round:Nat ->
      {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.refreeze(index, capacity, engine, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic) : Browser.Decision},
    ready: @world:Content.AllocatedWorld -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:SurfaceTypes.Surface -> @round:Nat ->
      {Browser.selected(Plan.Ready{world}, index, capacity, engine, state, semantic, round) == Browser.Stopped{Browser.admit(world, capacity, engine, state, semantic)} : Browser.Search}}

law evidence:
  Requirements

law rich_local_value_preserves_focus_owner:
  for key: UIIdentity.Key
  for style: Source.Style
  for content: Source.RichContent
  for attachments: +List<Source.Node>
  for native_owner: Maybe<&2, String>
  for font: T.Presentation
  {Content.local_value(Source.RichText{key, style, content, attachments, native_owner}, font) ==
    Content.Value{Source.RichText{key, style, content, Nil{}, native_owner}, font} : Content.Value}
