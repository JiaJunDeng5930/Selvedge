import Base
import ../../MODEL.bend as M
import ../../UI.bend as Product
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/stdlib.bend as Std
import ../../core/SYSTEM.bend as Core
import ../../core/client-services.bend as Services
import ../../core/interface.bend as Interface
import ../../core/ui-world.bend as View
import ../../core/user-experience.bend as E
import ../../core/user-input.bend as U
import ../MODEL.bend as Model
import ../design.bend as Design
import ../font-observation.bend as F
import ../typography.bend as T
import ../editor.bend as Editor
import ../focus.bend as Focus
import ../interaction.bend as Physical
import ../platform.bend as Platform
import ../reading.bend as Reading
import ../rendered.bend as Rendered

import ../laws.bend as Rule
import ../paint-rules.bend as PaintRules
import ../physical-renderer-rules.bend as RendererRules
import ./paint.bend as ProofPaint
import ./physical-renderer.bend as ProofRenderer
import ../../bendlib/proofs/logic.bend as Logic
import ../editor-rules.bend as Rules_editor_rules
import ../model-rules.bend as Rules_model_rules
import ../reading-rules.bend as Rules_reading_rules
import ./platform.bend as Proof_platform
import ../platform-rules.bend as Rules_platform

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

def product_input_result_raw(input: Product.Input, +core: Core.State, +platform: Platform.Platform) ->
  {Model.platform_product(Platform.step_raw(Platform.ProductInput{input}, Platform.State{core, platform})) ==
    Product.step(input, core) : Core.Decision}:
  match core:
    case Core.State{+application, +services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          after_core_preserves_decision(Product.step(input, Core.State{application, services}),
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})

def product_input_result(+input: Product.Input, +core: Core.State, +platform: Platform.Platform) ->
  {Model.platform_product(Platform.step(Platform.ProductInput{input}, Platform.State{core, platform})) ==
    Product.step(input, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.platform_product(Platform.step(Platform.ProductInput{input}, Platform.State{core, platform})),
    Model.platform_product(Platform.step_raw(Platform.ProductInput{input}, Platform.State{core, platform})),
    Product.step(input, core),
    Rules_platform.realized_preserves_product(Platform.step_raw(Platform.ProductInput{input}, Platform.State{core, platform})),
    product_input_result_raw(input, core, platform))

def product_refinement(+input: Product.Input, +core: Core.State, +platform: Platform.Platform,
  generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State) ->
  {Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
    Model.State{Platform.State{core, platform}, generation, realization, environment, font})) == Product.step(input, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.product(Model.step(Model.PlatformInput{Platform.ProductInput{input}},
      Model.State{Platform.State{core, platform}, generation, realization, environment, font})),
    Model.platform_product(Platform.step(Platform.ProductInput{input}, Platform.State{core, platform})),
    Product.step(input, core),
    Rules_model_rules.production_commit_preserves_product(Platform.step(Platform.ProductInput{input},
      Platform.State{core, platform}), (generation + 1n : Nat), environment, font),
    product_input_result(input, core, platform))

def model_capacity_matches_platform(platform: Platform.Platform) ->
  {Model.capacity(platform) == Rule.platform_capacity(platform) : View.Capacity}:
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

def element_refinement(+key: String, +gesture: Interface.Gesture, +core: Core.State,
  +platform: Platform.Platform, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, font: F.State) ->
  {Model.product(Model.step(Model.ElementInput{key, gesture},
    Model.State{Platform.State{core, platform}, generation, realization, environment, font})) ==
    Product.step(Product.Element{Rule.platform_capacity(platform), key, gesture}, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.product(Model.step(Model.ElementInput{key, gesture},
      Model.State{Platform.State{core, platform}, generation, realization, environment, font})),
    Model.platform_product(Platform.after_core(
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform)),
    Product.step(Product.Element{Rule.platform_capacity(platform), key, gesture}, core),
    Rules_model_rules.production_commit_preserves_product(Platform.after_core(
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform),
      (generation + 1n : Nat), environment, font),
    Equal.trans(Core.Decision,
      Model.platform_product(Platform.after_core(
        Product.step(Product.Element{Model.capacity(platform), key, gesture}, core), platform)),
      Product.step(Product.Element{Model.capacity(platform), key, gesture}, core),
      Product.step(Product.Element{Rule.platform_capacity(platform), key, gesture}, core),
      after_core_preserves_decision(Product.step(Product.Element{Model.capacity(platform), key, gesture}, core),
        platform),
      Equal.cong(View.Capacity, Core.Decision,
        (capacity => Product.step(Product.Element{capacity, key, gesture}, core)),
        Model.capacity(platform), Rule.platform_capacity(platform), model_capacity_matches_platform(platform))))

def frame_silent(received: Nat, frame: Rendered.Frame, application: Platform.State,
  generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State) ->
  {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font}) ==
    Model.Decision{
      Model.State{application, generation, realization, environment, font},
      Platform.unchanged(Rule.model_core(application)), Nil{}} : Model.Decision}:
  match application:
    case Platform.State{Core.State{application, services}, platform}: {==}

