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

def after_core_scoped_preserves(decision: Core.Decision, platform: Platform.Platform,
  current_scope: Focus.Scope) ->
  {Model.platform_product(Platform.after_core_scoped(decision, platform, current_scope)) ==
    decision : Core.Decision}:
  match decision:
    case Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

def after_core_preserves_decision(decision: Core.Decision, platform: Platform.Platform) ->
  {Model.platform_product(Platform.after_core(decision, platform)) == decision : Core.Decision}:
  match decision:
    case Core.Decision{Core.State{+application, +services}, reply, runtime, interaction, service, durable}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}:
          after_core_scoped_preserves(
            Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable},
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope},
            Focus.current(Core.State{application, services}, capacity))

def product_input_result(input: Product.Input, +core: Core.State, +platform: Platform.Platform) ->
  {Model.platform_product(Platform.step(Platform.ProductInput{input}, Platform.State{core, platform})) ==
    Product.step(input, core) : Core.Decision}:
  match core:
    case Core.State{+application, +services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          after_core_preserves_decision(Product.step(input, Core.State{application, services}),
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})

def product_refinement(+input: Product.Input, +core: Core.State, +platform: Platform.Platform,
  generation: Nat, realization: Rendered.State) ->
  {Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
    Model.State{Platform.State{core, platform}, generation, realization})) == Product.step(input, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
      Model.State{Platform.State{core, platform}, generation, realization})),
    Model.platform_product(Platform.step(Platform.ProductInput{input}, Platform.State{core, platform})),
    Product.step(input, core),
    Model.realization_preserves_product(Platform.step(Platform.ProductInput{input},
      Platform.State{core, platform}), (generation + 1n : Nat)),
    product_input_result(input, core, platform))

def model_capacity_matches_platform(platform: Platform.Platform) ->
  {Model.capacity(platform) == platform_capacity(platform) : View.Capacity}:
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

def element_refinement(+key: String, +gesture: Interface.Gesture, +core: Core.State,
  +platform: Platform.Platform, generation: Nat, realization: Rendered.State) ->
  {Model.product(Model.step(Model.ElementInput{key, gesture},
    Model.State{Platform.State{core, platform}, generation, realization})) ==
    Product.step(Product.Element{platform_capacity(platform), key, gesture}, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.product(Model.step(Model.ElementInput{key, gesture},
      Model.State{Platform.State{core, platform}, generation, realization})),
    Model.platform_product(Platform.after_core(
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform)),
    Product.step(Product.Element{platform_capacity(platform), key, gesture}, core),
    Model.realization_preserves_product(Platform.after_core(
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform),
      (generation + 1n : Nat)),
    Equal.trans(Core.Decision,
      Model.platform_product(Platform.after_core(
        Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform)),
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core),
      Product.step(Product.Element{platform_capacity(platform), key, gesture}, core),
      after_core_preserves_decision(Product.step(Product.Element{Model.capacity(platform), key, gesture}, core),
        platform),
      Equal.cong(View.Capacity, Core.Decision,
        (capacity => Product.step(Product.Element{capacity, key, gesture}, core)),
        Model.capacity(platform), platform_capacity(platform), model_capacity_matches_platform(platform))))

def frame_silent(received: Nat, frame: Rendered.Frame, application: Platform.State,
  generation: Nat, realization: Rendered.State) ->
  {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization}) ==
    Model.Decision{
      Model.State{application, generation, Rendered.observe(generation, received, Model.surface(application), frame, realization)},
      Platform.unchanged(model_core(application)), Nil{}} : Model.Decision}:
  match application:
    case Platform.State{Core.State{application, services}, platform}: {==}

def stale_frame(+received: Nat, +frame: Rendered.Frame, +application: Platform.State,
  +generation: Nat, +realization: Rendered.State,
  stale: {Nat.is_eq(generation, received) == False{} : Bool}) ->
  {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization}) ==
    Model.Decision{Model.State{application, generation, realization},
      Platform.unchanged(model_core(application)), Nil{}} : Model.Decision}:
  Platform.State{core, platform} = application
  Equal.trans(Model.Decision,
    Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization}),
    Model.Decision{Model.State{application, generation,
      Rendered.observe(generation, received, Model.surface(application), frame, realization)},
      Platform.unchanged(core), Nil{}},
    Model.Decision{Model.State{application, generation, realization}, Platform.unchanged(core), Nil{}},
    frame_silent(received, frame, application, generation, realization),
    Equal.cong(Rendered.State, Model.Decision,
      (frame_state => Model.Decision{Model.State{application, generation, frame_state},
        Platform.unchanged(core), Nil{}}),
      Rendered.observe(generation, received, Model.surface(application), frame, realization),
      realization,
      Rendered.stale_frame_retains_state(generation, received, Model.surface(application), frame, realization, stale)))

