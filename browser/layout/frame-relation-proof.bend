import Base
import ../../interaction/IDENTITY.bend as Identity
import ./GEOMETRY.bend as SpatialModel
import ../appearance/TYPOGRAPHY.bend as T
import ./enclosure.bend as E
import ./SPACE.bend as Space
import ../appearance/DESIGN.bend as D
import ../appearance/MODEL.bend as A
import ../controls/PROGRAM.bend as C
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ./frame-relation-laws.bend as Rule

def content_preserves_arrangement(+value: D.Style, content: E.ContentArea) ->
  {E.frame_gap(D.style_frame(A.with_content_area(value, content))) == E.frame_gap(D.style_frame(value)) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, E.Frame{old_content, arrangement}, minimum, maximum, states} = value
  {==}

def actual_choice_geometry(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {Rule.actual_geometry(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_layout(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_mark_contains_icon(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {Nat.is_le(Rule.mark_icon_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context))), Rule.mark_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def selection_keeps_allocation(+key: Identity.Key, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout}:
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

def actual_choice_normalization(+key: Identity.Key, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String,
  +role: InterfaceView.Role, +context: C.Context, +fallback: D.Style, +typography: T.Presentation) -> Rule.actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography):
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

def Rule.evidence():
  Rule.Requirements{
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
