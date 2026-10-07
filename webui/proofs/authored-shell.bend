import ../../core/composition.bend as Composition
import Base
import ../../core/ui-identity.bend as UIIdentity
import ../authored-shell.bend as Shell
import ../authored-shell-rules.bend as Rule
import ../source.bend as Source
import ../typography.bend as Typography
import ../physical-space.bend as Model
import ../space.bend as Space
import ../space-laws.bend as SpaceRules
import ../physical-space-rules.bend as PhysicalRules
import ../design.bend as Design
import ../spatial.bend as Spatial
import ../enclosure.bend as Enclosure
import ../../core/ui-world.bend as View
import ../../core/SYSTEM.bend as Core
import ../../core/interface.bend as InterfaceView
import ./space.bend as Order
import ../../bendlib/proofs/logic.bend as Logic
import ./physical-space.bend as ModelProof
import ../../bendlib/proofs/algebra.bend as Alg
import ../../bendlib/stdlib.bend as Std

def events(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_events(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def interaction(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_interaction(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def children(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_children(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def wrapper(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Rule.wrapper_children(key, style, children):
  {==}

def no_wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Rule.wrapper_events(key, style, children):
  {==}

def footer(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Rule.footer_children(key, tag, style, attributes, children, settings, font):
  {==}


def reading_policy(+width: Model.AxisSize, maximum: Nat) -> Rule.reading_policy(width, maximum):
  match width:
    case Model.NaturalSize{}: {==}
    case Model.StretchSize{}: {==}
    case Model.CappedStretchSize{cap}: {==}
    case Model.ExactSize{extent}: {==}
    case Model.LimitedSize{minimum, preferred, maximum_extra}: {==}
    case Model.PercentSize{percent}: {==}
    case Model.CappedNaturalSize{percent}: {==}
    case Model.AdaptiveNaturalSize{percent}: {==}

def reading_layout(+layout: Source.Layout, maximum: Nat) -> Rule.reading_layout(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def reading_stretch_width(direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, height: Model.AxisSize, floor: Enclosure.Extent, scroll: Model.Scroll, position: Spatial.Position, +maximum: Nat, +minimum: Nat, preferred: Nat, offered: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, room_fits: {Nat.is_le(minimum, room) == True{} : Bool}) ->
  {PhysicalRules.allocated_width(Rule.reading_stretch_dimension(direction, main, cross, frame, height, floor, scroll, position, maximum, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>}:
  ModelProof.capped_stretch_width(minimum, preferred, offered, maximum, room, fits, room_fits)

def reframing_key(+node: Source.Node, layout: Source.Layout) -> {Source.key_of(Shell.reframe(node, layout)) == Source.key_of(node) : UIIdentity.Key}:
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def creation_population(+children: +List<Source.Node>, +maximum: Nat) -> Rule.creation_population(children, maximum):
  match children:
    case Nil{}: {==}
    case Con{+node, +rest}:
      Equal.trans(+List<UIIdentity.Key>, Source.key_of(Shell.reframe(node, Shell.creation_layout(Shell.layout_of(node), maximum))) <> Rule.keys(Shell.creation_children(rest, maximum)),
        Source.key_of(node) <> Rule.keys(Shell.creation_children(rest, maximum)), Source.key_of(node) <> Rule.keys(rest),
        Equal.cong(UIIdentity.Key, +List<UIIdentity.Key>, (key => key <> Rule.keys(Shell.creation_children(rest, maximum))), Source.key_of(Shell.reframe(node, Shell.creation_layout(Shell.layout_of(node), maximum))), Source.key_of(node), reframing_key(node, Shell.creation_layout(Shell.layout_of(node), maximum))),
        Equal.cong(+List<UIIdentity.Key>, +List<UIIdentity.Key>, (keys => Source.key_of(node) <> keys), Rule.keys(Shell.creation_children(rest, maximum)), Rule.keys(rest), creation_population(rest, maximum)))

def creation_group(key: UIIdentity.Key, font: Source.FontChoice, +maximum: Nat, children: +List<Source.Node>) -> Rule.creation_group(key, font, maximum, children):
  {==}

def creation_group_spacing(key: UIIdentity.Key, font: Source.FontChoice, maximum: Nat, children: +List<Source.Node>) -> Rule.creation_group_spacing(key, font, maximum, children):
  {==}

def creation_reading_width(+parameters: Design.LayoutParameters) -> Rule.creation_reading_width(parameters):
  {==}

def creation_assembly(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: Typography.Presentation,
  created: {Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}} : Design.MainStructure}) -> Rule.creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font):
  Equal.cong(Design.MainStructure, Shell.ShellAuthorship,
    (structure => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, Shell.scene_navigation_placement(content), parameters, layers, base, overlays, anchors), structure, Shell.structure_reading_width(structure, parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme)), Shell.scene_structure(content), Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, created)

def creation_child_layout(+layout: Source.Layout, maximum: Nat) -> Rule.creation_child_layout(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def creation_main(+key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Rule.creation_main(key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def other_main_fields(+measure: Composition.Measure, +heading: Composition.Heading, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag,
  direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum: Enclosure.Extent, scroll: Model.Scroll, position: Spatial.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates,
  attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_organization(organization) == True{} : Bool}) -> Rule.other_main(Design.MainStructure{measure, heading, organization}, key, tag,
    Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum):
  match organization:
    case Composition.CenteredCreation{}: Logic.impossible(Rule.other_main(Design.MainStructure{measure, heading, Composition.CenteredCreation{}}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum), other)
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def other_main_style(+measure: Composition.Measure, +heading: Composition.Heading, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_organization(organization) == True{} : Bool}) -> Rule.other_main(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  other_main_fields(measure, heading, organization, key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, maximum, other)

def other_main(+structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_structure(structure) == True{} : Bool}) -> Rule.other_main(structure, key, tag, style, attributes, children, maximum):
  Design.MainStructure{measure, heading, organization} = structure
  other_main_style(measure, heading, organization, key, tag, style, attributes, children, maximum, other)

def navigation_box(key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, +width: Nat) -> Rule.navigation_box(key, tag, style, attributes, children, rest, width):
  Source.Style{Source.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def settings_identified(+node: Source.Node,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}) ->
  {UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")) == True{} : Bool}:
  Equal.cong(UIIdentity.Key, Bool, (key => UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))),
    Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open"), identified)

def settings_group_found(+node: Source.Node, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}) ->
  {Shell.split_base_settings(UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")), node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}:
  Equal.cong(Bool, Shell.BaseParts, (found => Shell.split_base_settings(found, node, Shell.BaseParts{navigation, main, settings, other})),
    UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")), True{}, settings_identified(node, identified))

def settings_classification(+node: Source.Node, +role: InterfaceView.Role, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}, belongs: {Rule.settings_role(role) == True{} : Bool}) -> Rule.settings_classification(node, role, navigation, main, settings, other):
  match role:
    case InterfaceView.Main{}: Logic.impossible(Rule.settings_classification(node, InterfaceView.Main{}, navigation, main, settings, other), belongs)
    case InterfaceView.Navigation{}: Logic.impossible(Rule.settings_classification(node, InterfaceView.Navigation{}, navigation, main, settings, other), belongs)
    case InterfaceView.NavigationHeader{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Heading{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.PrimaryButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.DestructiveButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.SelectedButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.ComposerActions{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.DialogActions{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Timeline{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Activity{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.UserMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.AssistantMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Composer{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Approval{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Toolbar{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.CodeBlock{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.ApprovalQueue{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Section{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Dialog{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Menu{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Details{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Card{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Button{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Field{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Content{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Alert{}: settings_group_found(node, navigation, main, settings, other, identified)


def reverse_layer_accumulator(+remaining: +List<Source.Node>, +acc: +List<Source.Node>, +behind: +List<Source.Node>) ->
  {List.reverse.go(&2, Source.Node, remaining, List.append(&2, Source.Node, acc, behind)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, remaining, acc), behind) : +List<Source.Node>}:
  Std.list_ind(~Source.Node,
    ~(layers => @+accumulator:+List<Source.Node> -> @+background:+List<Source.Node> ->
      {List.reverse.go(&2, Source.Node, layers, List.append(&2, Source.Node, accumulator, background)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, layers, accumulator), background) : +List<Source.Node>}),
    ~(+accumulator => +background => {==}),
    ~(+front => +rest => hypothesis => +accumulator => +background => hypothesis(front <> accumulator, background)), remaining)(acc, behind)

def front_layer_last(+first: Source.Node, +rest: +List<Source.Node>) -> Rule.front_layer_last(first, rest):
  reverse_layer_accumulator(rest, Nil{}, first <> Nil{})

def recipe_structure(recipe: Composition.Recipe) -> Rule.recipe_structure(recipe):
  Composition.Recipe{measure, heading, organization, composer, decisions, latest} = recipe
  {==}

def available_children(children: +List<Source.Node>, maximum: Nat) -> Rule.available_children(children, maximum): {==}

def page_frame(previous: Enclosure.Frame) -> Rule.page_frame(previous): {==}

def measure_width(parameters: Design.LayoutParameters, heading: Composition.Heading, organization: Composition.Body) -> Rule.measure_width(parameters, heading, organization): {==}

def beside_main_style(style: Source.Style, +required: Nat) -> Rule.beside_main_style(style, required):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {==}

def compact_main_style(style: Source.Style, required: Nat) -> Rule.compact_main_style(style, required): {==}

def main_population(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, structure: Design.MainStructure, maximum: Nat, beside: Bool, required: Nat) -> Rule.main_population(key, tag, style, attributes, children, rest, structure, maximum, beside, required): {==}

def main_placement_input(placement: View.NavigationPlacement, parameters: Design.LayoutParameters, structure: Design.MainStructure, reading_width: Nat, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>, docked: +List<Source.Node>, font: Typography.Presentation) -> Rule.main_placement_input(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font):
  match placement:
    case View.LeadingNavigation{}: {==}
    case View.ModalNavigation{}: {==}
    case View.CollapsedNavigation{}: {==}


def beside_floor_fields(measure: Composition.Measure, heading: Composition.Heading, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum_width: Nat, minimum_height: Nat, scroll: Model.Scroll, position: Spatial.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(Design.MainStructure{measure, heading, organization}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}, attributes, children, maximum, required):
  match organization:
    case Composition.CenteredCreation{}: {==}
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def beside_floor_style(measure: Composition.Measure, heading: Composition.Heading, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum, required):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  beside_floor_fields(measure, heading, organization, key, tag, direction, main, cross, frame, width, height, minimum_width, minimum_height, scroll, position, font, chrome, states, attributes, children, maximum, required)

def beside_box_floor(structure: Design.MainStructure, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(structure, key, tag, style, attributes, children, maximum, required):
  Design.MainStructure{measure, heading, organization} = structure
  beside_floor_style(measure, heading, organization, key, tag, style, attributes, children, maximum, required)

def Rule.base_shared_classification(node, role, parts): {==}

def Rule.base_group_navigation(node, navigation, main, settings, other): {==}

def Rule.base_group_main(node, navigation, main, settings, other): {==}

def Rule.base_group_footer(node, navigation, main, settings, other): {==}

def Rule.base_group_other(node, navigation, main, settings, other): {==}

def navigation_projection(content: Core.Scene) -> Rule.navigation_projection(content):
  Core.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = content
  {==}

def assembly_placement(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: Typography.Presentation, placement: View.NavigationPlacement,
  projected: {Shell.scene_navigation_placement(content) == placement : View.NavigationPlacement}) -> Rule.assembly_placement(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font, placement):
  Equal.cong(View.NavigationPlacement, Shell.ShellAuthorship,
    (selected => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, selected, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, selected, parameters, font, theme)), Shell.scene_navigation_placement(content), placement, projected)

def chronological_main_frame(frame: Enclosure.Frame) -> Rule.chronological_main_frame(frame): {==}

def chronological_main_cross() -> Rule.chronological_main_cross(): {==}

def chronological_main_leading(previous: Spatial.Alignment) -> Rule.chronological_main_leading(previous): {==}

def chronological_reading_width(+parameters: Design.LayoutParameters) -> Rule.chronological_reading_width(parameters):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}

def conversation_title_font(+font: Source.FontChoice) -> Rule.conversation_title_font(font):
  match font:
    case Source.InheritFont{}: {==}
    case Source.ExplicitFont{presentation}: {==}

def conversation_title_style(+style: Source.Style) -> Rule.conversation_title_style(style):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match direction:
    case Model.Vertical{}: {==}
    case Model.Horizontal{}: {==}
    case Model.ResponsiveHorizontal{}: {==}
    case Model.Layered{}: {==}

def conversation_title_text(+key: UIIdentity.Key, +value: String, +font: Source.FontChoice, wrapping: Typography.Wrapping) -> Rule.conversation_title_text(key, value, font, wrapping): {==}

def conversation_title_box(+key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>) -> Rule.conversation_title_box(key, tag, style, attributes, children): {==}

def conversation_title_children(+values: +List<Source.Node>) -> Rule.conversation_title_children(values):
  match values:
    case Nil{}: {==}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}: {==}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}: {==}
    case Con{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, rest}: {==}
    case Con{Source.Glyph{key, drawing, style}, rest}: {==}
    case Con{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, rest}: {==}
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}: {==}
    case Con{Source.Text{key, value, font, wrapping}, rest}: {==}

def conversation_title_other(+node: Source.Node) -> Rule.conversation_title_other(node):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: Unit{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: Unit{}

def other_heading_children(+heading: Composition.Heading, key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Rule.other_heading_children(heading, key, style, children):
  match heading:
    case Composition.NoHeading{}: {==}
    case Composition.PageHeading{}: {==}
    case Composition.ConversationHeading{}: Unit{}

def conversation_header_frame(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> Rule.conversation_header_frame(key, style, title, actions):
  Source.Style{layout, font, chrome, states} = style
  {==}

def conversation_main(+measure: Composition.Measure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, title: Source.Node, actions: Source.Node, remaining: +List<Source.Node>, +maximum: Nat) -> Rule.conversation_main(measure, key, tag, style, attributes, title, actions, remaining, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def conversation_header(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> Rule.conversation_header(key, style, title, actions):
  Source.Style{layout, font, chrome, states} = style
  {==}

def task_action_flow(+visual: Design.Style, position: Composition.Position) -> Rule.task_action_flow(visual, position): {==}

def Rule.evidence():
  Rule.Requirements{conversation_title_font, conversation_title_style, conversation_title_text, conversation_title_box, conversation_title_children, conversation_title_other, other_heading_children, chronological_main_frame, chronological_main_cross(), chronological_main_leading, chronological_reading_width, conversation_header_frame, conversation_main, conversation_header, task_action_flow, navigation_projection, assembly_placement, beside_box_floor, beside_main_style, compact_main_style, main_population, main_placement_input, measure_width, recipe_structure, available_children, page_frame, front_layer_last, events, interaction, children, wrapper, no_wrapper_events, reading_policy, reading_layout, reading_stretch_width, creation_population, creation_group, creation_group_spacing, creation_reading_width, creation_assembly, creation_child_layout, creation_main, other_main, navigation_box, settings_classification, footer}


def Rule.modal_navigation_geometry(node, capacity, parameters, layers, base, overlays, anchors, docked, floating):
  View.Capacity{navigation_beside, details_beside} = capacity
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def Rule.modal_navigation_population(key, tag, style, attributes, children, rest, capacity, parameters, layers, base, overlays, anchors, identified):
  Equal.cong(InterfaceView.Role, Shell.OverlayParts,
    (role => Shell.split_overlay_node(Source.Box{key, tag, style, attributes, children}, role, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors,
      Shell.split_overlays(rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors))),
    Shell.base_role(key, overlays), InterfaceView.Navigation{}, identified)

def Rule.modal_navigation_box_preserved(key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, capacity, parameters, layers, base, overlays, anchors, docked, floating):
  View.Capacity{navigation_beside, details_beside} = capacity
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def Rule.dialog_reading_span(navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width): {==}

def Rule.dialog_floating_geometry(node, parameters, layers, base, overlays, anchors, docked, floating):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def Rule.dialog_floating_box_preserved(key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, parameters, layers, base, overlays, anchors, docked, floating):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}
