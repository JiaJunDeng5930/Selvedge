import Base
import ../MODEL.bend as M
import ../UI.bend as Product
import ../bendlib/association-map.bend as Finite
import ../bendlib/stdlib.bend as Std
import ../core/SYSTEM.bend as Core
import ../core/client-services.bend as Services
import ../core/interface.bend as Interface
import ../core/ui-world.bend as View
import ../core/user-experience.bend as E
import ../core/user-input.bend as U
import ./MODEL.bend as Model
import ./design.bend as Design
import ./font-observation.bend as F
import ./typography.bend as T
import ./editor.bend as Editor
import ./focus.bend as Focus
import ./interaction.bend as Physical
import ./platform.bend as Platform
import ./reading.bend as Reading
import ./rendered.bend as Rendered


def model_core(application: Platform.State) -> Core.State:
  Platform.State{core, platform} = application
  core

def platform_effects(decision: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, +effects} = decision
  effects

def platform_editors(platform: Platform.Platform, owner: U.Editor) -> Editor.Editor:
  Platform.Platform{readers, +editors, focused, ticket, reduced, capacity, scope} = platform
  Platform.find_editor(editors, owner)

def platform_capacity(platform: Platform.Platform) -> View.Capacity:
  Platform.Platform{readers, editors, focused, ticket, reduced, +capacity, scope} = platform
  capacity

def platform_scope(platform: Platform.Platform) -> Focus.Scope:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, +scope} = platform
  scope

def platform_ticket(platform: Platform.Platform) -> Nat:
  Platform.Platform{readers, editors, focused, +ticket, reduced, capacity, scope} = platform
  ticket

def with_scope(platform: Platform.Platform, next_scope: Focus.Scope) -> Platform.Platform:
  Platform.Platform{+readers, +editors, focused, ticket, reduced, capacity, scope} = platform
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, next_scope}

def with_saved_editor(platform: Platform.Platform, owner: U.Editor, editor: Editor.Editor) -> Platform.Platform:
  Platform.Platform{+readers, +editors, focused, ticket, reduced, capacity, scope} = platform
  Platform.Platform{readers, Platform.save_editor(editors, owner, editor), focused, ticket, reduced, capacity, scope}

def platform_bookmarks(platform: Platform.Platform) -> +List<Finite.Entry(Reading.Bookmark)>:
  Platform.Platform{+readers, editors, focused, ticket, reduced, capacity, scope} = platform
  readers

def decision_bookmarks(decision: Platform.Decision) -> +List<Finite.Entry(Reading.Bookmark)>:
  Platform.Decision{product, platform, effects} = decision
  platform_bookmarks(platform)

def stale_reading_law(-application: E.Application, -services: Services.State, -platform: Platform.Platform, -task: Nat, -generation: Nat, -event: Reading.Event, -inactive: {Platform.active_reader(application, task, generation) == False{} : Bool}) -> Type:
  {Platform.step(Platform.ReadingInput{task, generation, event},
      Platform.State{Core.State{application, services}, platform}) ==
      Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}} : Platform.Decision}

def session_readers(session: E.Session) -> +List<Finite.Entry(E.Reader)>:
  E.Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks} = session
  readers

def conversation_session(session: E.Session, task: Nat) -> E.Session:
  E.Session{route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks} = session
  E.Session{U.Conversation{task}, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}

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
  Model.Decision{Model.State{application, generation, realization, environment, font}, product, effects} = decision
  font

def model_application(state: Model.State) -> Platform.State:
  Model.State{application, generation, realization, environment, font} = state
  application

def decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  platform_capacity(platform)

def decision_application(decision: Model.Decision) -> Platform.State:
  Model.Decision{Model.State{application, generation, realization, environment, font}, product, effects} = decision
  application

