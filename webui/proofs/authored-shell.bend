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
import ../../core/interface.bend as UI
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
  created: {Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}} : Design.MainStructure}) -> Rule.creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font):
  Equal.cong(Design.MainStructure, Shell.Result,
    (structure => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, parameters, layers, base, overlays, anchors), structure, Shell.structure_reading_width(structure, parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme)), Shell.scene_structure(content), Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}}, created)

def creation_child_layout(+layout: Source.Layout, maximum: Nat) -> Rule.creation_child_layout(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def creation_main(+key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Rule.creation_main(key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def other_main_fields(+measure: Composition.Measure, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag,
  direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum: Enclosure.Extent, scroll: Model.Scroll, position: Spatial.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates,
  attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_organization(organization) == True{} : Bool}) -> Rule.other_main(Design.MainStructure{measure, organization}, key, tag,
    Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum):
  match organization:
    case Composition.CenteredCreation{}: Logic.impossible(Rule.other_main(Design.MainStructure{measure, Composition.CenteredCreation{}}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum), other)
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def other_main_style(+measure: Composition.Measure, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_organization(organization) == True{} : Bool}) -> Rule.other_main(Design.MainStructure{measure, organization}, key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  other_main_fields(measure, organization, key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, maximum, other)

def other_main(+structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {Rule.other_structure(structure) == True{} : Bool}) -> Rule.other_main(structure, key, tag, style, attributes, children, maximum):
  Design.MainStructure{measure, organization} = structure
  other_main_style(measure, organization, key, tag, style, attributes, children, maximum, other)

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

def settings_classification(+node: Source.Node, +role: UI.Role, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}, belongs: {Rule.settings_role(role) == True{} : Bool}) -> Rule.settings_classification(node, role, navigation, main, settings, other):
  match role:
    case UI.Main{}: Logic.impossible(Rule.settings_classification(node, UI.Main{}, navigation, main, settings, other), belongs)
    case UI.Navigation{}: Logic.impossible(Rule.settings_classification(node, UI.Navigation{}, navigation, main, settings, other), belongs)
    case UI.NavigationHeader{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Heading{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.PrimaryButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.DestructiveButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.SelectedButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.ComposerActions{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Timeline{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Activity{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.UserMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.AssistantMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Composer{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Approval{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Toolbar{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.CodeBlock{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.ApprovalQueue{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Section{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Dialog{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Menu{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Details{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Card{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Button{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Field{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Content{}: settings_group_found(node, navigation, main, settings, other, identified)
    case UI.Alert{}: settings_group_found(node, navigation, main, settings, other, identified)


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

def measure_width(parameters: Design.LayoutParameters, organization: Composition.Body) -> Rule.measure_width(parameters, organization): {==}

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


def beside_floor_fields(measure: Composition.Measure, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum_width: Nat, minimum_height: Nat, scroll: Model.Scroll, position: Spatial.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(Design.MainStructure{measure, organization}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}, attributes, children, maximum, required):
  match organization:
    case Composition.CenteredCreation{}: {==}
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def beside_floor_style(measure: Composition.Measure, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(Design.MainStructure{measure, organization}, key, tag, style, attributes, children, maximum, required):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  beside_floor_fields(measure, organization, key, tag, direction, main, cross, frame, width, height, minimum_width, minimum_height, scroll, position, font, chrome, states, attributes, children, maximum, required)

def beside_box_floor(structure: Design.MainStructure, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Rule.beside_box_floor(structure, key, tag, style, attributes, children, maximum, required):
  Design.MainStructure{measure, organization} = structure
  beside_floor_style(measure, organization, key, tag, style, attributes, children, maximum, required)

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
  Equal.cong(View.NavigationPlacement, Shell.Result,
    (selected => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, selected, parameters, font, theme)), Shell.scene_navigation_placement(content), placement, projected)

def Rule.evidence():
  Rule.Requirements{navigation_projection, assembly_placement, beside_box_floor, beside_main_style, compact_main_style, main_population, main_placement_input, measure_width, recipe_structure, available_children, page_frame, front_layer_last, events, interaction, children, wrapper, no_wrapper_events, reading_policy, reading_layout, reading_stretch_width, creation_population, creation_group, creation_group_spacing, creation_reading_width, creation_assembly, creation_child_layout, creation_main, other_main, navigation_box, settings_classification, footer}
