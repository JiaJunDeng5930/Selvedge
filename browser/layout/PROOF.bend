import Base
import ./anchor-geometry-rules.bend as Rule
import ./GEOMETRY.bend as SpatialModel
import ./SPACE.bend as Space
import ../appearance/TYPOGRAPHY.bend as T
import ./enclosure.bend as E
import ../appearance/MODEL.bend as A
import ../controls/PROGRAM.bend as C
import ../appearance/DESIGN.bend as D
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ./enclosure-laws.bend as RuleEnclosureLaws
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ./frame-relation-laws.bend as RuleFrameRelationLaws
import ./natural-size.bend as Size
import ./natural-size-rules.bend as RuleNaturalSizeRules
import ./physical-content-rules.bend as RulePhysicalContentRules
import ../document/MODEL.bend as Doc
import ../document/SOURCE.bend as Source
import ./physical-space.bend as Model
import ./physical-control-rules.bend as RulePhysicalControlRules
import ./MODEL.bend as World
import ./physical-receipt-laws.bend as RulePhysicalReceiptLaws
import ./CONTENT.bend as Content
import ../runtime/MODEL.bend as Browser
import ../runtime/SEMANTICS.bend as Legacy
import ../focus/MODEL.bend as Focus
import ../runtime/native-fields.bend as Native
import ./physical-renderer-rules.bend as RulePhysicalRendererRules
import ./RENDERER.bend as Renderer
import ./PROGRAM.bend as Allocation
import ../appearance/paint-rules.bend as PaintRule
import ../../bendlib/stdlib.bend as Std
import ./SOURCE.bend as SourceSource
import ./physical-source-rules.bend as RulePhysicalSourceRules
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/algebra-proof.bend as Alg
import ./space-laws.bend as RuleSpaceLaws
import ./container-space-laws.bend as RuleContainerSpaceLaws
import ./physical-packing-rules.bend as RulePhysicalPackingRules
import ./physical-space-rules.bend as ModelRules
import ./text-space-rules.bend as RuleTextSpaceRules
import ./physical-allocation-population-rules.bend as RulePhysicalAllocationPopulationRules
import ./physical-height-rules.bend as RulePhysicalHeightRules
import ./physical-width-rules.bend as RulePhysicalWidthRules
import ./CONTRACT.bend as RuleContract

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
  {RuleEnclosureLaws.area(A.action_style_insets(value, geometry, space, gap, content_height)) == space : E.ContentArea}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def layout_copied(+value: D.Style, +layout: C.ContentLayout, +geometry: C.Geometry, content_height: Nat) ->
  {RuleEnclosureLaws.area(A.action_content_style(value, layout, geometry, content_height)) == C.layout_content_area(layout) : E.ContentArea}:
  C.ContentLayout{alignment, space, gap} = layout
  action_insets(value, geometry, space, gap, content_height)

def flow_preserves_area(+value: D.Style, flow: SpatialModel.Flow) ->
  {RuleEnclosureLaws.area(A.with_flow(value, flow)) == RuleEnclosureLaws.area(value) : E.ContentArea}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def minimum_extent(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat, +content_height: Nat) ->
  {D.style_minimum_height(A.action_style_insets(value, geometry, space, gap, content_height)) == Nat.max(C.geometry_minimum_height(geometry), E.extent_height(E.required_extent(0n, content_height, A.chrome_border_width(RuleEnclosureLaws.chrome(value)), space))) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def canvas(+meaning: InterfaceView.Meaning, +typography: T.Presentation) ->
  {RuleEnclosureLaws.area(A.style(InterfaceView.Main{}, meaning, typography)) == E.ambient(0n, 0n) : E.ContentArea}:
  {==}

def state_allocation(+value: D.Style, +space: E.ContentArea) ->
  {RuleEnclosureLaws.interaction(A.with_content_area(value, space)) == RuleEnclosureLaws.interaction(value) : D.ControlStates}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.Frame{old_area, old_arrangement} = content_frame
  {==}

def page_content() -> RuleEnclosureLaws.page_content(): {==}

def RuleEnclosureLaws.evidence():
  RuleEnclosureLaws.Requirements{page_content(), positive, +width => +height => +border => +space => {==}, +width => +height => +profile => {==}, action_insets, layout_copied, +value => +face => +geometry =>
      Equal.trans(E.ContentArea, RuleEnclosureLaws.area(A.action_style(value, face, geometry)),
        RuleEnclosureLaws.area(A.action_content_style(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry))), C.layout_content_area(C.content_layout(face)),
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

def actual_choice_geometry(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {RuleFrameRelationLaws.actual_geometry(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_layout(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_mark_contains_icon(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {Nat.is_le(RuleFrameRelationLaws.mark_icon_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context))), RuleFrameRelationLaws.mark_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def selection_keeps_allocation(+key: Identity.Key, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def flow_assigned(+value: D.Style, +flow: SpatialModel.Flow) ->
  {RuleFrameRelationLaws.style_flow(A.with_flow(value, flow)) == flow : SpatialModel.Flow}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def choice_style_normalization(+value: D.Style, +size: C.Geometry, label: String, description: Maybe<&2, String>, selected: Bool) ->
  {RuleFrameRelationLaws.choice_style_metrics(A.action_style(value, C.ChoiceFace{label, description, None{}, selected}, size)) == (8n, SpatialModel.ChoiceFlow{}) : (Nat & SpatialModel.Flow)}:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} = size
  {==}

def actual_choice_normalization(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String,
  +role: InterfaceView.Role, +context: C.Context, +fallback: D.Style, +typography: T.Presentation) -> RuleFrameRelationLaws.actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography):
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

def RuleFrameRelationLaws.evidence():
  RuleFrameRelationLaws.Requirements{
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

def RuleNaturalSizeRules.evidence():
  RuleNaturalSizeRules.Requirements{
    (capacity => left => right => conflict => addition_capacity(capacity, left, right, conflict)),
    (capacity => left => right => nonzero => conflict => multiplication_capacity(capacity, left, right, nonzero, conflict)),
    (capacity => left => multiplication_zero(capacity, left))}

def RulePhysicalContentRules.rich_local_value_preserves_focus_owner(key, style, content, attachments, native_owner, font): {==}

def attributes_consume_control_states(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String,
  interaction: Model.Interaction<Doc.DOMEvent>) -> RulePhysicalControlRules.attributes_claim(tag, attrs, name, interaction):
  {==}

def rendered_controls_consume_control_states(key: Identity.Key, tag: Source.ControlTag, style: Source.Style,
  attrs: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.DOMEvent,
  remaining: +List<Doc.DOMEvent>, original_children: +List<Source.Node>, font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool) ->
  RulePhysicalControlRules.render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native):
  {==}

def background_uses_rest_channel(chrome: D.Chrome) -> RulePhysicalControlRules.background_channel_claim(chrome):
  D.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def foreground_uses_rest_channel(chrome: D.Chrome) -> RulePhysicalControlRules.foreground_channel_claim(chrome):
  D.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def RulePhysicalControlRules.evidence():
  RulePhysicalControlRules.Requirements{background_uses_rest_channel, foreground_uses_rest_channel, attributes_consume_control_states, rendered_controls_consume_control_states}

def RulePhysicalControlRules.keyboard_activation_total(event):
  match event:
    case Doc.Activate{key}: {==}
    case Doc.EditText{key}: {==}
    case Doc.ConfirmText{key}: {==}
    case Doc.EditToggle{key}: {==}
    case Doc.SelectFiles{key}: {==}
    case Doc.DragCard{key}: {==}
    case Doc.DropCard{key}: {==}
    case Doc.PlaceCard{key, target}: {==}
    case Doc.SelectDestination{key}: {==}

def RulePhysicalControlRules.keyboard_activation_empty(): {==}
def RulePhysicalControlRules.keyboard_activation_cons(first,remaining): {==}
def RulePhysicalControlRules.keyboard_control_display_only(): {==}
def RulePhysicalControlRules.keyboard_control_operable(first,remaining,enabled): {==}

def RulePhysicalControlRules.keyboard_attribute_projection(active,interaction,name):
  match active:
    case True{}: {==}
    case False{}: {==}

def RulePhysicalControlRules.nonnative_attribute_projection(attrs,name,interaction): {==}

def RulePhysicalControlRules.control_attribute_projection(tag,attrs,name,interaction):
  match tag:
    case Source.Button{}: {==}
    case Source.Summary{}: {==}
    case Source.ArticleControl{}: {==}
    case Source.DivControl{}: {==}
    case Source.SectionControl{}: {==}
    case Source.SpanControl{}: {==}

def RulePhysicalControlRules.source_control_interaction(key,tag,style,attrs,name,enabled,first,remaining,children): {==}
def RulePhysicalControlRules.rendered_control_projection(capacity,key,tag,style,attrs,name,enabled,first,remaining,original_children,font,interaction,styles,children,native): {==}

def RulePhysicalControlRules.native_field_probe_appearance(kind): {==}

def RulePhysicalControlRules.native_field_rendered_appearance(kind, rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def RulePhysicalControlRules.toggle_field_probe_appearance(): {==}

def RulePhysicalControlRules.toggle_field_rendered_appearance(rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def RulePhysicalControlRules.other_native_field_appearance(minimum, multiple): {==}

def RulePhysicalControlRules.toggle_geometry_bounded(): {==}
def RulePhysicalControlRules.toggle_geometry_centered(): {==}
def RulePhysicalControlRules.toggle_probe_rectangle(): {==}
def RulePhysicalControlRules.toggle_target_rectangle(): {==}
def RulePhysicalControlRules.toggle_visual_rectangle(style):
  Source.Style{layout, font, D.Chrome{foreground, background, border, width, radius, shadow}, states} = style
  {==}
def RulePhysicalControlRules.production_toggle_face(key, meaning, name, placement, availability, typography, parameters):
  match placement:
    case C.AccessibleOnly{}: {==}
    case C.AboveInput{}: {==}
    case C.BesideInput{}: {==}
def RulePhysicalControlRules.unchecked_toggle_glyph(key): {==}
def RulePhysicalControlRules.toggle_authoring_allocation(key, meaning, name, placement, availability, visual, parameters):
  match placement visual:
    case C.AccessibleOnly{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case C.AboveInput{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case C.BesideInput{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
def RulePhysicalControlRules.beside_label_activation(key, name, visual, field):
  D.Style{text, D.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def RulePhysicalControlRules.toggle_rendered_composition(key, style, attrs, attributes, styles, events, children): {==}


def RulePhysicalControlRules.measurement_probe_targets(request, roots): {==}

def RulePhysicalControlRules.native_target_probe_targets(request, roots): {==}

def publication(+world: Content.AllocatedWorld, capacity: View.Capacity, +legacy: Legacy.State, +semantic: InterfaceView.Surface) ->
  {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([RulePhysicalReceiptLaws.world_source(world)], semantic), None{}} : Browser.Published}:
  match world:
    case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def state_authored_evidence(+model_state: Browser.State, +source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: SpatialModel.Box, +semantic: InterfaceView.Surface) ->
  RulePhysicalReceiptLaws.authored_claim(model_state, source, index, capacity, font, viewport, semantic):
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def state_measured_evidence(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +tokens: +List<String>, +semantic: InterfaceView.Surface, +round: Nat) ->
  RulePhysicalReceiptLaws.measurement_claim(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), index, capacity, engine, tokens, semantic, round):
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def state_remeasure_evidence(+model_state: Browser.State, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +semantic: InterfaceView.Surface, +round: Nat) ->
  {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.refreeze(index, capacity, engine, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), semantic) : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def RulePhysicalReceiptLaws.evidence():
  RulePhysicalReceiptLaws.Requirements{
    +world => capacity => +legacy => +semantic => publication(world, capacity, legacy, semantic),
    state_authored_evidence,
    generation => first => remaining => index => capacity => engine => state => semantic => round => {==},
    state_measured_evidence,
    state_remeasure_evidence,
    world => index => capacity => engine => state => semantic => round => {==}}

def rich_parent(+capacity: Nat, +font: T.Presentation, policy: Source.RichPolicy) ->
  {RulePhysicalRendererRules.text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))}:
  match policy:
    case Source.RichPolicy{Source.CodeSurface{frame, surface}, toolbar, gap, indent, code, wrap}: {==}

def admitted_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, valid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), True{}, valid)

def rejected_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, invalid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), False{}, invalid)

def reading_box(+capacity: Nat, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool,
  recognized: {Renderer.reading_content(attrs) == content : Bool}) ->
  RulePhysicalRendererRules.reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content):
  Equal.cong(Bool, +List<Doc.Property>,
    (is_content => Renderer.reading_styles(is_content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style))))),
    Renderer.reading_content(attrs), content, recognized)

def observation_appended(attrs: +List<Doc.Property>, +key: String) ->
  {RulePhysicalRendererRules.last_attribute(Renderer.properties(attrs, [Doc.Property{"data-frame-key", key}])) == Some{Doc.Property{"data-frame-key", key}} : Maybe<&2, Doc.Property>}:
  match attrs:
    case Nil{}: {==}
    case Con{first, rest}:
      match rest:
        case Nil{}: {==}
        case Con{next, tail}: observation_appended(Con{next, tail}, key)

def field_observation(+kind: Source.NativeFieldKind, +key: Identity.Key, +style: Source.Style,
  +attrs: +List<Source.Attribute>, attributes: +List<Doc.Property>, +styles: +List<Doc.Property>, events: +List<Doc.DOMEvent>, children: +List<Doc.Node>, +identity: String) ->
  {RulePhysicalRendererRules.field_observation(kind, Renderer.observed_field(kind, identity, Renderer.native_field_leaf(kind, key, style, attrs, attributes, styles, events, children))) == Some{Doc.Property{"data-frame-key", identity}} : Maybe<&2, Doc.Property>}:
  match kind:
    case Source.TextField{}: observation_appended(attributes, identity)
    case Source.MessageField{}: observation_appended(attributes, identity)
    case Source.TextAreaField{}: observation_appended(attributes, identity)
    case Source.SelectField{}: observation_appended(attributes, identity)
    case Source.MultiSelectField{}: observation_appended(attributes, identity)
    case Source.NumberField{minimum}: observation_appended(attributes, identity)
    case Source.FileField{multiple}: observation_appended(attributes, identity)
    case Source.DirectoryField{}: observation_appended(attributes, identity)
    case Source.SearchField{}: observation_appended(attributes, identity)
    case Source.SecretField{}: observation_appended(attributes, identity)
    case Source.ToggleField{}: observation_appended(attributes, identity)

def leaf_observation(+capacity: Nat, +value: Content.Value, physical_key: String, bounds: SpatialModel.Box,
  canvas: E.Extent, +rule: Model.Rule, +interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) ->
  RulePhysicalRendererRules.leaf_observation_claim(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned):
  match value:
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: observation_appended(Renderer.text_attributes(wrap, text), Renderer.observation_key(value))
    case Content.Value{Source.Glyph{key, picture, style}, font}: {==}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}:
      match content:
        case Source.RichContent{source, text, policy}: {==}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}:
      field_observation(kind, key, style, attrs,
        Renderer.properties(Renderer.field_authored(kind, attrs), Renderer.properties(Renderer.field_attributes(kind, text),
          Renderer.properties([Doc.Property{"class", "native-control"}, Doc.Property{"placeholder", placeholder}, Doc.Property{"aria-label", name}], Renderer.availability(interaction, True{})))),
        Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), Renderer.properties(Renderer.visual(style), Renderer.field_padding(kind, rule)))),
        Renderer.event_list(interaction), Renderer.choices(options, key), Renderer.observation_key(value))
    case Content.Value{Source.Box{key, tag, style, attrs, children}, font}: {==}
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, font}: {==}
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, children}, font}: {==}

def container_observation(+capacity: Nat, +value: Content.Value, interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, +native: Bool) ->
  RulePhysicalRendererRules.container_observation_claim(capacity, value, interaction, styles, children, native):
  match value:
    case Content.Value{Source.Box{key, tag, style, attrs, original}, font}: observation_appended(Renderer.attributes(attrs), Renderer.observation_key(value))
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, original}, font}: observation_appended(Renderer.control_attributes(tag, attrs, name, interaction), Renderer.observation_key(value))
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, original}, font}:
      match native:
        case True{}: {==}
        case False{}: {==}
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: {==}
    case Content.Value{Source.Glyph{key, picture, style}, font}: {==}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}: {==}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: {==}

def RulePhysicalRendererRules.evidence():
  RulePhysicalRendererRules.Requirements{key => dom_key => tag => attrs => styles => events => children => {==}, identity => dom_key => attrs => styles => events => input_key => input_attrs => input_styles => input_events => input_children => rest => {==}, owner => target => key => identity => native_target => attrs => style => original => font => interaction => rule => bounds => canvas => direction => children => {==}, leaf_observation, container_observation, reading_box, styles => {==}, styles => {==}, rich_parent, generation => key => tag => style => children => font => theme => {==}, admitted_world, rejected_world}

def field_native_footprint(+kind: Source.NativeFieldKind, +node: Source.Node, +key: String,
  +style: Source.ResolvedStyle, +generation: Nat, +observations: +List<Content.Observation>) ->
  RulePhysicalSourceRules.field_native_footprint(kind, node, key, style, generation, observations): {==}