def stale_frame(+received: Nat, +frame: Rendered.Frame, +application: Platform.State,
  +generation: Nat, +realization: Rendered.State, +environment: Design.Environment, +font: F.State,
  stale: {Nat.is_eq(generation, received) == False{} : Bool}) ->
  {Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font}) ==
    Model.Decision{Model.State{application, generation, realization, environment, font},
      Platform.unchanged(Rule.model_core(application)), Nil{}} : Model.Decision}:
  frame_silent(received, frame, application, generation, realization, environment, font)

def stale_reading_raw(application: E.Application, services: Services.State, platform: Platform.Platform,
  task: Nat, generation: Nat, event: Reading.ReadingEvent,
  inactive: {Platform.active_reader(application, task, generation) == False{} : Bool}) -> {Platform.step_raw(Platform.ReadingInput{task, generation, event}, Platform.State{Core.State{application, services}, platform}) == Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}} : Platform.Decision}:
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
      Equal.cong(Bool, Platform.Decision,
        (owned => Platform.read(owned, task, generation, event, Core.State{application, services},
          Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
        Platform.active_reader(application, task, generation), False{}, inactive)


def layout_after_product(program: M.World(), +session: E.Session, +task: Nat, +generation: Nat,
  +disclosures: +List<E.Disclosure>, +bookmarks: +List<Finite.Entry(Reading.Bookmark)>,
  +anchor: Physical.Anchor,
  +reader_observed: {E.reader(Rule.session_readers(session), task) ==
    E.Reader{generation, U.ReadHistory{}, disclosures} : E.Reader},
  bookmark_observed: {Finite.find(~Reading.Bookmark, bookmarks, task) ==
    Some{Reading.Bookmark{Some{anchor}}} : Maybe<&2, Reading.Bookmark>}) ->
  {Platform.layout_for(E.Application{program, Rule.conversation_session(session, task)}, bookmarks) ==
    [Platform.ApplyReading{task, generation, Reading.PreserveAnchor{anchor}}] : +List<Platform.Effect>}:
  E.Session{route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks, next_layer} = session
  reader = E.reader(readers, task)
  generation_observed = Equal.cong(E.Reader, Nat, E.reader_generation, reader,
    E.Reader{generation, U.ReadHistory{}, disclosures}, reader_observed)
  position_observed = Equal.cong(E.Reader, U.ReadingIntent, E.reader_position, reader,
    E.Reader{generation, U.ReadHistory{}, disclosures}, reader_observed)
  bookmark_value = Equal.cong(Maybe<&2, Reading.Bookmark>, Reading.Bookmark,
    Platform.bookmark, Finite.find(~Reading.Bookmark, bookmarks, task),
    Some{Reading.Bookmark{Some{anchor}}}, bookmark_observed)
  layout_position = Equal.cong(U.ReadingIntent, +List<Reading.Effect>,
    (position => Reading.layout(position, Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)))),
    E.reader_position(reader), U.ReadHistory{}, position_observed)
  layout_bookmark = Equal.cong(Reading.Bookmark, +List<Reading.Effect>,
    (bookmark => Reading.layout(U.ReadHistory{}, bookmark)),
    Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)),
    Reading.Bookmark{Some{anchor}}, bookmark_value)
  layout_effect = Equal.trans(+List<Reading.Effect>,
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
    layout_position, layout_bookmark)
  layout_preserves = Equal.trans(+List<Reading.Effect>,
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
    [Reading.PreserveAnchor{anchor}], layout_effect, Rules_reading_rules.history_layout(anchor))
  generation_effect = Equal.cong(Nat, +List<Platform.Effect>,
    (value => [Platform.ApplyReading{task, value, Reading.PreserveAnchor{anchor}}]),
    E.reader_generation(reader), generation, generation_observed)
  effect = Equal.cong(+List<Reading.Effect>, +List<Platform.Effect>,
    (value => Platform.wrap_scroll(value, task, E.reader_generation(reader))),
    Reading.layout(E.reader_position(reader), Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))),
    [Reading.PreserveAnchor{anchor}], layout_preserves)
  Equal.trans(+List<Platform.Effect>,
    Platform.layout_for(E.Application{program, Rule.conversation_session(session, task)}, bookmarks),
    [Platform.ApplyReading{task, E.reader_generation(reader), Reading.PreserveAnchor{anchor}}],
    [Platform.ApplyReading{task, generation, Reading.PreserveAnchor{anchor}}],
    effect, generation_effect)

