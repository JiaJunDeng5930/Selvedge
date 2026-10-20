import Base
import ../controls/GEOMETRY.bend as Geometry
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/categories.bend as Categories
import ./render-contract.bend as RuleCodeObservationRules
import ../runtime/MODEL.bend as Browser
import ../layout/CONTENT.bend as Content
import ./MODEL.bend as Observation
import ./SOURCE.bend as Source
import ../MODEL.bend as Web
import ../../interaction/conversation/CODE.bend as Code
import ../appearance/DESIGN.bend as Design
import ./RENDERED.bend as Rendered
import ./SPEC.bend as Spec
import ./diagnostic-proof.bend as Diagnostic
import ../runtime/SEMANTICS.bend as Legacy
import ../../interaction/session/MODEL.bend as E
import ../../interaction/conversation/OUTPUT.bend as Live
import ../../interaction/STATE.bend as Core
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/PROGRAM.bend as Interface
import ../../interaction/presentation/CONTRACT.bend as FenceRules
import ../../interaction/presentation/interaction-proof.bend as FenceEvidence
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../harness/DOMAIN.bend as D

def known_observations_agreement(+observations: +List<Observation.Observation>, +session: E.Session) ->
  {Browser.known_code_observations(observations, session) == RuleCodeObservationRules.expected_known_code_observations(observations, session) : Bool}:
  match observations:
    case Nil{}: {==}
    case Con{Observation.Observation{identity, text, source_value}, rest}:
      Equal.cong(Bool, Bool, (known => E.code_source_known(identity, session) && known),
        Browser.known_code_observations(rest, session), RuleCodeObservationRules.expected_known_code_observations(rest, session),
        known_observations_agreement(rest, session))

def owned_known_agreement(+owned: Bool, +observations: +List<Observation.Observation>, +session: E.Session) ->
  {owned && Browser.known_code_observations(observations, session) ==
    (owned && RuleCodeObservationRules.expected_known_code_observations(observations, session)) : Bool}:
  Equal.cong(Bool, Bool, (known => owned && known), Browser.known_code_observations(observations, session),
    RuleCodeObservationRules.expected_known_code_observations(observations, session), known_observations_agreement(observations, session))

def RuleCodeObservationRules.published_qualification(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}:
              owned_known_agreement(Browser.code_batch_owned(observations, source), observations,
                RuleCodeObservationRules.observation_session(Browser.State{legacy, serial, anchors, lifecycle, Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}, attention, updates}))

def code_sources_spec(+qualified: Bool, +generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Browser.Decision:
  match qualified:
    case False{}: Browser.Decision{state, Nil{}}
    case True{}: Browser.accept(True{}, Browser.code_sources_fold(observations, Legacy.Decision{Browser.legacy(state), Nil{}}), state)

def code_sources_checked(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State, +qualified: Bool,
  observed: {Browser.code_batch_qualified(generation, observations, state) == qualified : Bool}) ->
  {Browser.code_sources_admitted(Categories.admit_checked(Browser.CodeSourcesCandidate, Browser.code_sources_predicate, Browser.CodeSourcesCandidate{generation, observations, state}, qualified, observed), state) == code_sources_spec(qualified, generation, observations, state) : Browser.Decision}:
  match qualified:
    case False{}: {==}
    case True{}: {==}

def code_sources_equation(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) ->
  {Browser.code_sources(generation, observations, state) == code_sources_spec(Browser.code_batch_qualified(generation, observations, state), generation, observations, state) : Browser.Decision}:
  code_sources_checked(generation, observations, state, Browser.code_batch_qualified(generation, observations, state), {==})

def RuleCodeObservationRules.rejected_batch(generation, observations, state, rejected):
  Equal.trans(Browser.Decision, Browser.code_sources(generation, observations, state), code_sources_spec(Browser.code_batch_qualified(generation, observations, state), generation, observations, state),
    Browser.Decision{state, Nil{}}, code_sources_equation(generation, observations, state),
    Equal.cong(Bool, Browser.Decision,
      (qualified => code_sources_spec(qualified, generation, observations, state)),
      Browser.code_batch_qualified(generation, observations, state), False{}, rejected))

def RuleCodeObservationRules.qualified_batch(generation, observations, state, qualified):
  Equal.trans(Browser.Decision, Browser.code_sources(generation, observations, state), code_sources_spec(Browser.code_batch_qualified(generation, observations, state), generation, observations, state),
    Browser.accept(True{}, Browser.code_sources_fold(observations, Legacy.Decision{Browser.legacy(state), Nil{}}), state), code_sources_equation(generation, observations, state),
    Equal.cong(Bool, Browser.Decision,
      (admitted => code_sources_spec(admitted, generation, observations, state)),
      Browser.code_batch_qualified(generation, observations, state), True{}, qualified))

def RuleCodeObservationRules.empty_batch(generation, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def qualification_membership_agreement(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) ->
  {Browser.code_batch_qualified(generation, observations, state) == RuleCodeObservationRules.actual_membership(observations, state) : Bool}:
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}:
              owned_known_agreement(Browser.code_batch_owned(observations, source), observations,
                RuleCodeObservationRules.observation_session(Browser.State{legacy, serial, anchors, lifecycle, Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}, attention, updates}))

