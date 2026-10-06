import ../anchor-geometry.bend as AnchorGeometry
import ../../core/interface.bend as UI
import ./native-fields.bend as NativeProof
import ../native-fields-rules.bend as NativeRules
import Base
import ../physical-browser.bend as Browser
import ../physical-browser-rules.bend as Rule
import ../browser.bend as Legacy
import ../MODEL.bend as Web
import ../design.bend as Design
import ../rendered.bend as Rendered
import ../physical-world.bend as World
import ../physical-content.bend as Content
import ../authored-shell.bend as Shell
import ../../core/ui-world.bend as View
import ../../bendlib/stdlib.bend as Std

def stale_frames(+received: Nat, +frame: Rendered.Frame, +state: Browser.State,
  proof: {Browser.frame_owned(received, state) == False{} : Bool}) ->
  Rule.stale_frames_claim(received, frame, state):
  Std.transport(Bool, False{},
    (owned => {Browser.received_frame(owned, frame, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.frame_owned(received, state), proof)

def stale_measurements(+received: Nat, +tokens: +List<String>, +state: Browser.State,
  proof: {Browser.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Std.transport(Bool, False{},
    (owned => {Browser.measured_current(owned, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.measurement_owned(received, state), proof)

def ready_document(+legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: UI.Surface) ->
  Rule.ready_document_claim(legacy, serial, anchors, capacity, engine, world, semantic):
  match legacy:
    case Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}:
      match world:
        case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def anchor_preserves_program(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: Browser.State) ->
  Rule.anchor_preserves_program_claim(key, left, top, width, height, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match legacy:
        case Legacy.State{web, sequence, ticket, pending, receipt}:
          match web:
            case Web.State{application, generation, realization, environment, font}:
              match environment:
                case Design.Environment{viewport, dark, root}:
                  match viewport:
                    case Design.Viewport{viewport_width, viewport_height}: {==}

def publication_preserves_existing(+last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  waiting: {Browser.display_ready(state) == False{} : Bool}) -> Rule.publication_preserves_existing_claim(last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for(has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
    Std.transport(Bool, False{},
      (ready => {Browser.publication_for(True{}, ready, Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
      {==}, Browser.display_ready(state), waiting),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def publication_current(+last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  ready: {Browser.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool}) -> Rule.publication_current_claim(last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for(has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
    Std.transport(Bool, True{},
      (is_ready => {Browser.publication_for(True{}, is_ready, Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
      Std.transport(Bool, True{},
        (is_current => {Browser.publication_for(True{}, True{}, is_current, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
        {==}, Nat.is_eq(Browser.displayed_generation(state), last_published), current),
      Browser.display_ready(state), ready),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def frame_capture_program(+frame: Rendered.Frame, +state: Browser.State) -> Rule.frame_capture_program_claim(frame, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, old}}: {==}

def Rule.evidence():
  Rule.Requirements{
    +shift => +identity => +initial => +restore => +occurrence => +basis => +semantic => +frame => +state => {==},
    NativeRules.evidence,
    +frame => +state => frame_capture_program(frame, state),
    +key => +shift => +basis => +semantic => +frame => +state => {==},
    +received => +frame => +state => proof => stale_frames(received, frame, state, proof),
    +received => +tokens => +state => proof => stale_measurements(received, tokens, state, proof),
    +legacy => +serial => +anchors => +capacity => +engine => +world => +semantic => ready_document(legacy, serial, anchors, capacity, engine, world, semantic),
    +key => +left => +top => +width => +height => +state => anchor_preserves_program(key, left, top, width, height, state),
    +last_published => +state => existing => waiting => publication_preserves_existing(last_published, state, existing, waiting),
    +last_published => +state => existing => ready => current => publication_current(last_published, state, existing, ready, current)}


def Rule.forwarded_frame_uses_published_surface(stored, serial, anchors, lifecycle, world, semantic, scope, basis, old, frame): {==}

def Rule.failed_font_candidate_blocked(application, generation, realization, environment, font_generation, scale,
  sequence, ticket, pending, serial, anchors, lifecycle, displayed, index): {==}

def Rule.unmet_frame_status(semantic, application, generation, frame_generation, frame, violations, environment, font,
  sequence, ticket, pending, serial, anchors, capacity, engine, displayed): {==}


def eligible_fields(+enabled: Bool, +visible: Bool, +scroll: Bool,
  admitted: {enabled == True{} : Bool}, reachable: {visible || scroll == True{} : Bool}) ->
  {enabled && (visible || scroll) == True{} : Bool}:
  match enabled visible scroll:
    case False{} True{} True{}: admitted
    case False{} True{} False{}: admitted
    case False{} False{} True{}: admitted
    case False{} False{} False{}: admitted
    case True{} True{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} False{} False{}: reachable

def Rule.enabled_reachable_tab_member(element, admitted, reachable):
  match element:
    case Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit}:
      eligible_fields(enabled, visible, scroll, admitted, reachable)

def Rule.rejected_native_focus_preserves_state(generation, owner, identity, state, rejected):
  Equal.cong(Bool, Browser.Decision,
    (owned => Browser.native_focus_if_owned(owned, owner, identity, state)),
    Browser.native_observation_owned(generation, owner, identity, state), False{}, rejected)

def Rule.missing_native_frame_rejects(semantic, owner, identity): {==}

def Rule.stale_native_focus_preserves_state(generation, owner, identity, state, stale):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
          Equal.cong(Bool, Browser.Decision,
            (current => Browser.native_focus_if_owned(current && Browser.source_delegates(source, owner) &&
              Rendered.read_only(UI.find_node(UI.active_nodes(semantic), owner)) && Browser.native_frame_owned(frame, semantic, owner, identity), owner, identity, state)),
            Nat.is_eq(generation, published), False{}, stale)
