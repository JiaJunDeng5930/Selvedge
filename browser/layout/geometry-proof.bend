import Base
import ./geometry-contract.bend as Rule
import ./enclosure.bend as E
import ../appearance/DESIGN.bend as D
import ../controls/PROGRAM.bend as C
import ../appearance/MODEL.bend as A
import ./SPACE.bend as Space
import ./GEOMETRY.bend as SpatialModel
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/MODEL.bend as View
import ./natural-size.bend as Size
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/algebra-proof.bend as Alg
import ../../bendlib/stdlib.bend as Std
import ./physical-space.bend as Model

def Rule.forward_clip(distance, extent, limit): {==}

def Rule.backward_clip(distance, extent, limit): {==}

def Rule.forward_forward(left, top, width, height, viewport_width, viewport_height): {==}

def Rule.forward_backward(left, top, width, height, viewport_width, viewport_height): {==}

def Rule.backward_forward(left, top, width, height, viewport_width, viewport_height): {==}

def Rule.backward_backward(left, top, width, height, viewport_width, viewport_height): {==}

def Rule.negative_top_regression(): {==}

def positive(+profile: E.Profile) ->
  {(Nat.min(1n, E.inline(E.area(profile))), Nat.min(1n, E.block(E.area(profile)))) == (1n, 1n) : (Nat & Nat)}:
  match profile:
    case E.IconControl{}: {==}
    case E.TextControl{}: {==}
    case E.OptionControl{}: {==}
    case E.NavigationRow{}: {==}
    case E.Field{}: {==}
    case E.SearchField{}: {==}
    case E.Composer{}: {==}
    case E.Card{}: {==}
    case E.Menu{}: {==}
    case E.UserMessage{}: {==}
    case E.Details{}: {==}
    case E.Navigation{}: {==}
    case E.Approval{}: {==}
    case E.CodeBlock{}: {==}
    case E.Lane{}: {==}
    case E.ArchiveGroup{}: {==}
    case E.PageContent{}: {==}

def action_insets(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat, content_height: Nat) ->
  {Rule.area(A.action_style_insets(value, geometry, space, gap, content_height)) == space : E.ContentArea}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def layout_copied(+value: D.Style, +layout: C.ContentLayout, +geometry: C.Geometry, content_height: Nat) ->
  {Rule.area(A.action_content_style(value, layout, geometry, content_height)) == C.layout_content_area(layout) : E.ContentArea}:
  C.ContentLayout{alignment, space, gap} = layout
  action_insets(value, geometry, space, gap, content_height)

def flow_preserves_area(+value: D.Style, flow: SpatialModel.Flow) ->
  {Rule.area(A.with_flow(value, flow)) == Rule.area(value) : E.ContentArea}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def minimum_extent(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat, +content_height: Nat) ->
  {D.style_minimum_height(A.action_style_insets(value, geometry, space, gap, content_height)) == Nat.max(C.geometry_minimum_height(geometry), E.extent_height(E.required_extent(0n, content_height, A.chrome_border_width(Rule.chrome(value)), space))) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def canvas(+meaning: SurfaceTypes.Meaning, +typography: T.Presentation) ->
  {Rule.area(A.style(SurfaceTypes.Main{}, meaning, typography)) == E.ambient(0n, 0n) : E.ContentArea}:
  {==}

def state_allocation(+value: D.Style, +space: E.ContentArea) ->
  {Rule.interaction(A.with_content_area(value, space)) == Rule.interaction(value) : D.ControlStates}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.Frame{old_area, old_arrangement} = content_frame
  {==}

def page_content() -> Rule.page_content(): {==}

def Rule.enclosure_evidence():
  Rule.EnclosureRequirements{page_content(), positive, +width => +height => +border => +space => {==}, +width => +height => +profile => {==}, action_insets, layout_copied, +value => +face => +geometry =>
      Equal.trans(E.ContentArea, Rule.area(A.action_style(value, face, geometry)),
        Rule.area(A.action_content_style(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry))), C.layout_content_area(C.content_layout(face)),
        flow_preserves_area(A.action_content_style(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry)), A.action_flow(face, C.content_layout(face))),
        layout_copied(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry)))
    ,
    +typography => minimum_extent,
    +typography => {==},
    +typography => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => canvas(meaning, typography),
    +typography => {==}, {==}, {==}, {==}, state_allocation, +text => {==}, +text => +selected => {==},
    +typography => {==}}

def content_preserves_arrangement(+value: D.Style, content: E.ContentArea) ->
  {E.frame_gap(D.style_frame(A.with_content_area(value, content))) == E.frame_gap(D.style_frame(value)) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, E.Frame{old_content, arrangement}, minimum, maximum, states} = value
  {==}

def actual_choice_geometry(+key: Identity.Key, +selected: Bool, +description: String, +input: InteractionTypes.Input, +availability: View.Availability, +label: String, +role: SurfaceTypes.Role, +context: C.Context) ->
  {Rule.actual_geometry(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_layout(+key: Identity.Key, +selected: Bool, +description: String, +input: InteractionTypes.Input, +availability: View.Availability, +label: String, +role: SurfaceTypes.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_mark_contains_icon(+key: Identity.Key, +selected: Bool, +description: String, +input: InteractionTypes.Input, +availability: View.Availability, +label: String, +role: SurfaceTypes.Role, +context: C.Context) ->
  {Nat.is_le(Rule.mark_icon_extent(C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context))), Rule.mark_extent(C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def selection_keeps_allocation(+key: Identity.Key, +description: String, +input: InteractionTypes.Input, +availability: View.Availability, +label: String, +role: SurfaceTypes.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def flow_assigned(+value: D.Style, +flow: SpatialModel.Flow) ->
  {Rule.style_flow(A.with_flow(value, flow)) == flow : SpatialModel.Flow}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def choice_style_normalization(+value: D.Style, +size: C.Geometry, label: String, description: Maybe<&2, String>, selected: Bool) ->
  {Rule.choice_style_metrics(A.action_style(value, C.ChoiceFace{label, description, None{}, selected}, size)) == (8n, SpatialModel.ChoiceFlow{}) : (Nat & SpatialModel.Flow)}:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} = size
  {==}

def actual_choice_normalization(+key: Identity.Key, +selected: Bool, +description: String, +input: InteractionTypes.Input, +availability: View.Availability, +label: String,
  +role: SurfaceTypes.Role, +context: C.Context, +fallback: D.Style, +typography: T.Presentation) -> Rule.actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography):
  match context:
    case C.Context{C.PageArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.NavigationArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.ComposerArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.ToolbarArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.CodeArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.ActivityArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.ApprovalArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.MenuArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.DialogArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.CollectionArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.CardArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.BoardViewArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)
    case C.Context{C.BoardLaneArea{}, selection, code, appearance, access, settings_open, layers, execution, source_family}:
      +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
      choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)

def Rule.frame_relation_evidence():
  Rule.FrameRelationRequirements{
    +value => +face => +size => flow_assigned(A.action_content_style(value, C.content_layout(face), size, A.intrinsic_content_height(face, D.style_text(value), size)), A.action_flow(face, C.content_layout(face))),
    +typography => +key => +selected => +description => +input => +availability => +label => +role => +context => +fallback => actual_choice_normalization(key, selected, description, input, availability, label, role, context, fallback, typography),
    +content => +gap => {==},
    +content => +spacing => {==},
    content => {==},
    content_preserves_arrangement,
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    actual_choice_geometry,
    actual_choice_layout,
    actual_choice_mark_contains_icon,
    selection_keeps_allocation,
    +typography => +meaning => {==},
    +typography => +meaning => {==}}

def addition_capacity(+capacity: Nat, +left: Nat, +right: Nat,
  conflict: {Nat.is_le(left, Nat.sub(capacity, right)) == False{} : Bool}) ->
  {Size.checked_add(capacity, left, right) == None{} : Maybe<&2, Nat>}:
  Equal.cong(Bool, Maybe<&2, Nat>, (accepted => Size.add_if_capacity(accepted, left, right)),
    Nat.is_le(left, Nat.sub(capacity, right)), False{}, conflict)

def multiplication_capacity(+capacity: Nat, +left: Nat, +right: Nat,
  nonzero: {Nat.is_eq(right, 0n) == False{} : Bool},
  conflict: {Nat.is_le(left, Nat.div(capacity, right)) == False{} : Bool}) ->
  {Size.checked_mul(capacity, left, right) == None{} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, Size.checked_mul(capacity, left, right), Size.multiply_zero_with_capacity(False{}, capacity, left, right), None{},
    Equal.cong(Bool, Maybe<&2, Nat>, (zero => Size.multiply_zero_with_capacity(zero, capacity, left, right)),
      Nat.is_eq(right, 0n), False{}, nonzero),
    Equal.cong(Bool, Maybe<&2, Nat>, (accepted => Size.multiply_if_capacity(accepted, left, right)),
      Nat.is_le(left, Nat.div(capacity, right)), False{}, conflict))

def multiplication_zero(+capacity: Nat, left: Nat) ->
  {Size.checked_mul(capacity, left, 0n) == Some{0n} : Maybe<&2, Nat>}:
  {==}

def Rule.natural_size_evidence():
  Rule.NaturalSizeRequirements{
    (capacity => left => right => conflict => addition_capacity(capacity, left, right, conflict)),
    (capacity => left => right => nonzero => conflict => multiplication_capacity(capacity, left, right, nonzero, conflict)),
    (capacity => left => multiplication_zero(capacity, left))}

def choose_extent_successor(+choice: Bool, +first: Nat, +second: Nat) ->
  {Space.choose_extent(choice, 1n+first, 1n+second) == 1n+Space.choose_extent(choice, first, second) : Nat}:
  match choice:
    case True{}: {==}
    case False{}: {==}

def larger_eq_max(+first: Nat, +second: Nat) ->
  {Space.larger(first, second) == Nat.max(first, second) : Nat}:
  match first second:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right:
      Equal.trans(Nat, Space.larger(1n+left, 1n+right), 1n+Space.larger(left, right), 1n+Nat.max(left, right),
        choose_extent_successor(Nat.is_ge(left, right), left, right),
        Equal.cong(Nat, Nat, (n => 1n+n), Space.larger(left, right), Nat.max(left, right), larger_eq_max(left, right)))

def smaller_eq_min(+first: Nat, +second: Nat) ->
  {Space.smaller(first, second) == Nat.min(first, second) : Nat}:
  match first second:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right:
      Equal.trans(Nat, Space.smaller(1n+left, 1n+right), 1n+Space.smaller(left, right), 1n+Nat.min(left, right),
        choose_extent_successor(Nat.is_ge(left, right), right, left),
        Equal.cong(Nat, Nat, (n => 1n+n), Space.smaller(left, right), Nat.min(left, right), smaller_eq_min(left, right)))

def zero_le(value: Nat) -> {Nat.is_le(0n, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

def ge_le(+first: Nat, +second: Nat) ->
  {Nat.is_ge(first, second) == Nat.is_le(second, first) : Bool}:
  match first second:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: ge_le(left, right)

def and_join(+a: Bool, +b: Bool, first: {a == True{} : Bool}, second: {b == True{} : Bool}) ->
  {Bool.and(a, b) == True{} : Bool}:
  match a:
    case False{}: Logic.impossible({Bool.and(False{}, b) == True{} : Bool}, first)
    case True{}: second

def and_parts(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) ->
  {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case False{}: Logic.impossible({False{} == True{} : Bool} & {b == True{} : Bool}, proof)
    case True{}: ({==}, proof)

def max_left(+a: Nat, +b: Nat) -> {Nat.is_le(a, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), a), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), a), Nat.is_le(a, Nat.max(a, b)), ge_le(Nat.max(a, b), a)), Nat.max_ge_l(a, b))

def max_right(+a: Nat, +b: Nat) -> {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(b, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), b), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), b), Nat.is_le(b, Nat.max(a, b)), ge_le(Nat.max(a, b), b)), Nat.max_ge_r(a, b))

