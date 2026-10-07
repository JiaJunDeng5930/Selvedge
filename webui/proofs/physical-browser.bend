import ../physical-allocation.bend as Allocation
import ../anchor-geometry.bend as AnchorGeometry
import ../../core/interface.bend as InterfaceView
import ./native-fields.bend as NativeProof
import ../native-fields-rules.bend as NativeRules
import Base
import ../frontend-utility.bend as Utility
import ../focus.bend as Focus
import ../platform.bend as Platform
import ../physical-browser.bend as Browser
import ../physical-plan.bend as Plan
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
import ../../bendlib/proofs/logic.bend as Logic

def stale_frames(+received: Nat, +frame: Rendered.Frame, +state: Browser.State,
  proof: {Browser.frame_owned(received, state) == False{} : Bool}) ->
  Rule.stale_frames_claim(received, frame, state):
  Std.transport(Bool, False{},
    (owned => {Browser.received_frame(owned, frame, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.frame_owned(received, state), proof)

def stale_measurements(+received: Browser.MeasurementTicket, +tokens: +List<String>, +state: Browser.State,
  proof: {Browser.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Std.transport(Bool, False{},
    (owned => {Browser.measured_current(owned, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.measurement_owned(received, state), proof)

def ready_document(+rendering_capacity: Nat, +legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: InterfaceView.Surface) ->
  Rule.ready_document_claim(Browser.State{legacy, serial, anchors, Browser.Displaying{layout_capacity, engine, semantic}, Some{Browser.published(world, layout_capacity, legacy, semantic)}}, rendering_capacity, layout_capacity, engine, world, semantic):
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

def pending_publication_at(+text_capacity: Nat, +last_published: Nat, +state: Browser.State,
  waiting: {Rule.publication_pending(state) == True{} : Bool}) ->
  {Browser.publication_for_at(text_capacity, True{}, Browser.display_ready(state), Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}:
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case Browser.WaitingEnvironment{}: {==}
        case Browser.WaitingFont{}: {==}
        case Browser.Measuring{index, capacity, engine, semantic, round}: {==}
        case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
        case Browser.UtilityDisplaying{purpose, engine}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, Nat.is_eq(Browser.displayed_generation(Browser.State{legacy, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, displayed}), last_published), Browser.State{legacy, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, displayed})} : Browser.Publication}, waiting)
        case Browser.UtilityRejected{problem}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, False{}, Nat.is_eq(Browser.displayed_generation(Browser.State{legacy, serial, anchors, Browser.UtilityRejected{problem}, displayed}), last_published), Browser.State{legacy, serial, anchors, Browser.UtilityRejected{problem}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.UtilityRejected{problem}, displayed})} : Browser.Publication}, waiting)
        case Browser.Displaying{capacity, engine, semantic}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, Nat.is_eq(Browser.displayed_generation(Browser.State{legacy, serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed}), last_published), Browser.State{legacy, serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed})} : Browser.Publication}, waiting)
        case Browser.Blocked{problem}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, False{}, Nat.is_eq(Browser.displayed_generation(Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed}), last_published), Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed})} : Browser.Publication}, waiting)

def publication_preserves_pending_at(+text_capacity: Nat, +last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(state) == True{} : Bool}) -> Rule.publication_preserves_pending_claim_at(text_capacity, last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for_at(text_capacity, has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
    pending_publication_at(text_capacity, last_published, state, waiting),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def ready_publication_at(+text_capacity: Nat, +state: Browser.State, ready: {Browser.display_ready(state) == True{} : Bool}) ->
  {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}:
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case Browser.Displaying{capacity, engine, semantic}: {==}
        case Browser.UtilityDisplaying{purpose, engine}: {==}
        case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed})} : Browser.Publication}, ready)
        case Browser.UtilityRejected{problem}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.UtilityRejected{problem}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.UtilityRejected{problem}, displayed})} : Browser.Publication}, ready)
        case Browser.WaitingEnvironment{}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.WaitingEnvironment{}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.WaitingEnvironment{}, displayed})} : Browser.Publication}, ready)
        case Browser.WaitingFont{}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.WaitingFont{}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.WaitingFont{}, displayed})} : Browser.Publication}, ready)
        case Browser.Measuring{index, capacity, engine, semantic, round}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed})} : Browser.Publication}, ready)
        case Browser.Blocked{problem}: Logic.impossible(
          {Browser.publication_for_at(text_capacity, True{}, True{}, True{}, Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed}) == Browser.KeepPublished{Browser.native_updates(Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed})} : Browser.Publication}, ready)