def admitted(+duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared,
  proof: {Content.duplicate_native_slot(Content.native_slots(prepared)) == duplicate : Maybe<&2, Content.NativeSlot>}) ->
  {RulePhysicalContentRules.ready_native_targets_valid(SourceSource.admit_duplicate(duplicate, prepared)) == True{} : Bool}:
  match duplicate:
    case None{}:
      Std.transport(Maybe<&2, Content.NativeSlot>, None{},
        (result => {RulePhysicalContentRules.no_duplicate(result) == True{} : Bool}), {==},
        Content.duplicate_native_slot(Content.native_slots(prepared)), proof)
    case Some{Content.NativeSlot{owner_key, target_key}}:
      match prepared:
        case Content.Prepared{snapshot, tree, roots, policies}: {==}

def admission(+prepared: Content.Prepared) ->
  {RulePhysicalContentRules.ready_native_targets_valid(SourceSource.admit_native_targets(prepared)) == True{} : Bool}:
  admitted(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared, {==})

def single_root(trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, +snapshot: Content.Snapshot,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {RulePhysicalContentRules.ready_native_targets_valid(SourceSource.single_root(trees, snapshot, roots, policies)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{tree, Nil{}}: admission(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: {==}

def preparation(result: SourceSource.Forest, +snapshot: Content.Snapshot) ->
  {RulePhysicalContentRules.ready_native_targets_valid(SourceSource.preparation(result, snapshot)) == True{} : Bool}:
  match result:
    case SourceSource.ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case SourceSource.MissingForest{first, remaining}: {==}
    case SourceSource.InvalidForest{error}: {==}

def native_targets(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) ->
  RulePhysicalSourceRules.native_targets_claim(snapshot, observations):
  match snapshot:
    case Content.Snapshot{generation, source, default_font}:
      preparation(SourceSource.prepare_forest(source <> Nil{}, default_font, generation, "", 0n, SourceSource.Ordinary{}, observations), snapshot)

def field_width_formula(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(RulePhysicalSourceRules.column_floor(policy, observation), RulePhysicalSourceRules.observed_minimum(observation)) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_column_floor(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.column_floor(policy, observation)) == True{} : Bool}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_l(Nat.mul(columns, advance), minimum)

def field_observed_minimum(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.observed_minimum(observation)) == True{} : Bool}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_r(Nat.mul(columns, advance), minimum)

def field_preferred_width(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.preferred_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.observed_preferred(observation)) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_minimum_height_fields(+capacity: Nat, +kind: Source.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {RulePhysicalSourceRules.minimum_height(SourceSource.field_natural_demand_at(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == RulePhysicalSourceRules.expected_height(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def field_minimum_height(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.minimum_height(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == RulePhysicalSourceRules.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_minimum_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_preferred_height_fields(+capacity: Nat, +kind: Source.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {RulePhysicalSourceRules.preferred_height(SourceSource.field_natural_demand_at(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == RulePhysicalSourceRules.expected_height(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def field_preferred_height(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.preferred_height(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == RulePhysicalSourceRules.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_preferred_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_production_demand(+capacity: Nat, +label: Identity.Key, +kind: Source.NativeFieldKind, +style: Source.Style,
  +attributes: +List<Source.Attribute>, +value: String, +placeholder: String, +options: +List<Source.Choice>,
  +policy: Source.FieldPolicy, +name: String, +enabled: Bool, +first_event: Doc.DOMEvent,
  +remaining_events: +List<Doc.DOMEvent>, +key: String, +font: T.Presentation, +rule: Model.Rule,
  +observation: Content.Observation, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {RulePhysicalSourceRules.first_leaf_demand(SourceSource.observed_leaf_at(capacity, Source.Field{label, kind, style, attributes, value, placeholder,
    options, policy, name, enabled, first_event, remaining_events}, key, font, rule, observation, roots, policies)) ==
    Some{SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)} : Maybe<&2, Space.Demand>}:
  match policy:
    case Source.FieldPolicy{columns, minimum_lines, maximum_lines}: {==}

def RulePhysicalSourceRules.evidence():
  RulePhysicalSourceRules.Requirements{field_native_footprint, +snapshot => +observations => native_targets(snapshot, observations),
    field_width_formula, field_column_floor, field_observed_minimum, field_preferred_width,
    field_minimum_height, field_preferred_height, field_production_demand}

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
  {RuleSpaceLaws.maximum_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
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
  {RuleSpaceLaws.rigid_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
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
  valid: {RuleSpaceLaws.limits(~A, slots, placements) == True{} : Bool}) ->
  {Space.following_gap(~A, slots, gap) == RuleSpaceLaws.placement_gap(~A, placements, gap) : Nat}:
  match slots placements:
    case Nil{} Nil{}: {==}
    case Con{head, tail} Con{other, rest}: {==}
    case Nil{} Con{head, tail}: Logic.impossible({0n == gap : Nat}, valid)
    case Con{Space.Slot{value, dimension}, tail} Nil{}: Logic.impossible({gap == 0n : Nat}, valid)

def used_split(~A: Data, +value: A, +offset: Nat, +size: Nat, +rest: +List<Space.Placement<A>>, +gap: Nat) ->
  {RuleSpaceLaws.used(~A, Space.Placement{value, offset, size} <> rest, gap) ==
    Nat.add(size, Nat.add(RuleSpaceLaws.placement_gap(~A, rest, gap), RuleSpaceLaws.used(~A, rest, gap))) : Nat}:
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
  upper: {RuleSpaceLaws.maximum_ok(dimension, size) == True{} : Bool},
  rigid: {RuleSpaceLaws.rigid_ok(dimension, size) == True{} : Bool},
  head_balance: {Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)) == budget : Nat},
  tail: RuleSpaceLaws.AllocationEvidence<A, slots, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap))), next_budget, result>) ->
  RuleSpaceLaws.AllocationEvidence<A, Space.Slot{value, dimension} <> slots, gap, offset, budget,
    Space.prepend(~A, Space.Placement{value, offset, size}, result)>:
  Space.Allocation{+placements, +unused} = result
  RuleSpaceLaws.AllocationEvidence{payloads, +bounds, order, balance} = tail
  +same_gap = gap_agrees(~A, slots, placements, gap, bounds)
  next_order = Equal.trans(Bool,
    RuleSpaceLaws.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, RuleSpaceLaws.placement_gap(~A, placements, gap)))),
    RuleSpaceLaws.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap)))), True{},
    Equal.cong(Nat, Bool, (n => RuleSpaceLaws.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, n)))),
      RuleSpaceLaws.placement_gap(~A, placements, gap), Space.following_gap(~A, slots, gap),
      Equal.sym(Nat, Space.following_gap(~A, slots, gap), RuleSpaceLaws.placement_gap(~A, placements, gap), same_gap)), order)
  concrete_head_balance = Equal.trans(Nat,
    Nat.add(size, Nat.add(RuleSpaceLaws.placement_gap(~A, placements, gap), next_budget)),
    Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)), budget,
    Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(n, next_budget))), RuleSpaceLaws.placement_gap(~A, placements, gap),
      Space.following_gap(~A, slots, gap), Equal.sym(Nat, Space.following_gap(~A, slots, gap), RuleSpaceLaws.placement_gap(~A, placements, gap), same_gap)), head_balance)
  RuleSpaceLaws.AllocationEvidence{
    Equal.cong(+List<A>, +List<A>, (items => value <> items), RuleSpaceLaws.placement_values(~A, placements), RuleSpaceLaws.slot_values(~A, slots), payloads),
    conjunction(Nat.is_le(Space.minimum(dimension), size), RuleSpaceLaws.maximum_ok(dimension, size) && (RuleSpaceLaws.rigid_ok(dimension, size) && RuleSpaceLaws.limits(~A, slots, placements)), lower,
      conjunction(RuleSpaceLaws.maximum_ok(dimension, size), RuleSpaceLaws.rigid_ok(dimension, size) && RuleSpaceLaws.limits(~A, slots, placements), upper,
        conjunction(RuleSpaceLaws.rigid_ok(dimension, size), RuleSpaceLaws.limits(~A, slots, placements), rigid, bounds))),
    conjunction(Nat.is_eq(offset, offset), RuleSpaceLaws.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, RuleSpaceLaws.placement_gap(~A, placements, gap)))), eq_refl(offset), next_order),
    Equal.trans(Nat, Nat.add(RuleSpaceLaws.used(~A, Space.Placement{value, offset, size} <> placements, gap), unused),
      Nat.add(Nat.add(size, Nat.add(RuleSpaceLaws.placement_gap(~A, placements, gap), RuleSpaceLaws.used(~A, placements, gap))), unused), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(n, unused)), RuleSpaceLaws.used(~A, Space.Placement{value, offset, size} <> placements, gap),
        Nat.add(size, Nat.add(RuleSpaceLaws.placement_gap(~A, placements, gap), RuleSpaceLaws.used(~A, placements, gap))), used_split(~A, value, offset, size, placements, gap)),
      combined_balance(size, RuleSpaceLaws.placement_gap(~A, placements, gap), RuleSpaceLaws.used(~A, placements, gap), unused, next_budget, budget, balance, concrete_head_balance))}

# The induction reserves the entire remaining sequence before choosing a size.
def place_evidence(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat,
  fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), budget) == True{} : Bool}) ->
  RuleSpaceLaws.AllocationEvidence<A, slots, gap, offset, budget, Space.place_from(~A, slots, gap, offset, budget)>:
  match slots:
    case Nil{}: RuleSpaceLaws.AllocationEvidence{{==}, {==}, {==}, {==}}
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
  {RuleSpaceLaws.maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(Nat.add(lower, extra), maximum_extra)
    case Space.Fill{lower}: {==}

def space_proof_finish_claim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  evidence: RuleSpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  RuleSpaceLaws.PackedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  evidence

def pack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  RuleSpaceLaws.PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available)):
  Std.transport(Bool, True{}, (feasible => RuleSpaceLaws.PackedClaim(~A, slots, gap, available, Space.feasible_pack(~A, feasible, slots, gap, available))),
    space_proof_finish_claim(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available), place_evidence(~A, slots, gap, 0n, available, fits)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), fits)

def pack_insufficient(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  does_not_fit: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool}) ->
  {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>}:
  Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), False{}, does_not_fit)

def finish_packed(~A: Data, result: Space.Allocation<A>) -> {RuleSpaceLaws.packed(~A, Space.finish(~A, result)) == True{} : Bool}:
  Space.Allocation{placements, unused} = result
  {==}

def feasible_tag(~A: Data, +feasible: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {RuleSpaceLaws.packed(~A, Space.feasible_pack(~A, feasible, slots, gap, available)) == feasible : Bool}:
  match feasible:
    case False{}: {==}
    case True{}: finish_packed(~A, Space.place_from(~A, slots, gap, 0n, available))

def RuleSpaceLaws.evidence(A):
  RuleSpaceLaws.Requirements{larger_eq_max, smaller_eq_min, dimension_minimum, dimension_maximum,
    +slots => +gap => +available => feasible_tag(~A, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), slots, gap, available),
    +slots => +gap => +available => does_not_fit => pack_insufficient(~A, slots, gap, available, does_not_fit),
    +slots => +gap => +available => +fits => pack_complete(~A, slots, gap, available, fits)}