def RuleCodeObservationRules.invalid_published_batch(generation, observations, state, invalid):
  RuleCodeObservationRules.rejected_batch(generation, observations, state,
    Equal.trans(Bool, Browser.code_batch_qualified(generation, observations, state), RuleCodeObservationRules.actual_membership(observations, state), False{},
      qualification_membership_agreement(generation, observations, state), invalid))

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
    case Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}: {==}

def RuleCodeObservationRules.all_entries(identity, text, source_value, rest, source): {==}

def RuleCodeObservationRules.declared_content(owner, identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}:
      Equal.cong(Bool, Bool, (same => Browser.code_same_source(owner, source) && same),
        SafeText.string_equal(value, source_value), String.eq(value, source_value), TextProof.public_refines(value, source_value))

def RuleCodeObservationRules.undeclared_content(identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}

def RuleCodeObservationRules.generation_independent(first, second, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.authored_source(key, value, visual, code_visual, owner, attachments, native_owner, identity, source_value):
  match identity:
    case Code.Identity{source, ordinal}:
      Equal.cong(Bool, Bool, (same => Browser.code_same_source(owner, source) && same),
        SafeText.string_equal(value, source_value), String.eq(value, source_value), TextProof.public_refines(value, source_value))

def preview_origin_agreement(+origin: Maybe<&2, D.OutputOrigin>, +task: Nat, +operation: Nat, +index: Nat, +session: E.Session) ->
  {Interface.generated_source(origin, task, Code.StreamingPart{task, operation, index}, False{}, session) ==
    RuleCodeObservationRules.expected_preview_origin(origin, E.namespace(session), task, operation, index) : Code.Source}:
  match origin:
    case None{}: {==}
    case Some{origin}: {==}

def stream_output_key_agreement(+source: Code.Source, +fallback: Identity.Key) ->
  {Interface.output_key(source, fallback) == RuleCodeObservationRules.expected_output_key(source, fallback) : Identity.Key}:
  match source:
    case Code.Generated{namespace, viewer, origin, complete}: {==}
    case Code.SharedDocument{namespace, owner}: {==}
    case Code.Message{task, message}: {==}
    case Code.StreamingPart{task, operation, part}: {==}

def RuleCodeObservationRules.stream_source(task, operation, index, text, parent, state):
  RuleCodeObservationRules.StreamPartPresentation{
    Interface.live_part_node(index, text, task, operation, parent, state), {==},
    FenceRules.live_part_attachments_complete(index, text, task, operation, parent, state)}

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
  Std.transport(Bool, False{},
    (owned => @observed:{Nat.is_eq(current, received) == owned : Bool} ->
      {Rendered.received(Categories.admit_checked(Rendered.FrameReceipt, Rendered.frame_correlated,
        Rendered.FrameReceipt{current, received, surface, frame}, owned, observed), previous) == previous : Rendered.State}),
    observed => {==}, Nat.is_eq(current, received), different)({==})

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

def RuleCodeObservationRules.supporting_is_interactive(support, property, input, availability):
  {==}

def RuleCodeObservationRules.supporting_enabled_by_availability(support, property, input, availability):
  {==}

def element_lookup_match(+same: Bool, +element: Rendered.Element, fallback: Unit -> Maybe<&2, Rendered.Element>) ->
  {Rendered.find_element_match(same, element, fallback) ==
    Bool.pick((Maybe<&2, Rendered.Element>), same, Some{element}, fallback(Unit{})) : Maybe<&2, Rendered.Element>}:
  match same:
    case True{}: {==}
    case False{}: {==}

def complete_element_lookup(+elements: +List<Rendered.Element>, +key: String) ->
  {Rendered.find_element(elements, key) == Spec.first_observed_element(elements, key) : Maybe<&2, Rendered.Element>}:
  Diagnostic.first_observation(elements, key)

def complete_frame_resolution(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.resolve_nodes(nodes, elements) ==
    Diagnostic.observed_nodes(nodes, elements) : +List<Rendered.ResolvedNode>}:
  match nodes:
    case Nil{}: {==}
    case Con{+node, +rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, +children} = node
      +identity: String = Identity.encode(key)
      +found: Maybe<&2, Rendered.Element> = Rendered.find_element(elements, identity)
      +expected: Maybe<&2, Rendered.Element> = Spec.first_observed_element(elements, identity)
      +actual_children: +List<Rendered.ResolvedNode> = Rendered.resolve_nodes(children, elements)
      +expected_children: +List<Rendered.ResolvedNode> = Diagnostic.observed_nodes(children, elements)
      +actual_rest: +List<Rendered.ResolvedNode> = Rendered.resolve_nodes(rest, elements)
      +expected_rest: +List<Rendered.ResolvedNode> = Diagnostic.observed_nodes(rest, elements)
      +actual: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, actual_children} <> actual_rest
      +children_replaced: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, expected_children} <> actual_rest
      +rest_replaced: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, expected_children} <> expected_rest
      +target: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, expected, expected_children} <> expected_rest
      Equal.trans((+List<Rendered.ResolvedNode>), actual, children_replaced, target,
        Equal.cong((+List<Rendered.ResolvedNode>), (+List<Rendered.ResolvedNode>),
          (resolved => Rendered.ResolvedNode{node, identity, found, resolved} <> actual_rest),
          actual_children, expected_children, complete_frame_resolution(children, elements)),
        Equal.trans((+List<Rendered.ResolvedNode>), children_replaced, rest_replaced, target,
          Equal.cong((+List<Rendered.ResolvedNode>), (+List<Rendered.ResolvedNode>),
            (resolved => Rendered.ResolvedNode{node, identity, found, expected_children} <> resolved),
            actual_rest, expected_rest, complete_frame_resolution(rest, elements)),
          Equal.cong((Maybe<&2, Rendered.Element>), (+List<Rendered.ResolvedNode>),
            (observation => Rendered.ResolvedNode{node, identity, observation, expected_children} <> expected_rest),
            found, expected, complete_element_lookup(elements, identity))))