def blocked_publication_at(+capacity: Nat, +last_published: Nat, +legacy: Legacy.State, +serial: Nat,
  +anchors: +List<Shell.Anchor>, +problem: String, +displayed: Maybe<&2, Browser.Published>) -> Rule.blocked_publication_claim_at(Browser.State{legacy, serial, anchors, Browser.Blocked{problem}, displayed}, capacity, last_published, problem):
  match legacy:
    case Legacy.State{web, sequence, ticket, pending, receipt}:
      match web:
        case Web.State{application, generation, realization, environment, font}: {==}

def publication_current_at(+text_capacity: Nat, +last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  +ready: {Browser.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool}) -> Rule.publication_current_claim_at(text_capacity, last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for_at(text_capacity, has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
    Std.transport(Bool, True{},
      (is_ready => {Browser.publication_for_at(text_capacity, True{}, is_ready, Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
      Std.transport(Bool, True{},
        (is_current => {Browser.publication_for_at(text_capacity, True{}, True{}, is_current, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}),
        ready_publication_at(text_capacity, state, ready), Nat.is_eq(Browser.displayed_generation(state), last_published), current),
      Browser.display_ready(state), ready),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def frame_capture_program(+frame: Rendered.Frame, +state: Browser.State) -> Rule.frame_capture_program_claim(frame, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, old}}: {==}

def Rule.forwarded_frame_uses_published_surface(model_state, world, semantic, scope, basis, old, frame):
  Browser.State{+stored, +serial, +anchors, +lifecycle, +original_1} = model_state
  {==}

def Rule.failed_font_candidate_blocked(model_state, font_generation, scale, index):
  Browser.State{Legacy.State{Web.State{+application, +generation, +realization, +environment, +original_1}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.unmet_frame_status(model_state, semantic, frame_generation, frame, violations, capacity, engine):
  Browser.State{Legacy.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +original_3, +displayed} = model_state
  {==}

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
    case Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds}:
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
              Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && Browser.native_frame_owned(frame, semantic, owner, identity), owner, identity, state)),
            Nat.is_eq(generation, published), False{}, stale)

def Rule.stale_measurement_failure(ticket, reason, state, stale):
  Std.transport(Bool, False{},
    (owned => {Browser.measurement_failed(owned, reason, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.measurement_owned(ticket, state), stale)

def Rule.current_measurement_failure(ticket, reason, state, owned):
  Std.transport(Bool, True{},
    (accepted => {Browser.measurement_failed(accepted, reason, state) == Browser.utility_measurement_failure(reason, state) : Browser.Decision}),
    {==}, Browser.measurement_owned(ticket, state), owned)

def Rule.measurement_ownership_only_measuring(ticket, state, owned):
  match ticket:
    case Browser.MeasurementTicket{generation, received_round}:
      match state:
        case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
          match lifecycle:
            case Browser.Measuring{index, capacity, engine, semantic, round}: {==}
            case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
            case Browser.UtilityDisplaying{purpose, engine}: owned
            case Browser.UtilityRejected{problem}: owned
            case Browser.WaitingEnvironment{}: owned
            case Browser.WaitingFont{}: owned
            case Browser.Displaying{capacity, engine, semantic}: owned
            case Browser.Blocked{problem}: owned

def Rule.measurement_request_unavailable(state, inactive):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case Browser.WaitingEnvironment{}: {==}
        case Browser.WaitingFont{}: {==}
        case Browser.Displaying{capacity, engine, semantic}: {==}
        case Browser.Blocked{problem}: {==}
        case Browser.UtilityDisplaying{purpose, engine}: {==}
        case Browser.UtilityRejected{problem}: {==}
        case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}:
          Logic.impossible({Browser.measurement_request(Browser.State{legacy, serial, anchors, Browser.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}) == None{} : Maybe<&2, Browser.MeasurementRequest>}, Equal.sym(Bool, True{}, False{}, inactive))
        case Browser.Measuring{index, capacity, engine, semantic, round}:
          Logic.impossible(
            {Browser.measurement_request(Browser.State{legacy, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}) == None{} : Maybe<&2, Browser.MeasurementRequest>},
            Equal.sym(Bool, True{}, False{}, inactive))

def Rule.measurement_wrong_round(model_state, generation, received_round, round, index, capacity, engine, semantic, same_generation, stale_round):
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  Std.transport(Bool, True{},
    (same => {same && Nat.is_eq(received_round, round) == False{} : Bool}),
    Std.transport(Bool, False{},
      (same_round => {True{} && same_round == False{} : Bool}),
      {==}, Nat.is_eq(received_round, round), stale_round),
    Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))), same_generation)

def Rule.measurement_request_canonical(model_state, index, capacity, engine, semantic, round, generation, first, remaining, awaiting):
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  Std.transport(Plan.Plan, Plan.Awaiting{generation, first, remaining},
    (plan => {Browser.measurement_request_plan(plan, World.snapshot_generation(World.snapshot(engine)), round) ==
      Some{Browser.MeasurementRequest{Browser.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round}, Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, Browser.MeasurementRequest>}),
    {==}, World.plan(engine), awaiting)

def Rule.render_violations_unmet(model_state, observed_generation, frame, violations):
  Browser.State{Legacy.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.render_violations_awaiting(model_state, observed_generation):
  Browser.State{Legacy.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.render_violations_realized(model_state, observed_generation, frame):
  Browser.State{Legacy.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.pending_frame_effects(state):
  match state:
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.UtilityRejected{problem}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, None{}}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, None{}}}}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.UtilityDisplaying{purpose, engine}, Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, Some{frame}}}}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.WaitingEnvironment{}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.WaitingFont{}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Measuring{index, capacity, engine, semantic, round}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Blocked{problem}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, Rendered.Realized{observed_generation, frame}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, Rendered.Unmet{observed_generation, frame, violations}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Displaying{capacity, engine, semantic}, None{}}: {==}
    case Browser.State{Legacy.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, Browser.Displaying{capacity, engine, semantic}, Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}}: {==}