# Both subtractions are justified by the full minimum, including both insets.
def inset_budget_from(+leading: Nat, +trailing: Nat, +minimum: Nat, +available: Nat,
  evidence: {Nat.is_le(Nat.add(minimum, trailing), Nat.sub(available, leading)) == True{} : Bool} &
    {Nat.add(leading, Nat.sub(available, leading)) == available : Nat}) ->
  {Nat.is_le(minimum, RuleContainerSpaceLaws.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(RuleContainerSpaceLaws.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  (+remaining_fits, leading_balance) = evidence
  +remaining = Nat.sub(available, leading)
  +inner = RuleContainerSpaceLaws.inner_budget(leading, trailing, available)
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
  {Nat.is_le(minimum, RuleContainerSpaceLaws.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(RuleContainerSpaceLaws.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  inset_budget_from(leading, trailing, minimum, available,
    residual(leading, Nat.add(minimum, trailing), available, fits))

def container_space_proof_finish_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  +result: Space.Allocation<A>,
  evidence: RuleSpaceLaws.AllocationEvidence<A, slots, gap, leading, RuleContainerSpaceLaws.inner_budget(leading, trailing, available), result>,
  balance: {Nat.add(leading, Nat.add(RuleContainerSpaceLaws.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  RuleContainerSpaceLaws.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available, Space.finish(~A, result)):
  Space.Allocation{+placements, +unused} = result
  RuleSpaceLaws.AllocationEvidence{payloads, bounds, positions, +total} = evidence
  (RuleSpaceLaws.AllocationEvidence{payloads, bounds, positions, total},
    Equal.trans(Nat, Nat.add(leading, Nat.add(Nat.add(RuleSpaceLaws.used(~A, placements, gap), unused), trailing)),
      Nat.add(leading, Nat.add(RuleContainerSpaceLaws.inner_budget(leading, trailing, available), trailing)), available,
      Equal.cong(Nat, Nat, (n => Nat.add(leading, Nat.add(n, trailing))),
        Nat.add(RuleSpaceLaws.used(~A, placements, gap), unused), RuleContainerSpaceLaws.inner_budget(leading, trailing, available), total), balance))

def accepted_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  evidence: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), RuleContainerSpaceLaws.inner_budget(leading, trailing, available)) == True{} : Bool} &
    {Nat.add(leading, Nat.add(RuleContainerSpaceLaws.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  RuleContainerSpaceLaws.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available,
    Space.finish(~A, Space.place_from(~A, slots, gap, leading, RuleContainerSpaceLaws.inner_budget(leading, trailing, available)))):
  (inner_fits, balance) = evidence
  container_space_proof_finish_claim(~A, leading, trailing, gap, slots, available,
    Space.place_from(~A, slots, gap, leading, RuleContainerSpaceLaws.inner_budget(leading, trailing, available)),
    place_evidence(~A, slots, gap, leading, RuleContainerSpaceLaws.inner_budget(leading, trailing, available), inner_fits), balance)

def feasible_claim(~A: Data, +feasible: Bool, +container: Space.Container<A>, +available: Nat,
  decision: {Nat.is_le(Space.container_required(~A, container), available) == feasible : Bool}) ->
  RuleContainerSpaceLaws.ContainerClaim(~A, container, available, Space.feasible_container(~A, feasible, container, available)):
  match feasible:
    case False{}:
      Space.Container{leading, trailing, gap, slots} = container
      ({==}, ({==}, decision))
    case True{}:
      Space.Container{+leading, +trailing, +gap, +slots} = container
      accepted_claim(~A, leading, trailing, gap, slots, available,
        inset_budget(leading, trailing, Space.minimum_sequence(~A, slots, gap), available, decision))

def container_space_proof_complete(~A: Data, +container: Space.Container<A>, +available: Nat) ->
  RuleContainerSpaceLaws.ContainerClaim(~A, container, available, Space.pack_container(~A, container, available)):
  feasible_claim(~A, Nat.is_le(Space.container_required(~A, container), available), container, available, {==})

def RuleContainerSpaceLaws.evidence(A):
  RuleContainerSpaceLaws.Requirement{+container => +available => container_space_proof_complete(~A, container, available)}

def subtract_zero(+value: Nat) -> {Nat.sub(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

# These two bridges concern the saturating predecessor at the exact budget boundary.
def rank_at_zero(+value: Nat,
  enough: {Nat.is_le(value, 0n) == True{} : Bool}) -> {value == 0n : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: Logic.impossible({1n+rest == 0n : Nat}, enough)

def predecessor_in_budget(+value: Nat, +budget: Nat,
  enough: {Nat.is_le(value, 1n+budget) == True{} : Bool}) ->
  {Nat.is_le(Nat.sub(value, 1n), budget) == True{} : Bool}:
  match value:
    case 0n: zero_le(budget)
    case 1n+rest:
      Std.transport(Nat, rest, (predecessor => {Nat.is_le(predecessor, budget) == True{} : Bool}),
        enough, Nat.sub(rest, 0n), subtract_zero(rest))

# The closed decrease theorem is reusable inside the compile-time induction callbacks.
def iterate_rank_zero(~S: Data, ~step: S -> S, ~rank: S -> Nat,
  ~decreases: @+state:S -> {Nat.is_le(rank(step(state)), Nat.sub(rank(state), 1n)) == True{} : Bool},
  +seed: S, +budget: Nat,
  enough: {Nat.is_le(rank(seed), budget) == True{} : Bool}) ->
  {rank(Std.iter(~S, ~step, budget, seed)) == 0n : Nat}:
  Std.nat_ind(~(count =>
      @+initial:S ->
      @fits:{Nat.is_le(rank(initial), count) == True{} : Bool} ->
      {rank(Std.iter(~S, ~step, count, initial)) == 0n : Nat}),
    ~(initial => fits => rank_at_zero(rank(initial), fits)),
    ~(count => induction => initial => fits =>
      Equal.trans(Nat,
        rank(Std.iter(~S, ~step, 1n+count, initial)),
        rank(Std.iter(~S, ~step, count, step(initial))), 0n,
        Equal.cong(S, Nat, rank,
          Std.iter(~S, ~step, 1n+count, initial),
          Std.iter(~S, ~step, count, step(initial)),
          Equal.trans(S,
            Std.iter(~S, ~step, 1n+count, initial),
            step(Std.iter(~S, ~step, count, initial)),
            Std.iter(~S, ~step, count, step(initial)),
            Std.iter_add(~S, ~step, 1n, count, initial),
            Std.iter_swap_gen(~S, ~S, ~step, ~step, ~step, ~(state => {==}), count, initial))),
        induction(step(initial),
          le_trans(rank(step(initial)), Nat.sub(rank(initial), 1n), count,
            decreases(initial), predecessor_in_budget(rank(initial), count, fits))))),
    budget)(seed, enough)

def rigid_chosen(+dimension: Space.Dimension, +room: Nat) -> RulePhysicalPackingRules.rigid_extent(dimension, Space.choose(dimension, room)):
  match dimension:
    case Space.Rigid{extent}: {==}
    case Space.Fit{minimum, extra, maximum}: Unit{}
    case Space.Fill{minimum}: Unit{}

def rigid_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +room: Nat,
  +result: Space.Allocation<A>, proof: RulePhysicalPackingRules.allocation_rigid_extents(~A, rest, result)) ->
  RulePhysicalPackingRules.allocation_rigid_extents(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, Space.choose(dimension, room)}, result)):
  Space.Allocation{placements, unused} = result
  (rigid_chosen(dimension, room), proof)

def rigid_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) ->
  RulePhysicalPackingRules.allocation_rigid_extents(~A, slots, Space.place_from(~A, slots, gap, offset, budget)):
  match slots:
    case Nil{}: Unit{}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +room = Nat.sub(budget, Space.reservation(~A, rest, gap))
      +size = Space.choose(dimension, room)
      +between = Space.following_gap(~A, rest, gap)
      rigid_prefix(~A, value, dimension, rest, offset, room,
        Space.place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)),
        rigid_place(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def RulePhysicalPackingRules.rigid_placement(A, slots, gap, offset, budget): rigid_place(~A, slots, gap, offset, budget)

# This projection recovers authored slots from the tagged first allocation.
def original_slots(~A: Data, placements: +List<Space.Placement<Allocation.Tagged<A>>>) -> +List<Space.Slot<A>>:
  match placements:
    case Nil{}: Nil{}
    case Con{Space.Placement{Allocation.Tagged{value, original}, offset, extent}, rest}:
      Space.Slot{value, original} <> original_slots(~A, rest)

def allocation_original(~A: Data, result: Space.Allocation<Allocation.Tagged<A>>) -> +List<Space.Slot<A>>:
  Space.Allocation{placements, unused} = result
  original_slots(~A, placements)

def original_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +offset: Nat, +extent: Nat,
  +result: Space.Allocation<Allocation.Tagged<A>>, +rest: +List<Space.Slot<A>>,
  +proof: {allocation_original(~A, result) == rest : +List<Space.Slot<A>>}) ->
  {allocation_original(~A, Space.prepend(~Allocation.Tagged<A>, Space.Placement{Allocation.Tagged{value, dimension}, offset, extent}, result)) ==
    Space.Slot{value, dimension} <> rest : +List<Space.Slot<A>>}:
  Space.Allocation{placements, unused} = result
  Equal.cong(+List<Space.Slot<A>>, +List<Space.Slot<A>>, (tail => Space.Slot{value, dimension} <> tail), original_slots(~A, placements), rest, proof)

def original_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) ->
  {allocation_original(~A, Space.place_from(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, offset, budget)) == slots : +List<Space.Slot<A>>}:
  match slots:
    case Nil{}: {==}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +frozen = Allocation.freeze_slots(~A, rest)
      +size = Space.choose(Allocation.frozen_dimension(dimension), Nat.sub(budget, Space.reservation(~Allocation.Tagged<A>, frozen, gap)))
      +between = Space.following_gap(~Allocation.Tagged<A>, frozen, gap)
      original_prefix(~A, value, dimension, offset, size,
        Space.place_from(~Allocation.Tagged<A>, frozen, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)), rest,
        original_place(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def dimension_limit(+dimension: Space.Dimension, +extent: Nat) -> Bool:
  Nat.is_le(Space.minimum(dimension), extent) && (RuleSpaceLaws.maximum_ok(dimension, extent) && RuleSpaceLaws.rigid_ok(dimension, extent))

def physical_packing_proof_and_left(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  first({a == True{} : Bool}, {b == True{} : Bool}, and_parts(a, b, proof))

def physical_packing_proof_and_right(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  second({a == True{} : Bool}, {b == True{} : Bool}, and_parts(a, b, proof))

def extended_limit(+dimension: Space.Dimension, +extent: Nat, +share: Nat, +remaining: Nat,
  +proof: {dimension_limit(Allocation.frozen_dimension(dimension), extent) == True{} : Bool}) ->
  {dimension_limit(dimension, Allocation.shared_extent(dimension, extent, share, remaining)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{declared}: proof
    case Space.Fit{minimum, extra, maximum}: proof
    case Space.Fill{minimum}:
      +lower = physical_packing_proof_and_left(Nat.is_le(minimum, extent),
        RuleSpaceLaws.maximum_ok(Space.Rigid{minimum}, extent) && RuleSpaceLaws.rigid_ok(Space.Rigid{minimum}, extent), proof)
      and_join(Nat.is_le(minimum, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), True{},
        le_trans(minimum, extent, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining))), lower,
          le_add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), {==})

def bounds_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +extent: Nat,
  +result: Space.Allocation<A>, +head: {dimension_limit(dimension, extent) == True{} : Bool},
  tail: {RuleSpaceLaws.allocated_limits(~A, rest, result) == True{} : Bool}) ->
  {RuleSpaceLaws.allocated_limits(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, extent}, result)) == True{} : Bool}:
  Space.Allocation{+placements, unused} = result
  +lower = physical_packing_proof_and_left(Nat.is_le(Space.minimum(dimension), extent),
    RuleSpaceLaws.maximum_ok(dimension, extent) && RuleSpaceLaws.rigid_ok(dimension, extent), head)
  +rest_head = physical_packing_proof_and_right(Nat.is_le(Space.minimum(dimension), extent),
    RuleSpaceLaws.maximum_ok(dimension, extent) && RuleSpaceLaws.rigid_ok(dimension, extent), head)
  +upper = physical_packing_proof_and_left(RuleSpaceLaws.maximum_ok(dimension, extent), RuleSpaceLaws.rigid_ok(dimension, extent), rest_head)
  +rigid = physical_packing_proof_and_right(RuleSpaceLaws.maximum_ok(dimension, extent), RuleSpaceLaws.rigid_ok(dimension, extent), rest_head)
  and_join(Nat.is_le(Space.minimum(dimension), extent),
    RuleSpaceLaws.maximum_ok(dimension, extent) && (RuleSpaceLaws.rigid_ok(dimension, extent) && RuleSpaceLaws.limits(~A, rest, placements)), lower,
    and_join(RuleSpaceLaws.maximum_ok(dimension, extent), RuleSpaceLaws.rigid_ok(dimension, extent) && RuleSpaceLaws.limits(~A, rest, placements), upper,
      and_join(RuleSpaceLaws.rigid_ok(dimension, extent), RuleSpaceLaws.limits(~A, rest, placements), rigid, tail)))

def thawed_bounds(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +gap: Nat, +offset: Nat, +budget: Nat,
  +share: Nat, +remaining: Nat,
  +proof: {RuleSpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  {RuleSpaceLaws.allocated_limits(~A, original_slots(~A, placements),
    Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, offset, budget)) == True{} : Bool}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, previous_offset, +extent}, +rest}:
      +frozen = Allocation.frozen_dimension(dimension)
      +frozen_rest = Allocation.freeze_slots(~A, original_slots(~A, rest))
      +tail_limits = RuleSpaceLaws.limits(~Allocation.Tagged<A>, frozen_rest, rest)
      +lower = physical_packing_proof_and_left(Nat.is_le(Space.minimum(frozen), extent),
        RuleSpaceLaws.maximum_ok(frozen, extent) && (RuleSpaceLaws.rigid_ok(frozen, extent) && tail_limits), proof)
      +further = physical_packing_proof_and_right(Nat.is_le(Space.minimum(frozen), extent),
        RuleSpaceLaws.maximum_ok(frozen, extent) && (RuleSpaceLaws.rigid_ok(frozen, extent) && tail_limits), proof)
      +upper = physical_packing_proof_and_left(RuleSpaceLaws.maximum_ok(frozen, extent), RuleSpaceLaws.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid_tail = physical_packing_proof_and_right(RuleSpaceLaws.maximum_ok(frozen, extent), RuleSpaceLaws.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid = physical_packing_proof_and_left(RuleSpaceLaws.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +tail = physical_packing_proof_and_right(RuleSpaceLaws.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +first_bound = and_join(Nat.is_le(Space.minimum(frozen), extent),
        RuleSpaceLaws.maximum_ok(frozen, extent) && RuleSpaceLaws.rigid_ok(frozen, extent), lower,
        and_join(RuleSpaceLaws.maximum_ok(frozen, extent), RuleSpaceLaws.rigid_ok(frozen, extent), upper, rigid))
      +size = Allocation.shared_extent(dimension, extent, share, remaining)
      +next_remaining = Allocation.next_remainder(dimension, remaining)
      +thawed_rest = Allocation.thaw_slots(~A, rest, share, next_remaining)
      +between = Space.following_gap(~A, thawed_rest, gap)
      +next_offset = Nat.add(offset, Nat.add(size, between))
      +next_budget = Nat.sub(Nat.sub(budget, size), between)
      bounds_prefix(~A, value, dimension, original_slots(~A, rest), offset, size,
        Space.place_from(~A, thawed_rest, gap, next_offset, next_budget), extended_limit(dimension, extent, share, remaining, first_bound),
        thawed_bounds(~A, rest, gap, next_offset, next_budget, share, next_remaining, tail))

def thaw_values(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat) ->
  {RuleSpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)) == RuleSpaceLaws.slot_values(~A, original_slots(~A, placements)) : +List<A>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, offset, extent}, rest}:
      Equal.cong(+List<A>, +List<A>, (tail => value <> tail),
        RuleSpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, rest, share, Allocation.next_remainder(dimension, remaining))),
        RuleSpaceLaws.slot_values(~A, original_slots(~A, rest)), thaw_values(~A, rest, share, Allocation.next_remainder(dimension, remaining)))

def restored_allocation(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: RuleSpaceLaws.AllocationEvidence<A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available, result>,
  bounds: {RuleSpaceLaws.allocated_limits(~A, original_slots(~A, placements), result) == True{} : Bool}) ->
  RuleSpaceLaws.AllocationEvidence<A, original_slots(~A, placements), gap, 0n, available, result>:
  RuleSpaceLaws.AllocationEvidence{payloads, rigid_bounds, order, budget} = proof
  RuleSpaceLaws.AllocationEvidence{
    Equal.trans(+List<A>, RuleSpaceLaws.allocated_values(~A, result),
      RuleSpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)), RuleSpaceLaws.slot_values(~A, original_slots(~A, placements)),
      payloads, thaw_values(~A, placements, share, remaining)), bounds, order, budget}

def finish_shared(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: RuleSpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  RulePhysicalPackingRules.SharedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  proof


# Recover successful pack evidence through the allocator's complete feasibility law.
def unpack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: RuleSpaceLaws.PackedClaim(~A, slots, gap, available, Space.finish(~A, result))) ->
  RuleSpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, result>:
  Space.Allocation{placements, unused} = result
  proof

def feasibility(~A: Data, requirements: RuleSpaceLaws.Requirements<A>, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {RuleSpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)) == Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) : Bool}:
  RuleSpaceLaws.Requirements{larger, smaller, minimum, maximum, complete, insufficient, construction} = requirements
  complete(slots, gap, available)

def complete_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  RuleSpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, Space.place_from(~A, slots, gap, 0n, available)>:
  +complete_equation = feasibility(~A, RuleSpaceLaws.evidence(~A), slots, gap, available)
  +success = Equal.trans(Bool, RuleSpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, complete_equation, fits)
  +recovered = Equal.trans(Bool, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available),
    RuleSpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)), True{},
    Equal.sym(Bool, RuleSpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)),
      Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), complete_equation), success)
  +finished = Space.finish(~A, Space.place_from(~A, slots, gap, 0n, available))
  +same = Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, fits)
  unpack_complete(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available),
    Std.transport(Space.Packing<A>, Space.pack(~A, slots, gap, available),
      (result => RuleSpaceLaws.PackedClaim(~A, slots, gap, available, result)),
      pack_complete(~A, slots, gap, available, recovered), finished,
      Equal.sym(Space.Packing<A>, Space.pack(~A, slots, gap, available), finished, same)))

def restored_feasible(~A: Data, +fits: Bool, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available) == fits : Bool},
  first_bounds: {RuleSpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalPackingRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Space.feasible_pack(~A, fits, Allocation.thaw_slots(~A, placements, share, remaining), gap, available)):
  match fits:
    case False{}: Unit{}
    case True{}:
      finish_shared(~A, original_slots(~A, placements), gap, available,
        Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available),
        restored_allocation(~A, placements, share, remaining, gap, available,
          Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available),
          complete_place(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, available, equation),
          thawed_bounds(~A, placements, gap, 0n, available, share, remaining, first_bounds)))

def restored_pack(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat,
  first_bounds: {RuleSpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalPackingRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Space.pack(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, available)):
  restored_feasible(~A, Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available),
    placements, share, remaining, gap, available, {==}, first_bounds)

def redistribution_claim(~A: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<A>>>,
  +unused: Nat, +gap: Nat, +available: Nat,
  first_bounds: {RuleSpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalPackingRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Allocation.dispatch_redistribute_2(~A, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_pack(~A, placements, 0n, 0n, gap, available, first_bounds)
    case False{}: restored_pack(~A, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available, first_bounds)

def first_allocation_claim(~A: Data, +slots: +List<Space.Slot<A>>, +count: Nat, +gap: Nat, +available: Nat,
  +first: Space.Allocation<Allocation.Tagged<A>>,
  proof: RuleSpaceLaws.AllocationEvidence<Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available, first>,
  +original: {allocation_original(~A, first) == slots : +List<Space.Slot<A>>}) ->
  RulePhysicalPackingRules.SharedClaim(~A, slots, gap, available, Allocation.redistribute(~A, count, Space.finish(~Allocation.Tagged<A>, first), gap, available)):
  Space.Allocation{+placements, +unused} = first
  RuleSpaceLaws.AllocationEvidence{payloads, bounds, order, budget} = proof
  +source = original_slots(~A, placements)
  +self_bounds = Std.transport(+List<Space.Slot<A>>, slots,
    (sources => {RuleSpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, sources), placements) == True{} : Bool}),
    bounds, source, original)
  Std.transport(+List<Space.Slot<A>>, source,
    (sources => RulePhysicalPackingRules.SharedClaim(~A, sources, gap, available,
      Allocation.dispatch_redistribute_2(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available))),
    redistribution_claim(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available, self_bounds), slots,
    Equal.sym(+List<Space.Slot<A>>, source, slots, original))

def first_feasible(~A: Data, +fits: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available) == fits : Bool}) ->
  RulePhysicalPackingRules.SharedClaim(~A, slots, gap, available,
    Allocation.redistribute(~A, Allocation.fill_count(~A, slots),
      Space.feasible_pack(~Allocation.Tagged<A>, fits, Allocation.freeze_slots(~A, slots), gap, available), gap, available)):
  match fits:
    case False{}: Unit{}
    case True{}:
      first_allocation_claim(~A, slots, Allocation.fill_count(~A, slots), gap, available,
        Space.place_from(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available),
        complete_place(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, available, equation),
        original_place(~A, slots, gap, 0n, available))

def RulePhysicalPackingRules.shared_packing(A, slots, gap, available):
  first_feasible(~A, Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available), slots, gap, available, {==})

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
  {ModelRules.extent_contains(Model.extent_max(first, second), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = second
  and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Space.larger(h, y)),
    demand_max_left(w, x), demand_max_left(h, y))

def max_contains_second(+first: E.Extent, +second: E.Extent) ->
  {ModelRules.extent_contains(Model.extent_max(first, second), second) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = second
  and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Space.larger(h, y)),
    demand_max_right(w, x), demand_max_right(h, y))

def contains_trans(+outer: E.Extent, +middle: E.Extent, +inner: E.Extent,
  +first: {ModelRules.extent_contains(outer, middle) == True{} : Bool},
  +second: {ModelRules.extent_contains(middle, inner) == True{} : Bool}) ->
  {ModelRules.extent_contains(outer, inner) == True{} : Bool}:
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
  {ModelRules.extent_contains(Model.horizontal_extent(gap, first, rest), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(w, Nat.add(w, Nat.add(gap, x))), Nat.is_le(h, Space.larger(h, y)), le_add(w, Nat.add(gap, x)), demand_max_left(h, y))

def combine_first_vertical(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), first) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Nat.add(h, Nat.add(gap, y))), demand_max_left(w, x), le_add(h, Nat.add(gap, y)))