def fingerprint_bool_equal(+left: Bool, +right: Bool,
  accepted: {Cmp.is_eq(Bool.cmp(left, right)) == True{} : Bool}) -> {left == right : Bool}:
  match left right:
    case False{} False{}: {==}
    case False{} True{}: Logic.impossible({False{} == True{} : Bool}, accepted)
    case True{} False{}: Logic.impossible({True{} == False{} : Bool}, accepted)
    case True{} True{}: {==}

# Put the compared tail order first; each parameter is matched only once.
def fingerprint_word_tail(order: Cmp, left: Bool, right: Bool,
  accepted: {Cmp.is_eq(Word.cmp.fin(left, right, order)) == True{} : Bool}) ->
  {Cmp.is_eq(order) == True{} : Bool}:
  match order:
    case LT{}: Logic.impossible({False{} == True{} : Bool}, accepted)
    case EQ{}: {==}
    case GT{}: Logic.impossible({False{} == True{} : Bool}, accepted)

def fingerprint_word_head(order: Cmp, +left: Bool, +right: Bool,
  accepted: {Cmp.is_eq(Word.cmp.fin(left, right, order)) == True{} : Bool}) -> {left == right : Bool}:
  match order:
    case LT{}: Logic.impossible({left == right : Bool}, accepted)
    case EQ{}: fingerprint_bool_equal(left, right, accepted)
    case GT{}: Logic.impossible({left == right : Bool}, accepted)

def fingerprint_word_equal(+size: Nat, +left: Word(size), +right: Word(size),
  +accepted: {Cmp.is_eq(Word.cmp(size, left, right)) == True{} : Bool}) -> {left == right : Word(size)}:
  match size:
    case 0n:
      match left right:
        case WNil{} WNil{}: {==}
    case 1n+rest:
      match left right:
        case WCon{+a, +tail_a} WCon{+b, +tail_b}:
          +order: Cmp = Word.cmp(rest, tail_a, tail_b)
          Equal.trans(Word(1n+rest), WCon{a, tail_a}, WCon{b, tail_a}, WCon{b, tail_b},
            Equal.cong(Bool, Word(1n+rest), (head => WCon{head, tail_a}), a, b,
              fingerprint_word_head(order, a, b, accepted)),
            Equal.cong(Word(rest), Word(1n+rest), (tail => WCon{b, tail}), tail_a, tail_b,
              fingerprint_word_equal(rest, tail_a, tail_b, fingerprint_word_tail(order, a, b, accepted))))

def fingerprint_char_equal(+left: Char, +right: Char,
  accepted: {SafeText.char_equal(Char.cmp(left, right)) == True{} : Bool}) -> {left == right : Char}:
  match left right:
    case Chr{U32{+a}} Chr{U32{+b}}:
      Equal.cong(Word(32n), Char, (word => Chr{U32{word}}), a, b, fingerprint_word_equal(32n, a, b, accepted))