def after_core_keeps_bookmarks(decision: Core.Decision, platform: Platform.Platform) ->
  {Rule.decision_bookmarks(Platform.after_core(decision, platform)) == Rule.platform_bookmarks(platform) :
    +List<Finite.Entry(Reading.Bookmark)>}:
  match decision:
    case Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable}:
      Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
      {==}

def ime_entry_raw(+owner: U.Editor, +selection: Physical.Selection, +shift: Bool, +alt: Bool, +modified: Bool,
  +core: Core.State, +platform: Platform.Platform,
  editor_observed: {Rule.platform_editors(platform, owner) == Editor.Editor{owner, selection, True{}} : Editor.Editor}) ->
  {Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          editor_result = Rules_editor_rules.composing_enter(owner, selection, shift, alt, modified,
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
  editor_observed: {Rule.platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor},
  enabled: {Platform.editor_enabled(core, owner, Rule.platform_capacity(platform)) == True{} : Bool},
  permitted: {Focus.permits_composer(Rule.platform_scope(platform)) == True{} : Bool}) ->
  {Editor.step(Rule.platform_editors(platform, owner), Editor.Enter{False{}, False{}, modified},
    Platform.editor_enabled(core, owner, Rule.platform_capacity(platform)) &&
      Focus.permits_composer(Rule.platform_scope(platform)), False{}) ==
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

def ready_enter_raw(+owner: U.Editor, +selection: Physical.Selection, +modified: Bool, +core: Core.State,
  +platform: Platform.Platform,
  editor_observed: {Rule.platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor},
  enabled: {Platform.editor_enabled(core, owner, Rule.platform_capacity(platform)) == True{} : Bool},
  permitted: {Focus.permits_composer(Rule.platform_scope(platform)) == True{} : Bool}) ->
  {Model.platform_product(Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})) ==
    Product.step(Product.SubmitComposer{Rule.platform_capacity(platform), owner}, core) : Core.Decision}:
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
            Model.platform_product(Platform.step_raw(Platform.EditorInput{owner,
              Editor.Enter{False{}, False{}, modified}},
              Platform.State{Core.State{application, services},
                Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}})),
            Model.platform_product(Platform.edit_result(
              Editor.Decision{Editor.Editor{owner, selection, False{}}, True{}}, owner,
              Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Product.step(Product.SubmitComposer{capacity, owner}, Core.State{application, services}),
            Equal.trans(Core.Decision,
              Model.platform_product(Platform.step_raw(Platform.EditorInput{owner,
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

def modal_enter_decision_raw(+owner: U.Editor, +shift: Bool, +alt: Bool, +modified: Bool,
  identity: String, initial: String, restore: String, +occurrence: Maybe<&2, Nat>, +core: Core.State, +platform: Platform.Platform) ->
  {Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}) ==
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}} :
    Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}:
          temporary = Rule.with_scope(
            Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope},
            Focus.Temporary{identity, initial, restore, occurrence})
          selected: Editor.Editor = Platform.find_editor(editors, owner)
          disabled = Equal.trans(Bool,
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
              Focus.permits_composer(Focus.Temporary{identity, initial, restore, occurrence}),
            Platform.editor_enabled(Core.State{application, services}, owner, capacity) && False{},
            False{},
            Equal.cong(Bool, Bool,
              (permits => Platform.editor_enabled(Core.State{application, services}, owner, capacity) && permits),
              Focus.permits_composer(Focus.Temporary{identity, initial, restore, occurrence}), False{}, {==}),
            and_false_right(Platform.editor_enabled(Core.State{application, services}, owner, capacity)))
          local_result = Equal.trans(Editor.Decision,
            Editor.step(selected, Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore, occurrence}), False{}),
            Editor.step(selected, Editor.Enter{shift, alt, modified}, False{}, False{}),
            Editor.Decision{selected, False{}},
            Equal.cong(Bool, Editor.Decision,
              (enabled => Editor.step(selected, Editor.Enter{shift, alt, modified}, enabled, False{})),
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore, occurrence}), False{}, disabled),
            enter_disabled_editor(selected, shift, alt, modified))
          Equal.cong(Editor.Decision, Platform.Decision,
            (result => Platform.edit_result(result, owner, Core.State{application, services}, temporary)),
            Editor.step(selected, Editor.Enter{shift, alt, modified},
              Platform.editor_enabled(Core.State{application, services}, owner, capacity) &&
                Focus.permits_composer(Focus.Temporary{identity, initial, restore, occurrence}), False{}),
            Editor.Decision{selected, False{}}, local_result)