def combine_first(+direction: Model.Direction, +gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {ModelRules.extent_contains(Model.combine_extent(direction, gap, first, rest), first) == True{} : Bool}:
  match direction:
    case Model.Horizontal{}: combine_first_horizontal(gap, first, rest)
    case Model.Vertical{}: combine_first_vertical(gap, first, rest)
    case Model.ResponsiveHorizontal{}: combine_first_vertical(gap, first, rest)
    case Model.Layered{}: max_contains_first(first, rest)

def combine_rest_horizontal(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {ModelRules.extent_contains(Model.horizontal_extent(gap, first, rest), rest) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(x, Nat.add(w, Nat.add(gap, x))), Nat.is_le(y, Space.larger(h, y)),
    le_trans(x, Nat.add(gap, x), Nat.add(w, Nat.add(gap, x)), add_contains_second(gap, x), add_contains_second(w, Nat.add(gap, x))), demand_max_right(h, y))

def combine_rest_vertical(+gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), rest) == True{} : Bool}:
  E.Extent{+w, +h} = first
  E.Extent{+x, +y} = rest
  and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Nat.add(h, Nat.add(gap, y))), demand_max_right(w, x),
    le_trans(y, Nat.add(gap, y), Nat.add(h, Nat.add(gap, y)), add_contains_second(gap, y), add_contains_second(h, Nat.add(gap, y))))

def combine_rest(+direction: Model.Direction, +gap: Nat, +first: E.Extent, +rest: E.Extent) ->
  {ModelRules.extent_contains(Model.combine_extent(direction, gap, first, rest), rest) == True{} : Bool}:
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
  {ModelRules.preferred_covers_minimum(Model.prepend_demand(direction, gap, first, rest)) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = rest
  max_contains_first(Model.combine_extent(direction, gap, a, c), Model.combine_extent(direction, gap, b, d))

def extent_contains_self(+extent: E.Extent) ->
  {ModelRules.extent_contains(extent, extent) == True{} : Bool}:
  E.Extent{+width, +height} = extent
  and_join(Nat.is_le(width, width), Nat.is_le(height, height), le_refl(width), le_refl(height))

def clearance_layered_contains(+outside: E.Insets, +extent: E.Extent) ->
  {ModelRules.extent_contains(Model.clearance_extent_layered(outside, extent), extent) == True{} : Bool}:
  E.Insets{+inline, +block} = outside
  E.Extent{+width, +height} = extent
  and_join(Nat.is_le(width, Nat.add(width, Nat.mul(2n, inline))), Nat.is_le(height, Nat.add(height, Nat.mul(2n, block))),
    le_add(width, Nat.mul(2n, inline)), le_add(height, Nat.mul(2n, block)))

def clearance_contains(+direction: Model.Direction, +position: SpatialModel.Position, +extent: E.Extent) ->
  {ModelRules.extent_contains(Model.clearance_extent(direction, position, extent), extent) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_layered_contains(Model.position_outside(position), extent)
    case Model.Horizontal{}: extent_contains_self(extent)
    case Model.Vertical{}: extent_contains_self(extent)
    case Model.ResponsiveHorizontal{}: extent_contains_self(extent)

def preferred_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {ModelRules.preferred_covers_minimum(Model.content_demand(~A, ~E, trees, direction, gap)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{Model.Leaf{key, value, interaction, +rule, demand, height}, +rest}:
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), Model.outer_demand(~E, Model.leaf_content_demand(demand, height), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))
    case Con{Model.Container{key, value, interaction, +rule, children}, +rest}:
      Model.Rule{child_direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap),
        Model.clearance_demand(direction, position, Model.outer_demand(~E, Model.content_demand(~A, ~E, children, child_direction, E.frame_gap(frame)), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))

def children_raise(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +outer: E.Extent, +inner: E.Extent,
  +contains: {ModelRules.extent_contains(outer, inner) == True{} : Bool},
  +participating: {ModelRules.child_minima_participate(~A, ~E, trees, inner) == True{} : Bool}) ->
  {ModelRules.child_minima_participate(~A, ~E, trees, outer) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{+tree, +rest}:
      +minimum = Model.minimum_demand(Model.demand(~A, ~E, tree))
      head = physical_space_proof_and_left(ModelRules.extent_contains(inner, minimum), ModelRules.child_minima_participate(~A, ~E, rest, inner), participating)
      tail = physical_space_proof_and_right(ModelRules.extent_contains(inner, minimum), ModelRules.child_minima_participate(~A, ~E, rest, inner), participating)
      and_join(ModelRules.extent_contains(outer, minimum), ModelRules.child_minima_participate(~A, ~E, rest, outer),
        contains_trans(outer, inner, minimum, contains, head), children_raise(~A, ~E, rest, outer, inner, contains, tail))

def prepend_children(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +rest: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat, +first: Space.Demand, +remaining: Space.Demand,
  same: {ModelRules.extent_contains(Model.minimum_demand(first), Model.minimum_demand(Model.demand(~A, ~E, tree))) == True{} : Bool},
  tail: {ModelRules.child_minima_participate(~A, ~E, rest, Model.minimum_demand(remaining)) == True{} : Bool}) ->
  {ModelRules.child_minima_participate(~A, ~E, tree <> rest, Model.minimum_demand(Model.prepend_demand(direction, gap, first, remaining))) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = remaining
  +required = Model.combine_extent(direction, gap, a, c)
  head = contains_trans(required, a, Model.minimum_demand(Model.demand(~A, ~E, tree)), combine_first(direction, gap, a, c), same)
  and_join(ModelRules.extent_contains(required, Model.minimum_demand(Model.demand(~A, ~E, tree))), ModelRules.child_minima_participate(~A, ~E, rest, required),
    head, children_raise(~A, ~E, rest, required, c, combine_rest(direction, gap, a, c), tail))

def clearance_demand_contains(+direction: Model.Direction, +position: SpatialModel.Position, +minimum: E.Extent, +preferred: E.Extent) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, Space.Demand{minimum, preferred})), minimum) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_contains(Model.Layered{}, position, minimum)
    case Model.Horizontal{}: extent_contains_self(minimum)
    case Model.Vertical{}: extent_contains_self(minimum)
    case Model.ResponsiveHorizontal{}: extent_contains_self(minimum)

def clearance_singleton(+direction: Model.Direction, +position: SpatialModel.Position, +first: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))) == True{} : Bool}:
  Space.Demand{minimum, preferred} = first
  Equal.trans(Bool,
    ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))),
    ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(first)), True{},
    Equal.cong(E.Extent, Bool, (extent => ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), extent)),
      Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n))), Model.minimum_demand(first), singleton_minimum(first)),
    clearance_demand_contains(direction, position, minimum, preferred))

def children_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {ModelRules.child_minima_participate(~A, ~E, trees, Model.minimum_demand(Model.content_demand(~A, ~E, trees, direction, gap))) == True{} : Bool}:
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
  {Nat.is_le(ModelRules.authored_minimum(size), ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
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
  {Nat.is_le(minimum, ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
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
  {Nat.is_le(ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred)), ModelRules.axis_preferred(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
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
  +width_floor: {Nat.is_le(mw, ModelRules.axis_minimum(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(mh, ModelRules.axis_minimum(height)) == True{} : Bool}) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.demand_from_axes(width, height)), E.Extent{mw, mh}) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  and_join(Nat.is_le(mw, lower_width), Nat.is_le(mh, lower_height), width_floor, height_floor)

def authored_floor(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), Model.minimum_demand(content)) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), mw, mh,
    axis_intrinsic_floor(width, mw, pw), axis_intrinsic_floor(height, mh, ph))

def axes_preferred(+width: Model.AxisDemand, +height: Model.AxisDemand,
  +width_floor: {Nat.is_le(ModelRules.axis_minimum(width), ModelRules.axis_preferred(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(ModelRules.axis_minimum(height), ModelRules.axis_preferred(height)) == True{} : Bool}) ->
  {ModelRules.preferred_covers_minimum(Model.demand_from_axes(width, height)) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  and_join(Nat.is_le(lower_width, chosen_width), Nat.is_le(lower_height, chosen_height), width_floor, height_floor)

def authored_preferred(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {ModelRules.preferred_covers_minimum(Model.authored_demand(width, height, content)) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_preferred(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph),
    axis_preferred_floor(width, mw, pw), axis_preferred_floor(height, mh, ph))

def authored_lower_pair(+width: Model.AxisSize, +height: Model.AxisSize, content: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), E.Extent{ModelRules.authored_minimum(width), ModelRules.authored_minimum(height)}) == True{} : Bool}:
  Space.Demand{E.Extent{+mw, +mh}, E.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), ModelRules.authored_minimum(width), ModelRules.authored_minimum(height),
    axis_authored_floor(width, mw, pw), axis_authored_floor(height, mh, ph))

def outer_authored_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), ModelRules.rule_authored_minimum(rule)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_lower_pair(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_preferred(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.preferred_covers_minimum(Model.outer_demand(~E, content, rule, interaction)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_preferred(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_intrinsic_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, interaction))) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_floor(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def operable_outer(~E: Data, +content: E.Extent, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.outer_extent(~E, content, rule, Model.Operable{first, remaining, enabled}), E.Extent{32n, 32n}) == True{} : Bool}:
  E.Extent{+w, +h} = content
  Model.Rule{direction, main, cross, +frame, +border, width, height, +minimum, scroll, position} = rule
  contains_trans(Model.extent_max(E.required_extent(w, h, border, E.frame_content(frame)), Model.extent_max(minimum, E.Extent{32n, 32n})),
    Model.extent_max(minimum, E.Extent{32n, 32n}), E.Extent{32n, 32n},
    max_contains_second(E.required_extent(w, h, border, E.frame_content(frame)), Model.extent_max(minimum, E.Extent{32n, 32n})), max_contains_second(minimum, E.Extent{32n, 32n}))

def operable(~E: Data, +content: Space.Demand, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), E.Extent{32n, 32n}) == True{} : Bool}:
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
  conflict: {ModelRules.percentage_conflict(extent, minimum) == True{} : Bool}) ->
  {Model.capped_dimension(extent, minimum, preferred) == None{} : Maybe<&2, Space.Dimension>}:
  match extent:
    case None{}: {==}
    case Some{+cap}:
      +chosen = Space.smaller(cap, Space.larger(minimum, preferred))
      capped_rejected(Nat.is_le(minimum, cap), Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(cap, chosen)}, conflict)

def capped_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +maximum_percent: Nat,
  conflict: {ModelRules.percentage_conflict(Model.percentage_extent(offered, maximum_percent), minimum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  capped_extent_conflict(Model.percentage_extent(offered, maximum_percent), minimum, preferred, conflict)

def capped_stretch_accepted(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered) == Some{ModelRules.capped_stretch_dimension(minimum, maximum)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (valid => Model.accept_dimension(valid, ModelRules.capped_stretch_dimension(minimum, maximum))), Nat.is_le(minimum, maximum), True{}, fits)

def capped_stretch_rejected_checked(+fits: Bool, dimension: Space.Dimension) ->
  {ModelRules.rejected(Model.accept_dimension(fits, dimension)) == Bool.not(fits) : Bool}:
  match fits:
    case False{}: {==}
    case True{}: {==}

def capped_stretch_rejected(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat) ->
  {ModelRules.rejected(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered)) == Bool.not(Nat.is_le(minimum, maximum)) : Bool}:
  capped_stretch_rejected_checked(Nat.is_le(minimum, maximum), ModelRules.capped_stretch_dimension(minimum, maximum))

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
  {ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>}:
  accepted = Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, (result => ModelRules.allocated_width(result, room)),
    Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), Some{ModelRules.capped_stretch_dimension(minimum, maximum)}, capped_stretch_accepted(minimum, preferred, offered, maximum, fits))
  selected = Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room), Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room), smaller_eq_min(Nat.add(minimum, Nat.sub(maximum, minimum)), room))
  bounded = Equal.cong(Nat, Maybe<&2, Nat>, (cap => Some{Nat.min(cap, room)}), Nat.add(minimum, Nat.sub(maximum, minimum)), maximum, capped_stretch_balance(minimum, maximum, fits))
  Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room),
    Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(room, maximum)},
    Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, accepted, selected),
    Equal.trans(Maybe<&2, Nat>, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(maximum, room)}, Some{Nat.min(room, maximum)}, bounded,
      Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(maximum, room), Nat.min(room, maximum), minimum_commutes(maximum, room))))

def capped_stretch_attained(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, +room_fits: {Nat.is_le(maximum, room) == True{} : Bool}) ->
  {ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{maximum} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Nat.min(room, maximum)}, Some{maximum},
    capped_stretch_width(minimum, preferred, offered, maximum, room, fits, le_trans(minimum, maximum, room, fits, room_fits)),
    Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(room, maximum), maximum,
      Equal.trans(Nat, Nat.min(room, maximum), Nat.min(maximum, room), maximum, minimum_commutes(room, maximum), minimum_attained(maximum, room, room_fits))))

def adaptive_exact(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Some{ModelRules.adaptive_fit(minimum, preferred, offered, nominal_cap)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    valid => Model.adaptive_checked(valid, minimum, preferred, offered, nominal_cap),
    Nat.is_le(minimum, offered), True{}, fits)

def adaptive_total(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))} : Maybe<&2, Space.Dimension>}:
  Equal.trans(Maybe<&2, Space.Dimension>,
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Model.adaptive_dimension(Some{ModelRules.nominal_percentage(offered, percent)}, minimum, preferred, offered),
    Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
    Equal.cong(Bool, Maybe<&2, Space.Dimension>,
      accepted => Model.adaptive_dimension(Model.percentage_checked(accepted, offered, percent), minimum, preferred, offered),
      Nat.is_le(percent, 100n), True{}, valid),
    adaptive_exact(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent), fits))

def adaptive_minimum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {ModelRules.minimum_result(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered)) == Some{minimum} : Maybe<&2, Nat>}:
  Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, result => ModelRules.minimum_result(result),
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
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
  {ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap) == ModelRules.adaptive_maximum(minimum, offered, nominal_cap) : Nat}:
  +maximum = ModelRules.adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  +maximum_floor = smaller_floor(minimum, offered, Space.larger(minimum, nominal_cap), fits, demand_max_left(minimum, nominal_cap))
  +chosen_floor = smaller_floor(minimum, maximum, Space.larger(minimum, preferred), maximum_floor, demand_max_left(minimum, preferred))
  Equal.trans(Nat, ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap),
    Nat.add(chosen, Nat.sub(maximum, chosen)), maximum,
    Equal.cong(Nat, Nat, size => Nat.add(size, Nat.sub(maximum, chosen)),
      Nat.add(minimum, Nat.sub(chosen, minimum)), chosen, capped_stretch_balance(minimum, chosen, chosen_floor)),
    capped_stretch_balance(chosen, maximum, smaller_left(maximum, Space.larger(minimum, preferred))))

def adaptive_fit_bound(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered),
    Nat.is_le(ModelRules.adaptive_maximum(minimum, offered, nominal_cap), offered), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(size, offered),
      ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), ModelRules.adaptive_maximum(minimum, offered, nominal_cap),
      adaptive_fit_maximum(minimum, preferred, offered, nominal_cap, fits)),
    smaller_left(offered, Space.larger(minimum, nominal_cap)))

def adaptive_maximum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {ModelRules.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered) == True{} : Bool}:
  Equal.trans(Bool,
    ModelRules.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered),
    Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent)), offered), True{},
    Equal.cong(Maybe<&2, Space.Dimension>, Bool, result => ModelRules.maximum_fits(result, offered),
      Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
      Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
      adaptive_total(minimum, preferred, offered, percent, valid, fits)),
    adaptive_fit_bound(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent), fits))

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
  +effective = ModelRules.adaptive_maximum(minimum, offered, nominal_cap)
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
      Some{ModelRules.adaptive_fit(minimum, preferred, offered, nominal_cap)},
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