def le_refl(+value: Nat) -> {Nat.is_le(value, value) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, value), Nat.is_ge(value, value), True{},
    Equal.sym(Bool, Nat.is_ge(value, value), Nat.is_le(value, value), ge_le(value, value)), Nat.ge_refl(value))

def add_comm(+first: Nat, +second: Nat) ->
  {Nat.add(first, second) == Nat.add(second, first) : Nat}:
  match first:
    case 0n: Equal.sym(Nat, Nat.add(second, 0n), second, Alg.nat_add_zero(second))
    case 1n+rest:
      Equal.trans(Nat, 1n+Nat.add(rest, second), 1n+Nat.add(second, rest), Nat.add(second, 1n+rest),
        Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, second), Nat.add(second, rest), add_comm(rest, second)),
        Equal.sym(Nat, Nat.add(second, 1n+rest), 1n+Nat.add(second, rest), Alg.nat_add_succ(second, rest)))

def le_add(+first: Nat, +extra: Nat) -> {Nat.is_le(first, Nat.add(first, extra)) == True{} : Bool}:
  match first:
    case 0n: zero_le(extra)
    case 1n+rest: le_add(rest, extra)

def le_trans(+first: Nat, +second: Nat, +third: Nat,
  left: {Nat.is_le(first, second) == True{} : Bool},
  right: {Nat.is_le(second, third) == True{} : Bool}) ->
  {Nat.is_le(first, third) == True{} : Bool}:
  match first second third:
    case 0n _ _: zero_le(third)
    case 1n+a 0n _: Logic.impossible({Nat.is_le(1n+a, third) == True{} : Bool}, left)
    case 1n+a 1n+b 0n: Logic.impossible({Nat.is_le(1n+a, 0n) == True{} : Bool}, right)
    case 1n+a 1n+b 1n+c: le_trans(a, b, c, left, right)

def min_le_first(+first: Nat, +second: Nat) ->
  {Nat.is_le(Nat.min(first, second), first) == True{} : Bool}:
  match first second:
    case 0n _: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: min_le_first(left, right)

def min_le_second(+first: Nat, +second: Nat) ->
  {Nat.is_le(Nat.min(first, second), second) == True{} : Bool}:
  match first second:
    case 0n _: zero_le(second)
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: min_le_second(left, right)

def min_floor(+lower: Nat, +extra: Nat, +room: Nat,
  fits: {Nat.is_le(lower, room) == True{} : Bool}) ->
  {Nat.is_le(lower, Nat.min(Nat.add(lower, extra), room)) == True{} : Bool}:
  match lower room:
    case 0n _: zero_le(Nat.min(extra, room))
    case 1n+rest 0n: Logic.impossible({Nat.is_le(1n+rest, Nat.min(Nat.add(1n+rest, extra), 0n)) == True{} : Bool}, fits)
    case 1n+rest 1n+remaining: min_floor(rest, extra, remaining, fits)

def first(-P: Type, -Q: Type, pair: P & Q) -> P:
  (left, right) = pair
  left

def second(-P: Type, -Q: Type, pair: P & Q) -> Q:
  (left, right) = pair
  right

def residual_step(+own: Nat, +rest: Nat, +remaining: Nat,
  evidence: {Nat.is_le(rest, Nat.sub(remaining, own)) == True{} : Bool} &
    {Nat.add(own, Nat.sub(remaining, own)) == remaining : Nat}) ->
  {Nat.is_le(rest, Nat.sub(1n+remaining, 1n+own)) == True{} : Bool} &
  {Nat.add(1n+own, Nat.sub(1n+remaining, 1n+own)) == 1n+remaining : Nat}:
  (tail_fits, balance) = evidence
  (tail_fits, Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(own, Nat.sub(remaining, own)), remaining, balance))

# Cancelling a reserved prefix uses the actual saturating subtraction.

def residual(+prefix: Nat, +rest: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(prefix, rest), budget) == True{} : Bool}) ->
  {Nat.is_le(rest, Nat.sub(budget, prefix)) == True{} : Bool} &
  {Nat.add(prefix, Nat.sub(budget, prefix)) == budget : Nat}:
  match prefix budget:
    case 0n 0n: (fits, {==})
    case 0n 1n+remaining: (fits, {==})
    case 1n+own 0n:
      Logic.impossible({Nat.is_le(rest, Nat.sub(0n, 1n+own)) == True{} : Bool} &
        {Nat.add(1n+own, Nat.sub(0n, 1n+own)) == 0n : Nat}, fits)
    case 1n+own 1n+remaining:
      residual_step(own, rest, remaining, residual(own, rest, remaining, fits))

def room_fits(+own: Nat, +reserve: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}) ->
  {Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool}:
  swapped = Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(own, reserve), Nat.add(reserve, own), add_comm(own, reserve))
  swapped_fits = Equal.trans(Bool, Nat.is_le(Nat.add(reserve, own), budget), Nat.is_le(Nat.add(own, reserve), budget), True{},
    Equal.sym(Bool, Nat.is_le(Nat.add(own, reserve), budget), Nat.is_le(Nat.add(reserve, own), budget), swapped), fits)
  first({Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool},
    {Nat.add(reserve, Nat.sub(budget, reserve)) == budget : Nat}, residual(reserve, own, budget, swapped_fits))

def reserve_fits(+own: Nat, +reserve: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}) ->
  {Nat.is_le(reserve, budget) == True{} : Bool}:
  le_trans(reserve, Nat.add(reserve, own), budget, le_add(reserve, own),
    Equal.trans(Bool, Nat.is_le(Nat.add(reserve, own), budget), Nat.is_le(Nat.add(own, reserve), budget), True{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(reserve, own), Nat.add(own, reserve), add_comm(reserve, own)), fits))

def reserved_use(+own: Nat, +reserve: Nat, +budget: Nat,
  reserve_in_budget: {Nat.is_le(reserve, budget) == True{} : Bool},
  own_in_room: {Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}:
  match reserve budget:
    case 0n 0n:
      %Equal.sym(Nat, Nat.add(own, 0n), own, Alg.nat_add_zero(own)) : {Nat.is_le(_, 0n) == True{} : Bool}
      own_in_room
    case 0n 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 0n), own, Alg.nat_add_zero(own)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      own_in_room
    case 1n+rest 0n:
      Logic.impossible({Nat.is_le(Nat.add(own, 1n+rest), 0n) == True{} : Bool}, reserve_in_budget)
    case 1n+rest 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 1n+rest), 1n+Nat.add(own, rest), Alg.nat_add_succ(own, rest)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      reserved_use(own, rest, remaining, reserve_in_budget, own_in_room)