def synchronize_retained_entry(found: Maybe<&2, U.Draft>, editor: Editor.Editor,
  evidence: Rule.RetainedEntry(found)) ->
  {Platform.synchronize_editor(found, editor) == editor : Editor.Editor}:
  match found evidence:
    case None{} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Editing{}, directory_entry}} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Rejected{revision, reason}, directory_entry}} Unit{}: {==}
    case Some{U.Draft{revision, body, U.Accepted{revision, reply}, directory_entry}} impossible:
      match impossible:

def synchronize_retained(+drafts: +List<U.Draft>, +editors: +List<Editor.Editor>,
  evidence: Rule.Retained(drafts, editors)) ->
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

def advance_preserves_bookmark(tape: Rule.Tape) ->
  {Rule.tape_bookmark(Rule.advance(tape)) == Rule.tape_bookmark(tape) : Reading.Bookmark}:
  match tape:
    case Rule.Tape{bookmark, pending, receipts, reduced}:
      match pending:
        case Nil{}: {==}
        case Con{Rule.Size{composer, viewport}, rest}: {==}


def stale_focus_ticket_raw(core: Core.State, platform: Platform.Platform, received: Nat, identity: String, observed: Maybe<&2, Focus.Target>,
  stale: {Nat.is_eq(received, Rule.platform_ticket(platform)) == False{} : Bool}) ->
  {Platform.step_raw(Platform.FocusApplied{received, Focus.Product{identity}, observed}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          Equal.cong(Bool, Platform.Decision,
            (owned => Platform.focus_result(owned && Platform.focus_confirmed(Focus.Product{identity}, observed), Focus.Product{identity}, Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Nat.is_eq(received, ticket) && Platform.active_focus(Core.State{application, services}, capacity, identity),
            False{},
            Equal.trans(Bool,
              Nat.is_eq(received, ticket) && Platform.active_focus(Core.State{application, services}, capacity, identity),
              False{} && Platform.active_focus(Core.State{application, services}, capacity, identity),
              False{},
              Equal.cong(Bool, Bool,
                (expected => expected && Platform.active_focus(Core.State{application, services}, capacity, identity)),
                Nat.is_eq(received, Rule.platform_ticket(platform)), False{}, stale),
              and_false_left(Platform.active_focus(Core.State{application, services}, capacity, identity))))

def inactive_focus_raw(core: Core.State, platform: Platform.Platform, identity: String, observed: Maybe<&2, Focus.Target>,
  inactive: {Platform.active_focus(core, Rule.platform_capacity(platform), identity) == False{} : Bool}) ->
  {Platform.step_raw(Platform.FocusApplied{Rule.platform_ticket(platform), Focus.Product{identity}, observed}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  match core:
    case Core.State{application, services}:
      match platform:
        case Platform.Platform{readers, editors, focused, +ticket, reduced, capacity, scope}:
          Equal.cong(Bool, Platform.Decision,
            (owned => Platform.focus_result(owned && Platform.focus_confirmed(Focus.Product{identity}, observed), Focus.Product{identity}, Core.State{application, services},
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
            Nat.is_eq(Rule.platform_ticket(platform), ticket) &&
              Platform.active_focus(Core.State{application, services}, capacity, identity),
            False{},
            Equal.trans(Bool,
              Nat.is_eq(Rule.platform_ticket(platform), ticket) &&
                Platform.active_focus(Core.State{application, services}, capacity, identity),
              Nat.is_eq(Rule.platform_ticket(platform), ticket) && False{},
              False{},
              Equal.cong(Bool, Bool,
                (is_active => Nat.is_eq(Rule.platform_ticket(platform), ticket) && is_active),
                Platform.active_focus(core, Rule.platform_capacity(platform), identity), False{}, inactive),
              and_false_right(Nat.is_eq(Rule.platform_ticket(platform), ticket))))

def production_commit_font(decision: Platform.Decision, generation: Nat, environment: Design.Environment, +font: F.State) ->
  {Rule.font_state(Model.production_commit(decision, generation, environment, font)) == F.retag(font, generation) : F.State}:
  Platform.Decision{product, platform, effects} = decision
  {==}


def idle_product(application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, font: F.State) ->
  {Model.product(Model.idle(application, generation, realization, environment, font)) == Platform.unchanged(Rule.model_core(application)) : Core.Decision}:
  match application:
    case Platform.State{core, platform}: {==}

def production_typography_product(owned: Bool, +application: Platform.State, generation: Nat,
  realization: Rendered.State, environment: Design.Environment, font: F.State, observation: F.Observation) ->
  {Model.product(Model.production_typography_owned(owned, application, generation, realization, environment, font, observation)) ==
    Platform.unchanged(Rule.model_core(application)) : Core.Decision}:
  match owned:
    case True{}: idle_product(application, generation, realization, environment, F.accept(font, Nil{}, observation))
    case False{}: idle_product(application, generation, realization, environment, font)


def typography_product(+state: Model.State, +observation: F.Observation) ->
  {Model.product(Model.step(Model.TypographyObserved{observation}, state)) ==
    Platform.unchanged(Rule.model_core(Rule.model_application(state))) : Core.Decision}:
  Model.State{+application, generation, realization, environment, +font} = state
  F.Observation{+received, metrics} = observation
  production_typography_product(Nat.is_eq(F.generation(font), received), application, generation, realization, environment, font, F.Observation{received, metrics})


def capacity_booleans(+a: Bool, +b: Bool, +c: Bool, +d: Bool,
  same: {Platform.same_capacity(View.Capacity{a, b}, View.Capacity{c, d}) == True{} : Bool}) ->
  {View.Capacity{a, b} == View.Capacity{c, d} : View.Capacity}:
  match a b c d:
    case False{} False{} False{} False{}: {==}
    case False{} False{} False{} True{}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case False{} False{} True{} False{}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case False{} False{} True{} True{}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case False{} True{} False{} False{}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case False{} True{} False{} True{}: {==}
    case False{} True{} True{} False{}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case False{} True{} True{} True{}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case True{} False{} False{} False{}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case True{} False{} False{} True{}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case True{} False{} True{} False{}: {==}
    case True{} False{} True{} True{}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case True{} True{} False{} False{}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case True{} True{} False{} True{}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case True{} True{} True{} False{}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case True{} True{} True{} True{}: {==}

def capacity_equal(first: View.Capacity, second: View.Capacity,
  same: {Platform.same_capacity(first, second) == True{} : Bool}) ->
  {first == second : View.Capacity}:
  View.Capacity{a, b} = first
  View.Capacity{c, d} = second
  capacity_booleans(a, b, c, d, same)

def scoped_capacity(decision: Core.Decision, platform: Platform.Platform, scope: Focus.Scope) ->
  {Rule.decision_capacity(Platform.after_core_scoped(decision, platform, scope)) == Rule.platform_capacity(platform) : View.Capacity}:
  Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable} = decision
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, old_scope} = platform
  {==}

def reconciled_capacity(+decision: Core.Decision, platform: Platform.Platform) ->
  {Rule.decision_capacity(Platform.after_core(decision, platform)) == Rule.platform_capacity(platform) : View.Capacity}:
  Core.Decision{+state, reply, runtime, interaction, services, durable} = decision
  Platform.Platform{readers, editors, focused, ticket, reduced, +capacity, scope} = platform
  scoped_capacity(Core.Decision{state, reply, runtime, interaction, services, durable},
    Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, Focus.current(state, capacity))

def merge_capacity(product: Core.Decision, effects: +List<Platform.Effect>, +refreshed: Platform.Decision) ->
  {Rule.decision_capacity(Platform.merge_reflow(product, effects, refreshed)) == Rule.decision_capacity(refreshed) : View.Capacity}:
  match refreshed:
    case Platform.Decision{ignored, platform, reconciliation}: {==}

def changed_capacity_fields(decision: Platform.Decision, +capacity: View.Capacity) ->
  {Rule.decision_capacity(Platform.changed_capacity(decision, capacity)) == capacity : View.Capacity}:
  Platform.Decision{Core.Decision{+state, +reply, +runtime, +interaction, +services, +durable},
    Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, old_capacity, +scope}, +effects} = decision
  Equal.trans(View.Capacity,
    Rule.decision_capacity(Platform.merge_reflow(Core.Decision{state, reply, runtime, interaction, services, durable}, effects, Platform.after_core(Platform.unchanged(state), Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))),
    Rule.decision_capacity(Platform.after_core(Platform.unchanged(state), Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})), capacity,
    merge_capacity(Core.Decision{state, reply, runtime, interaction, services, durable}, effects, Platform.after_core(Platform.unchanged(state), Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope})),
    reconciled_capacity(Platform.unchanged(state), Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))

def retained_capacity_fields(same: Bool, +decision: Platform.Decision, +capacity: View.Capacity,
  agreement: {Platform.same_capacity(Rule.decision_capacity(decision), capacity) == same : Bool}) ->
  {Rule.decision_capacity(Platform.retained_capacity(same, decision, capacity)) == capacity : View.Capacity}:
  match same:
    case True{}: capacity_equal(Rule.decision_capacity(decision), capacity, agreement)
    case False{}: changed_capacity_fields(decision, capacity)

def reflow_capacity_fields(+decision: Platform.Decision, +capacity: View.Capacity) ->
  {Rule.decision_capacity(Platform.reflow_capacity(decision, capacity)) == capacity : View.Capacity}:
  Platform.Decision{+product, Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +old_capacity, +scope}, +effects} = decision
  retained_capacity_fields(Platform.same_capacity(old_capacity, capacity),
    Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, capacity, {==})


def reflow_same(+decision: Platform.Decision, +capacity: View.Capacity,
  same: {Platform.same_capacity(Rule.decision_capacity(decision), capacity) == True{} : Bool}) ->
  {Platform.reflow_capacity(decision, capacity) == decision : Platform.Decision}:
  Platform.Decision{+product, Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +old_capacity, +scope}, +effects} = decision
  Equal.cong(Bool, Platform.Decision,
    (equal => Platform.retained_capacity(equal, Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, capacity)),
    Platform.same_capacity(old_capacity, capacity), True{}, same)

def ime_entry(+owner: U.Editor, +selection: Physical.Selection, +shift: Bool, +alt: Bool, +modified: Bool,
  +core: Core.State, +platform: Platform.Platform,
  editor_observed: {Rule.platform_editors(platform, owner) == Editor.Editor{owner, selection, True{}} : Editor.Editor}) ->
  {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}} : Platform.Decision}:
  Equal.trans(Platform.Decision,
    Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, platform}),
    Platform.realized_decision(Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}}),
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}},
    Equal.cong(Platform.Decision, Platform.Decision, Platform.realized_decision,
      Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, platform}),
      Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}}), Nil{}}, ime_entry_raw(owner, selection, shift, alt, modified, core, platform, editor_observed)),
    Rules_platform.realized_empty(Platform.unchanged(core),
      Rule.with_saved_editor(platform, owner, Editor.Editor{owner, selection, True{}})))