def ModelRules.evidence(A, E):
  ModelRules.Requirements{
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


def ModelRules.aligned_clearance_contains(outside, horizontal, vertical, extent):
  clearance_layered_contains(outside, extent)

def measured_minimum_bound(+observation: Content.Observation) ->
  {Nat.is_le(RuleTextSpaceRules.minimum_width(SourceSource.text_natural_demand(T.SingleLine{}, observation)), SourceSource.observation_advance(observation)) == True{} : Bool}:
  min_le_second(SourceSource.observation_minimum(observation), SourceSource.observation_advance(observation))

def natural_preferred_bound(+observation: Content.Observation) ->
  {Nat.is_le(SourceSource.observation_preferred(observation), RuleTextSpaceRules.preferred_width(SourceSource.text_natural_demand(T.SingleLine{}, observation))) == True{} : Bool}:
  max_right(Nat.min(SourceSource.observation_minimum(observation), SourceSource.observation_advance(observation)), SourceSource.observation_preferred(observation))

def demand_policy(+wrapping: T.Wrapping, +observation: Content.Observation) -> RuleTextSpaceRules.demand_claim(wrapping, observation):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.UnbrokenLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def attributes_policy(+wrapping: T.Wrapping, +text: String) -> RuleTextSpaceRules.attributes_claim(wrapping, text):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.UnbrokenLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def RuleTextSpaceRules.evidence():
  RuleTextSpaceRules.Requirements{
    measured_minimum_bound,
    natural_preferred_bound,
    demand_policy,
    label => text => choice => +wrapping => key => font => rule => +observation => roots => policies => {==},
    +capacity => +key => +text => choice => font => bounds => canvas => rule => interaction => styles => owned => {==},
    attributes_policy}

def RuleTextSpaceRules.unbroken_width(observation): {==}
def RuleTextSpaceRules.unbroken_dimensions(observation): {==}
def RuleTextSpaceRules.unbroken_height(key,height): {==}
def RuleTextSpaceRules.unbroken_render(capacity,key,text,choice,font,bounds,canvas,rule,interaction,styles,owned): {==}

def RuleTextSpaceRules.unbroken_metric(metric):
  match metric:
    case T.Metric{key,minimum,preferred,height,advance}: {==}

def SlotsPopulation(~T: Data, +children: +List<T>, result: Allocation.SlotsOutcome<T>) -> Type:
  match result:
    case Allocation.SlotsReady{slots}: {RuleSpaceLaws.slot_values(~T, slots) == children : +List<T>}
    case Allocation.SlotsFailure{failure}: {True{} == True{} : Bool}

def PlanPopulation(~T: Data, +children: +List<T>, result: Allocation.ChildPlan<T>) -> Type:
  match result:
    case Allocation.ChildrenPlanned{placements, canvas}: {RuleSpaceLaws.placement_values(~T, placements) == children : +List<T>}
    case Allocation.PlanningFailure{failure}: {True{} == True{} : Bool}

def PackingPopulation(~T: Data, +children: +List<T>, result: Space.Packing<T>) -> Type:
  match result:
    case Space.Packed{placements, unused}: {RuleSpaceLaws.placement_values(~T, placements) == children : +List<T>}
    case Space.Insufficient{required, available}: {True{} == True{} : Bool}

def prepend_population(~T: Data, +result: Allocation.SlotsOutcome<T>, +head: T, +tail: +List<T>, +dimension: Space.Dimension,
  proof: SlotsPopulation(~T, tail, result)) ->
  SlotsPopulation(~T, head <> tail, Allocation.prepend_slot(~T, Space.Slot{head, dimension}, result)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Equal.cong(+List<T>, +List<T>, (values => head <> values), RuleSpaceLaws.slot_values(~T, slots), tail, proof)

def materialized_population(~T: Data, +selector: Maybe<&2, Space.Dimension>, +head: T, +tail: +List<T>,
  +key: String, +axis: Allocation.Axis, +lower: Nat, +offered: Nat, +rest: Allocation.SlotsOutcome<T>,
  proof: SlotsPopulation(~T, tail, rest)) ->
  SlotsPopulation(~T, head <> tail, Allocation.materialized_slot(~T, selector, head, key, axis, lower, offered, rest)):
  match selector:
    case None{}: {==}
    case Some{dimension}: prepend_population(~T, rest, head, tail, dimension, proof)

def width_demand_population(~A: Data, ~E: Data, +demand: Space.Demand, +head: Model.Tree<A, E>,
  +tail: +List<Model.Tree<A, E>>, +offered: Nat, +rest: Allocation.SlotsOutcome<Model.Tree<A, E>>,
  proof: SlotsPopulation(~Model.Tree<A, E>, tail, rest)) ->
  SlotsPopulation(~Model.Tree<A, E>, head <> tail, Allocation.width_slot_demand(~A, ~E, demand, head, offered, rest)):
  Space.Demand{minimum, preferred} = demand
  materialized_population(~Model.Tree<A, E>,
    Model.materialize(Allocation.inline_size(Allocation.tree_rule(~A, ~E, head)), Allocation.axis_extent(Allocation.InlineAxis{}, minimum), Allocation.axis_extent(Allocation.InlineAxis{}, preferred), offered),
    head, tail, Allocation.tree_key(~A, ~E, head), Allocation.InlineAxis{}, Allocation.axis_extent(Allocation.InlineAxis{}, minimum), offered, rest, proof)

def width_population(~A: Data, ~E: Data, +children: +List<Model.Tree<A, E>>, +offered: Nat) ->
  SlotsPopulation(~Model.Tree<A, E>, children, Allocation.width_slots(~A, ~E, children, offered)):
  Std.list_ind(~Model.Tree<A, E>, ~(trees => @+available:Nat -> SlotsPopulation(~Model.Tree<A, E>, trees, Allocation.width_slots(~A, ~E, trees, available))),
    ~(+available => {==}), ~(+head => +tail => proof => +available => width_demand_population(~A, ~E, Model.demand(~A, ~E, head), head, tail, Nat.sub(available, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, head))), Allocation.width_slots(~A, ~E, tail, available), proof(available))), children)(offered)

def height_demand_population(~A: Data, ~E: Data, +demand: Space.Demand, +head: Allocation.MeasuredTree<A, E>,
  +tail: +List<Allocation.MeasuredTree<A, E>>, +offered: Nat, +rest: Allocation.SlotsOutcome<Allocation.MeasuredTree<A, E>>,
  proof: SlotsPopulation(~Allocation.MeasuredTree<A, E>, tail, rest)) ->
  SlotsPopulation(~Allocation.MeasuredTree<A, E>, head <> tail, Allocation.height_slot_demand(~A, ~E, demand, head, offered, rest)):
  Space.Demand{minimum, preferred} = demand
  materialized_population(~Allocation.MeasuredTree<A, E>,
    Model.materialize(Allocation.block_size(Allocation.measured_rule(~A, ~E, head)), Allocation.axis_extent(Allocation.BlockAxis{}, minimum), Allocation.axis_extent(Allocation.BlockAxis{}, preferred), offered),
    head, tail, Allocation.measured_key(~A, ~E, head), Allocation.BlockAxis{}, Allocation.axis_extent(Allocation.BlockAxis{}, minimum), offered, rest, proof)

def height_population(~A: Data, ~E: Data, +children: +List<Allocation.MeasuredTree<A, E>>, +offered: Nat) ->
  SlotsPopulation(~Allocation.MeasuredTree<A, E>, children, Allocation.height_slots(~A, ~E, children, offered)):
  Std.list_ind(~Allocation.MeasuredTree<A, E>, ~(trees => @+available:Nat -> SlotsPopulation(~Allocation.MeasuredTree<A, E>, trees, Allocation.height_slots(~A, ~E, trees, available))),
    ~(+available => {==}), ~(+head => +tail => proof => +available => height_demand_population(~A, ~E, Allocation.measured_demand(~A, ~E, head), head, tail, Nat.sub(available, Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, head))), Allocation.height_slots(~A, ~E, tail, available), proof(available))), children)(offered)

# Successful packing carries the imported complete payload equation; failure imposes no feasibility claim.
def packed_claim_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat, +result: Space.Packing<T>,
  proof: RuleSpaceLaws.PackedClaim(~T, slots, gap, available, result)) -> PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), result):
  match result:
    case Space.Insufficient{required, received}: Empty.absurd(PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Space.Insufficient{required, received}), proof)
    case Space.Packed{placements, unused}:
      RuleSpaceLaws.AllocationEvidence{payloads, bounds, order, budget} = proof
      payloads

def pack_fit_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~T, slots, gap), available) == fits : Bool}) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  match fits:
    case True{}:
      packed_claim_population(~T, slots, gap, available, Space.pack(~T, slots, gap, available), pack_complete(~T, slots, gap, available, equation))
    case False{}:
      Std.transport(Space.Packing<T>, Space.Insufficient{Space.minimum_sequence(~T, slots, gap), available},
        (result => PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), result)), {==}, Space.pack(~T, slots, gap, available),
        pack_insufficient(~T, slots, gap, available, equation))

def pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  pack_fit_population(~T, Nat.is_le(Space.minimum_sequence(~T, slots, gap), available), slots, gap, available, {==})

def tagged_value(~T: Data, tagged: Allocation.Tagged<T>) -> T:
  Allocation.Tagged{value, dimension} = tagged
  value

def freeze_population_step(~T: Data, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>,
  proof: {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))) == RuleSpaceLaws.slot_values(~T, tail) : +List<T>}) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, head <> tail))) == RuleSpaceLaws.slot_values(~T, head <> tail) : +List<T>}:
  Space.Slot{+value, dimension} = head
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))), RuleSpaceLaws.slot_values(~T, tail), proof)

def freeze_population(~T: Data, +slots: +List<Space.Slot<T>>) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))) == RuleSpaceLaws.slot_values(~T, slots) : +List<T>}:
  Std.list_ind(~Space.Slot<T>, ~(values => {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, values))) == RuleSpaceLaws.slot_values(~T, values) : +List<T>}), ~{==},
    ~(+head => +tail => proof => freeze_population_step(~T, head, tail, proof)), slots)

def thaw_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat) ->
  {RuleSpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)) == Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)) : +List<T>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +original}, offset, extent}, rest}:
      Equal.cong(+List<T>, +List<T>, (values => value <> values),
        RuleSpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, rest, share, Allocation.next_remainder(original, remaining))),
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, rest)),
        thaw_population(~T, rest, share, Allocation.next_remainder(original, remaining)))

def packing_retarget(~T: Data, +old: +List<T>, +children: +List<T>, +result: Space.Packing<T>,
  proof: PackingPopulation(~T, old, result), equation: {old == children : +List<T>}) -> PackingPopulation(~T, children, result):
  Std.transport(+List<T>, old, (values => PackingPopulation(~T, values, result)), proof, children,
    Equal.sym(+List<T>, old, children, equation))

def restored_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available)):
  packing_retarget(~T, RuleSpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available),
    pack_population(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available), thaw_population(~T, placements, share, remaining))

def redistribution_population(~T: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +unused: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Allocation.dispatch_redistribute_2(~T, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_population(~T, placements, 0n, 0n, gap, available)
    case False{}: restored_population(~T, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available)

def first_pack_population(~T: Data, +first: Space.Packing<Allocation.Tagged<T>>, +slots: +List<Space.Slot<T>>, +count: Nat, +gap: Nat, +available: Nat,
  proof: PackingPopulation(~Allocation.Tagged<T>, RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), first)) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.redistribute(~T, count, first, gap, available)):
  match first:
    case Space.Insufficient{required, received}: {==}
    case Space.Packed{placements, unused}:
      packing_retarget(~T,
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
        RuleSpaceLaws.slot_values(~T, slots), Allocation.dispatch_redistribute_2(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        redistribution_population(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        Equal.trans(+List<T>,
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))),
          RuleSpaceLaws.slot_values(~T, slots),
          Equal.cong(+List<Allocation.Tagged<T>>, +List<T>,
            (values => Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), values)),
            RuleSpaceLaws.placement_values(~Allocation.Tagged<T>, placements), RuleSpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), proof),
          freeze_population(~T, slots)))

def shared_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.shared_pack(~T, slots, gap, available)):
  first_pack_population(~T, Space.pack(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available), slots, Allocation.fill_count(~T, slots), gap, available,
    pack_population(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available))

def shift_population_step(~T: Data, +placement: Space.Placement<T>, +tail: +List<Space.Placement<T>>, +shift: Nat,
  proof: {RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, tail, shift)) == RuleSpaceLaws.placement_values(~T, tail) : +List<T>}) ->
  {RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placement <> tail, shift)) == RuleSpaceLaws.placement_values(~T, placement <> tail) : +List<T>}:
  Space.Placement{+value, offset, extent} = placement
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, tail, shift)),
    RuleSpaceLaws.placement_values(~T, tail), proof)

def shift_population(~T: Data, +placements: +List<Space.Placement<T>>, +shift: Nat) ->
  {RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placements, shift)) == RuleSpaceLaws.placement_values(~T, placements) : +List<T>}:
  Std.list_ind(~Space.Placement<T>, ~(values => @+amount:Nat -> {RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, values, amount)) == RuleSpaceLaws.placement_values(~T, values) : +List<T>}), ~(amount => {==}),
    ~(+head => +tail => proof => +amount => shift_population_step(~T, head, tail, amount, proof(amount))), placements)(shift)

def parallel_append_population(~T: Data, +rest: Allocation.ChildPlan<T>, +placements: +List<Space.Placement<T>>, +children: +List<T>, +tree: T, +shift: Nat,
  head_proof: {RuleSpaceLaws.placement_values(~T, placements) == (tree <> Nil{}) : +List<T>},
  tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.dispatch_prepare_parallel_8(~T, rest, placements, shift)):
  match rest:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{tail, canvas}:
      +shifted = Allocation.shift_placements(~T, placements, shift)
      Equal.trans(+List<T>,
        RuleSpaceLaws.placement_values(~T, List.append(&2, Space.Placement<T>, shifted, tail)),
        List.append(&2, T, RuleSpaceLaws.placement_values(~T, shifted), RuleSpaceLaws.placement_values(~T, tail)), tree <> children,
        Std.map_app(~Space.Placement<T>, ~T, ~(value => RuleSpaceLaws.placement_value(~T, value)), shifted, tail),
        Equal.trans(+List<T>,
          List.append(&2, T, RuleSpaceLaws.placement_values(~T, shifted), RuleSpaceLaws.placement_values(~T, tail)),
          List.append(&2, T, tree <> Nil{}, RuleSpaceLaws.placement_values(~T, tail)), tree <> children,
          Equal.cong(+List<T>, +List<T>, (values => List.append(&2, T, values, RuleSpaceLaws.placement_values(~T, tail))),
            RuleSpaceLaws.placement_values(~T, shifted), tree <> Nil{},
            Equal.trans(+List<T>, RuleSpaceLaws.placement_values(~T, shifted), RuleSpaceLaws.placement_values(~T, placements), tree <> Nil{}, shift_population(~T, placements, shift), head_proof)),
          Equal.cong(+List<T>, +List<T>, (values => tree <> values), RuleSpaceLaws.placement_values(~T, tail), children, tail_proof)))

def packed_parallel_population(~T: Data, ~key_of: T -> String, +first: Space.Packing<T>, +tree: T, +axis: Allocation.Axis, +alignment: SpatialModel.Alignment, +rest: Allocation.ChildPlan<T>, +children: +List<T>,
  head_proof: PackingPopulation(~T, tree <> Nil{}, first), tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.packed_parallel(~T, ~key_of, first, tree, axis, alignment, rest)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      parallel_append_population(~T, rest, placements, children, tree, Allocation.alignment_offset(alignment, unused), head_proof, tail_proof)

def clearance_pack_checked_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.clearance_pack_checked(~T, fits, slots, clearance, available)):
  match fits:
    case False{}: {==}
    case True{}: shared_population(~T, slots, 0n, Nat.sub(available, clearance))

def clearance_pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.clearance_pack(~T, slots, clearance, available)):
  clearance_pack_checked_population(~T, Nat.is_le(clearance, available), slots, clearance, available)

def parallel_population_step(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: SpatialModel.Alignment,
  proof: PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment))) ->
  PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, head <> tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, head <> tail, axis, canvas, alignment)):
  Space.Slot{+tree, +dimension} = head
  packed_parallel_population(~T, ~key_of, Allocation.clearance_pack(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), tree, axis, alignment,
    Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment), RuleSpaceLaws.slot_values(~T, tail),
    clearance_pack_population(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), proof)

def parallel_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +slots: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: SpatialModel.Alignment) ->
  PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)):
  Std.list_ind(~Space.Slot<T>, ~(values => @+actual_axis:Allocation.Axis -> @+actual_canvas:Nat -> @+actual_alignment:SpatialModel.Alignment ->
      PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, values), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, values, actual_axis, actual_canvas, actual_alignment))),
    ~(+actual_axis => +actual_canvas => +actual_alignment => {==}),
    ~(+head => +tail => proof => +actual_axis => +actual_canvas => +actual_alignment =>
      parallel_population_step(~T, ~key_of, ~clearance_of, head, tail, actual_axis, actual_canvas, actual_alignment, proof(actual_axis)(actual_canvas)(actual_alignment))), slots)(axis)(canvas)(alignment)

def sequential_population(~T: Data, +first: Space.Packing<T>, +slots: +List<Space.Slot<T>>, +key: String, +axis: Allocation.Axis, +alignment: SpatialModel.Alignment, +canvas: Nat,
  proof: PackingPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), first)) ->
  PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.dispatch_prepare_slots_9(~T, first, key, axis, alignment, canvas)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      Equal.trans(+List<T>,
        RuleSpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placements, Allocation.alignment_offset(alignment, unused))),
        RuleSpaceLaws.placement_values(~T, placements), RuleSpaceLaws.slot_values(~T, slots), shift_population(~T, placements, Allocation.alignment_offset(alignment, unused)), proof)

def sequence_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +is_sequence: Bool, +key: String, +axis: Allocation.Axis,
  +slots: +List<Space.Slot<T>>, +gap: Nat, +canvas: Nat, +alignment: SpatialModel.Alignment) ->
  PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.destructure_prepare_slots_sequence(~T, ~key_of, ~clearance_of, is_sequence, key, axis, slots, gap, canvas, alignment)):
  match is_sequence:
    case False{}: parallel_population(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)
    case True{}: sequential_population(~T, Allocation.shared_pack(~T, slots, gap, canvas), slots, key, axis, alignment, canvas, shared_population(~T, slots, gap, canvas))