def chosen_lower(+dimension: Space.Dimension, +room: Nat,
  fits: {Nat.is_le(Space.minimum(dimension), room) == True{} : Bool}) ->
  {Nat.is_le(Space.minimum(dimension), Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: le_refl(value)
    case Space.Fit{lower, extra, maximum_extra}:
      %Equal.sym(Nat, Space.smaller(Nat.add(lower, extra), room), Nat.min(Nat.add(lower, extra), room), smaller_eq_min(Nat.add(lower, extra), room)) : {Nat.is_le(lower, _) == True{} : Bool}
      min_floor(lower, extra, room, fits)
    case Space.Fill{lower}: fits

def chosen_room(+dimension: Space.Dimension, +room: Nat,
  fits: {Nat.is_le(Space.minimum(dimension), room) == True{} : Bool}) ->
  {Nat.is_le(Space.choose(dimension, room), room) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: fits
    case Space.Fit{lower, extra, maximum_extra}:
      %Equal.sym(Nat, Space.smaller(Nat.add(lower, extra), room), Nat.min(Nat.add(lower, extra), room), smaller_eq_min(Nat.add(lower, extra), room)) : {Nat.is_le(_, room) == True{} : Bool}
      min_le_second(Nat.add(lower, extra), room)
    case Space.Fill{lower}: le_refl(room)

def chosen_upper(+dimension: Space.Dimension, +room: Nat) ->
  {Rule.maximum_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: le_refl(value)
    case Space.Fit{lower, extra, maximum_extra}:
      %Equal.sym(Nat, Space.smaller(Nat.add(lower, extra), room), Nat.min(Nat.add(lower, extra), room), smaller_eq_min(Nat.add(lower, extra), room)) : {Nat.is_le(_, Nat.add(Nat.add(lower, extra), maximum_extra)) == True{} : Bool}
      le_trans(Nat.min(Nat.add(lower, extra), room), Nat.add(lower, extra), Nat.add(Nat.add(lower, extra), maximum_extra),
        min_le_first(Nat.add(lower, extra), room), le_add(Nat.add(lower, extra), maximum_extra))
    case Space.Fill{lower}: {==}

def eq_refl(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: eq_refl(rest)

def chosen_rigid(+dimension: Space.Dimension, +room: Nat) ->
  {Rule.rigid_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: eq_refl(value)
    case Space.Fit{lower, extra, maximum_extra}: {==}
    case Space.Fill{lower}: {==}

def conjunction(+first: Bool, +second: Bool,
  left: {first == True{} : Bool}, right: {second == True{} : Bool}) ->
  {(first && second) == True{} : Bool}:
  Equal.trans(Bool, first && second, second, True{},
    Equal.cong(Bool, Bool, (value => value && second), first, True{}, left), right)

def sequence_split(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap) ==
    Nat.add(Space.minimum(dimension), Space.reservation(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(Space.minimum(dimension), 0n), Space.minimum(dimension), Alg.nat_add_zero(Space.minimum(dimension)))
    case Con{next, tail}: {==}

def reserve_split(~A: Data, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.reservation(~A, rest, gap) == Nat.add(Space.following_gap(~A, rest, gap), Space.minimum_sequence(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: {==}
    case Con{head, tail}: {==}

def gap_agrees(~A: Data, +slots: +List<Space.Slot<A>>, +placements: +List<Space.Placement<A>>, +gap: Nat,
  valid: {Rule.limits(~A, slots, placements) == True{} : Bool}) ->
  {Space.following_gap(~A, slots, gap) == Rule.placement_gap(~A, placements, gap) : Nat}:
  match slots placements:
    case Nil{} Nil{}: {==}
    case Con{head, tail} Con{other, rest}: {==}
    case Nil{} Con{head, tail}: Logic.impossible({0n == gap : Nat}, valid)
    case Con{Space.Slot{value, dimension}, tail} Nil{}: Logic.impossible({gap == 0n : Nat}, valid)

def used_split(~A: Data, +value: A, +offset: Nat, +size: Nat, +rest: +List<Space.Placement<A>>, +gap: Nat) ->
  {Rule.used(~A, Space.Placement{value, offset, size} <> rest, gap) ==
    Nat.add(size, Nat.add(Rule.placement_gap(~A, rest, gap), Rule.used(~A, rest, gap))) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(size, 0n), size, Alg.nat_add_zero(size))
    case Con{head, tail}: {==}

def combined_balance(+size: Nat, +between: Nat, +tail_used: Nat, +unused: Nat, +next_budget: Nat, +budget: Nat,
  tail_balance: {Nat.add(tail_used, unused) == next_budget : Nat},
  head_balance: {Nat.add(size, Nat.add(between, next_budget)) == budget : Nat}) ->
  {Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused) == budget : Nat}:
  Equal.trans(Nat, Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused),
    Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)), budget,
    Alg.nat_add_assoc(size, Nat.add(between, tail_used), unused),
    Equal.trans(Nat, Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)),
      Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(size, n)), Nat.add(Nat.add(between, tail_used), unused),
        Nat.add(between, Nat.add(tail_used, unused)), Alg.nat_add_assoc(between, tail_used, unused)),
      Equal.trans(Nat, Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))),
        Nat.add(size, Nat.add(between, next_budget)), budget,
        Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(between, n))), Nat.add(tail_used, unused), next_budget, tail_balance), head_balance)))

def prefix_evidence(~A: Data, +value: A, +dimension: Space.Dimension, +slots: +List<Space.Slot<A>>, +gap: Nat,
  +offset: Nat, +size: Nat, +budget: Nat, +next_budget: Nat, +result: Space.Allocation<A>,
  lower: {Nat.is_le(Space.minimum(dimension), size) == True{} : Bool},
  upper: {Rule.maximum_ok(dimension, size) == True{} : Bool},
  rigid: {Rule.rigid_ok(dimension, size) == True{} : Bool},
  head_balance: {Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)) == budget : Nat},
  tail: Rule.AllocationEvidence<A, slots, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap))), next_budget, result>) ->
  Rule.AllocationEvidence<A, Space.Slot{value, dimension} <> slots, gap, offset, budget,
    Space.prepend(~A, Space.Placement{value, offset, size}, result)>:
  Space.Allocation{+placements, +unused} = result
  Rule.AllocationEvidence{payloads, +bounds, order, balance} = tail
  +same_gap = gap_agrees(~A, slots, placements, gap, bounds)
  next_order = Equal.trans(Bool,
    Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Rule.placement_gap(~A, placements, gap)))),
    Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap)))), True{},
    Equal.cong(Nat, Bool, (n => Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, n)))),
      Rule.placement_gap(~A, placements, gap), Space.following_gap(~A, slots, gap),
      Equal.sym(Nat, Space.following_gap(~A, slots, gap), Rule.placement_gap(~A, placements, gap), same_gap)), order)
  concrete_head_balance = Equal.trans(Nat,
    Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), next_budget)),
    Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)), budget,
    Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(n, next_budget))), Rule.placement_gap(~A, placements, gap),
      Space.following_gap(~A, slots, gap), Equal.sym(Nat, Space.following_gap(~A, slots, gap), Rule.placement_gap(~A, placements, gap), same_gap)), head_balance)
  Rule.AllocationEvidence{
    Equal.cong(+List<A>, +List<A>, (items => value <> items), Rule.placement_values(~A, placements), Rule.slot_values(~A, slots), payloads),
    conjunction(Nat.is_le(Space.minimum(dimension), size), Rule.maximum_ok(dimension, size) && (Rule.rigid_ok(dimension, size) && Rule.limits(~A, slots, placements)), lower,
      conjunction(Rule.maximum_ok(dimension, size), Rule.rigid_ok(dimension, size) && Rule.limits(~A, slots, placements), upper,
        conjunction(Rule.rigid_ok(dimension, size), Rule.limits(~A, slots, placements), rigid, bounds))),
    conjunction(Nat.is_eq(offset, offset), Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Rule.placement_gap(~A, placements, gap)))), eq_refl(offset), next_order),
    Equal.trans(Nat, Nat.add(Rule.used(~A, Space.Placement{value, offset, size} <> placements, gap), unused),
      Nat.add(Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap))), unused), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(n, unused)), Rule.used(~A, Space.Placement{value, offset, size} <> placements, gap),
        Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap))), used_split(~A, value, offset, size, placements, gap)),
      combined_balance(size, Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap), unused, next_budget, budget, balance, concrete_head_balance))}

# The induction reserves the entire remaining sequence before choosing a size.