def ready_enter(+owner: U.Editor, +selection: Physical.Selection, +modified: Bool, +core: Core.State,
  +platform: Platform.Platform,
  editor_observed: {Rule.platform_editors(platform, owner) == Editor.Editor{owner, selection, False{}} : Editor.Editor},
  enabled: {Platform.editor_enabled(core, owner, Rule.platform_capacity(platform)) == True{} : Bool},
  permitted: {Focus.permits_composer(Rule.platform_scope(platform)) == True{} : Bool}) ->
  {Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})) ==
    Product.step(Product.SubmitComposer{Rule.platform_capacity(platform), owner}, core) : Core.Decision}:
  Equal.trans(Core.Decision,
    Model.platform_product(Platform.step(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})),
    Model.platform_product(Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})),
    Product.step(Product.SubmitComposer{Rule.platform_capacity(platform), owner}, core),
    Rules_platform.realized_preserves_product(Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{False{}, False{}, modified}},
    Platform.State{core, platform})),
    ready_enter_raw(owner, selection, modified, core, platform, editor_observed, enabled, permitted))

def modal_enter_decision(+owner: U.Editor, +shift: Bool, +alt: Bool, +modified: Bool,
  +identity: String, +initial: String, +restore: String, +occurrence: Maybe<&2, Nat>, +core: Core.State, +platform: Platform.Platform) ->
  {Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}) ==
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}} :
    Platform.Decision}:
  Equal.trans(Platform.Decision,
    Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}),
    Platform.realized_decision(Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}}),
    Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}},
    Equal.cong(Platform.Decision, Platform.Decision, Platform.realized_decision,
      Platform.step_raw(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
    Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}),
      Platform.Decision{Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}}, modal_enter_decision_raw(owner, shift, alt, modified, identity, initial, restore, occurrence, core, platform)),
    Rules_platform.realized_empty(Platform.unchanged(core),
      Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
        Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner))))