def stale_reading(application: E.Application, services: Services.State, platform: Platform.Platform,
  task: Nat, generation: Nat, event: Reading.Event,
  inactive: {Platform.active_reader(application, task, generation) == False{} : Bool}) ->
  {Platform.step(Platform.ReadingInput{task, generation, event},
    Platform.State{Core.State{application, services}, platform}) ==
    Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}} : Platform.Decision}:
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
      Equal.cong(Bool, Platform.Decision,
        (owned => Platform.read(owned, task, generation, event, Core.State{application, services},
          Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
        Platform.active_reader(application, task, generation), False{}, inactive)

def history_layout_changed(height: F32, viewport: F32, anchor: Physical.Anchor, reduced: Bool) ->
  {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{},
    Reading.Bookmark{Some{anchor}}, reduced) ==
    Reading.Decision{Reading.Bookmark{Some{anchor}}, None{},
      [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.PreserveAnchor{anchor}]} : Reading.Decision}:
  Equal.cong(Reading.Effect, Reading.Decision,
    (effect => Reading.Decision{Reading.Bookmark{Some{anchor}}, None{},
      [Reading.ReserveComposer{Reading.reserve(height, viewport)}, effect]}),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
    Reading.PreserveAnchor{anchor},
    Reading.history_layout(anchor))

def history_layout_missing(height: F32, viewport: F32, reduced: Bool) ->
  {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{},
    Reading.Bookmark{None{}}, reduced) ==
    Reading.Decision{Reading.Bookmark{None{}}, None{},
      [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.MeasureAnchor{}]} : Reading.Decision}:
  Equal.cong(Reading.Effect, Reading.Decision,
    (effect => Reading.Decision{Reading.Bookmark{None{}}, None{},
      [Reading.ReserveComposer{Reading.reserve(height, viewport)}, effect]}),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{None{}}),
    Reading.MeasureAnchor{},
    Reading.missing_history_anchor())

def follow_latest_layout(bookmark: Reading.Bookmark, reduced: Bool) ->
  {Reading.step(Reading.FollowLatest{}, U.ReadHistory{}, bookmark, reduced) ==
    Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}}, [Reading.AlignLatest{Bool.not(reduced)}]} :
    Reading.Decision}:
  {==}

def reduced_follow_latest_layout(unit: Unit) ->
  {Reading.step(Reading.FollowLatest{}, U.ReadHistory{}, Reading.Bookmark{None{}}, True{}) ==
    Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}}, [Reading.AlignLatest{False{}}]} :
    Reading.Decision}:
  {==}

def session_readers(session: E.Session) -> +List<Finite.Entry(E.Reader)>:
  E.Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks} = session
  readers

def conversation_session(session: E.Session, task: Nat) -> E.Session:
  E.Session{route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks} = session
  E.Session{U.Conversation{task}, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}