def place_evidence(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat,
  fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), budget) == True{} : Bool}) ->
  Rule.AllocationEvidence<A, slots, gap, offset, budget, Space.place_from(~A, slots, gap, offset, budget)>:
  match slots:
    case Nil{}: Rule.AllocationEvidence{{==}, {==}, {==}, {==}}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +reserve = Space.reservation(~A, rest, gap)
      +between = Space.following_gap(~A, rest, gap)
      +room = Nat.sub(budget, reserve)
      +size = Space.choose(dimension, room)
      +next_budget = Nat.sub(Nat.sub(budget, size), between)
      +sequence_fits = Equal.trans(Bool, Nat.is_le(Nat.add(Space.minimum(dimension), reserve), budget),
        Nat.is_le(Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap), budget), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(Space.minimum(dimension), reserve),
          Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap),
          Equal.sym(Nat, Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap), Nat.add(Space.minimum(dimension), reserve), sequence_split(~A, value, dimension, rest, gap))), fits)
      +minimum_in_room = room_fits(Space.minimum(dimension), reserve, budget, sequence_fits)
      +allocated_in_budget = reserved_use(size, reserve, budget,
        reserve_fits(Space.minimum(dimension), reserve, budget, sequence_fits), chosen_room(dimension, room, minimum_in_room))
      +allocated_with_split = Equal.trans(Bool, Nat.is_le(Nat.add(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap))), budget),
        Nat.is_le(Nat.add(size, reserve), budget), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(size, n), budget)), Nat.add(between, Space.minimum_sequence(~A, rest, gap)), reserve,
          Equal.sym(Nat, reserve, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), reserve_split(~A, rest, gap))), allocated_in_budget)
      +tail_reserve_fits = first({Nat.is_le(Nat.add(between, Space.minimum_sequence(~A, rest, gap)), Nat.sub(budget, size)) == True{} : Bool},
        {Nat.add(size, Nat.sub(budget, size)) == budget : Nat}, residual(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), budget, allocated_with_split))
      size_balance = second({Nat.is_le(Nat.add(between, Space.minimum_sequence(~A, rest, gap)), Nat.sub(budget, size)) == True{} : Bool},
        {Nat.add(size, Nat.sub(budget, size)) == budget : Nat}, residual(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), budget, allocated_with_split))
      +next_fits = first({Nat.is_le(Space.minimum_sequence(~A, rest, gap), next_budget) == True{} : Bool},
        {Nat.add(between, next_budget) == Nat.sub(budget, size) : Nat}, residual(between, Space.minimum_sequence(~A, rest, gap), Nat.sub(budget, size), tail_reserve_fits))
      gap_balance = second({Nat.is_le(Space.minimum_sequence(~A, rest, gap), next_budget) == True{} : Bool},
        {Nat.add(between, next_budget) == Nat.sub(budget, size) : Nat}, residual(between, Space.minimum_sequence(~A, rest, gap), Nat.sub(budget, size), tail_reserve_fits))
      head_balance = Equal.trans(Nat, Nat.add(size, Nat.add(between, next_budget)), Nat.add(size, Nat.sub(budget, size)), budget,
        Equal.cong(Nat, Nat, (n => Nat.add(size, n)), Nat.add(between, next_budget), Nat.sub(budget, size), gap_balance), size_balance)
      prefix_evidence(~A, value, dimension, rest, gap, offset, size, budget, next_budget,
        Space.place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), next_budget),
        chosen_lower(dimension, room, minimum_in_room), chosen_upper(dimension, room), chosen_rigid(dimension, room), head_balance,
        place_evidence(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), next_budget, next_fits))

def dimension_minimum(+dimension: Space.Dimension) ->
  {Nat.is_le(Space.minimum(dimension), Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(lower, extra)
    case Space.Fill{lower}: le_refl(lower)

def dimension_maximum(+dimension: Space.Dimension) ->
  {Rule.maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(Nat.add(lower, extra), maximum_extra)
    case Space.Fill{lower}: {==}

def space_proof_finish_claim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  evidence: Rule.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  Rule.PackedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  evidence

def pack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  Rule.PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available)):
  Std.transport(Bool, True{}, (feasible => Rule.PackedClaim(~A, slots, gap, available, Space.feasible_pack(~A, feasible, slots, gap, available))),
    space_proof_finish_claim(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available), place_evidence(~A, slots, gap, 0n, available, fits)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), fits)

def pack_insufficient(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  does_not_fit: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool}) ->
  {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>}:
  Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), False{}, does_not_fit)

def finish_packed(~A: Data, result: Space.Allocation<A>) -> {Rule.packed(~A, Space.finish(~A, result)) == True{} : Bool}:
  Space.Allocation{placements, unused} = result
  {==}

def feasible_tag(~A: Data, +feasible: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {Rule.packed(~A, Space.feasible_pack(~A, feasible, slots, gap, available)) == feasible : Bool}:
  match feasible:
    case False{}: {==}
    case True{}: finish_packed(~A, Space.place_from(~A, slots, gap, 0n, available))

def Rule.space_evidence(A):
  Rule.SpaceRequirements{larger_eq_max, smaller_eq_min, dimension_minimum, dimension_maximum,
    +slots => +gap => +available => feasible_tag(~A, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), slots, gap, available),
    +slots => +gap => +available => does_not_fit => pack_insufficient(~A, slots, gap, available, does_not_fit),
    +slots => +gap => +available => +fits => pack_complete(~A, slots, gap, available, fits)}

# Both subtractions are justified by the full minimum, including both insets.

def inset_budget_from(+leading: Nat, +trailing: Nat, +minimum: Nat, +available: Nat,
  evidence: {Nat.is_le(Nat.add(minimum, trailing), Nat.sub(available, leading)) == True{} : Bool} &
    {Nat.add(leading, Nat.sub(available, leading)) == available : Nat}) ->
  {Nat.is_le(minimum, Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  (+remaining_fits, leading_balance) = evidence
  +remaining = Nat.sub(available, leading)
  +inner = Rule.inner_budget(leading, trailing, available)
  inner_fits = room_fits(minimum, trailing, remaining, remaining_fits)
  swapped_fits = Equal.trans(Bool, Nat.is_le(Nat.add(trailing, minimum), remaining),
    Nat.is_le(Nat.add(minimum, trailing), remaining), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, remaining)), Nat.add(trailing, minimum),
      Nat.add(minimum, trailing), add_comm(trailing, minimum)), remaining_fits)
  trailing_balance = second({Nat.is_le(minimum, Nat.sub(remaining, trailing)) == True{} : Bool},
    {Nat.add(trailing, Nat.sub(remaining, trailing)) == remaining : Nat},
    residual(trailing, minimum, remaining, swapped_fits))
  inner_balance = Equal.trans(Nat, Nat.add(inner, trailing), Nat.add(trailing, inner), remaining,
    add_comm(inner, trailing), trailing_balance)
  (inner_fits, Equal.trans(Nat, Nat.add(leading, Nat.add(inner, trailing)), Nat.add(leading, remaining), available,
    Equal.cong(Nat, Nat, (n => Nat.add(leading, n)), Nat.add(inner, trailing), remaining, inner_balance), leading_balance))

def inset_budget(+leading: Nat, +trailing: Nat, +minimum: Nat, +available: Nat,
  fits: {Nat.is_le(Nat.add(leading, Nat.add(minimum, trailing)), available) == True{} : Bool}) ->
  {Nat.is_le(minimum, Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  inset_budget_from(leading, trailing, minimum, available,
    residual(leading, Nat.add(minimum, trailing), available, fits))

def container_space_proof_finish_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  +result: Space.Allocation<A>,
  evidence: Rule.AllocationEvidence<A, slots, gap, leading, Rule.inner_budget(leading, trailing, available), result>,
  balance: {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  Rule.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available, Space.finish(~A, result)):
  Space.Allocation{+placements, +unused} = result
  Rule.AllocationEvidence{payloads, bounds, positions, +total} = evidence
  (Rule.AllocationEvidence{payloads, bounds, positions, total},
    Equal.trans(Nat, Nat.add(leading, Nat.add(Nat.add(Rule.used(~A, placements, gap), unused), trailing)),
      Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)), available,
      Equal.cong(Nat, Nat, (n => Nat.add(leading, Nat.add(n, trailing))),
        Nat.add(Rule.used(~A, placements, gap), unused), Rule.inner_budget(leading, trailing, available), total), balance))

def accepted_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  evidence: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
    {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  Rule.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available,
    Space.finish(~A, Space.place_from(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available)))):
  (inner_fits, balance) = evidence
  container_space_proof_finish_claim(~A, leading, trailing, gap, slots, available,
    Space.place_from(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available)),
    place_evidence(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available), inner_fits), balance)

def feasible_claim(~A: Data, +feasible: Bool, +container: Space.Container<A>, +available: Nat,
  decision: {Nat.is_le(Space.container_required(~A, container), available) == feasible : Bool}) ->
  Rule.ContainerClaim(~A, container, available, Space.feasible_container(~A, feasible, container, available)):
  match feasible:
    case False{}:
      Space.Container{leading, trailing, gap, slots} = container
      ({==}, ({==}, decision))
    case True{}:
      Space.Container{+leading, +trailing, +gap, +slots} = container
      accepted_claim(~A, leading, trailing, gap, slots, available,
        inset_budget(leading, trailing, Space.minimum_sequence(~A, slots, gap), available, decision))

def container_space_proof_complete(~A: Data, +container: Space.Container<A>, +available: Nat) ->
  Rule.ContainerClaim(~A, container, available, Space.pack_container(~A, container, available)):
  feasible_claim(~A, Nat.is_le(Space.container_required(~A, container), available), container, available, {==})

def Rule.container_space_evidence(A):
  Rule.Requirement{+container => +available => container_space_proof_complete(~A, container, available)}