def fingerprint_true_left(+left: Bool, +right: Bool,
  accepted: {(left && right) == True{} : Bool}) -> {left == True{} : Bool}:
  match left:
    case False{}: Logic.impossible({False{} == True{} : Bool}, accepted)
    case True{}: {==}

def fingerprint_true_right(+left: Bool, +right: Bool,
  accepted: {(left && right) == True{} : Bool}) -> {right == True{} : Bool}:
  match left:
    case False{}: Logic.impossible({right == True{} : Bool}, accepted)
    case True{}: accepted

# Existing compared_heads already relates the actual Base comparator to both
# head equality and tail equality. No String.cmp reconstruction proof is copied.
def fingerprint_string_cons_accepts(+a: Char, +left: String, +b: Char, +right: String,
  accepted: {String.eq(SCon{a, left}, SCon{b, right}) == True{} : Bool}) ->
  {(SafeText.char_equal(Char.cmp(a, b)) && String.eq(left, right)) == True{} : Bool}:
  Equal.trans(Bool, (SafeText.char_equal(Char.cmp(a, b)) && String.eq(left, right)),
    String.eq(SCon{a, left}, SCon{b, right}), True{},
    Equal.sym(Bool, String.eq(SCon{a, left}, SCon{b, right}),
      (SafeText.char_equal(Char.cmp(a, b)) && String.eq(left, right)), TextProof.compared_heads(left, right, Char.cmp(a, b))), accepted)

def fingerprint_string_equal(+left: String, +right: String,
  +accepted: {String.eq(left, right) == True{} : Bool}) -> {left == right : String}:
  match left right:
    case SNil{} SNil{}: {==}
    case SNil{} SCon{head, tail}: Logic.impossible({SNil{} == SCon{head, tail} : String}, accepted)
    case SCon{head, tail} SNil{}: Logic.impossible({SCon{head, tail} == SNil{} : String}, accepted)
    case SCon{+a, +tail_a} SCon{+b, +tail_b}:
      +heads: Bool = SafeText.char_equal(Char.cmp(a, b))
      +tails: Bool = String.eq(tail_a, tail_b)
      Equal.trans(String, SCon{a, tail_a}, SCon{b, tail_a}, SCon{b, tail_b},
        Equal.cong(Char, String, (head => SCon{head, tail_a}), a, b,
          fingerprint_char_equal(a, b, fingerprint_true_left(heads, tails,
            fingerprint_string_cons_accepts(a, tail_a, b, tail_b, accepted)))),
        Equal.cong(String, String, (tail => SCon{b, tail}), tail_a, tail_b,
          fingerprint_string_equal(tail_a, tail_b, fingerprint_true_right(heads, tails,
            fingerprint_string_cons_accepts(a, tail_a, b, tail_b, accepted)))))

def fingerprint_safe_string_equal(+left: String, +right: String,
  accepted: {SafeText.string_equal(left, right) == True{} : Bool}) -> {left == right : String}:
  fingerprint_string_equal(left, right,
    Equal.trans(Bool, String.eq(left, right), SafeText.string_equal(left, right), True{},
      Equal.sym(Bool, SafeText.string_equal(left, right), String.eq(left, right), TextProof.public_refines(left, right)), accepted))

# This theorem uses the actual deterministic fold only through congruence.
# No injectivity, collision absence, overflow or multiplication law is assumed.
def fingerprint_equal_safe_strings(+left: String, +right: String,
  accepted: {SafeText.string_equal(left, right) == True{} : Bool}) ->
  {Rendered.key_fingerprint(left) == Rendered.key_fingerprint(right) : U32}:
  Equal.cong(String, U32, Rendered.key_fingerprint, left, right, fingerprint_safe_string_equal(left, right, accepted))

def fingerprint_same_u32(+value: U32) -> {U32.is_eq(value, value) == True{} : Bool}:
  match value:
    case U32{+word}:
      Equal.cong(Cmp, Bool, Cmp.is_eq, Word.cmp(32n, word, word), EQ{}, TextProof.same_word(32n, word))

def fingerprint_gate_admits_equal(+left: String, +right: String,
  accepted: {SafeText.string_equal(left, right) == True{} : Bool}) ->
  {U32.is_eq(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right)) == True{} : Bool}:
  +left_hash: U32 = Rendered.key_fingerprint(left)
  +right_hash: U32 = Rendered.key_fingerprint(right)
  Equal.trans(Bool, U32.is_eq(left_hash, right_hash), U32.is_eq(right_hash, right_hash), True{},
    Equal.cong(U32, Bool, (value => U32.is_eq(value, right_hash)), left_hash, right_hash,
      fingerprint_equal_safe_strings(left, right, accepted)), fingerprint_same_u32(right_hash))

