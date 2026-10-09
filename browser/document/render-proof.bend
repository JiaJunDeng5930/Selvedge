import Base
import ./render-contract.bend as RuleCodeObservationRules
import ../runtime/MODEL.bend as Browser
import ../layout/CONTENT.bend as Content
import ./MODEL.bend as Observation
import ./SOURCE.bend as Source
import ../MODEL.bend as Web
import ../../interaction/conversation/CODE.bend as Code
import ../appearance/DESIGN.bend as Design
import ./RENDERED.bend as Rendered

def RuleCodeObservationRules.published_qualification(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.rejected_batch(generation, observations, state, rejected):
  Equal.cong(Bool, Browser.Decision,
    (qualified => Browser.code_sources_if_qualified(qualified, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), False{}, rejected)

def RuleCodeObservationRules.qualified_batch(generation, observations, state, qualified):
  Equal.cong(Bool, Browser.Decision,
    (admitted => Browser.code_sources_if_qualified(admitted, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), True{}, qualified)

def RuleCodeObservationRules.empty_batch(generation, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.invalid_published_batch(generation, observations, state, invalid):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}:
              Equal.cong(Bool, Browser.Decision,
                (owned => Browser.code_sources_if_qualified(owned, observations, state)),
                Browser.code_batch_owned(observations, source), False{}, invalid)

def RuleCodeObservationRules.stale_batch(generation, observations, state, stale):
  RuleCodeObservationRules.invalid_published_batch(generation, observations, state, stale)

def RuleCodeObservationRules.unowned_entry(identity, text, source_value, rest, source, unowned):
  Equal.cong(Bool, Bool,
    (owned => owned && Browser.code_observations_owned(rest, source)),
    Browser.code_source_owned(source, identity, source_value), False{}, unowned)

def unowned_tail_result(+owned: Bool, +rest: +List<Observation.Observation>, +source: Source.Node,
    invalid: {Browser.code_observations_owned(rest, source) == False{} : Bool}) ->
    {owned && Browser.code_observations_owned(rest, source) == False{} : Bool}:
  match owned:
    case False{}: {==}
    case True{}: invalid

def RuleCodeObservationRules.unowned_tail(observation, rest, source, invalid):
  match observation:
    case Observation.Observation{identity, text, source_value}:
      unowned_tail_result(Browser.code_source_owned(source, identity, source_value), rest, source, invalid)

def RuleCodeObservationRules.fold_empty(decision): {==}

def RuleCodeObservationRules.fold_order(source, ordinal, text, source_value, rest, state, effects): {==}

def RuleCodeObservationRules.native_batch(generation, observations, state): {==}

def RuleCodeObservationRules.raw_source_rejected(identity, text, state): {==}

def RuleCodeObservationRules.raw_content_rejected(identity, text, state): {==}

def RuleCodeObservationRules.direct_web_rejected(generation, observations, state):
  match state:
    case Web.State{application, serial, realization, environment, font}: {==}

def RuleCodeObservationRules.missing_publication(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}: {==}

def RuleCodeObservationRules.all_entries(identity, text, source_value, rest, source): {==}

def RuleCodeObservationRules.declared_content(owner, identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}

def RuleCodeObservationRules.undeclared_content(identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}

def RuleCodeObservationRules.generation_independent(first, second, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.authored_source(key, value, visual, code_visual, owner, attachments, native_owner, identity, source_value):
  match identity:
    case Code.Identity{source, ordinal}: {==}

def RuleCodeObservationRules.stream_source(task, operation, index, text, parent, state): {==}

def canonical_frame(+visual: Design.Style) -> RuleCodeObservationRules.frame_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def canonical_chrome(+visual: Design.Style) -> RuleCodeObservationRules.chrome_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def policy_projection(visual: Design.Style, +code_visual: Design.Style, reserve: Nat) -> RuleCodeObservationRules.policy_uses_code_surface(visual, code_visual, reserve):
  {==}

def RuleCodeObservationRules.code_surface_evidence():
  RuleCodeObservationRules.CodeSurfaceRequirements{canonical_frame, canonical_chrome, policy_projection}

def RuleCodeObservationRules.stale_frame_retains_state(current, received, surface, frame, previous, different):
  Equal.cong(Bool, Rendered.State, (owned => Rendered.receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)

def RuleCodeObservationRules.native_ownership_is_complete(identity, owner, rest, active, elements): {==}

def RuleCodeObservationRules.native_order_is_owned(owner, identity, parent, rest): {==}

def RuleCodeObservationRules.native_tab_contract(active, elements, native_focus, order): {==}

def RuleCodeObservationRules.absent_control_is_not_tab_stop(): {==}

def RuleCodeObservationRules.observed_tab_participation(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds): {==}

def RuleCodeObservationRules.dialog_actions_persistent(): {==}

def RuleCodeObservationRules.dialog_actions_bounded(key, found, viewport): {==}

def RuleCodeObservationRules.disjoint_paint_controls_do_not_overlap(first, second, disjoint):
  match first second:
    case Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds} Rendered.Element{+other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}:
      Equal.cong(Bool, +List<Rendered.Violation>,
        (overlapping => List.append(&2, Rendered.Violation,
          Rendered.issue(overlapping, Rendered.OverlappingControls{key, other}), Nil{})),
        Rendered.overlaps(paint_bounds, other_paint_bounds), False{}, disjoint)

def RuleCodeObservationRules.observed_visible_paint_is_bounded(bounds, paint_bounds, viewport): {==}

def RuleCodeObservationRules.observed_hidden_paint_is_inactive(bounds, paint_bounds, viewport): {==}

def RuleCodeObservationRules.observed_code_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}

def RuleCodeObservationRules.unpainted_code_is_not_in_view(key,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}

def RuleCodeObservationRules.cropped_disjoint_code_is_not_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport,disjoint):
  match visible:
    case False{}: {==}
    case True{}: disjoint

def RuleCodeObservationRules.movement_is_interactive(destinations, face): {==}

def RuleCodeObservationRules.movement_enabled_by_offered_input(destinations, face): {==}

def RuleCodeObservationRules.source_frame_evidence():
  RuleCodeObservationRules.SourceFrameRequirements{
    +snapshot => +tree => +roots => +policies => {==},
    +key => +bounds => +interaction => +rest => +elements => +viewport => {==},
    +key => +bounds => +interaction => +rest => {==},
    +physical => +value => +interaction => +rule => +demand => +height => +bounds => +canvas => +rest => {==},
    +physical => +value => +interaction => +rule => +bounds => +canvas => +direction => +children => +rest => {==},
    +world => +viewport => +elements => +focused => +tab_order => +native_focus => {==},
    +left => +top => +width => +height => {==},
    +key => +bounds => +interaction => +viewport => +observed => +visible => +enabled => +tab => +keyboard => +scroll => +measured => +hit => +paint => {==},
    +focused => +entries => +elements => +viewport => {==},
    +key => +element => +viewport => {==}}