def demand_max_left(+first: Nat, +second: Nat) ->
  {Nat.is_le(first, Space.larger(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(first, Space.larger(first, second)), Nat.is_le(first, Nat.max(first, second)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(first, n)), Space.larger(first, second), Nat.max(first, second), larger_eq_max(first, second)),
    max_left(first, second))

def demand_max_right(+first: Nat, +second: Nat) ->
  {Nat.is_le(second, Space.larger(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(second, Space.larger(first, second)), Nat.is_le(second, Nat.max(first, second)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(second, n)), Space.larger(first, second), Nat.max(first, second), larger_eq_max(first, second)),
    max_right(first, second))

def physical_space_proof_and_left(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  first({a == True{} : Bool}, {b == True{} : Bool}, and_parts(a, b, evidence))

def physical_space_proof_and_right(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  second({a == True{} : Bool}, {b == True{} : Bool}, and_parts(a, b, evidence))

def max_contains_first(+first: E.Extent, +second: E.Extent) ->
  {Rule.extent_contains(Model.extent_max(first, second), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = second
  and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Space.larger(h, y)),
    demand_max_left(w, x), demand_max_left(h, y))

def max_contains_second(+first: E.Extent, +second: E.Extent) ->
  {Rule.extent_contains(Model.extent_max(first, second), second) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = second
  and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Space.larger(h, y)),
    demand_max_right(w, x), demand_max_right(h, y))

def contains_trans(+outer: E.Extent, +middle: E.Extent, +inner: E.Extent,
  +first: {Rule.extent_contains(outer, middle) == True{} : Bool},
  +second: {Rule.extent_contains(middle, inner) == True{} : Bool}) ->
  {Rule.extent_contains(outer, inner) == True{} : Bool}:
  E.Extent{+w, +h} = outer
  E.Extent{+x, +y} = middle
  E.Extent{+a, +b} = inner
  wx = physical_space_proof_and_left(Nat.is_le(x, w), Nat.is_le(y, h), first)
  hy = physical_space_proof_and_right(Nat.is_le(x, w), Nat.is_le(y, h), first)
  xa = physical_space_proof_and_left(Nat.is_le(a, x), Nat.is_le(b, y), second)
  yb = physical_space_proof_and_right(Nat.is_le(a, x), Nat.is_le(b, y), second)
  and_join(Nat.is_le(a, w), Nat.is_le(b, h), le_trans(a, x, w, xa, wx), le_trans(b, y, h, yb, hy))

def add_contains_second(+first: Nat, +second: Nat) ->
  {Nat.is_le(second, Nat.add(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(second, Nat.add(first, second)), Nat.is_le(second, Nat.add(second, first)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(second, n)), Nat.add(first, second), Nat.add(second, first), add_comm(first, second)), le_add(second, first))

def combine_first_horizontal(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.horizontal_extent(gap, first, rest), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(w, Nat.add(w, Nat.add(gap, x))), Nat.is_le(h, Space.larger(h, y)), le_add(w, Nat.add(gap, x)), demand_max_left(h, y))

def combine_first_vertical(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.vertical_extent(gap, first, rest), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Nat.add(h, Nat.add(gap, y))), demand_max_left(w, x), le_add(h, Nat.add(gap, y)))

def combine_first(+direction: Model.Direction, +gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.combine_extent(direction, gap, first, rest), first) == True{} : Bool}:
  match direction:
    case Model.Horizontal{}: combine_first_horizontal(gap, first, rest)
    case Model.Vertical{}: combine_first_vertical(gap, first, rest)
    case Model.ResponsiveHorizontal{}: combine_first_vertical(gap, first, rest)
    case Model.Layered{}: max_contains_first(first, rest)

def combine_rest_horizontal(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.horizontal_extent(gap, first, rest), rest) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(x, Nat.add(w, Nat.add(gap, x))), Nat.is_le(y, Space.larger(h, y)),
    le_trans(x, Nat.add(gap, x), Nat.add(w, Nat.add(gap, x)), add_contains_second(gap, x), add_contains_second(w, Nat.add(gap, x))), demand_max_right(h, y))

def combine_rest_vertical(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.vertical_extent(gap, first, rest), rest) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Nat.add(h, Nat.add(gap, y))), demand_max_right(w, x),
    le_trans(y, Nat.add(gap, y), Nat.add(h, Nat.add(gap, y)), add_contains_second(gap, y), add_contains_second(h, Nat.add(gap, y))))

def combine_rest(+direction: Model.Direction, +gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {Rule.extent_contains(Model.combine_extent(direction, gap, first, rest), rest) == True{} : Bool}:
  match direction:
    case Model.Horizontal{}: combine_rest_horizontal(gap, first, rest)
    case Model.Vertical{}: combine_rest_vertical(gap, first, rest)
    case Model.ResponsiveHorizontal{}: combine_rest_vertical(gap, first, rest)
    case Model.Layered{}: max_contains_second(first, rest)

def max_zero(+value: Nat) -> {Nat.max(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

def demand_max_zero(+value: Nat) -> {Space.larger(value, 0n) == value : Nat}:
  Equal.trans(Nat, Space.larger(value, 0n), Nat.max(value, 0n), value, larger_eq_max(value, 0n), max_zero(value))

def combine_empty(+extent: E.Extent) ->
  {Model.combine_extent(Model.Horizontal{}, 0n, extent, E.Extent{0n, 0n}) == extent : E.Extent}:
  E.Extent{+w, +h} = extent
  Equal.trans(E.Extent, E.Extent{Nat.add(w, 0n), Space.larger(h, 0n)}, E.Extent{w, Space.larger(h, 0n)}, E.Extent{w, h},
    Equal.cong(Nat, E.Extent, (n => E.Extent{n, Space.larger(h, 0n)}), Nat.add(w, 0n), w, Alg.nat_add_zero(w)),
    Equal.cong(Nat, E.Extent, (n => E.Extent{w, n}), Space.larger(h, 0n), h, demand_max_zero(h)))

def singleton_minimum(+first: Space.Demand) ->
  {Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n))) == Model.minimum_demand(first) : E.Extent}:
  Space.Demand{+minimum, preferred} = first
  combine_empty(minimum)

def prepend_preferred(+direction: Model.Direction, +gap: Nat, +first: Space.Demand, +rest: Space.Demand) ->
  {Rule.preferred_covers_minimum(Model.prepend_demand(direction, gap, first, rest)) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = rest
  max_contains_first(Model.combine_extent(direction, gap, a, c), Model.combine_extent(direction, gap, b, d))

def extent_contains_self(+extent: E.Extent) ->
  {Rule.extent_contains(extent, extent) == True{} : Bool}:
  E.Extent{+width, +height} = extent
  and_join(Nat.is_le(width, width), Nat.is_le(height, height), le_refl(width), le_refl(height))

def clearance_layered_contains(+outside: E.Insets, +extent: E.Extent) ->
  {Rule.extent_contains(Model.clearance_extent_layered(outside, extent), extent) == True{} : Bool}:
  E.Insets{+inline, +block} = outside
  E.Extent{+width, +height} = extent
  and_join(Nat.is_le(width, Nat.add(width, Nat.mul(2n, inline))), Nat.is_le(height, Nat.add(height, Nat.mul(2n, block))),
    le_add(width, Nat.mul(2n, inline)), le_add(height, Nat.mul(2n, block)))

def clearance_contains(+direction: Model.Direction, +position: SpatialModel.Position, +extent: E.Extent) ->
  {Rule.extent_contains(Model.clearance_extent(direction, position, extent), extent) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_layered_contains(Model.position_outside(position), extent)
    case Model.Horizontal{}: extent_contains_self(extent)
    case Model.Vertical{}: extent_contains_self(extent)
    case Model.ResponsiveHorizontal{}: extent_contains_self(extent)

def preferred_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {Rule.preferred_covers_minimum(Model.content_demand(~A, ~E, trees, direction, gap)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{Model.Leaf{key, value, interaction, +rule, demand, height}, +rest}:
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), Model.outer_demand(~E, Model.leaf_content_demand(demand, height), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))
    case Con{Model.Container{key, value, interaction, +rule, children}, +rest}:
      Model.Rule{child_direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap),
        Model.clearance_demand(direction, position, Model.outer_demand(~E, Model.content_demand(~A, ~E, children, child_direction, E.frame_gap(frame)), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))

def children_raise(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +outer: E.Extent, +inner: E.Extent,
  +contains: {Rule.extent_contains(outer, inner) == True{} : Bool},
  +participating: {Rule.child_minima_participate(~A, ~E, trees, inner) == True{} : Bool}) ->
  {Rule.child_minima_participate(~A, ~E, trees, outer) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{+tree, +rest}:
      +minimum = Model.minimum_demand(Model.demand(~A, ~E, tree))
      head = physical_space_proof_and_left(Rule.extent_contains(inner, minimum), Rule.child_minima_participate(~A, ~E, rest, inner), participating)
      tail = physical_space_proof_and_right(Rule.extent_contains(inner, minimum), Rule.child_minima_participate(~A, ~E, rest, inner), participating)
      and_join(Rule.extent_contains(outer, minimum), Rule.child_minima_participate(~A, ~E, rest, outer),
        contains_trans(outer, inner, minimum, contains, head), children_raise(~A, ~E, rest, outer, inner, contains, tail))

def prepend_children(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +rest: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat, +first: Space.Demand, +remaining: Space.Demand,
  same: {Rule.extent_contains(Model.minimum_demand(first), Model.minimum_demand(Model.demand(~A, ~E, tree))) == True{} : Bool},
  tail: {Rule.child_minima_participate(~A, ~E, rest, Model.minimum_demand(remaining)) == True{} : Bool}) ->
  {Rule.child_minima_participate(~A, ~E, tree <> rest, Model.minimum_demand(Model.prepend_demand(direction, gap, first, remaining))) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = remaining
  +required = Model.combine_extent(direction, gap, a, c)
  head = contains_trans(required, a, Model.minimum_demand(Model.demand(~A, ~E, tree)), combine_first(direction, gap, a, c), same)
  and_join(Rule.extent_contains(required, Model.minimum_demand(Model.demand(~A, ~E, tree))), Rule.child_minima_participate(~A, ~E, rest, required),
    head, children_raise(~A, ~E, rest, required, c, combine_rest(direction, gap, a, c), tail))

def clearance_demand_contains(+direction: Model.Direction, +position: SpatialModel.Position, +minimum: E.Extent, +preferred: E.Extent) ->
  {Rule.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, Space.Demand{minimum, preferred})), minimum) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_contains(Model.Layered{}, position, minimum)
    case Model.Horizontal{}: extent_contains_self(minimum)
    case Model.Vertical{}: extent_contains_self(minimum)
    case Model.ResponsiveHorizontal{}: extent_contains_self(minimum)

def clearance_singleton(+direction: Model.Direction, +position: SpatialModel.Position, +first: Space.Demand) ->
  {Rule.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))) == True{} : Bool}:
  Space.Demand{minimum, preferred} = first
  Equal.trans(Bool,
    Rule.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))),
    Rule.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(first)), True{},
    Equal.cong(E.Extent, Bool, (extent => Rule.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), extent)),
      Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n))), Model.minimum_demand(first), singleton_minimum(first)),
    clearance_demand_contains(direction, position, minimum, preferred))

