import Base
import ../harness/MODEL.bend as M
import ../interaction/MODEL.bend as Product
import ../bendlib/association-map.bend as Finite
import ../bendlib/stdlib.bend as Std
import ../interaction/STATE.bend as Core
import ../interaction/services/MODEL.bend as Services
import ../interaction/presentation/PROGRAM.bend as Interface
import ../interaction/presentation/MODEL.bend as View
import ../interaction/session/MODEL.bend as E
import ../interaction/INPUT.bend as U
import ./MODEL.bend as Model
import ./appearance/DESIGN.bend as Design
import ./appearance/FONT.bend as F
import ./appearance/TYPOGRAPHY.bend as T
import ./editor/MODEL.bend as Editor
import ./focus/MODEL.bend as Focus
import ./controls/GEOMETRY.bend as Physical
import ./runtime/PLATFORM.bend as Platform
import ./reading/MODEL.bend as Reading
import ./document/RENDERED.bend as Rendered
import ./appearance/paint-rules.bend as PaintRules
import ./layout/physical-renderer-rules.bend as RendererRules


def model_core(application: Platform.State) -> Core.State:
  Platform.core(application)

def platform_effects(decision: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, +effects} = decision
  effects

def platform_editors(platform: Platform.Platform, owner: U.Editor) -> Editor.Editor:
  Platform.find_editor(Platform.editors(platform), owner)

def platform_capacity(platform: Platform.Platform) -> View.Capacity:
  Platform.capacity(platform)

def platform_scope(platform: Platform.Platform) -> Focus.Scope:
  Platform.scope(platform)

def platform_ticket(platform: Platform.Platform) -> Nat:
  Platform.focus_ticket(platform)

def with_scope(platform: Platform.Platform, next_scope: Focus.Scope) -> Platform.Platform:
  Platform.with_scope(next_scope, platform)

def with_saved_editor(+platform: Platform.Platform, owner: U.Editor, editor: Editor.Editor) -> Platform.Platform:
  Platform.with_editors(Platform.save_editor(Platform.editors(platform), owner, editor), platform)

def platform_bookmarks(platform: Platform.Platform) -> +List<Finite.Entry(Reading.Bookmark)>:
  Platform.readers(platform)

def decision_bookmarks(decision: Platform.Decision) -> +List<Finite.Entry(Reading.Bookmark)>:
  Platform.Decision{product, platform, effects} = decision
  platform_bookmarks(platform)

def stale_reading_law(-application: E.Application, -services: Services.State, -platform: Platform.Platform, -task: Nat, -generation: Nat, -event: Reading.ReadingEvent, -inactive: {Platform.active_reader(application, task, generation) == False{} : Bool}) -> Type:
  {Platform.step(Platform.ReadingInput{task, generation, event},
      Platform.from_core(Core.from_application(application, services), platform)) ==
      Platform.Decision{Platform.unchanged(Core.from_application(application, services)), platform, Nil{}} : Platform.Decision}

def session_readers(session: E.Session) -> +List<Finite.Entry(E.Reader)>:
  E.readers(session)

def conversation_session(session: E.Session, task: Nat) -> E.Session:
  E.with_route(U.Conversation{task}, session)

def RetainedEntry(found: Maybe<&2, U.Draft>) -> Type:
  match found:
    case None{}: Unit
    case Some{U.Draft{revision, body, U.Editing{}, directory_entry}}: Unit
    case Some{U.Draft{revision, body, U.Rejected{revision, reason}, directory_entry}}: Unit
    case Some{U.Draft{revision, body, U.Accepted{revision, reply}, directory_entry}}: Empty

def Retained(drafts: +List<U.Draft>, editors: +List<Editor.Editor>) -> Type:
  match editors:
    case Nil{}: Unit
    case Con{Editor.Editor{+owner, selection, composing}, rest}:
      RetainedEntry(E.find_draft(drafts, owner)) & Retained(drafts, rest)

type Size is Data:
  Size{composer: F32, viewport: F32}

type Tape is Data:
  Tape{bookmark: Reading.Bookmark, pending: +List<Size>, receipts: +List<Reading.Decision>, reduced: Bool}

def tape_bookmark(tape: Tape) -> Reading.Bookmark:
  Tape{bookmark, pending, receipts, reduced} = tape
  bookmark

def reading_bookmark(decision: Reading.Decision) -> Reading.Bookmark:
  Reading.Decision{bookmark, intent, effects} = decision
  bookmark