def layout_after_product(program: M.World(), +session: E.Session, +task: Nat, +generation: Nat,
  +disclosures: +List<E.Disclosure>, +bookmarks: +List<Finite.Entry(Reading.Bookmark)>,
  +anchor: Physical.Anchor,
  +reader_observed: {E.reader(session_readers(session), task) ==
    E.Reader{generation, U.ReadHistory{}, disclosures} : E.Reader},
  bookmark_observed: {Finite.find(~Reading.Bookmark, bookmarks, task) ==
    Some{Reading.Bookmark{Some{anchor}}} : Maybe<&2, Reading.Bookmark>}) ->
  {Platform.layout_for(E.Application{program, conversation_session(session, task)}, bookmarks) ==
    [Platform.Scroll{task, generation, Reading.PreserveAnchor{anchor}}] : +List<Platform.Effect>}:
  E.Session{route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks} = session
  reader = E.reader(readers, task)
  generation_observed = Equal.cong(E.Reader, Nat, E.reader_generation, reader,
    E.Reader{generation, U.ReadHistory{}, disclosures}, reader_observed)
  position_observed = Equal.cong(E.Reader, U.ReadingIntent, E.reader_position, reader,
    E.Reader{generation, U.ReadHistory{}, disclosures}, reader_observed)
  bookmark_value = Equal.cong(Maybe<&2, Reading.Bookmark>, Reading.Bookmark,
    Platform.bookmark, Finite.find(~Reading.Bookmark, bookmarks, task),
    Some{Reading.Bookmark{Some{anchor}}}, bookmark_observed)
  layout_position = Equal.cong(U.ReadingIntent, Reading.Effect,
    (position => Reading.layout(position, Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)))),
    E.reader_position(reader), U.ReadHistory{}, position_observed)
  layout_bookmark = Equal.cong(Reading.Bookmark, Reading.Effect,
    (bookmark => Reading.layout(U.ReadHistory{}, bookmark)),
    Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)),
    Reading.Bookmark{Some{anchor}}, bookmark_value)
  layout_effect = Equal.trans(Reading.Effect,
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
    layout_position, layout_bookmark)
  layout_preserves = Equal.trans(Reading.Effect,
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
    Reading.PreserveAnchor{anchor}, layout_effect, Reading.history_layout(anchor))
  generation_effect = Equal.cong(Nat, +List<Platform.Effect>,
    (value => [Platform.Scroll{task, value, Reading.PreserveAnchor{anchor}}]),
    E.reader_generation(reader), generation, generation_observed)
  effect = Equal.cong(Reading.Effect, +List<Platform.Effect>,
    (value => [Platform.Scroll{task, E.reader_generation(reader), value}]),
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.PreserveAnchor{anchor}, layout_preserves)
  Equal.trans(+List<Platform.Effect>,
    Platform.layout_for(E.Application{program, conversation_session(session, task)}, bookmarks),
    [Platform.Scroll{task, E.reader_generation(reader), Reading.PreserveAnchor{anchor}}],
    [Platform.Scroll{task, generation, Reading.PreserveAnchor{anchor}}],
    effect, generation_effect)

def after_core_keeps_bookmarks(decision: Core.Decision, platform: Platform.Platform) ->
  {decision_bookmarks(Platform.after_core(decision, platform)) == platform_bookmarks(platform) :
    +List<Finite.Entry(Reading.Bookmark)>}:
  match decision:
    case Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable}:
      Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
      {==}