def children_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {Rule.child_minima_participate(~A, ~E, trees, Model.minimum_demand(Model.content_demand(~A, ~E, trees, direction, gap))) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{Model.Leaf{+key, +value, +interaction, +rule, +demand, +height}, +rest}:
      +first = Model.outer_demand(~E, Model.leaf_content_demand(demand, height), rule, interaction)
      prepend_children(~A, ~E, Model.Leaf{key, value, interaction, rule, demand, height}, rest, direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), first), Model.content_demand(~A, ~E, rest, direction, gap),
        clearance_singleton(direction, Model.rule_position(rule), first), children_content(~A, ~E, rest, direction, gap))
    case Con{Model.Container{+key, +value, +interaction, +rule, +children}, +rest}:
      Model.Rule{+child_direction, main, cross, +frame, border, width, height, minimum, scroll, position} = rule
      +first = Model.outer_demand(~E, Model.content_demand(~A, ~E, children, child_direction, E.frame_gap(frame)), rule, interaction)
      prepend_children(~A, ~E, Model.Container{key, value, interaction, rule, children}, rest, direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), first), Model.content_demand(~A, ~E, rest, direction, gap),
        clearance_singleton(direction, Model.rule_position(rule), first), children_content(~A, ~E, rest, direction, gap))

def axis_authored_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(Rule.authored_minimum(size), Rule.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: zero_le(minimum)
    case Model.StretchSize{}: zero_le(minimum)
    case Model.CappedStretchSize{maximum}: zero_le(minimum)
    case Model.ExactSize{extent}: max_right(minimum, extent)
    case Model.LimitedSize{authored, extra, maximum}: max_right(minimum, authored)
    case Model.PercentSize{percent}: zero_le(minimum)
    case Model.CappedNaturalSize{percent}: zero_le(minimum)
    case Model.AdaptiveNaturalSize{percent}: zero_le(minimum)

def axis_intrinsic_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(minimum, Rule.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: le_refl(minimum)
    case Model.StretchSize{}: le_refl(minimum)
    case Model.CappedStretchSize{maximum}: le_refl(minimum)
    case Model.ExactSize{extent}: max_left(minimum, extent)
    case Model.LimitedSize{authored, extra, maximum}: max_left(minimum, authored)
    case Model.PercentSize{percent}: le_refl(minimum)
    case Model.CappedNaturalSize{percent}: le_refl(minimum)
    case Model.AdaptiveNaturalSize{percent}: le_refl(minimum)

def axis_preferred_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(Rule.axis_minimum(Model.axis_demand(size, minimum, preferred)), Rule.axis_preferred(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: max_left(minimum, preferred)
    case Model.StretchSize{}: max_left(minimum, preferred)
    case Model.CappedStretchSize{maximum}: max_left(minimum, maximum)
    case Model.ExactSize{extent}: le_refl(Nat.max(minimum, extent))
    case Model.LimitedSize{authored, extra, maximum}:
      max_left(Nat.max(minimum, authored), Nat.min(Nat.add(Nat.add(authored, extra), maximum), Nat.max(Nat.max(minimum, authored), Nat.max(minimum, preferred))))
    case Model.PercentSize{percent}: max_left(minimum, preferred)
    case Model.CappedNaturalSize{percent}: max_left(minimum, preferred)
    case Model.AdaptiveNaturalSize{percent}: max_left(minimum, preferred)

def axes_floor(+width: Model.AxisDemand, +height: Model.AxisDemand, +mw: Nat, +mh: Nat,
  +width_floor: {Nat.is_le(mw, Rule.axis_minimum(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(mh, Rule.axis_minimum(height)) == True{} : Bool}) ->
  {Rule.extent_contains(Model.minimum_demand(Model.demand_from_axes(width, height)), E.Extent{mw, mh}) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  and_join(Nat.is_le(mw, lower_width), Nat.is_le(mh, lower_height), width_floor, height_floor)

def authored_floor(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {Rule.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), Model.minimum_demand(content)) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), mw, mh,
    axis_intrinsic_floor(width, mw, pw), axis_intrinsic_floor(height, mh, ph))

def axes_preferred(+width: Model.AxisDemand, +height: Model.AxisDemand,
  +width_floor: {Nat.is_le(Rule.axis_minimum(width), Rule.axis_preferred(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(Rule.axis_minimum(height), Rule.axis_preferred(height)) == True{} : Bool}) ->
  {Rule.preferred_covers_minimum(Model.demand_from_axes(width, height)) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  and_join(Nat.is_le(lower_width, chosen_width), Nat.is_le(lower_height, chosen_height), width_floor, height_floor)

def authored_preferred(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {Rule.preferred_covers_minimum(Model.authored_demand(width, height, content)) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_preferred(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph),
    axis_preferred_floor(width, mw, pw), axis_preferred_floor(height, mh, ph))

def authored_lower_pair(+width: Model.AxisSize, +height: Model.AxisSize, content: Space.Demand) ->
  {Rule.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), E.Extent{Rule.authored_minimum(width), Rule.authored_minimum(height)}) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), Rule.authored_minimum(width), Rule.authored_minimum(height),
    axis_authored_floor(width, mw, pw), axis_authored_floor(height, mh, ph))

def outer_authored_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {Rule.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), Rule.rule_authored_minimum(rule)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_lower_pair(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_preferred(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {Rule.preferred_covers_minimum(Model.outer_demand(~E, content, rule, interaction)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_preferred(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_intrinsic_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {Rule.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, interaction))) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_floor(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def operable_outer(~E: Data, +content: E.Extent, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {Rule.extent_contains(Model.outer_extent(~E, content, rule, Model.Operable{first, remaining, enabled}), E.Extent{32n, 32n}) == True{} : Bool}:
  E.Extent{+w, +h} = content
  Model.Rule{direction, main, cross, +frame, +border, width, height, +minimum, scroll, position} = rule
  contains_trans(Model.extent_max(E.required_extent(w, h, border, E.frame_content(frame)), Model.extent_max(minimum, E.Extent{32n, 32n})),
    Model.extent_max(minimum, E.Extent{32n, 32n}), E.Extent{32n, 32n},
    max_contains_second(E.required_extent(w, h, border, E.frame_content(frame)), Model.extent_max(minimum, E.Extent{32n, 32n})), max_contains_second(minimum, E.Extent{32n, 32n}))

def operable(~E: Data, +content: Space.Demand, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {Rule.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), E.Extent{32n, 32n}) == True{} : Bool}:
  Space.Demand{+content_minimum, preferred} = content
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, +scroll, position} = rule
  contains_trans(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})),
    Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), E.Extent{32n, 32n},
    outer_intrinsic_floor(~E, content, rule, Model.Operable{first, remaining, enabled}),
    operable_outer(~E, Model.viewport_content_minimum(content_minimum, scroll), rule, first, remaining, enabled))

def lower_conflict(+minimum: Nat, +authored: Nat, +maximum: Nat,
  conflict: {Nat.is_le(minimum, maximum) == False{} : Bool}) ->
  {Nat.is_le(Nat.max(minimum, authored), maximum) == False{} : Bool}:
  match minimum authored maximum:
    case 0n _ _: Logic.impossible({Nat.is_le(Nat.max(0n, authored), maximum) == False{} : Bool},
      Equal.trans(Bool, False{}, Nat.is_le(0n, maximum), True{}, Equal.sym(Bool, Nat.is_le(0n, maximum), False{}, conflict), zero_le(maximum)))
    case 1n+a 0n _: conflict
    case 1n+a 1n+b 0n: {==}
    case 1n+a 1n+b 1n+c: lower_conflict(a, b, c, conflict)

def exact_conflict(+minimum: Nat, preferred: Nat, offered: Nat, +extent: Nat,
  conflict: {Nat.is_le(minimum, extent) == False{} : Bool}) ->
  {Model.materialize(Model.ExactSize{extent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (fits => Model.accept_dimension(fits, Space.Rigid{extent})), Nat.is_le(minimum, extent), False{}, conflict)

def limited_conflict(+minimum: Nat, +preferred: Nat, offered: Nat, +authored: Nat, +extra: Nat, +maximum_extra: Nat,
  conflict: {Nat.is_le(minimum, Nat.add(Nat.add(authored, extra), maximum_extra)) == False{} : Bool}) ->
  {Model.materialize(Model.LimitedSize{authored, extra, maximum_extra}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  +maximum = Nat.add(Nat.add(authored, extra), maximum_extra)
  +lower = Space.larger(minimum, authored)
  +chosen = Space.smaller(maximum, Space.larger(lower, preferred))
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (fits => Model.accept_dimension(fits, Space.Fit{lower, Nat.sub(chosen, lower), Nat.sub(maximum, chosen)})),
    Nat.is_le(lower, maximum), False{},
    Equal.trans(Bool, Nat.is_le(lower, maximum), Nat.is_le(Nat.max(minimum, authored), maximum), False{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(n, maximum)), lower, Nat.max(minimum, authored), larger_eq_max(minimum, authored)),
      lower_conflict(minimum, authored, maximum, conflict)))

def invalid_percent(+minimum: Nat, preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.PercentSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    (valid => Model.percentage_dimension(Model.percentage_checked(valid, offered, percent), minimum)),
    Nat.is_le(percent, 100n), False{}, invalid)

def invalid_cap(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    (valid => Model.capped_dimension(Model.percentage_checked(valid, offered, percent), minimum, preferred)),
    Nat.is_le(percent, 100n), False{}, invalid)

def capped_rejected(+fits: Bool, +dimension: Space.Dimension,
  conflict: {Bool.not(fits) == True{} : Bool}) ->
  {Model.accept_dimension(fits, dimension) == None{} : Maybe<&2, Space.Dimension>}:
  match fits:
    case False{}: {==}
    case True{}: Logic.impossible(
      {Model.accept_dimension(True{}, dimension) == None{} : Maybe<&2, Space.Dimension>}, conflict)

def capped_extent_conflict(+extent: Maybe<&2, Nat>, +minimum: Nat, +preferred: Nat,
  conflict: {Rule.percentage_conflict(extent, minimum) == True{} : Bool}) ->
  {Model.capped_dimension(extent, minimum, preferred) == None{} : Maybe<&2, Space.Dimension>}:
  match extent:
    case None{}: {==}
    case Some{+cap}:
      +chosen = Space.smaller(cap, Space.larger(minimum, preferred))
      capped_rejected(Nat.is_le(minimum, cap), Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(cap, chosen)}, conflict)

def capped_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +maximum_percent: Nat,
  conflict: {Rule.percentage_conflict(Model.percentage_extent(offered, maximum_percent), minimum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  capped_extent_conflict(Model.percentage_extent(offered, maximum_percent), minimum, preferred, conflict)

def capped_stretch_accepted(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered) == Some{Rule.capped_stretch_dimension(minimum, maximum)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (valid => Model.accept_dimension(valid, Rule.capped_stretch_dimension(minimum, maximum))), Nat.is_le(minimum, maximum), True{}, fits)

def capped_stretch_rejected_checked(+fits: Bool, dimension: Space.Dimension) ->
  {Rule.rejected(Model.accept_dimension(fits, dimension)) == Bool.not(fits) : Bool}:
  match fits:
    case False{}: {==}
    case True{}: {==}

def capped_stretch_rejected(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat) ->
  {Rule.rejected(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered)) == Bool.not(Nat.is_le(minimum, maximum)) : Bool}:
  capped_stretch_rejected_checked(Nat.is_le(minimum, maximum), Rule.capped_stretch_dimension(minimum, maximum))

def capped_stretch_balance(+minimum: Nat, +maximum: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Nat.add(minimum, Nat.sub(maximum, minimum)) == maximum : Nat}:
  lower_fits = Equal.trans(Bool, Nat.is_le(Nat.add(minimum, 0n), maximum), Nat.is_le(minimum, maximum), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, maximum)), Nat.add(minimum, 0n), minimum, Alg.nat_add_zero(minimum)), fits)
  second({Nat.is_le(0n, Nat.sub(maximum, minimum)) == True{} : Bool},
    {Nat.add(minimum, Nat.sub(maximum, minimum)) == maximum : Nat}, residual(minimum, 0n, maximum, lower_fits))

# The base library defines minimum but exports no commutation or selection law.

def minimum_commutes(+left: Nat, +right: Nat) -> {Nat.min(left, right) == Nat.min(right, left) : Nat}:
  match left right:
    case 0n 0n: {==}
    case 0n 1n+b: {==}
    case 1n+a 0n: {==}
    case 1n+a 1n+b: Equal.cong(Nat, Nat, (n => 1n+n), Nat.min(a, b), Nat.min(b, a), minimum_commutes(a, b))

def minimum_attained(+maximum: Nat, +room: Nat,
  fits: {Nat.is_le(maximum, room) == True{} : Bool}) -> {Nat.min(maximum, room) == maximum : Nat}:
  match maximum room:
    case 0n _: {==}
    case 1n+a 0n: Logic.impossible({Nat.min(1n+a, 0n) == 1n+a : Nat}, fits)
    case 1n+a 1n+b: Equal.cong(Nat, Nat, (n => 1n+n), Nat.min(a, b), a, minimum_attained(a, b, fits))

def capped_stretch_width(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, room_fits: {Nat.is_le(minimum, room) == True{} : Bool}) ->
  {Rule.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>}:
  accepted = Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, (result => Rule.allocated_width(result, room)),
    Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), Some{Rule.capped_stretch_dimension(minimum, maximum)}, capped_stretch_accepted(minimum, preferred, offered, maximum, fits))
  selected = Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room), Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room), smaller_eq_min(Nat.add(minimum, Nat.sub(maximum, minimum)), room))
  bounded = Equal.cong(Nat, Maybe<&2, Nat>, (cap => Some{Nat.min(cap, room)}), Nat.add(minimum, Nat.sub(maximum, minimum)), maximum, capped_stretch_balance(minimum, maximum, fits))
  Equal.trans(Maybe<&2, Nat>, Rule.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room),
    Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(room, maximum)},
    Equal.trans(Maybe<&2, Nat>, Rule.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, accepted, selected),
    Equal.trans(Maybe<&2, Nat>, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(maximum, room)}, Some{Nat.min(room, maximum)}, bounded,
      Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(maximum, room), Nat.min(room, maximum), minimum_commutes(maximum, room))))