def stale_focus_ticket(+core: Core.State, +platform: Platform.Platform, received: Nat, identity: String, observed: Maybe<&2, Focus.Target>,
  stale: {Nat.is_eq(received, Rule.platform_ticket(platform)) == False{} : Bool}) ->
  {Platform.step(Platform.FocusApplied{received, Focus.Product{identity}, observed}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  Equal.trans(Platform.Decision,
    Platform.step(Platform.FocusApplied{received, Focus.Product{identity}, observed}, Platform.State{core, platform}),
    Platform.realized_decision(Platform.Decision{Platform.unchanged(core), platform, Nil{}}),
    Platform.Decision{Platform.unchanged(core), platform, Nil{}},
    Equal.cong(Platform.Decision, Platform.Decision, Platform.realized_decision,
      Platform.step_raw(Platform.FocusApplied{received, Focus.Product{identity}, observed}, Platform.State{core, platform}),
      Platform.Decision{Platform.unchanged(core), platform, Nil{}}, stale_focus_ticket_raw(core, platform, received, identity, observed, stale)),
    Rules_platform.realized_empty(Platform.unchanged(core), platform))

def inactive_focus(+core: Core.State, +platform: Platform.Platform, identity: String, observed: Maybe<&2, Focus.Target>,
  inactive: {Platform.active_focus(core, Rule.platform_capacity(platform), identity) == False{} : Bool}) ->
  {Platform.step(Platform.FocusApplied{Rule.platform_ticket(platform), Focus.Product{identity}, observed}, Platform.State{core, platform}) ==
    Platform.Decision{Platform.unchanged(core), platform, Nil{}} : Platform.Decision}:
  Equal.trans(Platform.Decision,
    Platform.step(Platform.FocusApplied{Rule.platform_ticket(platform), Focus.Product{identity}, observed}, Platform.State{core, platform}),
    Platform.realized_decision(Platform.Decision{Platform.unchanged(core), platform, Nil{}}),
    Platform.Decision{Platform.unchanged(core), platform, Nil{}},
    Equal.cong(Platform.Decision, Platform.Decision, Platform.realized_decision,
      Platform.step_raw(Platform.FocusApplied{Rule.platform_ticket(platform), Focus.Product{identity}, observed}, Platform.State{core, platform}),
      Platform.Decision{Platform.unchanged(core), platform, Nil{}}, inactive_focus_raw(core, platform, identity, observed, inactive)),
    Rules_platform.realized_empty(Platform.unchanged(core), platform))

def stale_reading(+application: E.Application, +services: Services.State, +platform: Platform.Platform,
  task: Nat, generation: Nat, event: Reading.ReadingEvent,
  inactive: {Platform.active_reader(application, task, generation) == False{} : Bool}) -> Rule.stale_reading_law(application, services, platform, task, generation, event, inactive):
  Equal.trans(Platform.Decision,
    Platform.step(Platform.ReadingInput{task, generation, event}, Platform.State{Core.State{application, services}, platform}),
    Platform.realized_decision(Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}}),
    Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}},
    Equal.cong(Platform.Decision, Platform.Decision, Platform.realized_decision,
      Platform.step_raw(Platform.ReadingInput{task, generation, event}, Platform.State{Core.State{application, services}, platform}),
      Platform.Decision{Platform.unchanged(Core.State{application, services}), platform, Nil{}},
      stale_reading_raw(application, services, platform, task, generation, event, inactive)),
    Rules_platform.realized_empty(Platform.unchanged(Core.State{application, services}), platform))