def ime_entry(+owner: U.Editor, +selection: Physical.Selection, +shift: Bool, +alt: Bool, +modified: Bool,
  +core: Core.State, +platform: Platform.Platform,
  editor_observed: {platform_editors(platform, owner) == Editor.Editor{owner, selection, True{}} : Editor.Editor}) ->
  {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core),
      with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          editor_result = Editor.composing_enter(owner, selection, shift, alt, modified,
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
              Focus.permits_composer(scope), False{})
          local_result = Equal.trans(Editor.Decision,
            Editor.step(Platform.find_editor(editors, owner), Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.step(Editor.Editor{owner, selection, True{}}, Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.Decision{Editor.Editor{owner, selection, True{}}, False{}},
            Equal.cong(Editor.Editor, Editor.Decision,
              (editor => Editor.step(editor, Editor.Enter{shift, alt, modified},
                Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                  Focus.permits_composer(scope), False{})),
              Platform.find_editor(editors, owner), Editor.Editor{owner, selection, True{}}, editor_observed),
            editor_result)
          Equal.cong(Editor.Decision, Platform.Decision,
            (result => Platform.edit_result(result, owner, Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Editor.step(Platform.find_editor(editors, owner), Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.Decision{Editor.Editor{owner, selection, True{}}, False{}}, local_result)

def both_true(first: Bool, second: Bool,
  first_true: {first == True{} : Bool}, second_true: {second == True{} : Bool}) ->
  {first && second == True{} : Bool}:
  Equal.trans(Bool, first && second, True{} && second, True{},
    Equal.cong(Bool, Bool, (value => value && second), first, True{}, first_true),
    Equal.cong(Bool, Bool, (value => True{} && value), second, True{}, second_true))

def ready_enter_key(modified: Bool) ->
  {Physical.submit_key(False{}, True{}, True{}, modified, False{}, False{}, True{}, False{}) == True{} : Bool}:
  {==}

def ready_enter_editor(+owner: U.Editor, +selection: Physical.Selection, +modified: Bool,
  +core: Core.State, +platform: Platform.Platform,
  editor_observed: {platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor},
  enabled: {Platform.editor_enabled(core, owner, platform_capacity(platform)) == True{} : Bool},
  permitted: {Focus.permits_composer(platform_scope(platform)) == True{} : Bool}) ->
  {Editor.step(platform_editors(platform, owner), Editor.Enter{False{}, False{}, modified},
    Platform.editor_enabled(core, owner, platform_capacity(platform)) &&
      Focus.permits_composer(platform_scope(platform)), False{}) ==
    Editor.Decision{Editor.Editor{owner, selection, False{}}, True{}} : Editor.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          enabled_scope = both_true(Platform.editor_enabled(Core.State{application, services}, owner, capacity),
            Focus.permits_composer(scope), enabled, permitted)
          selected_editor: Editor.Editor = Editor.Editor{owner, selection, False{}}
          literal_enabled = Equal.cong(Bool, Editor.Decision,
            (value => Editor.step(selected_editor, Editor.Enter{False{}, False{}, modified}, value, False{})),
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
              Focus.permits_composer(scope), True{}, enabled_scope)
          literal_submit = Equal.cong(Bool, Editor.Decision,
            (requested => Editor.Decision{selected_editor, requested}),
            Physical.submit_key(False{}, True{}, True{}, modified, False{}, False{}, True{}, False{}),
            True{}, ready_enter_key(modified))
          literal_result = Equal.trans(Editor.Decision,
            Editor.step(selected_editor, Editor.Enter{False{}, False{}, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.step(selected_editor, Editor.Enter{False{}, False{}, modified}, True{}, False{}),
            Editor.Decision{selected_editor, True{}}, literal_enabled, literal_submit)
          Equal.trans(Editor.Decision,
            Editor.step(Platform.find_editor(editors, owner), Editor.Enter{False{}, False{}, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.step(selected_editor, Editor.Enter{False{}, False{}, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(scope), False{}),
            Editor.Decision{selected_editor, True{}},
            Equal.cong(Editor.Editor, Editor.Decision,
              (editor => Editor.step(editor, Editor.Enter{False{}, False{}, modified},
                Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                  Focus.permits_composer(scope), False{})),
              Platform.find_editor(editors, owner), selected_editor, editor_observed),
            literal_result)

def ready_enter(+owner: U.Editor, +selection: Physical.Selection, +modified: Bool, +core: Core.State,
  +platform: Platform.Platform,
  editor_observed: {platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor},
  enabled: {Platform.editor_enabled(core, owner, platform_capacity(platform)) == True{} : Bool},
  permitted: {Focus.permits_composer(platform_scope(platform)) == True{} : Bool}) ->
  {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})) ==
    Product.step(Product.SubmitComposer{platform_capacity(platform), owner}, core) : Core.Decision}:
  match core:
    case Core.State{+application, +services}:
      match platform:
        case Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}:
          selected = Editor.step(Platform.find_editor(editors, owner),
            Editor.Enter{False{}, False{}, modified},
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
              Focus.permits_composer(scope), False{})
          selected_ok = ready_enter_editor(owner, selection, modified,
            Core.State{application, services},
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope},
            editor_observed, enabled, permitted)
          decision_ok = Equal.cong(Editor.Decision, Core.Decision,
            (result => Model.platform_product(Platform.edit_result(result, owner,
              Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))),
            selected, Editor.Decision{Editor.Editor{owner, selection, False{}}, True{}}, selected_ok)
          Equal.trans(Core.Decision,
            Model.platform_product(Platform.step(Platform.EditorInput{owner,
              Editor.Enter{False{}, False{}, modified}},
              Platform.State{Core.State{application, services},
                Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}})),
            Model.platform_product(Platform.edit_result(
              Editor.Decision{Editor.Editor{owner, selection, False{}}, True{}}, owner,
              Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Product.step(Product.SubmitComposer{capacity, owner}, Core.State{application, services}),
            Equal.trans(Core.Decision,
              Model.platform_product(Platform.step(Platform.EditorInput{owner,
                Editor.Enter{False{}, False{}, modified}},
                Platform.State{Core.State{application, services},
                  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}})),
              Model.platform_product(Platform.edit_result(selected, owner,
                Core.State{application, services},
                Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
              Model.platform_product(Platform.edit_result(
                Editor.Decision{Editor.Editor{owner, selection, False{}}, True{}}, owner,
                Core.State{application, services},
                Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
              Equal.cong(Editor.Decision, Core.Decision,
                (result => Model.platform_product(Platform.edit_result(result, owner,
                  Core.State{application, services},
                  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))),
                Editor.step(Platform.find_editor(editors, owner),
                  Editor.Enter{False{}, False{}, modified},
                  Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                    Focus.permits_composer(scope), False{}),
                selected, {==}),
              decision_ok),
            after_core_preserves_decision(
              Product.step(Product.SubmitComposer{capacity, owner}, Core.State{application, services}),
              Platform.Platform{readers,
                Platform.save_editor(editors, owner, Editor.Editor{owner, selection, False{}}),
                focused, ticket, reduced, capacity, scope}))

def and_false_right(value: Bool) -> {value && False{} == False{} : Bool}:
  match value:
    case True{}: {==}
    case False{}: {==}

def and_false_left(value: Bool) -> {False{} && value == False{} : Bool}:
  {==}

def enter_disabled(composing: Bool, shift: Bool, alt: Bool, modified: Bool, pending: Bool) ->
  {Physical.submit_key(composing, True{}, True{}, modified, shift, alt, False{}, pending) == False{} : Bool}:
  prefix = Bool.not(composing) && True{} && Bool.not(shift) && Bool.not(alt) && (True{} || modified)
  Equal.trans(Bool,
    Physical.submit_key(composing, True{}, True{}, modified, shift, alt, False{}, pending),
    False{} && Bool.not(pending), False{},
    Equal.cong(Bool, Bool, (enabled => enabled && Bool.not(pending)),
      prefix && False{}, False{}, and_false_right(prefix)),
    and_false_left(Bool.not(pending)))

def enter_disabled_editor(editor: Editor.Editor, shift: Bool, alt: Bool, modified: Bool) ->
  {Editor.step(editor, Editor.Enter{shift, alt, modified}, False{}, False{}) ==
    Editor.Decision{editor, False{}} : Editor.Decision}:
  Editor.Editor{owner, selection, composing} = editor
  Equal.cong(Bool, Editor.Decision,
    (requested => Editor.Decision{Editor.Editor{owner, selection, composing}, requested}),
    Physical.submit_key(composing, True{}, True{}, modified, shift, alt, False{}, False{}),
    False{},
    enter_disabled(composing, shift, alt, modified, False{}))

def modal_enter_decision(+owner: U.Editor, +shift: Bool, +alt: Bool, +modified: Bool,
  identity: String, initial: String, restore: String, +core: Core.State, +platform: Platform.Platform) ->
  {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})}) ==
    Platform.Decision{Platform.unchanged(core),
      with_saved_editor(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner,
        platform_editors(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner)), Nil{}} :
    Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}:
          temporary = with_scope(
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope},
            Focus.Temporary{identity, initial, restore})
          selected: Editor.Editor = Platform.find_editor(editors, owner)
          disabled = Equal.trans(Bool,
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
              Focus.permits_composer(Focus.Temporary{identity, initial, restore}),
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) && False{},
            False{},
            Equal.cong(Bool, Bool,
              (permits => Platform.editor_enabled(Core.State{application, services}, owner, capacity) && permits),
              Focus.permits_composer(Focus.Temporary{identity, initial, restore}), False{}, {==}),
            and_false_right(Platform.editor_enabled(Core.State{application, services}, owner, capacity)))
          local_result = Equal.trans(Editor.Decision,
            Editor.step(selected, Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore}), False{}),
            Editor.step(selected, Editor.Enter{shift, alt, modified}, False{}, False{}),
            Editor.Decision{selected, False{}},
            Equal.cong(Bool, Editor.Decision,
              (enabled => Editor.step(selected, Editor.Enter{shift, alt, modified}, enabled, False{})),
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore}), False{}, disabled),
            enter_disabled_editor(selected, shift, alt, modified))
          Equal.cong(Editor.Decision, Platform.Decision,
            (result => Platform.edit_result(result, owner, Core.State{application, services}, temporary)),
            Editor.step(selected, Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore}), False{}),
            Editor.Decision{selected, False{}}, local_result)