def capped_stretch_attained(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, +room_fits: {Nat.is_le(maximum, room) == True{} : Bool}) ->
  {Rule.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{maximum} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, Rule.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Nat.min(room, maximum)}, Some{maximum},
    capped_stretch_width(minimum, preferred, offered, maximum, room, fits, le_trans(minimum, maximum, room, fits, room_fits)),
    Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(room, maximum), maximum,
      Equal.trans(Nat, Nat.min(room, maximum), Nat.min(maximum, room), maximum, minimum_commutes(room, maximum), minimum_attained(maximum, room, room_fits))))

def adaptive_exact(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Some{Rule.adaptive_fit(minimum, preferred, offered, nominal_cap)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    valid => Model.adaptive_checked(valid, minimum, preferred, offered, nominal_cap),
    Nat.is_le(minimum, offered), True{}, fits)

def adaptive_total(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == Some{Rule.adaptive_fit(minimum, preferred, offered, Rule.nominal_percentage(offered, percent))} : Maybe<&2, Space.Dimension>}:
  Equal.trans(Maybe<&2, Space.Dimension>,
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Model.adaptive_dimension(Some{Rule.nominal_percentage(offered, percent)}, minimum, preferred, offered),
    Some{Rule.adaptive_fit(minimum, preferred, offered, Rule.nominal_percentage(offered, percent))},
    Equal.cong(Bool, Maybe<&2, Space.Dimension>,
      accepted => Model.adaptive_dimension(Model.percentage_checked(accepted, offered, percent), minimum, preferred, offered),
      Nat.is_le(percent, 100n), True{}, valid),
    adaptive_exact(minimum, preferred, offered, Rule.nominal_percentage(offered, percent), fits))

def adaptive_minimum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Rule.minimum_result(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered)) == Some{minimum} : Maybe<&2, Nat>}:
  Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, result => Rule.minimum_result(result),
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Some{Rule.adaptive_fit(minimum, preferred, offered, Rule.nominal_percentage(offered, percent))},
    adaptive_total(minimum, preferred, offered, percent, valid, fits))

# Existing packing arithmetic supplies the order and subtraction balance facts.

def smaller_floor(+minimum: Nat, +first: Nat, +second: Nat,
  first_fits: {Nat.is_le(minimum, first) == True{} : Bool}, second_fits: {Nat.is_le(minimum, second) == True{} : Bool}) ->
  {Nat.is_le(minimum, Space.smaller(first, second)) == True{} : Bool}:
  +extra = Nat.sub(first, minimum)
  Equal.trans(Bool, Nat.is_le(minimum, Space.smaller(first, second)), Nat.is_le(minimum, Nat.min(first, second)), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(minimum, size), Space.smaller(first, second), Nat.min(first, second), smaller_eq_min(first, second)),
    Equal.trans(Bool, Nat.is_le(minimum, Nat.min(first, second)), Nat.is_le(minimum, Nat.min(Nat.add(minimum, extra), second)), True{},
      Equal.cong(Nat, Bool, size => Nat.is_le(minimum, Nat.min(size, second)), first, Nat.add(minimum, extra),
        Equal.sym(Nat, Nat.add(minimum, extra), first, capped_stretch_balance(minimum, first, first_fits))),
      min_floor(minimum, extra, second, second_fits)))

