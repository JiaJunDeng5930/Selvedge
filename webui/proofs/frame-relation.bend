import Base
import ../typography.bend as T
import ../enclosure.bend as E
import ../space.bend as Space
import ../design.bend as D
import ../appearance.bend as A
import ../controls.bend as C
import ../renderer.bend as R
import ../document.bend as Doc
import ../enclosure-render-laws.bend as EnclosureRender
import ../../core/interface.bend as UI
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../frame-relation-laws.bend as Rule
import ./enclosure-render.bend as EnclosureRenderProof

def content_preserves_arrangement(+value: D.Style, content: E.ContentArea) ->
  {E.frame_gap(D.style_frame(A.with_content_area(value, content))) == E.frame_gap(D.style_frame(value)) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, E.Frame{old_content, arrangement}, minimum, maximum, states} = value
  {==}

def actual_choice_geometry(+key: String, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {Rule.actual_geometry(C.make_choice(key, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_layout(+key: String, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_mark_contains_icon(+key: String, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {Nat.is_le(Rule.mark_icon_extent(C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context))), Rule.mark_extent(C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def selection_keeps_allocation(+key: String, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def choice_group_gap(+key: String, +label: String, +visual: D.Style, +children: +List<Doc.Node>, +typography: T.Presentation) ->
  {R.attr(Doc.element_styles(R.choice_group_node(key, label, A.choice_group_style(visual), children, typography)), "gap") == R.px(E.separation(E.MenuItems{})) : String}:
  D.Style{text, D.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  E.Frame{content, arrangement} = frame
  +normalized = A.choice_group_style(D.Style{text, D.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow,
    E.Frame{content, arrangement}, minimum, maximum, states})
  Equal.trans(String,
    R.attr(Doc.element_styles(R.choice_group_node(key, label, normalized, children, typography)), "gap"),
    R.attr(R.style(normalized), "gap"), R.px(E.separation(E.MenuItems{})),
    EnclosureRenderProof.last_append(R.style(normalized), [R.property("flex-shrink", "0"), R.property("height", "auto")], "gap", ""),
    EnclosureRenderProof.parent_style(False{}, EnclosureRender.FrameGap{}, normalized))

def frame_value(+value: D.Style) ->
  {EnclosureRender.parent_value(value, EnclosureRender.FrameGap{}) == R.px(E.frame_gap(D.style_frame(value))) : String}:
  D.Style{text, D.Chrome{fg, bg, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  {==}

def card_gap(+key: String, +face: View.CardFace, +destinations: +List<UI.Placement>, +source: +List<R.Child>, +visual: D.Style, +typography: T.Presentation) -> Rule.card_gap_law(key, face, destinations, source, visual, typography):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  Equal.trans(String, R.attr(R.style(visual), "gap"), EnclosureRender.parent_value(visual, EnclosureRender.FrameGap{}), R.px(E.frame_gap(D.style_frame(visual))), EnclosureRenderProof.parent_style(False{}, EnclosureRender.FrameGap{}, visual), frame_value(visual))

def card_production_properties(+key: String, +face: View.CardFace, +destinations: +List<UI.Placement>, +source: +List<R.Child>, +meaning: UI.Meaning, +typography: T.Presentation) -> Rule.card_production_properties_law(key, face, destinations, source, meaning, typography):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  {==}

def action_frame_gap(+key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability, +name: String,
  +face: C.Face, +behavior: C.Behavior, +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) -> Rule.action_frame_gap_law(key, visual, input, availability, name, face, behavior, size, placement, help, feedback):
  Equal.trans(String,
    R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), "gap"),
    EnclosureRender.parent_value(visual, EnclosureRender.FrameGap{}), R.px(E.frame_gap(D.style_frame(visual))),
    EnclosureRenderProof.parent_action(EnclosureRender.FrameGap{}, key, visual, input, availability, name, face, behavior, size, placement, help, feedback), frame_value(visual))

def choice_frame_gap(+key: String, +label: String, +selected: Bool, +description: String, +visual: D.Style,
  +input: Core.Input, +availability: View.Availability, +name: String, +face: C.Face, +behavior: C.Behavior,
  +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback, +typography: T.Presentation) -> Rule.choice_frame_gap_law(key, label, selected, description, visual, input, availability, name, face, behavior, size, placement, help, feedback, typography):
  action_frame_gap(key, visual, input, availability, name, C.ChoiceFace{label, C.choice_description(description), selected}, behavior, size, placement, help, feedback)

def flow_assigned(+value: D.Style, +flow: D.Flow) ->
  {Rule.style_flow(A.with_flow(value, flow)) == flow : D.Flow}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def choice_style_normalization(+value: D.Style, +size: C.Geometry, label: String, description: Maybe<&2, String>, selected: Bool) ->
  {Rule.choice_style_metrics(A.action_style(value, C.ChoiceFace{label, description, selected}, size)) == (8n, D.ChoiceFlow{}) : (Nat & D.Flow)}:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} = size
  {==}

def actual_choice_normalization(+key: String, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String,
  +role: UI.Role, +context: C.Context, +fallback: D.Style, +typography: T.Presentation) -> Rule.actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography):
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
  choice_style_normalization(A.feedback_style(A.choice_button(selected, D.style_text(fallback)), C.feedback_for(intent), typography), C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}, C.name_for(intent, label), C.choice_description(description), selected)

def Rule.evidence():
  Rule.Requirements{
    +typography => +key => +id => +title => +description => +priority => +pinned => +status => +project => +labels => +owner => +updated => +destinations => +source => +visual => {==},
    +typography => +key => +face => +destinations => +source => +meaning => card_production_properties(key, face, destinations, source, meaning, typography), action_frame_gap,
    +typography => +key => +label => +selected => +description => +visual => +input => +availability => +name => +face => +behavior => +size => +placement => +help => +feedback => choice_frame_gap(key, label, selected, description, visual, input, availability, name, face, behavior, size, placement, help, feedback, typography), +value => +face => +size => flow_assigned(A.action_content_style(value, C.content_layout(face), size, A.intrinsic_content_height(face, D.style_text(value), size)), A.action_flow(face, C.content_layout(face))),
    +typography => +key => +selected => +description => +input => +availability => +label => +role => +context => +fallback => actual_choice_normalization(key, selected, description, input, availability, label, role, context, fallback, typography), +content => +gap => {==}, +content => +spacing => {==}, content => {==}, content_preserves_arrangement,
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==}, actual_choice_geometry, actual_choice_layout, actual_choice_mark_contains_icon, selection_keeps_allocation,
    +key => +label => +selected => +description => +visual => input => availability => name => behavior => +geometry => placement => help => feedback => {==}, +key => +selected => +extent => +icon => {==},
    +typography => +key => +project => +selected => +expanded => +children => {==}, {==}, {==},
    +typography => +key => label => +description => selected => +geometry => {==}, +typography => +key => label => selected => text_gap => extent => icon => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +key => +label => +visual => +children => choice_group_gap(key, label, visual, children, typography),
    +typography => +key => +face => +destinations => +source => +visual => card_gap(key, face, destinations, source, visual, typography), +stage => {==}, +key => +label => +count => +children => {==},
    +typography => +key => +label => +description => +selected => +text_gap => +region_gap => +extent => +icon => {==}}