def advance(tape: Tape) -> Tape:
  match tape:
    case Tape{bookmark, pending, receipts, +reduced}:
      match pending:
        case Nil{}: Tape{bookmark, Nil{}, receipts, reduced}
        case Con{Size{composer, viewport}, rest}:
          +decision = Reading.step(Reading.LayoutChanged{composer, viewport}, U.ReadHistory{}, bookmark, reduced)
          Tape{reading_bookmark(decision), rest,
            List.append(&2, Reading.Decision, receipts, [decision]), reduced}

def font_state(decision: Model.Decision) -> F.State:
  Model.Decision{state, product, effects} = decision
  Model.typography(state)

def model_application(state: Model.State) -> Platform.State:
  Model.application(state)

def decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  platform_capacity(platform)

type Environment is Type:
  Environment{
    reflow_same: @+decision:Platform.Decision -> @+capacity:View.Capacity ->
      @same:{Platform.same_capacity(decision_capacity(decision), capacity) == True{} : Bool} ->
      {Platform.reflow_capacity(decision, capacity) == decision : Platform.Decision},
    stale_typography: @+state:Model.State -> @+received:Nat -> @+metrics:+List<T.Metric> ->
      @stale:{Nat.is_eq(F.generation(Model.typography(state)), received) == False{} : Bool} ->
      {Model.step(Model.TypographyObserved{F.Observation{received, metrics}}, state) ==
        Model.idle_state(state) : Model.Decision},
    reflow_capacity_fields: @+decision:Platform.Decision -> @+capacity:View.Capacity ->
      {decision_capacity(Platform.reflow_capacity(decision, capacity)) == capacity : View.Capacity},
    environment_resets_font: @+state:Model.State -> @+environment:Design.Environment ->
      {font_state(Model.step(Model.EnvironmentObserved{environment}, state)) ==
        F.begin((Model.generation(state) + 1n : Nat), Model.environment_root(environment)) : F.State},
    typography_product: @+state: Model.State -> @+observation: F.Observation -> {Model.product(Model.step(Model.TypographyObserved{observation}, state)) ==
    Platform.unchanged(model_core(model_application(state))) : Core.Decision}
  }

type Product is Type:
  Product{
    product_refinement: @input:Product.Input -> @state:Model.State ->
      {Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}}, state)) ==
        Product.step(input, Platform.core(Model.application(state))) : Core.Decision},
    element_refinement: @key:String -> @gesture:Interface.Gesture -> @state:Model.State ->
      {Model.product(Model.step(Model.ElementInput{key, gesture}, state)) ==
        Product.step(Product.Element{Platform.capacity(Platform.platform(Model.application(state))), key, gesture},
          Platform.core(Model.application(state))) : Core.Decision}
  }

type Realization is Type:
  Realization{
    frame_silent: @received:Nat -> @frame:Rendered.Frame -> @state:Model.State ->
      {Model.step(Model.FrameObserved{received, frame}, state) ==
        Model.Decision{state, Platform.unchanged(Platform.core(Model.application(state))), Nil{}} : Model.Decision},
    stale_frame: @received:Nat -> @frame:Rendered.Frame -> @state:Model.State ->
      @stale:{Nat.is_eq(Model.generation(state), received) == False{} : Bool} ->
      {Model.step(Model.FrameObserved{received, frame}, state) ==
        Model.Decision{state, Platform.unchanged(Platform.core(Model.application(state))), Nil{}} : Model.Decision}
  }