def RetainedEntry(found: Maybe<&2, U.Draft>) -> Type:
  match found:
    case None{}: Unit
    case Some{U.Draft{revision, body, U.Editing{}}}: Unit
    case Some{U.Draft{revision, body, U.Rejected{revision, reason}}}: Unit
    case Some{U.Draft{revision, body, U.Accepted{revision, reply}}}: Empty

def Retained(drafts: +List<U.Draft>, editors: +List<Editor.Editor>) -> Type:
  match editors:
    case Nil{}: Unit
    case Con{Editor.Editor{+owner, selection, composing}, rest}:
      RetainedEntry(E.find_draft(drafts, owner)) & Retained(drafts, rest)

def synchronize_retained_entry(found: Maybe<&2, U.Draft>, editor: Editor.Editor,
  evidence: RetainedEntry(found)) ->
  {Platform.synchronize_editor(found, editor) == editor : Editor.Editor}:
  match found evidence:
    case None{} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Editing{}}} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Rejected{revision, reason}}} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Accepted{revision, reply}}} impossible:
      match impossible:

def synchronize_retained(+drafts: +List<U.Draft>, +editors: +List<Editor.Editor>,
  evidence: Retained(drafts, editors)) ->
  {Platform.synchronize_drafts(drafts, editors) == editors : +List<Editor.Editor>}:
  match editors:
    case Nil{}:
      match evidence:
        case Unit{}: {==}
    case Con{Editor.Editor{+owner, selection, composing}, rest}:
      match evidence:
        case (head, tail):
          +editor: Editor.Editor = Editor.Editor{owner, selection, composing}
          head_equal = synchronize_retained_entry(E.find_draft(drafts, owner), editor, head)
          tail_equal = synchronize_retained(drafts, rest, tail)
          head_list = Equal.cong(Editor.Editor, +List<Editor.Editor>,
            (value => value <> Platform.synchronize_drafts(drafts, rest)),
            Platform.synchronize_editor(E.find_draft(drafts, owner), editor), editor, head_equal)
          Equal.trans(+List<Editor.Editor>,
            Platform.synchronize_editor(E.find_draft(drafts, owner), editor) <>
              Platform.synchronize_drafts(drafts, rest),
            editor <> Platform.synchronize_drafts(drafts, rest),
            editor <> rest,
            head_list,
            Equal.cong(+List<Editor.Editor>, +List<Editor.Editor>,
              (tail_value => editor <> tail_value),
              Platform.synchronize_drafts(drafts, rest), rest, tail_equal))

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