def fingerprint_match_false(+gate: Bool, +left: String, +right: String,
  accepted: {SafeText.string_equal(left, right) == False{} : Bool}) ->
  {Rendered.fingerprint_match_admitted(gate, left, right) == False{} : Bool}:
  match gate:
    case False{}: {==}
    case True{}: accepted

def fingerprint_match_complete_case(+left: String, +right: String, equal: Bool,
  +observed: {SafeText.string_equal(left, right) == equal : Bool}) ->
  {Rendered.fingerprint_match(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right), left, right) == equal : Bool}:
  match equal:
    case False{}:
      fingerprint_match_false(U32.is_eq(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right)), left, right, observed)
    case True{}:
      Equal.trans(Bool,
        Rendered.fingerprint_match(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right), left, right),
        Rendered.fingerprint_match_admitted(True{}, left, right), True{},
        Equal.cong(Bool, Bool, (gate => Rendered.fingerprint_match_admitted(gate, left, right)),
          U32.is_eq(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right)), True{}, fingerprint_gate_admits_equal(left, right, observed)), observed)

def complete_fingerprint_match(+left: String, +right: String) ->
  {Rendered.fingerprint_match(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right), left, right) ==
    String.eq(left, right) : Bool}:
  Equal.trans(Bool,
    Rendered.fingerprint_match(Rendered.key_fingerprint(left), Rendered.key_fingerprint(right), left, right),
    SafeText.string_equal(left, right), String.eq(left, right),
    fingerprint_match_complete_case(left, right, SafeText.string_equal(left, right), {==}), TextProof.public_refines(left, right))

def complete_prepared_element_lookup(+elements: +List<Rendered.Element>, +key: String) ->
  {Rendered.find_prepared_element(Rendered.prepare_elements(elements), Rendered.key_fingerprint(key), key) ==
    Spec.first_observed_element(elements, key) : Maybe<&2, Rendered.Element>}:
  match elements:
    case Nil{}: {==}
    case Con{Rendered.Element{+current, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}, +rest}:
      +element: Rendered.Element = Rendered.Element{current, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}
      +query_fingerprint: U32 = Rendered.key_fingerprint(key)
      +actual_tail: Maybe<&2, Rendered.Element> = Rendered.find_prepared_element(Rendered.prepare_elements(rest), query_fingerprint, key)
      +expected_tail: Maybe<&2, Rendered.Element> = Spec.first_observed_element(rest, key)
      +actual_match: Bool = Rendered.fingerprint_match(Rendered.key_fingerprint(current), query_fingerprint, current, key)
      +plain: Bool = String.eq(current, key)
      +actual_step: Maybe<&2, Rendered.Element> = Bool.pick((Maybe<&2, Rendered.Element>), actual_match, Some{element}, actual_tail)
      +plain_step: Maybe<&2, Rendered.Element> = Bool.pick((Maybe<&2, Rendered.Element>), plain, Some{element}, actual_tail)
      Equal.trans((Maybe<&2, Rendered.Element>),
        Rendered.find_prepared_element(Rendered.prepare_elements(element <> rest), query_fingerprint, key), actual_step,
        Spec.first_observed_element(element <> rest, key),
        element_lookup_match(actual_match, element, (_ => actual_tail)),
        Equal.trans((Maybe<&2, Rendered.Element>), actual_step, plain_step,
          Spec.first_observed_element(element <> rest, key),
          Equal.cong(Bool, (Maybe<&2, Rendered.Element>),
            (matched => Bool.pick((Maybe<&2, Rendered.Element>), matched, Some{element}, actual_tail)),
            actual_match, plain, complete_fingerprint_match(current, key)),
          Equal.cong((Maybe<&2, Rendered.Element>), (Maybe<&2, Rendered.Element>),
            (tail => Bool.pick((Maybe<&2, Rendered.Element>), plain, Some{element}, tail)),
            actual_tail, expected_tail, complete_prepared_element_lookup(rest, key))))