type Reading is Type:
  Reading{
    stale_reading: @application:E.Application -> @services:Services.State -> @platform:Platform.Platform ->
      @task:Nat -> @generation:Nat -> @event:Reading.ReadingEvent ->
      @inactive:{Platform.active_reader(application, task, generation) == False{} : Bool} ->
      stale_reading_law(application, services, platform, task, generation, event, inactive),
    history_layout_changed: @height:F32 -> @viewport:F32 -> @anchor:Physical.Anchor -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{},
          Reading.Bookmark{Some{anchor}}, reduced) ==
          Reading.Decision{Reading.Bookmark{Some{anchor}}, None{},
            [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.PreserveAnchor{anchor}]} : Reading.Decision},
    history_layout_missing: @height:F32 -> @viewport:F32 -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{},
          Reading.Bookmark{None{}}, reduced) ==
          Reading.Decision{Reading.Bookmark{None{}}, None{},
            [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.MeasureAnchor{}]} : Reading.Decision},
    follow_latest_layout: @bookmark:Reading.Bookmark -> @reduced:Bool ->
      {Reading.step(Reading.FollowLatest{}, U.ReadHistory{}, bookmark, reduced) ==
          Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}}, [Reading.CancelAnchorObservation{}, Reading.AlignLatest{Bool.not(reduced)}]} :
          Reading.Decision},
    layout_after_product: @program:M.World() -> @session:E.Session -> @task:Nat -> @generation:Nat ->
      @disclosures:+List<E.Disclosure> -> @bookmarks:+List<Finite.Entry(Reading.Bookmark)> -> @anchor:Physical.Anchor ->
      @reader_observed:{E.reader(session_readers(session), task) == E.Reader{generation, U.ReadHistory{}, disclosures} : E.Reader} ->
      @bookmark_observed:{Finite.find(~Reading.Bookmark, bookmarks, task) ==
        Some{Reading.Bookmark{Some{anchor}}} : Maybe<&2, Reading.Bookmark>} ->
      {Platform.layout_for(E.from_program(program, conversation_session(session, task)), bookmarks) ==
        [Platform.ApplyReading{task, generation, Reading.PreserveAnchor{anchor}}] : +List<Platform.Effect>},
    after_core_keeps_bookmarks: @decision:Core.Decision -> @platform:Platform.Platform ->
      {decision_bookmarks(Platform.after_core(decision, platform)) == platform_bookmarks(platform) :
        +List<Finite.Entry(Reading.Bookmark)>},
    layout_sequence_preserves_bookmark: @count:Nat -> @seed:Tape ->
      {tape_bookmark(Std.iter(~Tape, ~advance, count, seed)) == tape_bookmark(seed) : Reading.Bookmark}
  }

type Editing is Type:
  Editing{
    ime_entry: @owner:U.Editor -> @selection:Physical.Selection -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @core:Core.State -> @platform:Platform.Platform ->
      @editor_observed:{platform_editors(platform, owner) == Editor.Editor{owner, selection, True{}} : Editor.Editor} ->
      {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}}, Platform.from_core(core, platform)) ==
        Platform.Decision{Platform.unchanged(core),
          with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}} : Platform.Decision},
    ready_enter: @owner:U.Editor -> @selection:Physical.Selection -> @modified:Bool -> @core:Core.State ->
      @platform:Platform.Platform ->
      @editor_observed:{platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor} ->
      @enabled:{Platform.editor_enabled(core, owner, platform_capacity(platform)) == True{} : Bool} ->
      @permitted:{Focus.permits_composer(platform_scope(platform)) == True{} : Bool} ->
      {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
        Platform.from_core(core, platform))) ==
        Product.step(Product.SubmitComposer{platform_capacity(platform), owner}, core) : Core.Decision},
    temporary_enter_product: @owner:U.Editor -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @identity:String -> @initial:String -> @restore:String -> @+occurrence:Maybe<&2, Nat> -> @core:Core.State -> @platform:Platform.Platform ->
      {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.from_core(core, with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})))) ==
          Platform.unchanged(core) : Core.Decision},
    temporary_enter_effects: @owner:U.Editor -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @identity:String -> @initial:String -> @restore:String -> @+occurrence:Maybe<&2, Nat> -> @core:Core.State -> @platform:Platform.Platform ->
      {platform_effects(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.from_core(core, with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})))) ==
          Nil{} : +List<Platform.Effect>}
  }

type Focus is Type:
  Focus{
    stale_focus_ticket: @core:Core.State -> @platform:Platform.Platform -> @received:Nat -> @identity:String -> @observed:Maybe<&2, Focus.Target> ->
      @stale:{Nat.is_eq(received, platform_ticket(platform)) == False{} : Bool} ->
      {Platform.step(Platform.FocusApplied{received, Focus.Product{identity}, observed}, Platform.from_core(core, platform)) ==
        Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision},
    inactive_focus: @core:Core.State -> @platform:Platform.Platform -> @identity:String -> @observed:Maybe<&2, Focus.Target> ->
      @inactive:{Platform.active_focus(core, platform_capacity(platform), identity) == False{} : Bool} ->
      {Platform.step(Platform.FocusApplied{platform_ticket(platform), Focus.Product{identity}, observed}, Platform.from_core(core, platform)) ==
        Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision},
    synchronize_retained: @drafts:+List<U.Draft> -> @editors:+List<Editor.Editor> ->
      @retained:Retained(drafts, editors) ->
      {Platform.synchronize_drafts(drafts, editors) == editors : +List<Editor.Editor>}
  }

type Requirements is Type:
  Requirements{
    environment: Environment,
    product: Product,
    realization: Realization,
    reading: Reading,
    editing: Editing,
    focus: Focus,
    paint: PaintRules.Requirements,
    physical_renderer: RendererRules.Requirements
  }

law evidence:
  Requirements