def advance_preserves_bookmark(tape: Tape) ->
  {tape_bookmark(advance(tape)) == tape_bookmark(tape) : Reading.Bookmark}:
  match tape:
    case Tape{bookmark, pending, receipts, reduced}:
      match pending:
        case Nil{}: {==}
        case Con{Size{composer, viewport}, rest}: {==}

def layout_sequence_preserves_bookmark(count: Nat, seed: Tape) ->
  {tape_bookmark(Std.iter(~Tape, ~advance, count, seed)) == tape_bookmark(seed) : Reading.Bookmark}:
  Std.nat_ind(~(steps => @+initial:Tape ->
      {tape_bookmark(Std.iter(~Tape, ~advance, steps, initial)) == tape_bookmark(initial) : Reading.Bookmark}),
    ~(initial => {==}),
    ~(steps => evidence => initial =>
      Equal.trans(Reading.Bookmark,
        tape_bookmark(advance(Std.iter(~Tape, ~advance, steps, initial))),
        tape_bookmark(Std.iter(~Tape, ~advance, steps, initial)),
        tape_bookmark(initial),
        advance_preserves_bookmark(Std.iter(~Tape, ~advance, steps, initial)), evidence(initial))),
    count)(seed)

def temporary_enter_product(owner: U.Editor, shift: Bool, alt: Bool, modified: Bool,
  identity: String, initial: String, restore: String, core: Core.State, platform: Platform.Platform) ->
  {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})})) ==
    Platform.unchanged(core) : Core.Decision}:
  Equal.cong(Platform.Decision, Core.Decision, Model.platform_product,
    Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
      Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})}),
    Platform.Decision{Platform.unchanged(core),
      with_saved_editor(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner,
        platform_editors(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner)), Nil{}},
    modal_enter_decision(owner, shift, alt, modified, identity, initial, restore, core, platform))