def Rule.evidence():
  Rule.Requirements{PaintRules.evidence(), RendererRules.evidence(),reflow_same, +application => +generation => +realization => +environment => +font => +received => +metrics => stale =>
      Equal.cong(Bool, Model.Decision,
        (owned => Model.production_typography_owned(owned, application, generation, realization, environment, font, F.Observation{received, metrics})),
        Nat.is_eq(F.generation(font), received), False{}, stale)
    , reflow_capacity_fields, +application => +generation => realization => previous_environment => font => +environment =>
      production_commit_font(Platform.Decision{Platform.unchanged(Model.model_core(application)), Model.model_platform(application), Nil{}},
        (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))
    , typography_product,
    input => core => platform => environment => font => generation => realization =>
      product_refinement(input, core, platform, generation, realization, environment, font),
    key => gesture => core => platform => environment => font => generation => realization =>
      element_refinement(key, gesture, core, platform, generation, realization, environment, font),
    received => frame => application => environment => font => generation => realization =>
      frame_silent(received, frame, application, generation, realization, environment, font),
    received => frame => application => environment => font => generation => realization => stale =>
      stale_frame(received, frame, application, generation, realization, environment, font, stale),
    application => services => platform => task => generation => event => inactive =>
      stale_reading(application, services, platform, task, generation, event, inactive),
    height => viewport => anchor => reduced =>
      Equal.cong(+List<Reading.Effect>, Reading.Decision,
        (effects => Reading.Decision{Reading.Bookmark{Some{anchor}}, None{},
          Reading.ReserveComposer{Reading.reserve(height, viewport)} <> effects}),
        Reading.layout(U.ReadHistory{}, Reading.Bookmark{Some{anchor}}),
        [Reading.PreserveAnchor{anchor}],
        Rules_reading_rules.history_layout(anchor))
    ,
    height => viewport => reduced =>
      Equal.cong(+List<Reading.Effect>, Reading.Decision,
        (effects => Reading.Decision{Reading.Bookmark{None{}}, None{},
          Reading.ReserveComposer{Reading.reserve(height, viewport)} <> effects}),
        Reading.layout(U.ReadHistory{}, Reading.Bookmark{None{}}),
        [Reading.MeasureAnchor{}],
        Rules_reading_rules.missing_history_anchor())
    ,
    bookmark => reduced => {==},
    program => session => task => generation => disclosures => bookmarks => anchor => reader_observed => bookmark_observed =>
      layout_after_product(program, session, task, generation, disclosures, bookmarks, anchor,
        reader_observed, bookmark_observed),
    decision => platform => after_core_keeps_bookmarks(decision, platform),
    owner => selection => shift => alt => modified => core => platform => editor_observed =>
      ime_entry(owner, selection, shift, alt, modified, core, platform, editor_observed),
    owner => selection => modified => core => platform => editor_observed => enabled => permitted =>
      ready_enter(owner, selection, modified, core, platform, editor_observed, enabled, permitted),
    owner => shift => alt => modified => identity => initial => restore => +occurrence => core => platform =>
      Equal.cong(Platform.Decision, Core.Decision, Model.platform_product,
        Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}),
        Platform.Decision{Platform.unchanged(core),
          Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
            Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}},
        modal_enter_decision(owner, shift, alt, modified, identity, initial, restore, occurrence, core, platform))
    ,
    owner => shift => alt => modified => identity => initial => restore => +occurrence => core => platform =>
      Equal.cong(Platform.Decision, +List<Platform.Effect>, Rule.platform_effects,
        Platform.step(Platform.EditorInput{owner, Editor.Enter{shift, alt, modified}},
          Platform.State{core, Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence})}),
        Platform.Decision{Platform.unchanged(core),
          Rule.with_saved_editor(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner,
            Rule.platform_editors(Rule.with_scope(platform, Focus.Temporary{identity, initial, restore, occurrence}), owner)), Nil{}},
        modal_enter_decision(owner, shift, alt, modified, identity, initial, restore, occurrence, core, platform))
    ,
    core => platform => received => identity => observed => stale =>
      stale_focus_ticket(core, platform, received, identity, observed, stale),
    core => platform => identity => observed => inactive => inactive_focus(core, platform, identity, observed, inactive),
    drafts => editors => retained => synchronize_retained(drafts, editors, retained),
    count => seed =>
      Std.nat_ind(~(steps => @+initial:Rule.Tape ->
          {Rule.tape_bookmark(Std.iter(~Rule.Tape, ~Rule.advance, steps, initial)) == Rule.tape_bookmark(initial) : Reading.Bookmark}),
        ~(initial => {==}),
        ~(steps => evidence => initial =>
          Equal.trans(Reading.Bookmark,
            Rule.tape_bookmark(Rule.advance(Std.iter(~Rule.Tape, ~Rule.advance, steps, initial))),
            Rule.tape_bookmark(Std.iter(~Rule.Tape, ~Rule.advance, steps, initial)),
            Rule.tape_bookmark(initial),
            advance_preserves_bookmark(Std.iter(~Rule.Tape, ~Rule.advance, steps, initial)), evidence(initial))),
        count)(seed)

  }