def complete_prepared_frame_resolution(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.resolve_prepared_nodes(nodes, Rendered.prepare_elements(elements)) ==
    Diagnostic.observed_nodes(nodes, elements) : +List<Rendered.ResolvedNode>}:
  match nodes:
    case Nil{}: {==}
    case Con{+node, +rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, +children} = node
      +identity: String = Identity.encode(key)
      +found: Maybe<&2, Rendered.Element> = Rendered.find_prepared_element(Rendered.prepare_elements(elements), Rendered.key_fingerprint(identity), identity)
      +expected: Maybe<&2, Rendered.Element> = Spec.first_observed_element(elements, identity)
      +actual_children: +List<Rendered.ResolvedNode> = Rendered.resolve_prepared_nodes(children, Rendered.prepare_elements(elements))
      +expected_children: +List<Rendered.ResolvedNode> = Diagnostic.observed_nodes(children, elements)
      +actual_rest: +List<Rendered.ResolvedNode> = Rendered.resolve_prepared_nodes(rest, Rendered.prepare_elements(elements))
      +expected_rest: +List<Rendered.ResolvedNode> = Diagnostic.observed_nodes(rest, elements)
      +actual: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, actual_children} <> actual_rest
      +children_replaced: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, expected_children} <> actual_rest
      +rest_replaced: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, found, expected_children} <> expected_rest
      +target: +List<Rendered.ResolvedNode> = Rendered.ResolvedNode{node, identity, expected, expected_children} <> expected_rest
      Equal.trans((+List<Rendered.ResolvedNode>), actual, children_replaced, target,
        Equal.cong((+List<Rendered.ResolvedNode>), (+List<Rendered.ResolvedNode>),
          (resolved => Rendered.ResolvedNode{node, identity, found, resolved} <> actual_rest),
          actual_children, expected_children, complete_prepared_frame_resolution(children, elements)),
        Equal.trans((+List<Rendered.ResolvedNode>), children_replaced, rest_replaced, target,
          Equal.cong((+List<Rendered.ResolvedNode>), (+List<Rendered.ResolvedNode>),
            (resolved => Rendered.ResolvedNode{node, identity, found, expected_children} <> resolved),
            actual_rest, expected_rest, complete_prepared_frame_resolution(rest, elements)),
          Equal.cong((Maybe<&2, Rendered.Element>), (+List<Rendered.ResolvedNode>),
            (observation => Rendered.ResolvedNode{node, identity, observation, expected_children} <> expected_rest),
            found, expected, complete_prepared_element_lookup(elements, identity))))

def fingerprinted_resolution_case(+prepared: Bool, +nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.resolve_frame_admitted(prepared, nodes, elements) ==
    Diagnostic.observed_nodes(nodes, elements) : +List<Rendered.ResolvedNode>}:
  match prepared:
    case False{}: complete_frame_resolution(nodes, elements)
    case True{}: complete_prepared_frame_resolution(nodes, elements)

def complete_fingerprinted_frame_resolution(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.resolve_frame_nodes(nodes, elements) ==
    Diagnostic.observed_nodes(nodes, elements) : +List<Rendered.ResolvedNode>}:
  fingerprinted_resolution_case(Rendered.frame_nodes_many(nodes) && Rendered.frame_elements_many(elements), nodes, elements)


def RuleCodeObservationRules.complete_element_lookup(elements, key): Diagnostic.first_observation(elements, key)
def RuleCodeObservationRules.complete_ordered_tabs(nodes, elements, native_focus): Diagnostic.expected_tabs(nodes, elements, native_focus)
def RuleCodeObservationRules.complete_native_ownership(native_focus, nodes, elements): Diagnostic.native_valid(native_focus, nodes, elements)

def complete_layout_check_with(+active: +List<SurfaceTypes.Node>, +frame: Rendered.Frame, +controls: +List<Rendered.ControlExposure>) ->
  {Rendered.layout_check_with(active, frame, controls) == Spec.layout_diagnostics(active, frame, controls) : +List<Rendered.Violation>}:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  +observed: Rendered.Frame = Rendered.Frame{viewport, elements, focused, tab_order, native_focus}
  Std.transport((+List<Rendered.ResolvedNode>), Diagnostic.observed_nodes(active, elements),
    (resolved => {Diagnostic.validation_terms(resolved, active, observed, controls) == Spec.layout_diagnostics(active, observed, controls) : +List<Rendered.Violation>}),
    Diagnostic.validation_terms_requirement(active, observed, controls), Rendered.resolve_frame_nodes(active, elements),
    complete_fingerprinted_frame_resolution(active, elements))

def RuleCodeObservationRules.complete_layout_check_with(active, frame, controls): complete_layout_check_with(active, frame, controls)