def temporary_enter_effects(owner: U.Editor, shift: Bool, alt: Bool, modified: Bool,
  identity: String, initial: String, restore: String, core: Core.State, platform: Platform.Platform) ->
  {platform_effects(Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})})) ==
    Nil{} : +List<Platform.Effect>}:
  Equal.cong(Platform.Decision, +List<Platform.Effect>, platform_effects,
    Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
      Platform.State{core, with_scope(platform, Focus.Temporary{identity, initial, restore})}),
    Platform.Decision{Platform.unchanged(core),
      with_saved_editor(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner,
        platform_editors(with_scope(platform, Focus.Temporary{identity, initial, restore}), owner)), Nil{}},
    modal_enter_decision(owner, shift, alt, modified, identity, initial, restore, core, platform))

def stale_focus_ticket(core: Core.State, platform: Platform.Platform, received: Nat, identity: String,
  stale: {Nat.is_eq(received, platform_ticket(platform)) == False{} : Bool}) ->
  {Platform.step(Platform.FocusApplied{received, identity}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          Equal.cong(Bool, Platform.Decision,
            (owned => Platform.focus_result(owned, identity, Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Nat.is_eq(received, ticket) && Platform.active_focus(Core.State{application, services}, capacity, identity),
            False{},
            Equal.trans(Bool,
              Nat.is_eq(received, ticket) && Platform.active_focus(Core.State{application, services}, capacity, identity),
              False{} && Platform.active_focus(Core.State{application, services}, capacity, identity),
              False{},
              Equal.cong(Bool, Bool,
                (expected => expected && Platform.active_focus(Core.State{application, services}, capacity, identity)),
                Nat.is_eq(received, platform_ticket(platform)), False{}, stale),
              and_false_left(Platform.active_focus(Core.State{application, services}, capacity, identity))))

def inactive_focus(core: Core.State, platform: Platform.Platform, identity: String,
  inactive: {Platform.active_focus(core, platform_capacity(platform), identity) == False{} : Bool}) ->
  {Platform.step(Platform.FocusApplied{platform_ticket(platform), identity}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, +ticket, reduced, capacity, scope}:
          Equal.cong(Bool, Platform.Decision,
            (owned => Platform.focus_result(owned, identity, Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Nat.is_eq(platform_ticket(platform), ticket) &&
              Platform.active_focus(Core.State{application, services}, capacity, identity),
            False{},
            Equal.trans(Bool,
              Nat.is_eq(platform_ticket(platform), ticket) &&
                Platform.active_focus(Core.State{application, services}, capacity, identity),
              Nat.is_eq(platform_ticket(platform), ticket) && False{},
              False{},
              Equal.cong(Bool, Bool,
                (is_active => Nat.is_eq(platform_ticket(platform), ticket) && is_active),
                Platform.active_focus(core, platform_capacity(platform), identity), False{}, inactive),
              and_false_right(Nat.is_eq(platform_ticket(platform), ticket))))

type Requirements is Type:
  Requirements{
    product_refinement: @input:Product.Input -> @core:Core.State -> @platform:Platform.Platform ->
      @generation:Nat -> @realization:Rendered.State ->
      {Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
        Model.State{Platform.State{core, platform}, generation, realization})) == Product.step(input, core) : Core.Decision},
    element_refinement: @key:String -> @gesture:Interface.Gesture -> @core:Core.State ->
      @platform:Platform.Platform -> @generation:Nat -> @realization:Rendered.State ->
      {Model.product(Model.step(Model.ElementInput{key, gesture},
        Model.State{Platform.State{core, platform}, generation, realization})) ==
        Product.step(Product.Element{platform_capacity(platform), key, gesture}, core) : Core.Decision},
    frame_silent: @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State ->
      {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization}) ==
        Model.Decision{Model.State{application, generation,
          Rendered.observe(generation, received, Model.surface(application), frame, realization)},
          Platform.unchanged(model_core(application)), Nil{}} : Model.Decision},
    stale_frame: @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State ->
      @stale:{Nat.is_eq(generation, received) == False{} : Bool} ->
      {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization}) ==
        Model.Decision{Model.State{application, generation, realization},
          Platform.unchanged(model_core(application)), Nil{}} : Model.Decision},
    stale_reading: @application:E.Application -> @services:Services.State -> @platform:Platform.Platform ->
      @task:Nat -> @generation:Nat -> @event:Reading.Event ->
      @inactive:{Platform.active_reader(application, task, generation) == False{} : Bool} ->
      {Platform.step(Platform.ReadingInput{task, generation, event},
        Platform.State{Core.State{application, services}, platform}) ==
        Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}} : Platform.Decision},
    history_layout_changed: @height:F32 -> @viewport:F32 -> @anchor:Physical.Anchor -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{}, Reading.Bookmark{Some{anchor}}, reduced) ==
        Reading.Decision{Reading.Bookmark{Some{anchor}}, None{},
          [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.PreserveAnchor{anchor}]} : Reading.Decision},
    history_layout_missing: @height:F32 -> @viewport:F32 -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{height, viewport}, U.ReadHistory{}, Reading.Bookmark{None{}}, reduced) ==
        Reading.Decision{Reading.Bookmark{None{}}, None{},
          [Reading.ReserveComposer{Reading.reserve(height, viewport)}, Reading.MeasureAnchor{}]} : Reading.Decision},
    follow_latest_layout: @bookmark:Reading.Bookmark -> @reduced:Bool ->
      {Reading.step(Reading.FollowLatest{}, U.ReadHistory{}, bookmark, reduced) ==
        Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}},
          [Reading.AlignLatest{Bool.not(reduced)}]} : Reading.Decision},
    reduced_follow_latest_layout: @unit:Unit ->
      {Reading.step(Reading.FollowLatest{}, U.ReadHistory{}, Reading.Bookmark{None{}}, True{}) ==
        Reading.Decision{Reading.Bookmark{None{}}, Some{U.FollowLatest{}},
          [Reading.AlignLatest{False{}}]} : Reading.Decision},
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