def smaller_left(+first: Nat, +second: Nat) -> {Nat.is_le(Space.smaller(first, second), first) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Space.smaller(first, second), first), Nat.is_le(Nat.min(first, second), first), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(size, first), Space.smaller(first, second), Nat.min(first, second), smaller_eq_min(first, second)),
    min_le_first(first, second))

def adaptive_fit_maximum(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Rule.adaptive_ceiling(minimum, preferred, offered, nominal_cap) == Rule.adaptive_maximum(minimum, offered, nominal_cap) : Nat}:
  +maximum = Rule.adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  +maximum_floor = smaller_floor(minimum, offered, Space.larger(minimum, nominal_cap), fits, demand_max_left(minimum, nominal_cap))
  +chosen_floor = smaller_floor(minimum, maximum, Space.larger(minimum, preferred), maximum_floor, demand_max_left(minimum, preferred))
  Equal.trans(Nat, Rule.adaptive_ceiling(minimum, preferred, offered, nominal_cap),
    Nat.add(chosen, Nat.sub(maximum, chosen)), maximum,
    Equal.cong(Nat, Nat, size => Nat.add(size, Nat.sub(maximum, chosen)),
      Nat.add(minimum, Nat.sub(chosen, minimum)), chosen, capped_stretch_balance(minimum, chosen, chosen_floor)),
    capped_stretch_balance(chosen, maximum, smaller_left(maximum, Space.larger(minimum, preferred))))

def adaptive_fit_bound(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Nat.is_le(Rule.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Rule.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered),
    Nat.is_le(Rule.adaptive_maximum(minimum, offered, nominal_cap), offered), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(size, offered),
      Rule.adaptive_ceiling(minimum, preferred, offered, nominal_cap), Rule.adaptive_maximum(minimum, offered, nominal_cap),
      adaptive_fit_maximum(minimum, preferred, offered, nominal_cap, fits)),
    smaller_left(offered, Space.larger(minimum, nominal_cap)))

def adaptive_maximum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Rule.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered) == True{} : Bool}:
  Equal.trans(Bool,
    Rule.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered),
    Nat.is_le(Rule.adaptive_ceiling(minimum, preferred, offered, Rule.nominal_percentage(offered, percent)), offered), True{},
    Equal.cong(Maybe<&2, Space.Dimension>, Bool, result => Rule.maximum_fits(result, offered),
      Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
      Some{Rule.adaptive_fit(minimum, preferred, offered, Rule.nominal_percentage(offered, percent))},
      adaptive_total(minimum, preferred, offered, percent, valid, fits)),
    adaptive_fit_bound(minimum, preferred, offered, Rule.nominal_percentage(offered, percent), fits))

def maximum_attained(+minimum: Nat, +maximum: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) -> {Space.larger(minimum, maximum) == maximum : Nat}:
  match minimum maximum:
    case 0n 0n: {==}
    case 0n 1n+b: {==}
    case 1n+a 0n: Logic.impossible({Space.larger(1n+a, 0n) == 0n : Nat}, fits)
    case 1n+a 1n+b:
      Equal.trans(Nat, Space.larger(1n+a, 1n+b), 1n+Space.larger(a, b), 1n+b,
        choose_extent_successor(Nat.is_ge(a, b), a, b),
        Equal.cong(Nat, Nat, value => 1n+value, Space.larger(a, b), b, maximum_attained(a, b, fits)))

def smaller_attained(+maximum: Nat, +cap: Nat,
  +fits: {Nat.is_le(cap, maximum) == True{} : Bool}) -> {Space.smaller(maximum, cap) == cap : Nat}:
  Equal.trans(Nat, Space.smaller(maximum, cap), Nat.min(maximum, cap), cap,
    smaller_eq_min(maximum, cap),
    Equal.trans(Nat, Nat.min(maximum, cap), Nat.min(cap, maximum), cap,
      minimum_commutes(maximum, cap), minimum_attained(cap, maximum, fits)))

def adaptive_normal(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +content_fits: {Nat.is_le(minimum, nominal_cap) == True{} : Bool}, +cap_fits: {Nat.is_le(nominal_cap, offered) == True{} : Bool}) ->
  {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Model.capped_dimension(Some{nominal_cap}, minimum, preferred) : Maybe<&2, Space.Dimension>}:
  +effective = Rule.adaptive_maximum(minimum, offered, nominal_cap)
  +effective_same = Equal.trans(Nat, effective, Space.smaller(offered, nominal_cap), nominal_cap,
    Equal.cong(Nat, Nat, size => Space.smaller(offered, size), Space.larger(minimum, nominal_cap), nominal_cap, maximum_attained(minimum, nominal_cap, content_fits)),
    smaller_attained(offered, nominal_cap, cap_fits))
  +chosen = Space.smaller(nominal_cap, Space.larger(minimum, preferred))
  Equal.trans(Maybe<&2, Space.Dimension>,
    Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered),
    Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
    Model.capped_dimension(Some{nominal_cap}, minimum, preferred),
    Equal.trans(Maybe<&2, Space.Dimension>,
      Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered),
      Some{Rule.adaptive_fit(minimum, preferred, offered, nominal_cap)},
      Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
      adaptive_exact(minimum, preferred, offered, nominal_cap, le_trans(minimum, nominal_cap, offered, content_fits, cap_fits)),
      Equal.cong(Nat, Maybe<&2, Space.Dimension>, maximum => Some{Space.Fit{minimum, Nat.sub(Space.smaller(maximum, Space.larger(minimum, preferred)), minimum), Nat.sub(maximum, Space.smaller(maximum, Space.larger(minimum, preferred)))}},
        effective, nominal_cap, effective_same)),
    Equal.sym(Maybe<&2, Space.Dimension>, Model.capped_dimension(Some{nominal_cap}, minimum, preferred), Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
      Equal.cong(Bool, Maybe<&2, Space.Dimension>, accepted => Model.accept_dimension(accepted, Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}),
        Nat.is_le(minimum, nominal_cap), True{}, content_fits)))

def adaptive_invalid(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    valid => Model.adaptive_dimension(Model.percentage_checked(valid, offered, percent), minimum, preferred, offered),
    Nat.is_le(percent, 100n), False{}, invalid)

def adaptive_conflict_extent(+extent: Maybe<&2, Nat>, +minimum: Nat, +preferred: Nat, +offered: Nat,
  conflict: {Nat.is_le(minimum, offered) == False{} : Bool}) ->
  {Model.adaptive_dimension(extent, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  match extent:
    case None{}: {==}
    case Some{cap}:
      Equal.cong(Bool, Maybe<&2, Space.Dimension>, valid => Model.adaptive_checked(valid, minimum, preferred, offered, cap),
        Nat.is_le(minimum, offered), False{}, conflict)

def adaptive_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  conflict: {Nat.is_le(minimum, offered) == False{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  adaptive_conflict_extent(Model.percentage_extent(offered, percent), minimum, preferred, offered, conflict)

def Rule.physical_space_evidence(A, E):
  Rule.PhysicalSpaceRequirements{
    axis_authored_floor,
    (content => rule => interaction => outer_authored_floor(~E, content, rule, interaction)),
    axis_intrinsic_floor, axis_preferred_floor, authored_preferred, authored_floor,
    (content => rule => interaction => outer_preferred(~E, content, rule, interaction)),
    (content => rule => interaction => outer_intrinsic_floor(~E, content, rule, interaction)),
    (minimum => preferred => extent => {==}),
    (minimum => preferred => authored => extra => maximum => max_right(minimum, authored)),

    (+minimum => +preferred => +offered => +cap => fits => adaptive_exact(minimum, preferred, offered, cap, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_total(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_minimum(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_maximum(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +cap => content_fits => cap_fits => adaptive_normal(minimum, preferred, offered, cap, content_fits, cap_fits)),
    (+minimum => +preferred => +offered => +percent => invalid => adaptive_invalid(minimum, preferred, offered, percent, invalid)),
    (+minimum => +preferred => +offered => +percent => conflict => adaptive_conflict(minimum, preferred, offered, percent, conflict)),
    capped_stretch_accepted, capped_stretch_rejected, capped_stretch_width, capped_stretch_attained,
    (tree => preferred_content(~A, ~E, tree <> Nil{}, Model.Horizontal{}, 0n)),
    (trees => direction => gap => children_content(~A, ~E, trees, direction, gap)),
    (content => rule => first => remaining => enabled => operable(~E, content, rule, first, remaining, enabled)),
    (minimum => preferred => offered => authored => extra => maximum_extra => conflict => limited_conflict(minimum, preferred, offered, authored, extra, maximum_extra, conflict)),
    (minimum => preferred => offered => extent => conflict => exact_conflict(minimum, preferred, offered, extent, conflict)),
    (minimum => preferred => offered => percent => invalid => invalid_percent(minimum, preferred, offered, percent, invalid)),
    (minimum => preferred => offered => percent => invalid => invalid_cap(minimum, preferred, offered, percent, invalid)),
    (minimum => preferred => offered => maximum_percent => conflict => capped_conflict(minimum, preferred, offered, maximum_percent, conflict))}

def Rule.aligned_clearance_contains(outside, horizontal, vertical, extent):
  clearance_layered_contains(outside, extent)