def complete_check(+active: +List<SurfaceTypes.Node>, +frame: Rendered.Frame) ->
  {Rendered.check(active, frame) == Spec.check_diagnostics(active, frame) : +List<Rendered.Violation>}:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  %Equal.sym((+List<Rendered.Violation>), Rendered.paint_geometry(elements, viewport), Spec.paint_geometry(elements, viewport), Diagnostic.paint_geometry(elements, viewport)) :
    {List.append(&2, Rendered.Violation, _, Rendered.layout_check_with(active, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}, Nil{})) == Spec.check_diagnostics(active, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}) : +List<Rendered.Violation>}
  Equal.cong((+List<Rendered.Violation>), (+List<Rendered.Violation>),
    (faults => List.append(&2, Rendered.Violation, Spec.paint_geometry(elements, viewport), faults)),
    Rendered.layout_check_with(active, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}, Nil{}), Spec.layout_diagnostics(active, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}, Nil{}),
    complete_layout_check_with(active, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}, Nil{}))

def RuleCodeObservationRules.complete_check(active, frame): complete_check(active, frame)

def complete_violations(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame) ->
  {Rendered.violations(surface, frame) == Spec.ordinary_frame_diagnostics(surface, frame) : +List<Rendered.Violation>}:
  SurfaceTypes.Surface{+content, +base, +overlays, +scope} = surface
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  +whole: SurfaceTypes.Surface = SurfaceTypes.Surface{content, base, overlays, scope}
  +observed: Rendered.Frame = Rendered.Frame{viewport, elements, focused, tab_order, native_focus}
  %Equal.sym((+List<SurfaceTypes.Node>), Interface.active_nodes(whole), Spec.active_nodes(whole), Diagnostic.active_nodes(whole)) :
    {List.append(&2, Rendered.Violation, Rendered.check(_, observed), Rendered.required_focus(scope, focused)) == Spec.ordinary_frame_diagnostics(whole, observed) : +List<Rendered.Violation>}
  %Equal.sym((+List<Rendered.Violation>), Rendered.check(Spec.active_nodes(whole), observed), Spec.check_diagnostics(Spec.active_nodes(whole), observed), complete_check(Spec.active_nodes(whole), observed)) :
    {List.append(&2, Rendered.Violation, _, Rendered.required_focus(scope, focused)) == Spec.ordinary_frame_diagnostics(whole, observed) : +List<Rendered.Violation>}
  Equal.cong((+List<Rendered.Violation>), (+List<Rendered.Violation>), (faults => List.append(&2, Rendered.Violation, Spec.check_diagnostics(Spec.active_nodes(whole), observed), faults)),
    Rendered.required_focus(scope, focused), Spec.required_focus(scope, focused), Diagnostic.required_focus(scope, focused))

def RuleCodeObservationRules.complete_violations(surface, frame): complete_violations(surface, frame)

def complete_violations_with(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame, +expectations: Rendered.FrameExpectations) ->
  {Rendered.violations_with(surface, frame, expectations) == Spec.frame_diagnostics(surface, frame, expectations) : +List<Rendered.Violation>}:
  SurfaceTypes.Surface{+content, +base, +overlays, +scope} = surface
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  Rendered.FrameExpectations{+controls} = expectations
  +whole: SurfaceTypes.Surface = SurfaceTypes.Surface{content, base, overlays, scope}
  +observed: Rendered.Frame = Rendered.Frame{viewport, elements, focused, tab_order, native_focus}
  %Equal.sym((+List<SurfaceTypes.Node>), Interface.active_nodes(whole), Spec.active_nodes(whole), Diagnostic.active_nodes(whole)) :
    {List.append(&2, Rendered.Violation, Rendered.source_exposure_checks(controls, elements), List.append(&2, Rendered.Violation, Rendered.paint_geometry(elements, viewport), List.append(&2, Rendered.Violation, Rendered.layout_check_with(_, observed, controls), Rendered.required_focus(scope, focused)))) == Spec.frame_diagnostics(whole, observed, Rendered.FrameExpectations{controls}) : +List<Rendered.Violation>}
  %Equal.sym((+List<Rendered.Violation>), Rendered.source_exposure_checks(controls, elements), Spec.source_exposure_checks(controls, elements), Diagnostic.source_exposure_checks(controls, elements)) :
    {List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.paint_geometry(elements, viewport), List.append(&2, Rendered.Violation, Rendered.layout_check_with(Spec.active_nodes(whole), observed, controls), Rendered.required_focus(scope, focused)))) == Spec.frame_diagnostics(whole, observed, Rendered.FrameExpectations{controls}) : +List<Rendered.Violation>}
  %Equal.sym((+List<Rendered.Violation>), Rendered.paint_geometry(elements, viewport), Spec.paint_geometry(elements, viewport), Diagnostic.paint_geometry(elements, viewport)) :
    {List.append(&2, Rendered.Violation, Spec.source_exposure_checks(controls, elements), List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.layout_check_with(Spec.active_nodes(whole), observed, controls), Rendered.required_focus(scope, focused)))) == Spec.frame_diagnostics(whole, observed, Rendered.FrameExpectations{controls}) : +List<Rendered.Violation>}
  %Equal.sym((+List<Rendered.Violation>), Rendered.layout_check_with(Spec.active_nodes(whole), observed, controls), Spec.layout_diagnostics(Spec.active_nodes(whole), observed, controls), complete_layout_check_with(Spec.active_nodes(whole), observed, controls)) :
    {List.append(&2, Rendered.Violation, Spec.source_exposure_checks(controls, elements), List.append(&2, Rendered.Violation, Spec.paint_geometry(elements, viewport), List.append(&2, Rendered.Violation, _, Rendered.required_focus(scope, focused)))) == Spec.frame_diagnostics(whole, observed, Rendered.FrameExpectations{controls}) : +List<Rendered.Violation>}
  %Equal.sym((+List<Rendered.Violation>), Rendered.required_focus(scope, focused), Spec.required_focus(scope, focused), Diagnostic.required_focus(scope, focused)) :
    {List.append(&2, Rendered.Violation, Spec.source_exposure_checks(controls, elements), List.append(&2, Rendered.Violation, Spec.paint_geometry(elements, viewport), List.append(&2, Rendered.Violation, Spec.layout_diagnostics(Spec.active_nodes(whole), observed, controls), _))) == Spec.frame_diagnostics(whole, observed, Rendered.FrameExpectations{controls}) : +List<Rendered.Violation>}
  {==}