def slots_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +key: String, +axis: Allocation.Axis, +rule: Model.Rule,
  +direction: Allocation.ResolvedDirection, +slots: +List<Space.Slot<T>>, +available: Nat) ->
  PlanPopulation(~T, RuleSpaceLaws.slot_values(~T, slots), Allocation.prepare_slots(~T, ~key_of, ~clearance_of, key, axis, rule, direction, slots, available)):
  sequence_population(~T, ~key_of, ~clearance_of, Allocation.sequential(axis, direction), key, axis, slots, Allocation.rule_gap(rule),
    Allocation.resolved_canvas(direction, available, Allocation.canvas_size(Allocation.scrolls(axis, Allocation.rule_scroll(rule)), available, Allocation.required_canvas(~T, Allocation.sequential(axis, direction), slots, Allocation.rule_gap(rule)))),
    Allocation.axis_alignment(axis, direction, rule))

def inline_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +direction: Allocation.ResolvedDirection,
  proof: PlanPopulation(~Model.Tree<A, E>, children, result)) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_11(~A, ~E, result, direction)):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def inline_rule_unchecked_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule_unchecked(~A, ~E, rule, key, available, slots)):
  Model.Rule{+authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  +direction = Allocation.resolve_direction(authored, Space.minimum_sequence(~Model.Tree<A, E>, slots, Allocation.rule_gap(rule)), available)
  inline_wrapper_population(~A, ~E,
    Allocation.prepare_slots(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available),
    RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots), direction,
    slots_population(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available))

def inline_gap_population(~A: Data, ~E: Data, +valid: Bool, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_gap(~A, ~E, valid, rule, key, available, slots)):
  match valid:
    case False{}: {==}
    case True{}: inline_rule_unchecked_population(~A, ~E, rule, key, available, slots)

def inline_rule_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots)):
  inline_gap_population(~A, ~E, Allocation.layered_gap_valid(rule), rule, key, available, slots)

def inline_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +key: String, +rule: Model.Rule, +available: Nat,
  proof: SlotsPopulation(~Model.Tree<A, E>, children, result)) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_10(~A, ~E, result, key, rule, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Model.Tree<A, E>>, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots),
        (values => RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, values, Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots))),
        inline_rule_population(~A, ~E, rule, key, available, slots), children,
        Equal.sym(+List<Model.Tree<A, E>>, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, slots), children, proof))

def inline_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>, +available: Nat) ->
  RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, children, Allocation.prepare_inline_children(~A, ~E, key, rule, children, available)):
  inline_dispatch_population(~A, ~E, Allocation.width_slots(~A, ~E, children, available), children, key, rule, available,
    width_population(~A, ~E, children, available))

def block_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  proof: PlanPopulation(~Allocation.MeasuredTree<A, E>, children, result)) -> RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, children, result):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def block_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection, +available: Nat,
  proof: SlotsPopulation(~Allocation.MeasuredTree<A, E>, children, result)) ->
  RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, children, Allocation.dispatch_prepare_block_children_17(~A, ~E, result, key, rule, direction, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Allocation.MeasuredTree<A, E>>, RuleSpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots),
        (values => RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, values,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available))),
        block_wrapper_population(~A, ~E,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available),
          RuleSpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots),
          slots_population(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available)),
        children, Equal.sym(+List<Allocation.MeasuredTree<A, E>>, RuleSpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots), children, proof))

def block_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection,
  +children: +List<Allocation.MeasuredTree<A, E>>, +available: Nat) ->
  RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, children, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, available)):
  block_dispatch_population(~A, ~E, Allocation.height_slots(~A, ~E, children, available), children, key, rule, direction, available,
    height_population(~A, ~E, children, available))

def RulePhysicalAllocationPopulationRules.evidence(A, E):
  RulePhysicalAllocationPopulationRules.Requirements{
    +key => +rule => +children => +available => inline_population(~A, ~E, key, rule, children, available),
    +key => +rule => +direction => +children => +available => block_population(~A, ~E, key, rule, direction, children, available)}


def RulePhysicalAllocationPopulationRules.aligned_layer_bounds(outside, horizontal, vertical, rule, left, top, available_width, available_height, width, height):
  E.Insets{inline, block} = outside
  {==}

def RulePhysicalAllocationPopulationRules.aligned_layer_clearance(outside, horizontal, vertical): {==}

def root_position_policy(~A: Data, ~E: Data, +position: SpatialModel.Position, +tree: Allocation.MeasuredTree<A, E>, +offered: SpatialModel.Box, +offset: Nat, +height: Nat) ->
  RulePhysicalAllocationPopulationRules.RootBoundsPolicy(~A, ~E, position, tree, offered, offset, height, Allocation.root_bounds_position(~A, ~E, position, tree, offered, offset, height)):
  match position:
    case SpatialModel.InFlow{}: {==}
    case SpatialModel.CenteredLayer{outside}: {==}
    case SpatialModel.AlignedLayer{outside, horizontal, vertical}: {==}
    case SpatialModel.AnchoredLayer{key, anchor, outside, gap, alignment}: {==}

def RulePhysicalAllocationPopulationRules.root_position(A, E, tree, offered, offset, height):
  root_position_policy(~A, ~E, Model.rule_position(Allocation.measured_rule(~A, ~E, tree)), tree, offered, offset, height)

def RulePhysicalAllocationPopulationRules.root_width_clearance(A, E, slots, tree, width, samples):
  {==}

def RulePhysicalAllocationPopulationRules.root_height_clearance(A, E, slots, tree, offered):
  {==}

def RulePhysicalAllocationPopulationRules.root_allocation_bounds(A, E, tree, value, rest, offset, height, offered):
  {==}

def measured_preferred(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {ModelRules.preferred_covers_minimum(Allocation.measured_demand(~A, ~E, tree)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      outer_preferred(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      outer_preferred(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def RulePhysicalAllocationPopulationRules.measured_preferred(A, E, tree):
  measured_preferred(~A, ~E, tree)

def measured_authored_floor(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree)), ModelRules.rule_authored_minimum(Allocation.measured_rule(~A, ~E, tree))) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      outer_authored_floor(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      outer_authored_floor(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def RulePhysicalAllocationPopulationRules.measured_authored_floor(A, E, tree):
  measured_authored_floor(~A, ~E, tree)

def physical_height_proof_placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Nat:
  Allocation.height_forest_work(~A, ~E, RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def physical_height_proof_return_rank(~A: Data, ~E: Data, target: Allocation.HeightReturn<A, E>) -> Nat:
  match target:
    case Allocation.HeightRootReturn{}: 0n
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}:
      Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent)))

# These are W(tree)-1 and W(tree)-2 with the singleton forest's trailing zero removed.
def visit_rank(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) -> Nat:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      Nat.add(3n, parent)
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Nat.add(5n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))

def checked_rank(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) -> Nat:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      Nat.add(2n, parent)
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))

def plan_rank(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +parent: Nat) -> Nat:
  match plan:
    case Allocation.PlanningFailure{failure}: Nat.add(2n, parent)
    case Allocation.ChildrenPlanned{placements, canvas_height}: Nat.add(3n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), parent))

def physical_height_proof_rank(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Nat:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_rank(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_rank(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_rank(~A, ~E, plan, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightComplete{result, parent}: Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightDone{result}: 0n

def visit_nonzero(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_eq(visit_rank(~A, ~E, tree, parent), 0n) == False{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}: {==}

def checked_nonzero(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_eq(checked_rank(~A, ~E, tree, parent), 0n) == False{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}: {==}

def plan_nonzero(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +parent: Nat) ->
  {Nat.is_eq(plan_rank(~A, ~E, plan, parent), 0n) == False{} : Bool}:
  match plan:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas_height}: {==}

def rank_zero(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) ->
  {Nat.is_eq(physical_height_proof_rank(~A, ~E, state), 0n) == RulePhysicalHeightRules.completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_nonzero(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_nonzero(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_nonzero(~A, ~E, plan, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}: {==}
    case Allocation.HeightComplete{result, parent}: {==}
    case Allocation.HeightDone{result}: {==}

def decrease_claim(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Type:
  {Nat.is_le(physical_height_proof_rank(~A, ~E, Allocation.height_step(~A, ~E, state)), Nat.sub(physical_height_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}

def physical_height_proof_visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(checked_rank(~A, ~E, tree, parent), Nat.sub(visit_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: le_refl(Nat.add(2n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      le_refl(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)))

def minimum_failure_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(Nat.add(1n, parent), Nat.sub(checked_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: le_refl(Nat.add(1n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        le_add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent),
        add_comm(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent))

# A child visit replaces its reserved parent edge with its explicit return frame.
def child_resume_rank(+own: Nat, +rest: Nat, +parent: Nat) ->
  {Nat.add(own, Nat.add(2n, Nat.add(rest, parent))) == Nat.add(2n, Nat.add(Nat.add(own, rest), parent)) : Nat}:
  match own:
    case 0n: {==}
    case 1n+tail:
      Equal.cong(Nat, Nat, (value => 1n+value), Nat.add(tail, Nat.add(2n, Nat.add(rest, parent))),
        Nat.add(2n, Nat.add(Nat.add(tail, rest), parent)), child_resume_rank(tail, rest, parent))

def children_visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>, +parent: Nat) ->
  {Nat.is_le(visit_rank(~A, ~E, tree, Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.height_forest_work(~A, ~E, tree <> RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, remaining)), parent)), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      le_refl(Nat.add(5n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent)))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat,
        Nat.add(2n, Nat.add(Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), physical_height_proof_placement_work(~A, ~E, remaining)), parent)),
        (next => {Nat.is_le(next, Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), physical_height_proof_placement_work(~A, ~E, remaining)), parent))) == True{} : Bool}),
        le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), physical_height_proof_placement_work(~A, ~E, remaining)), parent))),
        Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent))),
        child_resume_rank(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), physical_height_proof_placement_work(~A, ~E, remaining), parent))

# This premise preserves the full ordered population, not only its numeric weight.
def planned_minimum_decrease(~A: Data, ~E: Data,
  +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: {RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements) == children : +List<Allocation.MeasuredTree<A, E>>}) ->
  {Nat.is_le(Nat.add(3n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), parent)),
    Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  Std.transport(+List<Allocation.MeasuredTree<A, E>>, children,
    (values => {Nat.is_le(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, values), parent)),
      Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))) == True{} : Bool}),
    le_refl(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))),
    RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements),
    population)

def minimum_container_decrease(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(plan_rank(~A, ~E, plan, parent), Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.PlanningFailure{failure}:
      Std.transport(Nat, Nat.add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        le_add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent),
        add_comm(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent))
    case Allocation.ChildrenPlanned{placements, canvas_height}: planned_minimum_decrease(~A, ~E, placements, children, parent, population)

def physical_height_proof_step_decrease(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>) -> decrease_claim(~A, ~E, state):
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: physical_height_proof_visit_decrease(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: minimum_failure_decrease(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}, bounds, lower, parent}:
      le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, value, interaction, +rule, width, offset, +direction, +children}, bounds, lower, parent}:
      match bounds:
        case SpatialModel.Box{left, top, offered_width, +offered_height}:
          minimum_container_decrease(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), children, physical_height_proof_return_rank(~A, ~E, parent),
            block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))))
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      le_refl(Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), physical_height_proof_return_rank(~A, ~E, parent))))
    case Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightChildren{Con{Space.Placement{child, offset, extent}, remaining}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      children_visit_decrease(~A, ~E, child, remaining, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: {==}
    case Allocation.HeightComplete{result, Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}}:
      le_refl(Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent))))
    case Allocation.HeightDone{result}: {==}

# The production budget reserves one more edge than the initial root needs.
def initial_fits(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, bounds: SpatialModel.Box) ->
  {Nat.is_le(physical_height_proof_rank(~A, ~E, Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        (bound => {Nat.is_le(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), bound) == True{} : Bool}),
        le_add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        Nat.add(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)),
        add_comm(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)))

def physical_height_proof_iteration_rank_zero(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) ->
  {physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)) == 0n : Nat}:
  iterate_rank_zero(~Allocation.HeightState<A, E>, ~(state => Allocation.height_step(~A, ~E, state)),
    ~(state => physical_height_proof_rank(~A, ~E, state)), ~(+state => physical_height_proof_step_decrease(~A, ~E, state)),
    Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}},
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), initial_fits(~A, ~E, tree, bounds))

def physical_height_proof_complete(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) -> RulePhysicalHeightRules.complete_claim(~A, ~E, tree, bounds):
  Equal.trans(Bool,
    RulePhysicalHeightRules.completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)),
    Nat.is_eq(physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n),
      RulePhysicalHeightRules.completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), rank_zero(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds))),
    Equal.cong(Nat, Bool, (value => Nat.is_eq(value, 0n)), physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n,
      physical_height_proof_iteration_rank_zero(~A, ~E, tree, bounds)))

def RulePhysicalHeightRules.evidence(A, E):
  RulePhysicalHeightRules.Requirements{+tree => +bounds => physical_height_proof_complete(~A, ~E, tree, bounds)}

# Work ranks count pending transitions, including each suspended parent edge.
def physical_width_proof_placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>) -> Nat:
  Allocation.width_forest_work(~A, ~E, RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements))

def physical_width_proof_return_rank(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>) -> Nat:
  match return_to:
    case Allocation.WidthRootReturn{}: 0n
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, parent)))

def visit_work(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> Nat:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: 4n
    case Model.Container{key, value, interaction, rule, +children}: Nat.add(5n, Allocation.width_forest_work(~A, ~E, children))

def checked_work(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> Nat:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: 3n
    case Model.Container{key, value, interaction, rule, +children}: Nat.add(4n, Allocation.width_forest_work(~A, ~E, children))

def plan_work(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>) -> Nat:
  match plan:
    case Allocation.InlineFailure{failure}: 2n
    case Allocation.InlinePlanned{placements, direction, canvas}: Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements))

def physical_width_proof_rank(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Nat:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}:
      Nat.add(visit_work(~A, ~E, tree), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}:
      Nat.add(checked_work(~A, ~E, tree), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}:
      Nat.add(2n, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}:
      Nat.add(plan_work(~A, ~E, plan), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}:
      Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthComplete{result, return_to}: Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthDone{result}: 0n

def visit_zero(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(visit_work(~A, ~E, tree), continuation), 0n) == False{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}: {==}

def checked_zero(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(checked_work(~A, ~E, tree), continuation), 0n) == False{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}: {==}

def plan_zero(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(plan_work(~A, ~E, plan), continuation), 0n) == False{} : Bool}:
  match plan:
    case Allocation.InlineFailure{failure}: {==}
    case Allocation.InlinePlanned{placements, direction, canvas}: {==}

def rank_zero_completed(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) ->
  {Nat.is_eq(physical_width_proof_rank(~A, ~E, state), 0n) == RulePhysicalWidthRules.completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: visit_zero(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}: checked_zero(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: {==}
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}: plan_zero(~A, ~E, plan, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}: {==}
    case Allocation.WidthComplete{result, return_to}: {==}
    case Allocation.WidthDone{result}: {==}

def physical_width_proof_visit_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(checked_work(~A, ~E, tree), continuation), Nat.sub(Nat.add(visit_work(~A, ~E, tree), continuation), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: le_refl(Nat.add(3n, continuation))
    case Model.Container{key, value, interaction, rule, +children}: le_refl(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation))

# A rejected minimum skips all child work; its continuation still completes.
def below_prefix(+value: Nat, +extra: Nat) -> {Nat.is_le(value, Nat.add(extra, value)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, Nat.add(extra, value)), Nat.is_le(value, Nat.add(value, extra)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(value, n)), Nat.add(extra, value), Nat.add(value, extra), add_comm(extra, value)), le_add(value, extra))

def rejected_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(1n, continuation), Nat.sub(Nat.add(checked_work(~A, ~E, tree), continuation), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: below_prefix(continuation, 1n)
    case Model.Container{key, value, interaction, rule, +children}: below_prefix(continuation, Nat.add(2n, Allocation.width_forest_work(~A, ~E, children)))

def child_rank_join(+work: Nat, +rest: Nat, +continuation: Nat) ->
  {Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))) == Nat.add(2n, Nat.add(Nat.add(work, rest), continuation)) : Nat}:
  Equal.trans(Nat,
    Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))),
    Nat.add(2n, Nat.add(work, Nat.add(rest, continuation))),
    Nat.add(2n, Nat.add(Nat.add(work, rest), continuation)),
    Equal.trans(Nat,
      Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))),
      1n+Nat.add(work, 1n+Nat.add(rest, continuation)),
      Nat.add(2n, Nat.add(work, Nat.add(rest, continuation))),
      Alg.nat_add_succ(work, 1n+Nat.add(rest, continuation)),
      Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(work, 1n+Nat.add(rest, continuation)), 1n+Nat.add(work, Nat.add(rest, continuation)), Alg.nat_add_succ(work, Nat.add(rest, continuation)))),
    Equal.cong(Nat, Nat, (n => Nat.add(2n, n)), Nat.add(work, Nat.add(rest, continuation)), Nat.add(Nat.add(work, rest), continuation),
      Equal.sym(Nat, Nat.add(Nat.add(work, rest), continuation), Nat.add(work, Nat.add(rest, continuation)), Alg.nat_add_assoc(work, rest, continuation))))

def child_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +rest: +List<Space.Placement<Model.Tree<A, E>>>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(visit_work(~A, ~E, tree), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.width_forest_work(~A, ~E, tree <> RuleSpaceLaws.placement_values(~Model.Tree<A, E>, rest)), continuation)), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}:
      le_refl(Nat.add(6n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation)))
    case Model.Container{key, value, interaction, rule, +children}:
      Equal.trans(Bool,
        Nat.is_le(Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))),
        Nat.is_le(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)))),
          Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)),
          child_rank_join(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), physical_width_proof_placement_work(~A, ~E, rest), continuation)),
        le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))))