def evidence() -> Requirements:
  Requirements{
    input => core => platform => generation => realization =>
      product_refinement(input, core, platform, generation, realization),
    key => gesture => core => platform => generation => realization =>
      element_refinement(key, gesture, core, platform, generation, realization),
    received => frame => application => generation => realization =>
      frame_silent(received, frame, application, generation, realization),
    received => frame => application => generation => realization => stale =>
      stale_frame(received, frame, application, generation, realization, stale),
    application => services => platform => task => generation => event => inactive =>
      stale_reading(application, services, platform, task, generation, event, inactive),
    height => viewport => anchor => reduced => history_layout_changed(height, viewport, anchor, reduced),
    height => viewport => reduced => history_layout_missing(height, viewport, reduced),
    bookmark => reduced => follow_latest_layout(bookmark, reduced),
    unit => reduced_follow_latest_layout(unit),
    program => session => task => generation => disclosures => bookmarks => anchor => reader_observed => bookmark_observed =>
      layout_after_product(program, session, task, generation, disclosures, bookmarks, anchor,
        reader_observed, bookmark_observed),
    decision => platform => after_core_keeps_bookmarks(decision, platform),
    owner => selection => shift => alt => modified => core => platform => editor_observed =>
      ime_entry(owner, selection, shift, alt, modified, core, platform, editor_observed),
    owner => selection => modified => core => platform => editor_observed => enabled => permitted =>
      ready_enter(owner, selection, modified, core, platform, editor_observed, enabled, permitted),
    owner => shift => alt => modified => identity => initial => restore => core => platform =>
      temporary_enter_product(owner, shift, alt, modified, identity, initial, restore, core, platform),
    owner => shift => alt => modified => identity => initial => restore => core => platform =>
      temporary_enter_effects(owner, shift, alt, modified, identity, initial, restore, core, platform),
    core => platform => received => identity => stale =>
      stale_focus_ticket(core, platform, received, identity, stale),
    core => platform => identity => inactive => inactive_focus(core, platform, identity, inactive),
    drafts => editors => retained => synchronize_retained(drafts, editors, retained),
    count => seed => layout_sequence_preserves_bookmark(count, seed)
  }