def Rule.retained_frame_decision(first, state):
  Std.transport(+List<Legacy.Effect>, Browser.pending_frame_effects(state),
    (effects => {Browser.accepted(False{}, first, state) == Browser.Decision{state,
      List.append(&2, Legacy.Effect, first, effects)} : Browser.Decision}),
    {==}, Rule.pending_frame_effects_expected(state),
    Equal.sym(+List<Legacy.Effect>, Browser.pending_frame_effects(state),
      Rule.pending_frame_effects_expected(state), Rule.pending_frame_effects(state)))

def Rule.rebuilt_frame_decision(first, state): {==}

def inspection_product(+stored: Legacy.State, +displayed: Maybe<&2, Browser.Published>) ->
  {Browser.render_inspection_owned(False{}, stored, displayed) == Rule.inspection_owned_expected(False{}, stored, displayed) : Browser.RenderInspection}:
  match stored:
    case Legacy.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, published_frame}}: {==}
    case Legacy.State{Web.State{application, generation, Rendered.Realized{observed_generation, Rendered.Frame{viewport, elements, focused, tabs, native_focus}}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, published_frame}}: {==}
    case Legacy.State{Web.State{application, generation, Rendered.Unmet{observed_generation, Rendered.Frame{viewport, elements, focused, tabs, native_focus}, violations}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, published_frame}}: {==}