# The ordered population premise is needed only at successful container planning.
def population_decrease(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: {RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements) == children : +List<Model.Tree<A, E>>}) ->
  {Nat.is_le(Nat.add(Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements)), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)),
    Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)), True{},
    Equal.cong(+List<Model.Tree<A, E>>, Bool,
      (trees => Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, trees)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation))),
      RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements), children, population),
    le_refl(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)))

def independent_claim(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> Type:
  match state:
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit
    case _:
      {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(physical_width_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}

def visit_checked_decrease(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +return_to: Allocation.WidthReturn<A, E>) ->
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, return_to)), Nat.sub(physical_width_proof_rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}), 1n)) == True{} : Bool}:
  match valid:
    case True{}: physical_width_proof_visit_decrease(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case False{}:
      match tree:
        case Model.Leaf{key, value, interaction, rule, demand, height}: below_prefix(physical_width_proof_return_rank(~A, ~E, return_to), 2n)
        case Model.Container{key, value, interaction, rule, +children}: below_prefix(physical_width_proof_return_rank(~A, ~E, return_to), Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)))

def independent_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> independent_claim(~A, ~E, state, samples):
  match state:
    case Allocation.WidthVisit{+tree, +width, +offset, +return_to}: visit_checked_decrease(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), return_to), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), return_to)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: rejected_decrease(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: le_refl(Nat.add(2n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit{}
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}: le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}: le_refl(Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, placements), physical_width_proof_return_rank(~A, ~E, return_to))))
    case Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}: le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}: child_decrease(~A, ~E, child, rest, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: {==}
    case Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}: le_refl(Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, parent))))
    case Allocation.WidthDone{result}: {==}

# Match the actual computed plan before consuming its population evidence.
def planned_decrease(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(Nat.add(plan_work(~A, ~E, plan), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.InlineFailure{failure}: below_prefix(continuation, Nat.add(1n, Allocation.width_forest_work(~A, ~E, children)))
    case Allocation.InlinePlanned{placements, direction, canvas}: population_decrease(~A, ~E, placements, children, continuation, population)

def physical_width_proof_step_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) ->
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(physical_width_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}, samples)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, value, interaction, +rule, +children}, +width, offset, checked_rule, lower, return_to}:
      planned_decrease(~A, ~E,
        Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))),
        children, physical_width_proof_return_rank(~A, ~E, return_to),
        inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))))
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}, samples)
    case Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}, samples)
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}, samples)
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}, samples)
    case Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}: independent_decrease(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}, samples)
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}: independent_decrease(~A, ~E, Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}, samples)
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: independent_decrease(~A, ~E, Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}, samples)
    case Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}: independent_decrease(~A, ~E, Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}, samples)
    case Allocation.WidthDone{result}: independent_decrease(~A, ~E, Allocation.WidthDone{result}, samples)

def seed_in_budget(~A: Data, ~E: Data, tree: Model.Tree<A, E>) ->
  {Nat.is_le(visit_work(~A, ~E, tree), Allocation.width_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}:
      Equal.trans(Bool,
        Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, Nat.add(Allocation.width_forest_work(~A, ~E, children), 0n))),
        Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, Allocation.width_forest_work(~A, ~E, children))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, n))),
          Nat.add(Allocation.width_forest_work(~A, ~E, children), 0n), Allocation.width_forest_work(~A, ~E, children), Alg.nat_add_zero(Allocation.width_forest_work(~A, ~E, children))),
        below_prefix(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), 1n))

def initial_in_budget(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat) ->
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}), Allocation.width_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(visit_work(~A, ~E, tree), 0n), Allocation.width_forest_work(~A, ~E, tree <> Nil{})),
    Nat.is_le(visit_work(~A, ~E, tree), Allocation.width_forest_work(~A, ~E, tree <> Nil{})), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, Allocation.width_forest_work(~A, ~E, tree <> Nil{}))),
      Nat.add(visit_work(~A, ~E, tree), 0n), visit_work(~A, ~E, tree), Alg.nat_add_zero(visit_work(~A, ~E, tree))), seed_in_budget(~A, ~E, tree))

def execution_rank(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) -> Nat:
  physical_width_proof_rank(~A, ~E, Allocation.width_execution_state(~A, ~E, execution))

def execution_decrease(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) ->
  {Nat.is_le(execution_rank(~A, ~E, Allocation.width_execution_step(~A, ~E, execution)), Nat.sub(execution_rank(~A, ~E, execution), 1n)) == True{} : Bool}:
  Allocation.WidthExecution{state, samples} = execution
  physical_width_proof_step_decrease(~A, ~E, state, samples)

def physical_width_proof_iteration_rank_zero(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  {physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)) == 0n : Nat}:
  iterate_rank_zero(~Allocation.WidthExecution<A, E>, ~(execution => Allocation.width_execution_step(~A, ~E, execution)), ~(execution => execution_rank(~A, ~E, execution)),
    ~(+execution => execution_decrease(~A, ~E, execution)),
    Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, Allocation.width_forest_work(~A, ~E, tree <> Nil{}),
    initial_in_budget(~A, ~E, tree, width, offset))

def physical_width_proof_complete(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> RulePhysicalWidthRules.complete_claim(~A, ~E, tree, width, offset, samples):
  Equal.trans(Bool,
    RulePhysicalWidthRules.completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
    Nat.is_eq(physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n),
      RulePhysicalWidthRules.completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
      rank_zero_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples))),
    Equal.cong(Nat, Bool, (n => Nat.is_eq(n, 0n)), physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n,
      physical_width_proof_iteration_rank_zero(~A, ~E, tree, width, offset, samples)))

def RulePhysicalWidthRules.evidence(A, E):
  RulePhysicalWidthRules.Requirements{+tree => +width => +offset => +samples => physical_width_proof_complete(~A, ~E, tree, width, offset, samples)}

# Continuations reconstruct the successful source from fields consumed by the
# next production transition. The accumulated results retain their original order.
def placement_sources(~A: Data, ~E: Data, placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> +List<Model.Tree<A, E>>:
  Allocation.source_forest_measured(~A, ~E, RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def physical_height_source_proof_outcome_source(~A: Data, ~E: Data, result: Allocation.PositionedOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.Positioned{tree}: Some{Allocation.source_of_allocated(~A, ~E, tree)}
    case Allocation.PositionFailure{failure}: None{}

def physical_height_source_proof_cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def physical_height_source_proof_outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.PositionedOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{first, rest}: physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, rest))

def physical_height_source_proof_append_source(~A: Data, ~E: Data, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Model.Tree<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match previous:
    case None{}: None{}
    case Some{values}: Some{List.append(&2, Model.Tree<A, E>, values, remaining)}

def physical_height_source_proof_container_source(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, children: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, Model.Tree<A, E>>:
  match children:
    case None{}: None{}
    case Some{values}: Some{Model.Container{key, value, interaction, rule, values}}

def physical_height_source_proof_child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: physical_height_source_proof_append_source(~A, ~E, previous, tree <> placement_sources(~A, ~E, remaining))

def physical_height_source_proof_child_sources(~A: Data, ~E: Data, previous: +List<Allocation.PositionedOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  physical_height_source_proof_child_sources_from_erased(~A, ~E, current, physical_height_source_proof_outcome_sources(~A, ~E, previous), remaining)

def physical_height_source_proof_return_source(~A: Data, ~E: Data, return_to: Allocation.HeightReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.HeightRootReturn{}: current
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_child_sources(~A, ~E, previous, current, remaining)))

def physical_height_source_proof_plan_source(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.PlanningFailure{failure}: None{}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Some{Model.Container{key, value, interaction, rule, placement_sources(~A, ~E, placements)}}

def physical_height_source_proof_state_source(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: physical_height_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.HeightMinimumChecked{True{}, tree, bounds, lower, parent}: physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule,
        physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), placement_sources(~A, ~E, remaining))))
    case Allocation.HeightComplete{result, parent}: physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_outcome_source(~A, ~E, result))
    case Allocation.HeightDone{result}: physical_height_source_proof_outcome_source(~A, ~E, result)

def physical_height_source_proof_partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def physical_height_source_proof_return_none(~A: Data, ~E: Data, parent: Allocation.HeightReturn<A, E>) ->
  {physical_height_source_proof_return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.HeightRootReturn{}: {==}
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, rest}:
      physical_height_source_proof_return_none(~A, ~E, rest)

def physical_height_source_proof_return_drop(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => physical_height_source_proof_partial_match(~A, ~E, actual, expected)), {==},
    physical_height_source_proof_return_source(~A, ~E, parent, None{}), physical_height_source_proof_return_none(~A, ~E, parent))

def physical_height_source_proof_return_same(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def allocated_children_source(~A: Data, ~E: Data, children: Allocation.AllocatedChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.AllocationFailed{failure}: None{}
    case Allocation.ChildrenAllocated{trees}: Some{Allocation.source_forest_allocated(~A, ~E, trees)}

def physical_height_source_proof_merge_source(~A: Data, ~E: Data, +first: Allocation.PositionedOutcome<A, E>, +rest: Allocation.AllocatedChildren<A, E>) ->
  {allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, rest)) ==
    physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.PositionFailure{failure} _: {==}
    case Allocation.Positioned{tree} Allocation.AllocationFailed{failure}: {==}
    case Allocation.Positioned{Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}} Allocation.ChildrenAllocated{trees}: {==}
    case Allocation.Positioned{Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}} Allocation.ChildrenAllocated{trees}: {==}

def physical_height_source_proof_collected_source(~A: Data, ~E: Data, +values: +List<Allocation.PositionedOutcome<A, E>>) ->
  {allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, values)) ==
    physical_height_source_proof_outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, rest)),
        physical_height_source_proof_merge_source(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), trees)),
          allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest)), physical_height_source_proof_outcome_sources(~A, ~E, rest), physical_height_source_proof_collected_source(~A, ~E, rest)))

def physical_height_source_proof_append_empty(~A: Data, ~E: Data, +values: Maybe<&2, +List<Model.Tree<A, E>>>) ->
  {physical_height_source_proof_append_source(~A, ~E, values, Nil{}) == values : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case None{}: {==}
    case Some{+trees}:
      Equal.cong(+List<Model.Tree<A, E>>, Maybe<&2, +List<Model.Tree<A, E>>>,
        (children => Some{children}), List.append(&2, Model.Tree<A, E>, trees, Nil{}), trees, Std.app_nil_r(Model.Tree<A, E>, trees))

def physical_height_source_proof_append_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +remaining: +List<Model.Tree<A, E>>) ->
  {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, first, rest), remaining) ==
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, rest, remaining)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case None{} _: {==}
    case Some{tree} None{}: {==}
    case Some{tree} Some{trees}: {==}

def physical_height_source_proof_child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    physical_height_source_proof_child_sources_from_erased(~A, ~E, current, physical_height_source_proof_cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, first, rest), tree <> placement_sources(~A, ~E, remaining)),
      physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, rest, tree <> placement_sources(~A, ~E, remaining))),
      physical_height_source_proof_append_cons(~A, ~E, first, rest, tree <> placement_sources(~A, ~E, remaining)))

def physical_height_source_proof_append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  same: {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))) ==
    physical_height_source_proof_child_sources_from_erased(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, current), physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining)),
    physical_height_source_proof_child_sources_from_erased(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, current), physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => physical_height_source_proof_cons_source(~A, ~E, first, trees)),
      physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)), physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining), same),
    physical_height_source_proof_child_cons(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest), physical_height_source_proof_outcome_source(~A, ~E, current), remaining))

def physical_height_source_proof_append_current(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.Positioned{tree}: {==}
    case Nil{} Allocation.PositionFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{}))), placement_sources(~A, ~E, remaining)),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
        physical_height_source_proof_child_sources(~A, ~E, first <> rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining),
        physical_height_source_proof_append_cons(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)),
        physical_height_source_proof_append_current_cons(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), rest, current, remaining, physical_height_source_proof_append_current(~A, ~E, rest, current, remaining)))

def physical_height_source_proof_return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  same: physical_height_source_proof_partial_match(~A, ~E, actual, source),
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: physical_height_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{tree}: physical_height_source_proof_return_same(~A, ~E, parent, tree, source, expected, same, proof)

def physical_height_source_proof_checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box, +lower: Nat, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}), expected):
  match fits:
    case False{}: physical_height_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: proof

def physical_height_source_proof_plan_preserved(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Allocation.MeasuredTree<A, E>>,
  population: RulePhysicalAllocationPopulationRules.BlockPopulation(~A, ~E, children, plan)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}):
  match plan:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Equal.cong(+List<Allocation.MeasuredTree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, trees)}),
        RuleSpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements), children, population)

def physical_height_source_proof_finish_children_source(~A: Data, ~E: Data, +result: Allocation.AllocatedChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: SpatialModel.Box, +canvas: E.Extent, +direction: Allocation.ResolvedDirection) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, result)) ==
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.AllocationFailed{failure}: {==}
    case Allocation.ChildrenAllocated{trees}: {==}

def physical_height_source_proof_finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: SpatialModel.Box, +canvas: E.Extent, +direction: Allocation.ResolvedDirection) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))) ==
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})),
    physical_height_source_proof_finish_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous), key, value, interaction, rule, bounds, canvas, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, trees)),
      allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), physical_height_source_proof_outcome_sources(~A, ~E, previous), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
        physical_height_source_proof_collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}), physical_height_source_proof_outcome_sources(~A, ~E, previous), physical_height_source_proof_append_empty(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous))))))

def physical_height_source_proof_state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: physical_height_source_proof_partial_match(~A, ~E, before, expected)) -> physical_height_source_proof_partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => physical_height_source_proof_partial_match(~A, ~E, source, expected)), proof, after, same)

def leaf_demand_same(~A: Data, ~E: Data, +demand: Space.Demand, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +height: Model.Height, +bounds: SpatialModel.Box, +content_height: Nat, +inner_width: Nat, +inner_height: Nat) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocate_leaf_demand(~A, ~E, demand, key, value, interaction, rule, height, bounds, content_height, inner_width, inner_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match demand:
    case Space.Demand{E.Extent{min_width, min_height}, preferred}: {==}

def leaf_same(~A: Data, ~E: Data, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +bounds: SpatialModel.Box, +content_height: Nat) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match bounds:
    case SpatialModel.Box{left, top, +width, +block_height}:
      leaf_demand_same(~A, ~E, demand, key, value, interaction, rule, height, SpatialModel.Box{left, top, width, block_height}, content_height,
        Nat.sub(width, Nat.mul(2n, Allocation.axis_inset(Allocation.InlineAxis{}, rule))), Nat.sub(block_height, Nat.mul(2n, Allocation.axis_inset(Allocation.BlockAxis{}, rule))))

def physical_height_source_proof_step_preserved(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Allocation.height_step(~A, ~E, state)), expected):
  match state:
    case Allocation.HeightVisit{+tree, +bounds, +parent}:
      physical_height_source_proof_checked_preserved(~A, ~E, Nat.is_le(Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), Allocation.box_height(bounds)), tree, bounds,
        Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: proof
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{+key, +value, +interaction, +rule, +demand, +height, outer_width, inline_offset, +content_height}, +bounds, lower, +parent}:
      physical_height_source_proof_state_same(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}),
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height))), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_height_source_proof_return_source(~A, ~E, parent, source)),
          physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), Some{Model.Leaf{key, value, interaction, rule, demand, height}},
          leaf_same(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), proof)
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, +value, +interaction, +rule, outer_width, inline_offset, +direction, +children}, SpatialModel.Box{+left, +top, +width, +offered_height}, lower, +parent}:
      physical_height_source_proof_return_option(~A, ~E,
        physical_height_source_proof_plan_source(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}, parent, expected,
        physical_height_source_proof_plan_preserved(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule, children,
          block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule))))), proof)
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightChildren{Nil{}, +key, +value, +interaction, +rule, +bounds, +canvas, +direction, +content_left, +content_top, +previous, +parent}:
      physical_height_source_proof_state_same(~A, ~E,
        physical_height_source_proof_state_source(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}),
        physical_height_source_proof_state_source(~A, ~E, Allocation.height_step(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent})), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_height_source_proof_return_source(~A, ~E, parent, source)),
          physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
          physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})), physical_height_source_proof_finish_source(~A, ~E, previous, key, value, interaction, rule, bounds, canvas, direction)), proof)
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredLeaf{child_key, child_value, child_interaction, child_rule, demand, height, outer_width, inline_offset, content_height}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredContainer{child_key, child_value, child_interaction, child_rule, outer_width, inline_offset, child_direction, children}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: proof
    case Allocation.HeightComplete{+result, Allocation.HeightContainerReturn{+key, +value, +interaction, +rule, bounds, canvas, direction, content_left, content_top, +remaining, +previous, +parent}}:
      physical_height_source_proof_state_same(~A, ~E,
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, result), remaining))),
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, children))),
          physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)),
          physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, result), remaining), physical_height_source_proof_append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.HeightDone{result}: proof