def RuleCodeObservationRules.complete_violations_with(surface, frame, expectations): complete_violations_with(surface, frame, expectations)

def accepted_frame(+faults: +List<Rendered.Violation>, +generation: Nat, +frame: Rendered.Frame) ->
  {Rendered.accepted(faults, generation, frame) == Spec.accepted_frame(faults, generation, frame) : Rendered.State}:
  match faults:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def observed_owned(+owned: Bool, +current: Nat, +surface: SurfaceTypes.Surface, +frame: Rendered.Frame, +previous: Rendered.State, +expectations: Rendered.FrameExpectations) ->
  {Rendered.observed_with(owned, current, surface, frame, previous, expectations) == Spec.observed_owned(owned, current, surface, frame, previous, expectations) : Rendered.State}:
  match owned:
    case False{}: {==}
    case True{}:
      %Equal.sym((+List<Rendered.Violation>), Rendered.violations_with(surface, frame, expectations), Spec.frame_diagnostics(surface, frame, expectations), complete_violations_with(surface, frame, expectations)) :
        {Rendered.accepted(_, current, frame) == Spec.accepted_frame(Spec.frame_diagnostics(surface, frame, expectations), current, frame) : Rendered.State}
      accepted_frame(Spec.frame_diagnostics(surface, frame, expectations), current, frame)

def RuleCodeObservationRules.complete_observation(current, received, surface, frame, previous, expectations):
  observed_owned(Nat.is_eq(current, received), current, surface, frame, previous, expectations)

def RuleCodeObservationRules.complete_allocated_frame(world, frame): Diagnostic.allocated_check(world, frame)

def RuleCodeObservationRules.source_frame_evidence():
  RuleCodeObservationRules.SourceFrameRequirements{Diagnostic.allocated_expectations,
    +current => +received => +surface => +frame => +previous => +expectations => observed_owned(Nat.is_eq(current, received), current, surface, frame, previous, expectations),
    Diagnostic.allocated_check}

def ordinary_observation_admission(+owned: Bool, +current: Nat, +received: Nat, +surface: SurfaceTypes.Surface, +frame: Rendered.Frame, +previous: Rendered.State,
  matching: {Rendered.frame_correlated(Rendered.FrameReceipt{current, received, surface, frame}) == owned : Bool}) ->
  {Rendered.received(Categories.admit_checked(Rendered.FrameReceipt, Rendered.frame_correlated, Rendered.FrameReceipt{current, received, surface, frame}, owned, matching), previous) == Spec.ordinary_observed_owned(owned, current, surface, frame, previous) : Rendered.State}:
  match owned:
    case False{}: {==}
    case True{}:
      %Equal.sym((+List<Rendered.Violation>), Rendered.violations(surface, frame), Spec.ordinary_frame_diagnostics(surface, frame), complete_violations(surface, frame)) :
        {Rendered.accepted(_, current, frame) == Spec.accepted_frame(Spec.ordinary_frame_diagnostics(surface, frame), current, frame) : Rendered.State}
      accepted_frame(Spec.ordinary_frame_diagnostics(surface, frame), current, frame)

def RuleCodeObservationRules.complete_ordinary_observation(current, received, surface, frame, previous):
  ordinary_observation_admission(Nat.is_eq(current, received), current, received, surface, frame, previous, {==})