def inspection_owned(+utility: Bool, +stored: Legacy.State, +displayed: Maybe<&2, Browser.Published>) ->
  {Browser.render_inspection_owned(utility, stored, displayed) == Rule.inspection_owned_expected(utility, stored, displayed) : Browser.RenderInspection}:
  match utility:
    case True{}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}: {==}
    case False{}: inspection_product(stored, displayed)

def Rule.render_inspection(model_state):
  Browser.State{+stored, +serial, +anchors, +lifecycle, +displayed} = model_state
  inspection_owned(Browser.auxiliary_owned(Browser.State{stored, serial, anchors, lifecycle, displayed}), stored, displayed)

def state_ready_document_evidence(+model_state: Browser.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: InterfaceView.Surface) ->
  Rule.ready_document_claim(Browser.with_displayed(Some{Browser.published(world, layout_capacity, Browser.legacy(model_state), semantic)}, Browser.with_lifecycle(Browser.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic):
  Browser.State{+legacy, +serial, +anchors, +original_1, +original_2} = model_state
  ready_document(rendering_capacity, legacy, serial, anchors, layout_capacity, engine, world, semantic)

def state_blocked_publication_at_evidence(+model_state: Browser.State, +capacity: Nat, +last_published: Nat, +problem: String) ->
  Rule.blocked_publication_claim_at(Browser.with_lifecycle(Browser.Blocked{problem}, model_state), capacity, last_published, problem):
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  blocked_publication_at(capacity, last_published, legacy, serial, anchors, problem, displayed)

def Rule.evidence():
  Rule.Requirements{
    +shift => +identity => +initial => +restore => +occurrence => +basis => +semantic => +frame => +state => {==},
    NativeRules.evidence,
    +frame => +state => frame_capture_program(frame, state),
    +key => +shift => +basis => +semantic => +frame => +state => {==},
    +received => +frame => +state => proof => stale_frames(received, frame, state, proof),
    +received => +tokens => +state => proof => stale_measurements(received, tokens, state, proof),
    state_ready_document_evidence,
    +key => +left => +top => +width => +height => +state => anchor_preserves_program(key, left, top, width, height, state),
    +capacity => +last_published => +state => existing => waiting => publication_preserves_pending_at(capacity, last_published, state, existing, waiting),
    state_blocked_publication_at_evidence,
    +capacity => +last_published => +state => existing => +ready => current => publication_current_at(capacity, last_published, state, existing, ready, current)}

def Rule.unconfirmed_publication_has_no_focus_feedback(document, fields, ticket, before, after):
  match before:
    case None{}: {==}
    case Some{target}:
      match after:
        case None{}: {==}
        case Some{target}: {==}
def Rule.retained_publication_has_no_focus_feedback(fields, ticket, before, after): {==}
def Rule.absent_focus_has_no_publication_feedback(publication, ticket, after):
  match publication:
    case Browser.KeepPublished{fields}: {==}
    case Browser.Publish{generation, document, fields}: {==}
def Rule.owned_focus_has_no_publication_feedback(publication, ticket, before, after):
  match publication:
    case Browser.KeepPublished{fields}: {==}
    case Browser.Publish{generation, document, fields}:
      match before:
        case None{}: {==}
        case Some{target}: {==}
def Rule.confirmed_publication_focus_loss(generation, document, fields, ticket, before, confirmed):
  Std.transport(Bool, True{},
    (ready => {Browser.publication_focus_loss(ready, ticket, before) ==
      Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}),
    {==}, Bool.not(Nat.is_eq(generation, 0n)), confirmed)

def Rule.failure_message(key, axis, required, available, reason):
  match axis:
    case Allocation.InlineAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}
    case Allocation.BlockAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}
def Rule.infeasible_candidate_retries(index, state, failure): {==}
def Rule.infeasible_candidate_reports(model_state, index, failure):
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}
def Rule.selected_infeasible(failure, index, capacity, engine, state, semantic, round): {==}