def physical_height_source_proof_iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), budget, state)), expected):
  Std.nat_ind(~(n => @+seed:Allocation.HeightState<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, seed), source) ->
    physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed)), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => physical_height_source_proof_step_preserved(~A, ~E,
      Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(state, expected, proof)

def physical_height_source_proof_finish_completed(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +key: String, +height: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {RulePhysicalHeightRules.completed(~A, ~E, state) == True{} : Bool},
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.finish_height_iteration(~A, ~E, state, key, height, budget)):
  match state:
    case Allocation.HeightDone{Allocation.Positioned{tree}}: proof
    case Allocation.HeightDone{Allocation.PositionFailure{failure}}: {==}
    case Allocation.HeightVisit{tree, bounds, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightComplete{result, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)

def physical_height_source_proof_preserved(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) ->
  RulePhysicalSourceRules.height_source_source_claim(~A, ~E, Allocation.source_of_measured(~A, ~E, tree), Allocation.allocate_measured(~A, ~E, tree, bounds)):
  physical_height_source_proof_finish_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds), Allocation.measured_key(~A, ~E, tree), Allocation.box_height(bounds),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.source_of_measured(~A, ~E, tree),
    physical_height_proof_complete(~A, ~E, tree, bounds),
    physical_height_source_proof_iterate_preserved(~A, ~E, Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}, Allocation.source_of_measured(~A, ~E, tree), {==}))

def RulePhysicalSourceRules.height_source_evidence(A, E):
  RulePhysicalSourceRules.HeightSourceRequirements{+tree => +bounds => physical_height_source_proof_preserved(~A, ~E, tree, bounds)}

def stale(+generation: Nat, +receipts: +List<String>, +engine: World.Engine,
  proof: {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == False{} : Bool}) ->
  RuleContract.stale_claim(generation, receipts, engine):
  Std.transport(Bool, False{},
    (current => {World.receive_current(current, receipts, engine) == engine : World.Engine}),
    {==}, Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))),
    proof)

def rejected_member(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch) ->
  {World.measurement_valid_member(False{}, valid, request, observation, batch)
    == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}:
  match batch:
    case World.Batch{observations, viewports}: {==}


def rejection(+valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: World.Batch,
  proof: {RulePhysicalContentRules.observation_matches(request, observation) == False{} : Bool}) ->
  RuleContract.rejected_measurement_claim(valid, request, observation, batch):
  Std.transport(Bool, False{},
    (member => {World.measurement_valid_member(member, valid, request, observation, batch)
      == Fail{"invalid or duplicate physical measurement"} : Result<&2, &2, String, World.Batch>}),
    rejected_member(valid, request, observation, batch), RulePhysicalContentRules.observation_matches(request, observation),
    proof)


def production(+engine: World.Engine) -> RuleContract.production_claim(engine):
  match engine:
    case World.Engine{snapshot, viewport, observations, viewports, status}: {==}

def RuleContract.evidence():
  RuleContract.Requirements{+generation => +receipts => +engine => proof => stale(generation, receipts, engine, proof),
    +valid => +request => +observation => +batch => proof => rejection(valid, request, observation, batch, proof),
    +engine => production(engine), RulePhysicalWidthRules.evidence(~Content.Value, ~Doc.DOMEvent),
    RulePhysicalHeightRules.evidence(~Content.Value, ~Doc.DOMEvent), RulePhysicalAllocationPopulationRules.evidence(~Content.Value, ~Doc.DOMEvent)}

# The partial source observes only fields consumed by production. A failed or
# pending child makes the enclosing computation incapable of a ready result.
def physical_width_source_proof_outcome_source(~A: Data, ~E: Data, result: Allocation.WidthOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.WidthReady{tree}: Some{Allocation.source_of_measured(~A, ~E, tree)}
    case Allocation.HeightPending{first, remaining}: None{}
    case Allocation.WidthFailure{failure}: None{}

def physical_width_source_proof_cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def physical_width_source_proof_outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.WidthOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{first, rest}: physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, rest))

def physical_width_source_proof_append_source(~A: Data, ~E: Data, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Model.Tree<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match previous:
    case None{}: None{}
    case Some{values}: Some{List.append(&2, Model.Tree<A, E>, values, remaining)}

def physical_width_source_proof_container_source(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, children: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, Model.Tree<A, E>>:
  match children:
    case None{}: None{}
    case Some{values}: Some{Model.Container{key, value, interaction, rule, values}}

def physical_width_source_proof_child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: physical_width_source_proof_append_source(~A, ~E, previous, tree <> RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))

def physical_width_source_proof_child_sources(~A: Data, ~E: Data, previous: +List<Allocation.WidthOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  physical_width_source_proof_child_sources_from_erased(~A, ~E, current, physical_width_source_proof_outcome_sources(~A, ~E, previous), remaining)

def physical_width_source_proof_return_source(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.WidthRootReturn{}: current
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_child_sources(~A, ~E, previous, current, remaining)))

def physical_width_source_proof_plan_source(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.InlineFailure{failure}: None{}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Some{Model.Container{key, value, interaction, rule, RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements)}}

def physical_width_source_proof_state_source(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.WidthVisit{tree, width, offset, parent}: physical_width_source_proof_return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: physical_width_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.WidthMinimumChecked{True{}, tree, width, offset, rule, lower, parent}: physical_width_source_proof_return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: physical_width_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}})
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule,
        physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))))
    case Allocation.WidthComplete{result, parent}: physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_outcome_source(~A, ~E, result))
    case Allocation.WidthDone{result}: physical_width_source_proof_outcome_source(~A, ~E, result)

def physical_width_source_proof_partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def physical_width_source_proof_return_none(~A: Data, ~E: Data, parent: Allocation.WidthReturn<A, E>) ->
  {physical_width_source_proof_return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.WidthRootReturn{}: {==}
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, rest}:
      physical_width_source_proof_return_none(~A, ~E, rest)

def physical_width_source_proof_return_drop(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => physical_width_source_proof_partial_match(~A, ~E, actual, expected)), {==},
    physical_width_source_proof_return_source(~A, ~E, parent, None{}), physical_width_source_proof_return_none(~A, ~E, parent))

def physical_width_source_proof_return_same(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def measured_children_source(~A: Data, ~E: Data, children: Allocation.MeasuredChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.ChildrenFailed{failure}: None{}
    case Allocation.ChildrenPending{first, remaining}: None{}
    case Allocation.ChildrenMeasured{trees}: Some{Allocation.source_forest_measured(~A, ~E, trees)}

def physical_width_source_proof_merge_source(~A: Data, ~E: Data, +first: Allocation.WidthOutcome<A, E>, +rest: Allocation.MeasuredChildren<A, E>) ->
  {measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, rest)) ==
    physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), measured_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.WidthFailure{failure} _: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenPending{next, tail}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.WidthReady{Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, sample}} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, children}} Allocation.ChildrenMeasured{trees}: {==}

def physical_width_source_proof_collected_source(~A: Data, ~E: Data, +values: +List<Allocation.WidthOutcome<A, E>>) ->
  {measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, values)) ==
    physical_width_source_proof_outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest))),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest))),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, rest)),
        physical_width_source_proof_merge_source(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), trees)),
          measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest)), physical_width_source_proof_outcome_sources(~A, ~E, rest), physical_width_source_proof_collected_source(~A, ~E, rest)))

def physical_width_source_proof_append_empty(~A: Data, ~E: Data, +values: Maybe<&2, +List<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_append_source(~A, ~E, values, Nil{}) == values : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case None{}: {==}
    case Some{+trees}:
      Equal.cong(+List<Model.Tree<A, E>>, Maybe<&2, +List<Model.Tree<A, E>>>,
        (children => Some{children}), List.append(&2, Model.Tree<A, E>, trees, Nil{}), trees, Std.app_nil_r(Model.Tree<A, E>, trees))

def physical_width_source_proof_append_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +remaining: +List<Model.Tree<A, E>>) ->
  {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, first, rest), remaining) ==
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, rest, remaining)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case None{} _: {==}
    case Some{tree} None{}: {==}
    case Some{tree} Some{trees}: {==}

def physical_width_source_proof_child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    physical_width_source_proof_child_sources_from_erased(~A, ~E, current, physical_width_source_proof_cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, first, rest), tree <> RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
      physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, rest, tree <> RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
      physical_width_source_proof_append_cons(~A, ~E, first, rest, tree <> RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)))

def physical_width_source_proof_append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>,
  same: {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)) ==
    physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))) ==
    physical_width_source_proof_child_sources_from_erased(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, current), physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining)),
    physical_width_source_proof_child_sources_from_erased(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, current), physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => physical_width_source_proof_cons_source(~A, ~E, first, trees)),
      physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)), physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining), same),
    physical_width_source_proof_child_cons(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest), physical_width_source_proof_outcome_source(~A, ~E, current), remaining))

def physical_width_source_proof_append_current(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)) ==
    physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.WidthReady{tree}: {==}
    case Nil{} Allocation.HeightPending{first, tail}: {==}
    case Nil{} Allocation.WidthFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{}))), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
        physical_width_source_proof_child_sources(~A, ~E, first <> rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining),
        physical_width_source_proof_append_cons(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
        physical_width_source_proof_append_current_cons(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), rest, current, remaining, physical_width_source_proof_append_current(~A, ~E, rest, current, remaining)))

def physical_width_source_proof_return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  same: physical_width_source_proof_partial_match(~A, ~E, actual, source),
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{tree}: physical_width_source_proof_return_same(~A, ~E, parent, tree, source, expected, same, proof)

def physical_width_source_proof_checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, parent}), expected):
  match fits:
    case False{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: proof

def visit_preserved(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, parent)), expected):
  match valid:
    case False{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: physical_width_source_proof_checked_preserved(~A, ~E, Nat.is_le(lower, width), tree, width, offset, rule, lower, parent, expected, proof)

def leaf_preserved(~A: Data, ~E: Data, +sample: Maybe<&2, Nat>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +inner_width: Nat, +width: Nat, +offset: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}), expected):
  match sample:
    case None{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{sample}: proof

def physical_width_source_proof_plan_preserved(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>,
  population: RulePhysicalAllocationPopulationRules.InlinePopulation(~A, ~E, children, plan)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, children}):
  match plan:
    case Allocation.InlineFailure{failure}: {==}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, trees}), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements), children, population)

def physical_width_source_proof_finish_children_source(~A: Data, ~E: Data, +result: Allocation.MeasuredChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, result)) ==
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.ChildrenFailed{failure}: {==}
    case Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.ChildrenMeasured{trees}: {==}

def physical_width_source_proof_finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))) ==
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous))),
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})),
    physical_width_source_proof_finish_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous), key, value, interaction, rule, width, offset, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, trees)),
      measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), physical_width_source_proof_outcome_sources(~A, ~E, previous), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
        physical_width_source_proof_collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}), physical_width_source_proof_outcome_sources(~A, ~E, previous), physical_width_source_proof_append_empty(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous))))))

def physical_width_source_proof_state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: physical_width_source_proof_partial_match(~A, ~E, before, expected)) -> physical_width_source_proof_partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => physical_width_source_proof_partial_match(~A, ~E, source, expected)), proof, after, same)

def physical_width_source_proof_step_preserved(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), expected):
  match state:
    case Allocation.WidthVisit{+tree, +width, offset, +parent}:
      visit_preserved(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), parent), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: proof
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, +rule, demand, +height}, +width, offset, checked_rule, lower, parent}:
      leaf_preserved(~A, ~E, Allocation.leaf_height(height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), samples), key, value, interaction, rule, demand, height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), width, offset, parent, expected, proof)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, +value, +interaction, +rule, +children}, +width, offset, checked_rule, lower, +parent}:
      physical_width_source_proof_return_option(~A, ~E,
        physical_width_source_proof_plan_source(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, children}, parent, expected,
        physical_width_source_proof_plan_preserved(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule, children,
          inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))))), proof)
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthChildren{Nil{}, +key, +value, +interaction, +rule, +width, +offset, +direction, +previous, +parent}:
      physical_width_source_proof_state_same(~A, ~E,
        physical_width_source_proof_state_source(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}),
        physical_width_source_proof_state_source(~A, ~E, Allocation.width_step(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}, samples)), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_width_source_proof_return_source(~A, ~E, parent, source)),
          physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
          physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})), physical_width_source_proof_finish_source(~A, ~E, previous, key, value, interaction, rule, width, offset, direction)), proof)
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, parent}: proof
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: proof
    case Allocation.WidthComplete{+result, Allocation.WidthContainerReturn{+key, +value, +interaction, +rule, width, offset, direction, +remaining, +previous, +parent}}:
      physical_width_source_proof_state_same(~A, ~E,
        physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, result), remaining))),
        physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, children))),
          physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), RuleSpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
          physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, result), remaining), physical_width_source_proof_append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.WidthDone{result}: proof

def execution_preserved(~A: Data, ~E: Data, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Allocation.width_execution_step(~A, ~E, execution))), expected):
  match execution:
    case Allocation.WidthExecution{state, samples}: physical_width_source_proof_step_preserved(~A, ~E, state, samples, expected, proof)

def physical_width_source_proof_iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), budget, execution))), expected):
  Std.nat_ind(~(n => @+seed:Allocation.WidthExecution<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, seed)), source) ->
    physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed))), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => execution_preserved(~A, ~E,
      Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(execution, expected, proof)

def outcome_preserved(~A: Data, ~E: Data, +result: Allocation.WidthOutcome<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, result), expected)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, result):
  match result:
    case Allocation.WidthReady{tree}: proof
    case Allocation.HeightPending{first, remaining}: {==}
    case Allocation.WidthFailure{failure}: {==}

def physical_width_source_proof_finish_completed(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +key: String, +width: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {RulePhysicalWidthRules.completed(~A, ~E, state) == True{} : Bool},
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, state), expected)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.finish_width_iteration(~A, ~E, state, key, width, budget)):
  match state:
    case Allocation.WidthDone{+result}: outcome_preserved(~A, ~E, result, expected, proof)
    case Allocation.WidthVisit{tree, extent, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthMinimumChecked{fits, tree, extent, offset, rule, lower, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthLeafHeight{sample, leaf_key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthContainerPlan{plan, container_key, value, interaction, rule, outer_width, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthChildren{remaining, container_key, value, interaction, rule, outer_width, offset, direction, previous, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthComplete{result, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)

def measure_preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.measure_at(~A, ~E, tree, width, offset, samples)):
  physical_width_source_proof_finish_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples), Allocation.tree_key(~A, ~E, tree), width, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), tree,
    physical_width_proof_complete(~A, ~E, tree, width, offset, samples),
    physical_width_source_proof_iterate_preserved(~A, ~E, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, tree, {==}))

def first_tree(~A: Data, ~E: Data, values: +List<Model.Tree<A, E>>, fallback: Model.Tree<A, E>) -> Model.Tree<A, E>:
  match values:
    case Nil{}: fallback
    case Con{first, remaining}: first

def root_preserved(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: {RuleSpaceLaws.placement_values(~Model.Tree<A, E>, placements) == tree <> Nil{} : +List<Model.Tree<A, E>>}) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.root_measurement(~A, ~E, tree, placements, samples)):
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{+value, offset, extent}, rest}:
      Std.transport(Model.Tree<A, E>, value,
        (source => RulePhysicalSourceRules.width_source_source_claim(~A, ~E, source, Allocation.measure_at(~A, ~E, value, extent, offset, samples))),
        measure_preserved(~A, ~E, value, extent, offset, samples), tree,
        Equal.sym(Model.Tree<A, E>, value, tree,
          Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>, (values => first_tree(~A, ~E, values, value)),
            RuleSpaceLaws.placement_values(~Model.Tree<A, E>, Space.Placement{value, offset, extent} <> rest), tree <> Nil{}, population)))

def packed_preserved(~A: Data, ~E: Data, +packing: Space.Packing<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: PackingPopulation(~Model.Tree<A, E>, tree <> Nil{}, packing)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_16(~A, ~E, packing, tree, samples)):
  match packing:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}: root_preserved(~A, ~E, placements, tree, samples, population)

def slots_preserved(~A: Data, ~E: Data, +slots: Allocation.SlotsOutcome<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>,
  population: SlotsPopulation(~Model.Tree<A, E>, tree <> Nil{}, slots)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_15(~A, ~E, slots, tree, width, samples)):
  match slots:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{+values}:
      packed_preserved(~A, ~E, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree, samples,
        Std.transport(+List<Model.Tree<A, E>>, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, values),
          (children => PackingPopulation(~Model.Tree<A, E>, children, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))))),
          shared_population(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree <> Nil{}, Equal.sym(+List<Model.Tree<A, E>>, RuleSpaceLaws.slot_values(~Model.Tree<A, E>, values), tree <> Nil{}, population)))

def physical_width_source_proof_preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.fit_width(~A, ~E, tree, width, samples)):
  slots_preserved(~A, ~E, Allocation.width_slots(~A, ~E, tree <> Nil{}, width), tree, width, samples,
    width_population(~A, ~E, tree <> Nil{}, width))

def RulePhysicalSourceRules.width_source_evidence(A, E):
  RulePhysicalSourceRules.WidthSourceRequirements{+tree => +width => +samples => physical_width_source_proof_preserved(~A, ~E, tree, width, samples)}