type Requirements is Type:
  Requirements{reflow_same: @+decision:Platform.Decision -> @+capacity:View.Capacity ->
      @same:{Platform.same_capacity(decision_capacity(decision), capacity) == True{} : Bool} ->
      {Platform.reflow_capacity(decision, capacity) == decision : Platform.Decision},
    stale_typography: @+application: Platform.State -> @+generation: Nat -> @+realization: Rendered.State -> @+environment: Design.Environment -> @+font: F.State -> @+received: Nat -> @+metrics: +List<T.Metric> -> @stale: {Nat.is_eq(F.generation(font), received) == False{} : Bool} -> {Model.step(Model.TypographyObserved{F.Observation{received, metrics}}, Model.State{application, generation, realization, environment, font}) ==
    Model.idle(application, generation, realization, environment, font) : Model.Decision},
    reflow_capacity_fields: @+decision:Platform.Decision -> @+capacity:View.Capacity ->
      {decision_capacity(Platform.reflow_capacity(decision, capacity)) == capacity : View.Capacity},
    environment_resets_font: @+application: Platform.State -> @+generation: Nat -> @realization: Rendered.State -> @previous_environment: Design.Environment -> @font: F.State -> @+environment: Design.Environment -> {font_state(Model.step(Model.EnvironmentObserved{environment},
    Model.State{application, generation, realization, previous_environment, font})) ==
    F.begin((generation + 1n : Nat), Model.environment_root(environment)) : F.State},
    typography_product: @+state: Model.State -> @+observation: F.Observation -> {Model.product(Model.step(Model.TypographyObserved{observation}, state)) ==
    Platform.unchanged(model_core(model_application(state))) : Core.Decision},

    product_refinement: @input:Product.Input -> @core:Core.State -> @platform:Platform.Platform ->
      @environment:Design.Environment -> @font:F.State -> @generation:Nat -> @realization:Rendered.State ->
      {Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
        Model.State{Platform.State{core, platform}, generation, realization, environment, font})) == Product.step(input, core) : Core.Decision},
    element_refinement: @key:String -> @gesture:Interface.Gesture -> @core:Core.State ->
      @platform:Platform.Platform -> @environment:Design.Environment -> @font:F.State -> @generation:Nat -> @realization:Rendered.State ->
      {Model.product(Model.step(Model.ElementInput{key, gesture},
        Model.State{Platform.State{core, platform}, generation, realization, environment, font})) ==
        Product.step(Product.Element{platform_capacity(platform), key, gesture}, core) : Core.Decision},
    frame_silent: @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State ->
      @environment:Design.Environment -> @font:F.State -> @generation:Nat -> @realization:Rendered.State ->
      {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font}) ==
        Model.Decision{Model.State{application, generation,
          Model.production_frame(Nat.is_eq(generation, received), generation, frame, realization), environment, font},
          Platform.unchanged(model_core(application)), Nil{}} : Model.Decision},
    stale_frame: @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State ->
      @environment:Design.Environment -> @font:F.State -> @generation:Nat -> @realization:Rendered.State ->
      @stale:{Nat.is_eq(generation, received) == False{} : Bool} ->
      {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font}) ==
        Model.Decision{Model.State{application, generation, realization, environment, font},
          Platform.unchanged(model_core(application)), Nil{}} : Model.Decision},
    stale_reading: @application:E.Application -> @services:Services.State -> @platform:Platform.Platform ->
      @task:Nat -> @generation:Nat -> @event:Reading.Event ->
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
          Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}}, [Reading.AlignLatest{Bool.not(reduced)}]} :
          Reading.Decision},
    layout_after_product: @program:M.World() -> @session:E.Session -> @task:Nat -> @generation:Nat ->
      @disclosures:+List<E.Disclosure> -> @bookmarks:+List<Finite.Entry(Reading.Bookmark)> -> @anchor:Physical.Anchor ->
      @reader_observed:{E.reader(session_readers(session), task) == E.Reader{generation, U.ReadHistory{}, disclosures} : E.Reader} ->
      @bookmark_observed:{Finite.find(~Reading.Bookmark, bookmarks, task) ==
        Some{Reading.Bookmark{Some{anchor}}} : Maybe<&2, Reading.Bookmark>} ->
      {Platform.layout_for(E.Application{program, conversation_session(session, task)}, bookmarks) ==
        [Platform.Scroll{task, generation, Reading.PreserveAnchor{anchor}}] : +List<Platform.Effect>},
    after_core_keeps_bookmarks: @decision:Core.Decision -> @platform:Platform.Platform ->
      {decision_bookmarks(Platform.after_core(decision, platform)) == platform_bookmarks(platform) :
        +List<Finite.Entry(Reading.Bookmark)>},
    ime_entry: @owner:U.Editor -> @selection:Physical.Selection -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @core:Core.State -> @platform:Platform.Platform ->
      @editor_observed:{platform_editors(platform, owner) == Editor.Editor{owner, selection, True{}} : Editor.Editor} ->
      {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}}, Platform.State{core, platform}) ==
        Platform.Decision{Platform.unchanged(core),
          with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}} : Platform.Decision},
    ready_enter: @owner:U.Editor -> @selection:Physical.Selection -> @modified:Bool -> @core:Core.State ->
      @platform:Platform.Platform ->
      @editor_observed:{platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor} ->
      @enabled:{Platform.editor_enabled(core, owner, platform_capacity(platform)) == True{} : Bool} ->
      @permitted:{Focus.permits_composer(platform_scope(platform)) == True{} : Bool} ->
      {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
        Platform.State{core, platform})) ==
        Product.step(Product.SubmitComposer{platform_capacity(platform), owner}, core) : Core.Decision},
    temporary_enter_product: @owner:U.Editor -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @identity:String -> @initial:String -> @restore:String -> @core:Core.State -> @platform:Platform.Platform ->
      {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})})) ==
          Platform.unchanged(core) : Core.Decision},
    temporary_enter_effects: @owner:U.Editor -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
      @identity:String -> @initial:String -> @restore:String -> @core:Core.State -> @platform:Platform.Platform ->
      {platform_effects(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})})) ==
          Nil{} : +List<Platform.Effect>},
    stale_focus_ticket: @core:Core.State -> @platform:Platform.Platform -> @received:Nat -> @identity:String ->
      @stale:{Nat.is_eq(received, platform_ticket(platform)) == False{} : Bool} ->
      {Platform.step(Platform.FocusApplied{received, identity}, Platform.State{core, platform}) ==
        Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision},
    inactive_focus: @core:Core.State -> @platform:Platform.Platform -> @identity:String ->
      @inactive:{Platform.active_focus(core, platform_capacity(platform), identity) == False{} : Bool} ->
      {Platform.step(Platform.FocusApplied{platform_ticket(platform), identity}, Platform.State{core, platform}) ==
        Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision},
    synchronize_retained: @drafts:+List<U.Draft> -> @editors:+List<Editor.Editor> ->
      @retained:Retained(drafts, editors) ->
      {Platform.synchronize_drafts(drafts, editors) == editors : +List<Editor.Editor>},
    layout_sequence_preserves_bookmark: @count:Nat -> @seed:Tape ->
      {tape_bookmark(Std.iter(~Tape, ~advance, count, seed)) == tape_bookmark(seed) : Reading.Bookmark}
  }

law evidence:
  Requirements
